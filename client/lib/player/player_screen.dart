import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/platform.dart';
import '../core/prefs.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import 'end_screen.dart';
import 'player_controls.dart';
import 'video_layer.dart';

/// Full screen video player built on libmpv (media_kit).
///
/// Performance notes: the video itself is decoded and rendered by mpv with
/// hardware decoding; the Flutter overlay only rebuilds small widgets bound to
/// streams (time label, seek bar) and is fully removed when hidden.
class PlayerScreen extends StatefulWidget {
  final MediaItem item;
  final double startAt;

  /// Always draw the video as a Flutter texture, never on the TV video layer
  /// (used after the layer couldn't show a file).
  final bool texture;
  const PlayerScreen({
    super.key,
    required this.item,
    this.startAt = 0,
    this.texture = false,
  });

  /// The full screen player route. If the player replaces itself (to change
  /// how the video is drawn), the route's result is the new route's
  /// `popped` future, so callers can wait for the end of playback with
  /// [waitForPlayer].
  static Route<Object?> route(
    MediaItem item, {
    double startAt = 0,
    bool texture = false,
  }) => PageRouteBuilder<Object?>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, _, _) =>
        PlayerScreen(item: item, startAt: startAt, texture: texture),
    transitionsBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );

  /// Waits until the player [route] (and any player that replaced it) is gone.
  static Future<void> waitForPlayer(Future<Object?> pushed) async {
    Object? r = await pushed;
    while (r is Future) {
      r = await r;
    }
  }

  @override
  State<PlayerScreen> createState() => PlayerScreenState();
}

class PlayerScreenState extends State<PlayerScreen> with WindowListener {
  /// Emulator test only: print what the player does.
  static const _testLog = bool.fromEnvironment('HS_TEST_LOG');
  late final AppState app = context.read<AppState>();
  late final Prefs prefs = app.prefs;
  late final ApiClient api = app.api!;

  late final Player player;

  /// The Flutter texture the video is drawn into (null on the TV video layer).
  VideoController? controller;

  /// Android TV: the video is shown by the TV box on its own video layer
  /// under the app (see VideoLayer), instead of a Flutter texture.
  late final bool layer = !widget.texture && _layerFor(widget.item);
  int _layerToken = 0;
  int _attachedWid = 0;
  Future<void> _layerOps = Future.value();
  bool _replacing = false;

  /// Subtitle size in percent; the video layer draws subtitles in Flutter.
  late final ValueNotifier<int> subScale = ValueNotifier(prefs.subtitleScale);

  late MediaItem item = widget.item;
  final ValueNotifier<Related?> related = ValueNotifier(null);
  final ValueNotifier<bool> controlsVisible = ValueNotifier(true);
  final ValueNotifier<bool> ended = ValueNotifier(false);
  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<bool> fullscreen = ValueNotifier(false);
  final ValueNotifier<String?> osd = ValueNotifier(null);
  final ValueNotifier<bool> menuOpen = ValueNotifier(false);

  final FocusNode _focus = FocusNode(debugLabel: 'player');

  /// The play/pause button; a remote's up/down lands here when controls appear.
  final FocusNode playFocus = FocusNode(debugLabel: 'play');
  final List<StreamSubscription> _subs = [];
  Timer? _hideTimer;
  Timer? _progressTimer;
  Timer? _osdTimer;
  Timer? _volumeSaveTimer;
  bool _wasFullscreen = false;
  bool _closing = false;
  bool _tracksApplied = false;
  int _openToken = 0;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastReported = -1;
  double subDelay = 0;

  @override
  void initState() {
    super.initState();
    player = Player(
      configuration: PlayerConfiguration(
        title: 'Home Stream',
        libass: true,
        bufferSize: (AppPlatform.isAndroid ? 64 : 256) * 1024 * 1024,
        logLevel: _testLog ? MPVLogLevel.v : MPVLogLevel.warn,
      ),
    );
    if (_testLog) {
      final keep = RegExp(
        r'hwdec|hardware|mediacodec|Using|codec|vo/|wid|error|fatal|Video|surface',
        caseSensitive: false,
      );
      _subs.add(
        player.stream.log.listen((l) {
          final line = '${l.prefix}/${l.level}: ${l.text.trim()}';
          if (keep.hasMatch(line)) debugPrint('MPV $line');
        }),
      );
      debugPrint('LAYER player for ${widget.item.displayTitle}: layer=$layer');
    }
    if (!layer) {
      controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: true,
          hwdec: prefs.hardwareDecoding ? _hwdec : 'no',
        ),
      );
    }
    _subs.add(player.stream.completed.listen(_onCompleted));
    _subs.add(player.stream.error.listen(_onError));
    _subs.add(player.stream.tracks.listen((_) => _maybeApplyTracks()));
    _subs.add(
      player.stream.playing.listen((p) {
        if (!p) _reportProgress(force: true);
        _showControls(autoHide: p);
      }),
    );
    _subs.add(
      player.stream.volume.listen((v) {
        _volumeSaveTimer?.cancel();
        _volumeSaveTimer = Timer(
          const Duration(seconds: 1),
          () => prefs.volume = v,
        );
      }),
    );
    _progressTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _reportProgress(),
    );
    controlsVisible.addListener(_onControlsVisibility);
    menuOpen.addListener(_onMenu);
    AppPlatform.keepScreenOn(true);
    if (AppPlatform.isPhone && AppPlatform.isAndroid) {
      _applyOrientation();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (AppPlatform.isDesktop) windowManager.addListener(this);
    _initWindow();
    _configure().then((_) => _open(item, widget.startAt));
  }

  Future<void> _initWindow() async {
    if (!AppPlatform.isDesktop) return;
    try {
      _wasFullscreen = await windowManager.isFullScreen();
      fullscreen.value = _wasFullscreen;
      if (prefs.playerFullscreen && !_wasFullscreen) {
        await windowManager.setFullScreen(true);
        fullscreen.value = true;
      }
    } catch (_) {}
  }

  Future<void> _configure() async {
    final p = player.platform;
    if (p is! NativePlayer) return;
    Future<void> set(String k, String v) async {
      try {
        await p.setProperty(k, v);
      } catch (_) {}
    }

    await set('cache', 'yes');
    await set('cache-secs', '120');
    await set('demuxer-readahead-secs', '60');
    // TV boxes have 1-2 GB of RAM: keep a smaller rewind cache there
    await set(
      'demuxer-max-back-bytes',
      '${(AppPlatform.isAndroid ? 16 : 64) * 1024 * 1024}',
    );
    await set('network-timeout', '30');
    await set('user-agent', 'HomeStream/1.0');
    await set('volume-max', '150');
    await set('sub-auto', 'no');
    await set('sub-ass-override', 'scale');
    await set('sub-scale', (prefs.subtitleScale / 100).toStringAsFixed(2));
    await set('sub-border-size', '2.6');
    await set('sub-shadow-offset', '1.2');
    await set('sub-margin-y', '36');
    if (Platform.isWindows) await set('sub-font', 'Segoe UI Semibold');
    await set('hr-seek', 'yes');
    await set('hr-seek-framedrop', 'yes');
    if (AppPlatform.isAndroid) {
      // media_kit adds MPEG-4 Part 2 (Xvid/DivX, the usual AVI video) to the
      // Android hardware decoders. AVI gives most of those frames no
      // timestamp (B-frames) and many have "packed B-frames"; the hardware
      // decoder then outputs frames stamped 0 and playback stutters/freezes.
      // mpv's own default keeps MPEG-4 in software, which is cheap for these
      // SD files, so do the same (other codecs stay hardware decoded).
      try {
        await controller?.platform.future.timeout(const Duration(seconds: 5));
      } catch (_) {}
      await set('hwdec-codecs', 'h264,hevc,mpeg2video,vp8,vp9,av1');
      // media_kit turns on mpv's disk cache, which fails on Android ("Failed
      // to create file cache") and isn't wanted on a TV box's small storage
      await set('cache-on-disk', 'no');
    }
    if (layer) await _setUpLayer();
    // Let mpv choose sensible defaults; we apply language preferences ourselves.
    await set('sid', 'no');
    await player.setVolume(prefs.volume.clamp(0, 150));
  }

  // ---------------------------------------------------------------- playback

  Future<void> _open(MediaItem it, double startAt) async {
    final token = ++_openToken;
    item = it;
    _tracksApplied = false;
    _lastReported = -1;
    subDelay = 0;
    ended.value = false;
    error.value = null;
    related.value = null;
    if (mounted) setState(() {});
    _setTitle();
    api
        .related(it.id)
        .then((r) {
          if (token == _openToken && mounted) related.value = r;
        })
        .catchError((_) {});
    await _applyFileOptions(it);
    try {
      await player.open(
        Media(
          api.streamUrl(it),
          start: startAt > 1
              ? Duration(milliseconds: (startAt * 1000).round())
              : null,
        ),
        play: true,
      );
      final p = player.platform;
      if (p is NativePlayer) {
        try {
          await p.setProperty('sub-delay', '0');
        } catch (_) {}
      }
      if (layer) _checkLayer(token);
    } catch (e) {
      if (token == _openToken) error.value = 'Video açılamadı: $e';
    }
    _showControls();
  }

  // ------------------------------------------------------------ video layer

  /// Hardware decoders for the texture renderer. On Android, mpv's
  /// "auto-safe" means MediaCodec in copy-back mode: every decoded frame is
  /// copied to the CPU and uploaded to the GPU again, too slow for 1080p on
  /// TV boxes. "mediacodec" hands the frames to the GPU directly; mpv falls
  /// back to the copy mode (and then software) if that doesn't work.
  String get _hwdec =>
      AppPlatform.isAndroid ? 'mediacodec,mediacodec-copy' : 'auto-safe';

  static bool _isAvi(MediaFile? f) =>
      f != null &&
      (f.container.toLowerCase() == 'avi' ||
          f.path.toLowerCase().endsWith('.avi'));

  /// Whether [it] can be shown on the TV video layer: the layer needs the
  /// box's hardware decoder (it renders straight into the layer).
  bool _layerFor(MediaItem it) {
    if (!AppPlatform.isTv || !VideoLayer.available) return false;
    if (!prefs.tvVideoLayer || !prefs.hardwareDecoding) return false;
    final f = it.file;
    if (f == null) return true;
    if (_isAvi(f)) return false; // decoded in software (see _applyFileOptions)
    const hw = {'h264', 'hevc', 'vp9', 'av1', 'mpeg2video', 'vp8'};
    final codec = f.videoCodec.toLowerCase();
    return codec.isEmpty || hw.contains(codec);
  }

  Future<void> _setLayerProp(String k, String v) async {
    final p = player.platform;
    if (p is! NativePlayer) return;
    try {
      await p.setProperty(k, v);
    } catch (_) {}
  }

  Future<void> _setUpLayer() async {
    // mpv hands the hardware decoder the layer's surface (vo=mediacodec_embed)
    await _setLayerProp('vo', 'null');
    await _setLayerProp('hwdec', 'mediacodec');
    _subs.add(
      player.stream.videoParams.listen((v) {
        var w = v.dw ?? 0, h = v.dh ?? 0;
        if (v.rotate == 90 || v.rotate == 270) (w, h) = (h, w);
        if (w > 0 && h > 0) VideoLayer.setVideoSize(w, h);
      }),
    );
    VideoLayer.surface.addListener(_onLayerSurface);
    _layerToken = await VideoLayer.show();
    if (VideoLayer.surface.value == 0) {
      // wait for the surface, so the decoder starts with it
      final ready = Completer<void>();
      void check() {
        if (VideoLayer.surface.value != 0 && !ready.isCompleted) {
          ready.complete();
        }
      }

      VideoLayer.surface.addListener(check);
      await ready.future.timeout(const Duration(seconds: 3), onTimeout: () {});
      VideoLayer.surface.removeListener(check);
    }
    _onLayerSurface();
    await _layerOps;
  }

  void _onLayerSurface() {
    final wid = VideoLayer.surface.value;
    _layerOps = _layerOps.then((_) => _attachLayer(wid));
  }

  /// Points mpv at the layer's surface ([wid]), or detaches it (0) when the
  /// surface goes away (app in the background, player closing).
  Future<void> _attachLayer(int wid) async {
    if (wid == _attachedWid || (_closing && wid != 0)) return;
    _attachedWid = wid;
    if (_testLog) debugPrint('LAYER attach wid=$wid');
    // the order matters: mediacodec_embed must never start without a surface
    await _setLayerProp('vo', 'null');
    await _setLayerProp('wid', '$wid');
    if (wid == 0) {
      await _setLayerProp('vid', 'no');
      return;
    }
    await _setLayerProp('vo', 'mediacodec_embed');
    // reopen the video decoder on the new surface
    await _setLayerProp('vid', 'auto');
    if (player.state.duration > Duration.zero) {
      await player.seek(player.state.position);
    }
  }

  Future<void> _detachLayer() async {
    if (!layer) return;
    VideoLayer.surface.removeListener(_onLayerSurface);
    _layerOps = _layerOps.then((_) => _attachLayer(0));
    await _layerOps;
  }

  /// The layer only works with the box's hardware decoder. If it can't
  /// decode this file (e.g. 10-bit H.264), mpv drops the video and only the
  /// sound plays: reopen the file with the texture renderer, which can
  /// decode in software.
  Future<void> _checkLayer(int token) async {
    bool stale() => !mounted || token != _openToken || _replacing || _closing;
    // wait until the file plays (or has been loaded for a while)
    Duration? from;
    var waited = 0;
    while (true) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (stale()) return;
      if (_attachedWid == 0 || player.state.duration == Duration.zero) {
        continue; // no surface (in the background) or still loading
      }
      from ??= player.state.position;
      waited += 500;
      final moved = player.state.position - from;
      if (moved >= const Duration(milliseconds: 1500) || waited >= 8000) break;
    }
    // check twice, a decoder may still be starting
    for (var i = 0; i < 2; i++) {
      if (await _layerShowsVideo()) return;
      await Future.delayed(const Duration(seconds: 2));
      if (stale()) return;
    }
    _replace(item, player.state.position.inMilliseconds / 1000);
  }

  Future<bool> _layerShowsVideo() async {
    final p = player.platform;
    if (p is! NativePlayer || _attachedWid == 0) return true;
    final hasVideo = player.state.tracks.video.any(
      (t) => t.id != 'auto' && t.id != 'no',
    );
    if (!hasVideo) return true; // a sound-only file
    var hw = '', vid = '';
    try {
      hw = await p.getProperty('hwdec-current');
    } catch (_) {}
    try {
      vid = await p.getProperty('current-tracks/video/id');
    } catch (_) {}
    if (_testLog) debugPrint('LAYER check hwdec=$hw vid=$vid');
    return hw.startsWith('mediacodec') && vid.isNotEmpty;
  }

  /// Reopens [it] in a new player that draws the video the other way.
  Future<void> _replace(MediaItem it, double startAt) async {
    if (_replacing || _closing || !mounted) return;
    _replacing = true;
    if (_testLog) debugPrint('LAYER replace (layer=$layer) at $startAt');
    await _reportProgress(force: true);
    await _detachLayer();
    if (!mounted) return;
    final next = PlayerScreen.route(it, startAt: startAt, texture: layer);
    Navigator.of(context).pushReplacement(next, result: next.popped);
  }

  static bool _bitmapSubtitle(SubtitleTrack t) {
    final c = (t.codec ?? '').toLowerCase();
    return c.contains('pgs') ||
        c.contains('dvd_sub') ||
        c.contains('dvb_sub') ||
        c.contains('vobsub') ||
        c == 'xsub';
  }

  /// The video layer draws subtitles in Flutter from their text; picture
  /// subtitles (Blu-ray PGS, DVD) only show with mpv's own renderer.
  bool _needsTextureFor(SubtitleTrack t) {
    if (!layer || !_bitmapSubtitle(t)) return false;
    _replace(item, player.state.position.inMilliseconds / 1000);
    return true;
  }

  /// Per-file mpv options for AVI files.
  Future<void> _applyFileOptions(MediaItem it) async {
    final p = player.platform;
    if (p is! NativePlayer) return;
    final avi = _isAvi(it.file);
    Future<void> set(String k, String v) async {
      try {
        await p.setProperty(k, v);
      } catch (_) {}
    }

    // Badly interleaved AVI files keep audio and video far apart in the
    // file, so the demuxer jumps between two places for every packet. With
    // mpv's default 128 KiB stream buffer each jump is a new HTTP request
    // (measured: ~50 requests per second and a stall every few seconds over
    // Wi-Fi). A bigger buffer turns those jumps into reads from memory. Only
    // for AVI, so other formats keep fast seeking.
    await set('stream-buffer-size', '${avi ? 8 * 1024 * 1024 : 128 * 1024}');
    // AVI has no presentation timestamps for B-frames. Android's MediaCodec
    // decoders need them (FFmpeg stamps such frames 0), so also H.264 in AVI
    // would stutter there; AVI files are SD, decode them in software.
    if (AppPlatform.isAndroid && prefs.hardwareDecoding && !layer) {
      await set('hwdec', avi ? 'no' : _hwdec);
    }
  }

  void _setTitle() {
    if (!AppPlatform.isDesktop) return;
    try {
      windowManager.setTitle('${item.displayTitle} · Home Stream');
    } catch (_) {}
  }

  /// Adds external subtitles and applies audio/subtitle language preferences
  /// once mpv has parsed the file's tracks.
  Future<void> _maybeApplyTracks() async {
    if (_tracksApplied) return;
    final tracks = player.state.tracks;
    final realVideo = tracks.video.where((t) => t.id != 'auto' && t.id != 'no');
    final realAudio = tracks.audio.where((t) => t.id != 'auto' && t.id != 'no');
    if (realVideo.isEmpty && realAudio.isEmpty) return;
    _tracksApplied = true;
    final token = _openToken;
    final p = player.platform;

    // External subtitle files from the server.
    final ext = item.file?.externalSubtitles ?? const [];
    if (p is NativePlayer) {
      for (final s in ext) {
        try {
          await p.command([
            'sub-add',
            api.url(s.url),
            'auto',
            s.title.isNotEmpty
                ? s.title
                : (languageName(s.language).isNotEmpty
                      ? languageName(s.language)
                      : 'Harici altyazı'),
            s.language,
          ]);
        } catch (_) {}
      }
    }
    if (token != _openToken) return;
    // give mpv a moment to publish the new track list
    await Future.delayed(const Duration(milliseconds: 300));
    if (token != _openToken) return;

    final all = player.state.tracks;
    // Audio preference
    AudioTrack? audio;
    final aPref = prefs.audioLanguage;
    if (aPref != 'original') {
      audio = all.audio
          .where(
            (t) =>
                t.id != 'auto' &&
                t.id != 'no' &&
                languageMatches(t.language, aPref),
          )
          .firstOrNull;
      if (audio != null) await player.setAudioTrack(audio);
    }
    final currentAudio = audio ?? player.state.track.audio;

    // Subtitle preference
    final sPref = prefs.subtitleLanguage;
    final subs = all.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    bool forcedTrack(SubtitleTrack t) =>
        (t.title ?? '').toLowerCase().contains('forced');
    SubtitleTrack? pick;
    final choice = prefs.subtitleChoice;
    if (choice == 'off') {
      // turned off in the player on this device: stays off until turned on
      pick = null;
    } else if (choice.startsWith('on:') && subs.isNotEmpty) {
      // turned on in the player on this device: keep showing subtitles,
      // preferably in the same language as last time
      final lang = choice.substring(3);
      final full = subs.where((t) => !forcedTrack(t)).toList();
      final pool = full.isNotEmpty ? full : subs;
      pick =
          (lang.isNotEmpty
              ? pool.where((t) => languageMatches(t.language, lang)).firstOrNull
              : null) ??
          (sPref != 'off'
              ? pool
                    .where((t) => languageMatches(t.language, sPref))
                    .firstOrNull
              : null) ??
          pool.where((t) => t.isDefault == true).firstOrNull ??
          pool.first;
    } else if (sPref != 'off' && subs.isNotEmpty) {
      final audioIsPref = languageMatches(currentAudio.language, sPref);
      bool forced(SubtitleTrack t) =>
          (t.title ?? '').toLowerCase().contains('forced');
      final matching = subs
          .where((t) => languageMatches(t.language, sPref))
          .toList();
      if (audioIsPref) {
        pick = matching.where(forced).firstOrNull;
      } else {
        pick =
            matching.where((t) => !forced(t)).firstOrNull ??
            matching.firstOrNull;
        if (pick == null && sPref == 'tur') {
          // No Turkish track: fall back to a default-flagged or single external track.
          pick = subs.where((t) => t.isDefault == true).firstOrNull;
        }
      }
    }
    await player.setSubtitleTrack(pick ?? SubtitleTrack.no());
    if (pick != null) _needsTextureFor(pick);
  }

  void _onCompleted(bool done) {
    if (!done || _closing) return;
    final dur = player.state.duration.inMilliseconds / 1000;
    if (dur > 0) {
      api.reportProgress(item.id, dur, dur).catchError((_) => const UserData());
      _lastReported = dur;
    }
    if (prefs.playerFullscreen || fullscreen.value) {
      // stay in the current window mode
    }
    ended.value = true;
    _showControls(autoHide: false);
  }

  void _onError(String e) {
    // mpv reports some non-fatal errors (e.g. a single bad subtitle); only
    // surface them if playback can't continue.
    if (player.state.duration == Duration.zero) {
      error.value = 'Oynatma hatası: $e';
    } else {
      flashOsd('Uyarı: $e');
    }
  }

  Future<void> _reportProgress({bool force = false}) async {
    if (ended.value) return;
    final pos = player.state.position.inMilliseconds / 1000;
    final dur = player.state.duration.inMilliseconds / 1000;
    if (dur <= 0 || pos <= 0) return;
    if (!force && !player.state.playing) return;
    if ((pos - _lastReported).abs() < 2) return;
    _lastReported = pos;
    try {
      await api.reportProgress(item.id, pos, dur);
    } catch (_) {}
  }

  /// Plays another item in the same player (next episode, recommendation).
  Future<void> switchTo(MediaItem target, {double? startAt}) async {
    await _reportProgress(force: true);
    try {
      var t = target;
      if (t.isSeries) {
        final d = await api.item(t.id);
        t =
            d.nextUp ??
            (d.seasons.isNotEmpty ? d.seasons.first.episodes.first : t);
      }
      final full = await api.item(t.id);
      final start = startAt ?? (full.inProgress ? full.userData.position : 0.0);
      // e.g. an AVI episode after an MKV one on the TV video layer
      final wantLayer = !widget.texture && _layerFor(full);
      if (wantLayer != layer) {
        await _replace(full, start);
        return;
      }
      await _open(full, start);
    } catch (e) {
      flashOsd('Açılamadı: $e');
    }
  }

  Future<void> playNext() async {
    final next = related.value?.next;
    if (next != null) await switchTo(next, startAt: 0);
  }

  Future<void> replay() async {
    ended.value = false;
    await player.seek(Duration.zero);
    await player.play();
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    await _reportProgress(force: true);
    await _detachLayer();
    if (AppPlatform.isDesktop)
      try {
        if (!_wasFullscreen && await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
        }
        windowManager.setTitle('Home Stream');
      } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------- controls

  void _showControls({bool autoHide = true}) {
    if (!controlsVisible.value) controlsVisible.value = true;
    _hideTimer?.cancel();
    if (autoHide && player.state.playing && !ended.value) {
      // give remote users more time while they move between buttons
      final ms = _controlFocused ? 6000 : 2800;
      _hideTimer = Timer(Duration(milliseconds: ms), () {
        if (!menuOpen.value && player.state.playing)
          controlsVisible.value = false;
      });
    }
  }

  void onUserActivity() => _showControls(autoHide: true);

  /// Phones: landscape only, or follow the phone (remembered on the device).
  late final ValueNotifier<bool> autoRotate = ValueNotifier(
    prefs.playerAutoRotate,
  );

  void _applyOrientation() {
    autoRotate.value = prefs.playerAutoRotate;
    SystemChrome.setPreferredOrientations(
      autoRotate.value
          ? DeviceOrientation.values
          : const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
  }

  void toggleAutoRotate() {
    prefs.playerAutoRotate = !prefs.playerAutoRotate;
    if (AppPlatform.isAndroid) {
      _applyOrientation();
    } else {
      autoRotate.value = prefs.playerAutoRotate;
    }
    flashOsd(
      autoRotate.value
          ? 'Ekran telefonla birlikte döner'
          : 'Ekran yatay kilitli',
    );
    onUserActivity();
  }

  bool get _controlFocused {
    final f = FocusManager.instance.primaryFocus;
    return f != null && f != _focus && f.context != null;
  }

  // when the overlay hides, the remote goes back to seeking/pausing
  void _onControlsVisibility() {
    if (!controlsVisible.value && _controlFocused && !ended.value) {
      _focus.requestFocus();
    }
  }

  void _onMenu() {
    if (!menuOpen.value && _controlFocused && !ended.value) {
      // the menu's own buttons are gone; continue from the subtitle button
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controlsVisible.value) playFocus.requestFocus();
      });
    }
  }

  /// Back (remote, phone, Esc), one step at a time: close the menu or leave
  /// the focused button for the play button, then hide the overlay so only
  /// the video is left, then leave the player.
  void handleBack() {
    if (ended.value) {
      close();
      return;
    }
    if (menuOpen.value) {
      menuOpen.value = false;
      if (AppPlatform.isTv) focusControls();
      return;
    }
    if (AppPlatform.isTv || AppPlatform.isPhone) {
      if (controlsVisible.value) {
        final f = FocusManager.instance.primaryFocus;
        if (AppPlatform.isTv && _controlFocused && f != playFocus) {
          focusControls();
          return;
        }
        _hideTimer?.cancel();
        controlsVisible.value = false;
        _focus.requestFocus();
        return;
      }
      close();
      return;
    }
    // desktop (Esc): leave a focused button, then fullscreen, then the player
    if (_controlFocused) {
      _focus.requestFocus();
      if (player.state.playing) controlsVisible.value = false;
    } else if (fullscreen.value && !prefs.playerFullscreen) {
      toggleFullscreen();
    } else {
      close();
    }
  }

  /// Shows the overlay and puts focus on the play button (remote control).
  void focusControls() {
    _showControls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && playFocus.context != null) playFocus.requestFocus();
    });
  }

  void flashOsd(String text) {
    osd.value = text;
    _osdTimer?.cancel();
    _osdTimer = Timer(
      const Duration(milliseconds: 1400),
      () => osd.value = null,
    );
  }

  Future<void> toggleFullscreen() async {
    if (!AppPlatform.isDesktop) return;
    try {
      final v = !(await windowManager.isFullScreen());
      await windowManager.setFullScreen(v);
      fullscreen.value = v;
    } catch (_) {}
  }

  @override
  void onWindowEnterFullScreen() => fullscreen.value = true;
  @override
  void onWindowLeaveFullScreen() => fullscreen.value = false;

  Duration? _seekTarget;
  DateTime _seekAt = DateTime.fromMillisecondsSinceEpoch(0);

  void seekRelative(int seconds) {
    // holding a remote key fires quickly; build on the last target instead of
    // the position mpv hasn't reached yet
    final now = DateTime.now();
    final base =
        _seekTarget != null &&
            now.difference(_seekAt) < const Duration(milliseconds: 1200)
        ? _seekTarget!
        : player.state.position;
    final pos = base + Duration(seconds: seconds);
    final dur = player.state.duration;
    var target = pos < Duration.zero ? Duration.zero : pos;
    if (dur > Duration.zero && target > dur)
      target = dur - const Duration(milliseconds: 500);
    player.seek(target);
    _seekTarget = target;
    _seekAt = now;
    flashOsd(formatDuration(target.inMilliseconds / 1000));
    onUserActivity();
  }

  void changeVolume(double delta) {
    final v = (player.state.volume + delta).clamp(0.0, 150.0);
    player.setVolume(v);
    flashOsd('Ses: ${v.round()}%');
  }

  Future<void> setSubDelay(double v) async {
    subDelay = double.parse(v.toStringAsFixed(2));
    final p = player.platform;
    if (p is NativePlayer) await p.setProperty('sub-delay', '$subDelay');
    flashOsd('Altyazı gecikmesi: ${subDelay.toStringAsFixed(1)} sn');
  }

  Future<void> setSubScale(int percent) async {
    prefs.subtitleScale = percent;
    subScale.value = percent;
    final p = player.platform;
    if (p is NativePlayer)
      await p.setProperty('sub-scale', (percent / 100).toStringAsFixed(2));
  }

  Future<void> loadSubtitleFile() async {
    final res = await FilePicker.pickFile(
      dialogTitle: 'Altyazı dosyası seç',
      type: FileType.custom,
      allowedExtensions: ['srt', 'ass', 'ssa', 'vtt', 'sub', 'sup'],
    );
    final path = res?.path;
    if (path == null) return;
    final p = player.platform;
    if (p is NativePlayer) {
      await p.command([
        'sub-add',
        path,
        'select',
        path.split(RegExp(r'[\\/]')).last,
      ]);
      prefs.subtitleChoice = 'on:';
      flashOsd('Altyazı yüklendi');
    }
  }

  /// Selects a subtitle track chosen by the user and remembers the choice
  /// on this device (on/off and language) for the next videos.
  Future<void> selectSubtitle(SubtitleTrack t) async {
    await player.setSubtitleTrack(t);
    _rememberSubtitle(t.id == 'no' ? null : t);
    _needsTextureFor(t);
  }

  void _rememberSubtitle(SubtitleTrack? t) {
    prefs.subtitleChoice = t == null ? 'off' : 'on:${t.language ?? ''}';
  }

  void cycleSubtitle() {
    final subs = [
      SubtitleTrack.no(),
      ...player.state.tracks.subtitle.where(
        (t) => t.id != 'auto' && t.id != 'no',
      ),
    ];
    if (subs.length < 2) {
      flashOsd('Altyazı yok');
      return;
    }
    final cur = player.state.track.subtitle;
    final i = subs.indexWhere((t) => t.id == cur.id);
    final next = subs[(i + 1) % subs.length];
    selectSubtitle(next);
    flashOsd(
      next.id == 'no' ? 'Altyazı kapalı' : 'Altyazı: ${trackLabel(next)}',
    );
  }

  void cycleAudio() {
    final list = player.state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    if (list.length < 2) {
      flashOsd('Tek ses kanalı var');
      return;
    }
    final cur = player.state.track.audio;
    final i = list.indexWhere((t) => t.id == cur.id);
    final next = list[(i + 1) % list.length];
    player.setAudioTrack(next);
    flashOsd('Ses: ${trackLabel(next)}');
  }

  double _doubleTapX = 0;

  void _onDoubleTap() {
    if (ended.value) return;
    final w = MediaQuery.sizeOf(context).width;
    final step = prefs.seekStep;
    seekRelative(_doubleTapX < w / 2 ? -step : step);
  }

  void _onTap() {
    if (AppPlatform.isPhone) {
      // touch: a tap shows or hides the buttons, the buttons do the rest
      if (menuOpen.value) {
        menuOpen.value = false;
      } else if (controlsVisible.value && player.state.playing) {
        _hideTimer?.cancel();
        controlsVisible.value = false;
      } else {
        _showControls();
      }
      return;
    }
    final now = DateTime.now();
    final isDouble =
        now.difference(_lastTap) < const Duration(milliseconds: 300);
    _lastTap = now;
    if (menuOpen.value) {
      menuOpen.value = false;
      return;
    }
    if (ended.value) return;
    player.playOrPause();
    if (isDouble) {
      // double click: undo the pause toggle and switch fullscreen
      player.playOrPause();
      toggleFullscreen();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) {
      // one step per press (repeats and the key release are swallowed, so
      // Android doesn't also treat the press as "leave the screen")
      if (e is KeyDownEvent) handleBack();
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent && e is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    final step = prefs.seekStep;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final isOk =
        k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.gameButtonA;
    final isArrow =
        k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.arrowDown;
    if (_controlFocused) {
      // a button (or the menu) has focus: arrows move between buttons and
      // OK presses them; back steps out to the video
      if (isArrow || isOk || k == LogicalKeyboardKey.tab) {
        onUserActivity();
        return KeyEventResult.ignored;
      }
    }
    if (ended.value && (isArrow || isOk)) return KeyEventResult.ignored;
    if (isOk && AppPlatform.isTv) {
      // remote OK: pause/resume and show where we are
      player.playOrPause();
      _showControls();
      return KeyEventResult.handled;
    }
    if (AppPlatform.isTv &&
        (k == LogicalKeyboardKey.arrowUp ||
            k == LogicalKeyboardKey.arrowDown)) {
      focusControls();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlay) {
      player.play();
      onUserActivity();
    } else if (k == LogicalKeyboardKey.mediaPause) {
      player.pause();
      _showControls();
    } else if (k == LogicalKeyboardKey.mediaFastForward) {
      seekRelative(step * 3);
    } else if (k == LogicalKeyboardKey.mediaRewind) {
      seekRelative(-step * 3);
    } else if (k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.keyK ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      if (ended.value) return KeyEventResult.ignored;
      player.playOrPause();
      onUserActivity();
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.keyJ) {
      seekRelative(shift ? -60 : -step);
    } else if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.keyL) {
      seekRelative(shift ? 60 : step);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      changeVolume(5);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      changeVolume(-5);
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.f11) {
      toggleFullscreen();
    } else if (k == LogicalKeyboardKey.keyM) {
      final muted = player.state.volume == 0;
      player.setVolume(muted ? prefs.volume.clamp(10, 150) : 0);
      flashOsd(muted ? 'Ses açık' : 'Sessiz');
    } else if (k == LogicalKeyboardKey.keyS) {
      cycleSubtitle();
    } else if (k == LogicalKeyboardKey.keyA) {
      cycleAudio();
    } else if (k == LogicalKeyboardKey.keyN ||
        k == LogicalKeyboardKey.mediaTrackNext) {
      playNext();
    } else if (k == LogicalKeyboardKey.keyZ) {
      setSubDelay(subDelay - 0.1);
    } else if (k == LogicalKeyboardKey.keyX) {
      setSubDelay(subDelay + 0.1);
    } else if (k == LogicalKeyboardKey.bracketLeft) {
      final r = (player.state.rate - 0.25).clamp(0.25, 3.0);
      player.setRate(r);
      flashOsd('Hız: ${r}x');
    } else if (k == LogicalKeyboardKey.bracketRight) {
      final r = (player.state.rate + 0.25).clamp(0.25, 3.0);
      player.setRate(r);
      flashOsd('Hız: ${r}x');
    } else if (k == LogicalKeyboardKey.backspace) {
      close();
    } else if (k.keyLabel.length == 1 &&
        RegExp(r'[0-9]').hasMatch(k.keyLabel)) {
      final n = int.parse(k.keyLabel);
      final d = player.state.duration;
      if (d > Duration.zero) player.seek(d * (n / 10));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    AppPlatform.keepScreenOn(false);
    if (AppPlatform.isPhone && AppPlatform.isAndroid) {
      SystemChrome.setPreferredOrientations([]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (AppPlatform.isDesktop) windowManager.removeListener(this);
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _osdTimer?.cancel();
    _volumeSaveTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    if (!_closing) {
      // e.g. closed by route pop without close(): best effort final report
      final pos = player.state.position.inMilliseconds / 1000;
      final dur = player.state.duration.inMilliseconds / 1000;
      if (pos > 0 && dur > 0 && !ended.value) {
        api
            .reportProgress(item.id, pos, dur)
            .catchError((_) => const UserData());
      }
      if (AppPlatform.isDesktop)
        try {
          if (!_wasFullscreen) windowManager.setFullScreen(false);
          windowManager.setTitle('Home Stream');
        } catch (_) {}
    }
    VideoLayer.surface.removeListener(_onLayerSurface);
    final token = _layerToken;
    // mpv lets go of the layer's surface first, then the layer goes
    final disposed = player.dispose();
    if (layer) disposed.whenComplete(() => VideoLayer.hide(token));
    subScale.dispose();
    _focus.dispose();
    playFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _closing,
      // system back (when the key didn't reach the player first)
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) handleBack();
      },
      child: Scaffold(
        // on the TV video layer the video is under the app: keep it visible
        backgroundColor: layer ? Colors.transparent : Colors.black,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          // never a target of arrow navigation, only focused in code
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: ValueListenableBuilder<bool>(
            valueListenable: controlsVisible,
            builder: (context, visible, child) => MouseRegion(
              cursor: visible
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.none,
              onHover: (_) => onUserActivity(),
              child: child,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onTap,
                  // phones: double tap on the left/right half seeks
                  onDoubleTapDown: AppPlatform.isPhone
                      ? (d) => _doubleTapX = d.localPosition.dx
                      : null,
                  onDoubleTap: AppPlatform.isPhone ? _onDoubleTap : null,
                  child: layer
                      ? const SizedBox.expand()
                      : RepaintBoundary(
                          child: Video(
                            controller: controller!,
                            controls: NoVideoControls,
                            fill: Colors.black,
                            filterQuality: FilterQuality.medium,
                            subtitleViewConfiguration:
                                const SubtitleViewConfiguration(visible: false),
                          ),
                        ),
                ),
                if (layer) LayerSubtitles(state: this),
                // buffering spinner
                StreamBuilder<bool>(
                  stream: player.stream.buffering,
                  initialData: true,
                  builder: (context, snap) => IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: (snap.data ?? false) ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Center(
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                PlayerControls(state: this),
                NextEpisodePill(state: this),
                // OSD messages
                ValueListenableBuilder<String?>(
                  valueListenable: osd,
                  builder: (context, text, _) => IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: text == null ? 0 : 1,
                      duration: const Duration(milliseconds: 180),
                      child: Align(
                        alignment: const Alignment(0, -0.6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            text ?? '',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: ended,
                  builder: (context, isEnded, _) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: isEnded
                        ? EndScreen(state: this)
                        : const SizedBox.shrink(),
                  ),
                ),
                ValueListenableBuilder<String?>(
                  valueListenable: error,
                  builder: (context, err, _) => err == null
                      ? const SizedBox.shrink()
                      : _ErrorOverlay(state: this, message: err),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String trackLabel(dynamic t) {
  final lang = languageName((t.language as String?) ?? '');
  final title = (t.title as String?) ?? '';
  final parts = <String>[
    if (lang.isNotEmpty) lang,
    if (title.isNotEmpty && title != lang) title,
  ];
  if (parts.isEmpty) return 'Parça ${t.id}';
  return parts.join(' · ');
}

class _ErrorOverlay extends StatelessWidget {
  final PlayerScreenState state;
  final String message;
  const _ErrorOverlay({required this.state, required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: AppColors.danger,
            ),
            const SizedBox(height: 16),
            const Text(
              'Video oynatılamadı',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textDim),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PillButton(
                  primary: true,
                  icon: Icons.refresh_rounded,
                  label: 'Tekrar dene',
                  onPressed: () => state._open(
                    state.item,
                    state.player.state.position.inSeconds.toDouble(),
                  ),
                ),
                const SizedBox(width: 12),
                PillButton(
                  icon: Icons.arrow_back_rounded,
                  label: 'Geri dön',
                  onPressed: state.close,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Subtitles on the TV video layer, where mpv can't draw them: the current
/// subtitle text in white with a dark outline, like mpv's own style.
class LayerSubtitles extends StatelessWidget {
  final PlayerScreenState state;
  const LayerSubtitles({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<int>(
        valueListenable: state.subScale,
        builder: (context, scale, _) => StreamBuilder<List<String>>(
          stream: state.player.stream.subtitle,
          initialData: state.player.state.subtitle,
          builder: (context, snap) {
            final text = (snap.data?.firstOrNull ?? '').trim();
            if (text.isEmpty) return const SizedBox.shrink();
            final h = MediaQuery.sizeOf(context).height;
            // about mpv's default size (55 at 720 lines) at 100 %
            final size = h * 0.064 * scale / 100;
            final style = TextStyle(
              fontSize: size,
              height: 1.18,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            );
            return Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(h * 0.1, 0, h * 0.1, h * 0.055),
                child: Stack(
                  children: [
                    Text(
                      text,
                      textAlign: TextAlign.center,
                      style: style.copyWith(
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = size * 0.14
                          ..strokeJoin = StrokeJoin.round
                          ..color = Colors.black,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            offset: Offset(0, size * 0.05),
                            blurRadius: size * 0.08,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      text,
                      textAlign: TextAlign.center,
                      style: style.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
