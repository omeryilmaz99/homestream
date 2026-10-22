import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path_provider/path_provider.dart';

import '../core/models.dart';
import '../core/platform.dart';

/// Returns a playable URI for a track (local file or stream URL), or null
/// when the track can't be played right now (offline and not downloaded).
typedef SourceResolver = Future<String?> Function(Track t);

/// Returns the notification / lock screen picture for a track.
typedef ArtResolver = Future<Uri?> Function(Track t);

class PlayerSettings {
  int crossfade; // seconds, 0 = off
  bool smartCrossfade; // no crossfade inside an album
  String replayGain; // off | track | album
  bool hiFi; // AudioTrack + float output
  double volume; // 0..100
  bool pauseOnUnplug;
  PlayerSettings({
    this.crossfade = 0,
    this.smartCrossfade = true,
    this.replayGain = 'off',
    this.hiFi = true,
    this.volume = 100,
    this.pauseOnUnplug = true,
  });
}

class _Deck {
  final mk.Player p;
  final int n;
  String? trackId;
  bool failed = false;
  int token = 0;
  Duration pos = Duration.zero;
  Duration dur = Duration.zero;
  _Deck(this.p, this.n);
}

/// The music player: two mpv players (for crossfades), the play queue,
/// shuffle / repeat, the media notification and the saved playback state.
class MusicHandler extends BaseAudioHandler {
  MusicHandler._();

  /// A player without audio output, for UI tests.
  @visibleForTesting
  MusicHandler.headless();

  static Future<MusicHandler> create() async {
    final h = await AudioService.init(
      builder: MusicHandler._,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.homestream.music.playback',
        androidNotificationChannelName: 'Müzik çalma',
        androidNotificationChannelDescription: 'Çalan şarkı ve kontroller',
        androidNotificationIcon: 'drawable/ic_stat_music',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: true,
        notificationColor: Color(0xFF1DB954),
        fastForwardInterval: Duration(seconds: 10),
        rewindInterval: Duration(seconds: 10),
      ),
    );
    await h._init();
    return h;
  }

  // ---- public state for the UI ----
  final current = ValueNotifier<Track?>(null);
  final queueList = ValueNotifier<List<Track>>(const []);
  final index = ValueNotifier<int>(-1);
  final playing = ValueNotifier<bool>(false);
  final buffering = ValueNotifier<bool>(false);
  final position = ValueNotifier<Duration>(Duration.zero);
  final duration = ValueNotifier<Duration>(Duration.zero);
  final shuffle = ValueNotifier<bool>(false);
  final repeat = ValueNotifier<AudioServiceRepeatMode>(
    AudioServiceRepeatMode.none,
  );
  final contextName = ValueNotifier<String>('');
  final sleepAt = ValueNotifier<DateTime?>(null);
  final sleepEndOfTrack = ValueNotifier<bool>(false);
  final _messages = StreamController<String>.broadcast();

  /// Short messages for the user (errors, offline, ...).
  Stream<String> get messages => _messages.stream;

  SourceResolver? resolver;
  ArtResolver? artResolver;

  /// Called once per play (after 30 s or half the song).
  void Function(Track t)? onPlayed;

  /// Called whenever the saved state changes (e.g. to show the mini player).
  String serverId = '';
  String profileId = '';

  final settings = PlayerSettings();

  late final List<_Deck> _decks;
  int _cur = 0;
  _Deck get _d => _decks[_cur];
  _Deck get _o => _decks[1 - _cur];

  List<Track> _queue = [];
  List<Track> _original = [];
  int _index = -1;

  Timer? _fadeTimer;
  _Deck? _fadingOut;
  bool _preloading = false;
  double _duck = 1;
  bool _resumeAfterInterruption = false;
  AudioSession? _session;
  int _errorRun = 0;
  String? _countedFor;
  double _listened = 0;
  Duration _lastPos = Duration.zero;
  DateTime _lastSave = DateTime(0);
  Timer? _sleepTimer;
  bool _sleepFading = false;
  bool _restoring = false;

  Future<void> _init() async {
    _decks = [
      _Deck(
        mk.Player(
          configuration: const mk.PlayerConfiguration(
            title: 'Home Müzik',
            bufferSize: 32 * 1024 * 1024,
          ),
        ),
        0,
      ),
      _Deck(
        mk.Player(
          configuration: const mk.PlayerConfiguration(
            title: 'Home Müzik',
            bufferSize: 32 * 1024 * 1024,
          ),
        ),
        1,
      ),
    ];
    for (final d in _decks) {
      await _configure(d);
      _listen(d);
    }
    try {
      final s = await AudioSession.instance;
      await s.configure(const AudioSessionConfiguration.music());
      _session = s;
      s.interruptionEventStream.listen(_onInterruption);
      s.becomingNoisyEventStream.listen((_) {
        if (settings.pauseOnUnplug && playing.value) pause();
      });
    } catch (_) {}
    _broadcast();
  }

  Future<void> _setProp(_Deck d, String k, String v) async {
    try {
      final np = d.p.platform;
      if (np is mk.NativePlayer) await np.setProperty(k, v);
    } catch (_) {}
  }

  Future<void> _configure(_Deck d) async {
    await _setProp(d, 'vid', 'no');
    await _setProp(d, 'audio-display', 'no');
    // a mini PC's sleeping hard disk can take a while to answer
    await _setProp(d, 'network-timeout', '30');
    await _setProp(
      d,
      'stream-lavf-o',
      'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=10',
    );
    await _setProp(d, 'cache-secs', '300');
    await _setProp(d, 'demuxer-readahead-secs', '120');
    await _setProp(d, 'audio-client-name', 'Home Müzik');
    await _applyAudioOutput(d);
    await _setProp(d, 'replaygain', settings.replayGain);
    await _setProp(d, 'replaygain-clip', 'no');
  }

  Future<void> _applyAudioOutput(_Deck d) async {
    if (!AppPlatform.isAndroid) return;
    if (settings.hiFi) {
      await _setProp(d, 'audiotrack-pcm-float', 'yes');
      await _setProp(d, 'ao', 'audiotrack,opensles,');
    } else {
      await _setProp(d, 'ao', 'opensles,audiotrack,');
    }
  }

  void _listen(_Deck d) {
    d.p.stream.position.listen((p) {
      d.pos = p;
      if (identical(d, _d)) _onPosition(p);
    });
    d.p.stream.duration.listen((v) {
      d.dur = v;
      if (identical(d, _d) && v > Duration.zero) {
        duration.value = v;
        _updateMediaDuration(v);
      }
    });
    d.p.stream.playing.listen((v) {
      if (identical(d, _d) && !_restoring) {
        if (playing.value != v) {
          playing.value = v;
          AppPlatform.keepAwake(v);
          _broadcast();
          if (!v) _save();
        }
      }
    });
    d.p.stream.buffering.listen((v) {
      if (identical(d, _d) && buffering.value != v) {
        buffering.value = v;
        _broadcast();
      }
    });
    d.p.stream.completed.listen((v) {
      if (v && identical(d, _d) && d.trackId != null) _onCompleted();
    });
    d.p.stream.error.listen((e) => _onError(d, e));
  }

  // ---------- volume ----------

  /// mpv's volume is cubic: 50 is about -18 dB. Convert a linear gain.
  double _vol(double gain) {
    final g = gain.clamp(0.0, 1.0) * _duck;
    return 100 * math.pow(g, 1 / 3).toDouble() * (settings.volume / 100);
  }

  Future<void> setVolume(double v) async {
    settings.volume = v.clamp(0, 100);
    if (_fadeTimer == null) await _d.p.setVolume(_vol(1));
  }

  // ---------- loading ----------

  Future<bool> _load(
    _Deck d,
    Track t, {
    Duration start = Duration.zero,
    bool play = false,
    double gain = 1,
  }) async {
    final token = ++d.token;
    final uri = await resolver?.call(t);
    if (token != d.token) return false;
    if (uri == null) {
      d.trackId = null;
      d.failed = true;
      return false;
    }
    d.trackId = t.id;
    d.failed = false;
    d.pos = start;
    d.dur = Duration(milliseconds: (t.duration * 1000).round());
    await d.p.setVolume(_vol(gain));
    await d.p.open(
      mk.Media(uri, start: start > Duration.zero ? start : null),
      play: play,
    );
    return token == d.token;
  }

  Future<void> _unload(_Deck d) async {
    d.token++;
    d.trackId = null;
    d.failed = false;
    try {
      await d.p.stop();
    } catch (_) {}
  }

  int? _nextIndex([int? from]) {
    final i = from ?? _index;
    if (_queue.isEmpty) return null;
    if (i + 1 < _queue.length) return i + 1;
    if (repeat.value == AudioServiceRepeatMode.all) return 0;
    return null;
  }

  Future<void> _preload() async {
    if (_preloading) return;
    final ni = _nextIndex();
    if (ni == null) return;
    final t = _queue[ni];
    if (_o.trackId == t.id && !_o.failed) return;
    _preloading = true;
    try {
      await _load(_o, t, gain: 0);
    } finally {
      _preloading = false;
    }
  }

  // ---------- position, crossfade, counting ----------

  void _onPosition(Duration p) {
    final prev = _lastPos;
    _lastPos = p;
    position.value = p;
    final t = current.value;
    if (t == null) return;
    // play count
    final delta = (p - prev).inMilliseconds / 1000;
    if (playing.value && delta > 0 && delta < 2) {
      _listened += delta;
      if (_listened > 3) _errorRun = 0;
      final need = math.min(30.0, math.max(t.duration, 1) * 0.5);
      if (_countedFor != t.id && _listened >= need) {
        _countedFor = t.id;
        t.playCount++;
        t.lastPlayedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        onPlayed?.call(t);
      }
    }
    if (!playing.value) return;
    final dur = _d.dur > Duration.zero ? _d.dur : duration.value;
    if (dur <= Duration.zero) return;
    final left = dur - p;
    final cf = _crossfadeFor(t);
    // load the next song a little before the end
    if (left < Duration(seconds: cf + 25)) _preload();
    if (cf > 0 &&
        _fadeTimer == null &&
        !sleepEndOfTrack.value &&
        repeat.value != AudioServiceRepeatMode.one &&
        left <= Duration(seconds: cf) &&
        dur > Duration(seconds: cf * 2 + 5)) {
      _startCrossfade(cf);
    }
    if (DateTime.now().difference(_lastSave).inSeconds >= 5) _save();
  }

  int _crossfadeFor(Track t) {
    final cf = settings.crossfade;
    if (cf <= 0) return 0;
    final ni = _nextIndex();
    if (ni == null) return 0;
    final n = _queue[ni];
    if (settings.smartCrossfade &&
        t.albumId.isNotEmpty &&
        t.albumId == n.albumId &&
        n.trackNo == t.trackNo + 1) {
      return 0; // gapless album: keep the songs flowing into each other
    }
    return cf;
  }

  Future<void> _startCrossfade(int seconds) async {
    final ni = _nextIndex();
    if (ni == null) return;
    final next = _queue[ni];
    final outDeck = _d;
    final inDeck = _o;
    // mark as started so position ticks don't start it twice
    _fadeTimer = Timer(const Duration(days: 1), () {});
    if (inDeck.trackId != next.id || inDeck.failed) {
      final ok = await _load(inDeck, next, gain: 0);
      if (!ok) {
        _fadeTimer?.cancel();
        _fadeTimer = null;
        return; // the normal end-of-song path takes over
      }
    }
    if (!identical(outDeck, _d)) return;
    await inDeck.p.setVolume(0);
    await inDeck.p.play();
    _cur = inDeck.n;
    _fadingOut = outDeck;
    _setIndex(ni);
    final total = seconds * 1000;
    final started = DateTime.now();
    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 50), (tm) {
      final x = (DateTime.now().difference(started).inMilliseconds / total)
          .clamp(0.0, 1.0);
      // equal power curves
      outDeck.p.setVolume(_vol(math.cos(x * math.pi / 2)));
      inDeck.p.setVolume(_vol(math.sin(x * math.pi / 2)));
      if (x >= 1) _finishFade();
    });
  }

  /// Ends a running crossfade right away (seek, skip, pause...).
  void _finishFade() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    final out = _fadingOut;
    _fadingOut = null;
    if (out != null && !identical(out, _d)) _unload(out);
    _d.p.setVolume(_vol(1));
  }

  Future<void> _onCompleted() async {
    if (_fadeTimer != null) return;
    if (repeat.value == AudioServiceRepeatMode.one) {
      await _d.p.seek(Duration.zero);
      await _d.p.play();
      _countedFor = null;
      _listened = 0;
      return;
    }
    final ni = _nextIndex();
    if (sleepEndOfTrack.value) {
      sleepEndOfTrack.value = false;
      if (ni != null) {
        await _advanceTo(ni, play: false);
      } else {
        await _d.p.pause();
      }
      _messages.add('Uyku zamanlayıcısı: müzik durduruldu');
      return;
    }
    if (ni == null) {
      // end of the queue: stay on the last song, paused at the start
      await _d.p.pause();
      await _d.p.seek(Duration.zero);
      playing.value = false;
      AppPlatform.keepAwake(false);
      _broadcast();
      _save();
      return;
    }
    await _advanceTo(ni, play: true);
  }

  Future<void> _advanceTo(int i, {required bool play, int tries = 0}) async {
    if (i < 0 || i >= _queue.length) return;
    _finishFade();
    final t = _queue[i];
    final o = _o;
    _setIndex(i);
    if (o.trackId == t.id && !o.failed && o.pos < const Duration(seconds: 1)) {
      final old = _d;
      _cur = o.n;
      await o.p.setVolume(_vol(1));
      if (play) {
        await _activate();
        await o.p.play();
      }
      _unload(old);
    } else {
      _unload(o);
      final ok = await _load(_d, t, play: play && await _activate());
      if (!ok && _d.failed) {
        await _skipUnplayable(i, play: play, tries: tries);
        return;
      }
    }
    _broadcast();
    _save();
  }

  /// Offline and not downloaded: go on with the next song that can be played.
  Future<void> _skipUnplayable(
    int i, {
    required bool play,
    int tries = 0,
  }) async {
    final t = _queue[i];
    if (tries == 0) {
      _messages.add('"${t.title}" çalınamıyor (çevrimdışı ve indirilmemiş)');
    }
    final ni = _nextIndex(i);
    if (ni == null || tries > _queue.length) {
      playing.value = false;
      _broadcast();
      return;
    }
    await _advanceTo(ni, play: play, tries: tries + 1);
  }

  void _onError(_Deck d, String e) {
    if (!identical(d, _d) || d.trackId == null) {
      if (identical(d, _o)) d.failed = true; // preload failed: retried later
      return;
    }
    final low = e.toLowerCase();
    if (low.contains('audio device') || low.contains('audio output')) {
      if (settings.hiFi) {
        // some phones refuse the float output: use the safe one
        settings.hiFi = false;
        for (final x in _decks) {
          _applyAudioOutput(x);
        }
        _messages.add('Ses çıkışı uyumlu moda alındı');
        final p = position.value;
        final t = current.value;
        if (t != null) _load(_d, t, start: p, play: true);
      }
      return;
    }
    // mpv also logs recoverable errors: only act when the song doesn't move
    final before = d.pos;
    final id = d.trackId;
    Timer(const Duration(milliseconds: 1500), () {
      if (!identical(d, _d) || d.trackId != id) return;
      if (d.pos > before + const Duration(milliseconds: 300)) return;
      if (playing.value && d.pos > Duration.zero) return;
      _errorRun++;
      final t = current.value;
      _messages.add('Şarkı çalınamadı${t == null ? '' : ': ${t.title}'}');
      if (_errorRun >= 4) {
        _errorRun = 0;
        pause();
        _messages.add(
          'Arka arkaya şarkılar çalınamadı. Sunucu bağlantısını kontrol et.',
        );
        return;
      }
      final ni = _nextIndex();
      if (ni != null) _advanceTo(ni, play: true);
    });
  }

  // ---------- state ----------

  void _setIndex(int i) {
    _index = i;
    index.value = i;
    final t = (i >= 0 && i < _queue.length) ? _queue[i] : null;
    current.value = t;
    _countedFor = null;
    _listened = 0;
    _lastPos = Duration.zero;
    position.value = Duration.zero;
    duration.value = Duration(
      milliseconds: ((t?.duration ?? 0) * 1000).round(),
    );
    _publishMediaItem(t);
  }

  Future<void> _publishMediaItem(Track? t) async {
    if (t == null) {
      mediaItem.add(null);
      return;
    }
    MediaItem item(Uri? art) => MediaItem(
      id: t.id,
      title: t.title,
      artist: t.artist,
      album: t.album.isEmpty ? null : t.album,
      duration: duration.value > Duration.zero ? duration.value : null,
      artUri: art,
      genre: t.genre.isEmpty ? null : t.genre,
    );
    mediaItem.add(item(null));
    try {
      final art = await artResolver?.call(t);
      if (current.value?.id == t.id && art != null) mediaItem.add(item(art));
    } catch (_) {}
  }

  void _updateMediaDuration(Duration d) {
    final m = mediaItem.value;
    if (m != null && m.duration != d) mediaItem.add(m.copyWith(duration: d));
  }

  void _publishQueue() {
    queueList.value = List.unmodifiable(_queue);
    queue.add([
      for (final t in _queue)
        MediaItem(id: t.id, title: t.title, artist: t.artist, album: t.album),
    ]);
  }

  void _broadcast() {
    final hasTrack = current.value != null;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing.value ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToQueueItem,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: !hasTrack
            ? AudioProcessingState.idle
            : buffering.value
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: playing.value,
        updatePosition: position.value,
        bufferedPosition: position.value,
        speed: 1,
        queueIndex: _index < 0 ? null : _index,
        shuffleMode: shuffle.value
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: repeat.value,
      ),
    );
  }

  Future<bool> _activate() async {
    final s = _session;
    if (s == null) return true;
    try {
      return await s.setActive(true);
    } catch (_) {
      return true;
    }
  }

  void _onInterruption(AudioInterruptionEvent e) {
    if (e.begin) {
      switch (e.type) {
        case AudioInterruptionType.duck:
          _duck = 0.3;
          if (_fadeTimer == null) _d.p.setVolume(_vol(1));
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          if (playing.value) {
            _resumeAfterInterruption = e.type == AudioInterruptionType.pause;
            pause();
          }
      }
    } else {
      switch (e.type) {
        case AudioInterruptionType.duck:
          _duck = 1;
          if (_fadeTimer == null) _d.p.setVolume(_vol(1));
        case AudioInterruptionType.pause:
          if (_resumeAfterInterruption) play();
          _resumeAfterInterruption = false;
        case AudioInterruptionType.unknown:
          _resumeAfterInterruption = false;
      }
    }
  }

  // ---------- public controls ----------

  /// Starts playing a list. [start] -1 with [shuffled] picks a random first song.
  Future<void> playTracks(
    List<Track> tracks, {
    int start = 0,
    bool shuffled = false,
    String context = '',
  }) async {
    if (tracks.isEmpty) return;
    _finishFade();
    _original = List.of(tracks);
    contextName.value = context;
    shuffle.value = shuffled;
    if (shuffled) {
      final rest = List.of(tracks);
      Track? first;
      if (start >= 0 && start < rest.length) first = rest.removeAt(start);
      rest.shuffle();
      _queue = [?first, ...rest];
      start = 0;
    } else {
      _queue = List.of(tracks);
      start = start.clamp(0, tracks.length - 1);
    }
    _errorRun = 0;
    _publishQueue();
    _unload(_o);
    _setIndex(start);
    final ok = await _load(_d, _queue[start], play: await _activate());
    if (!ok && _d.failed) await _skipUnplayable(start, play: true);
    _broadcast();
    _save();
  }

  @override
  Future<void> play() async {
    if (current.value == null) return;
    if (_sleepFading) return;
    if (!await _activate()) return;
    if (_d.trackId == null || _d.failed) {
      final t = current.value!;
      final ok = await _load(_d, t, start: position.value, play: true);
      if (!ok && _d.failed) await _skipUnplayable(_index, play: true);
      return;
    }
    await _d.p.setVolume(_vol(1));
    await _d.p.play();
  }

  @override
  Future<void> pause() async {
    _finishFade();
    await _d.p.pause();
    _save();
  }

  Future<void> togglePlay() => playing.value ? pause() : play();

  @override
  Future<void> seek(Duration position) async {
    _finishFade();
    if (_d.trackId == null && current.value != null) {
      await _load(_d, current.value!, start: position, play: false);
    } else {
      await _d.p.seek(position);
    }
    this.position.value = position;
    _lastPos = position;
    _broadcast();
  }

  @override
  Future<void> fastForward() =>
      seek(position.value + const Duration(seconds: 10));

  @override
  Future<void> rewind() {
    final p = position.value - const Duration(seconds: 10);
    return seek(p < Duration.zero ? Duration.zero : p);
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;
    final ni = _nextIndex();
    if (ni == null) {
      // end of the list: back to the start, paused
      await _advanceTo(0, play: false);
      return;
    }
    await _advanceTo(ni, play: true);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    if (position.value > const Duration(seconds: 3) || _index == 0) {
      if (_index == 0 &&
          repeat.value == AudioServiceRepeatMode.all &&
          position.value <= const Duration(seconds: 3)) {
        await _advanceTo(_queue.length - 1, play: true);
        return;
      }
      await seek(Duration.zero);
      return;
    }
    await _advanceTo(_index - 1, play: true);
  }

  @override
  Future<void> skipToQueueItem(int index) => _advanceTo(index, play: true);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      setShuffle(shuffleMode != AudioServiceShuffleMode.none);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    repeat.value = repeatMode == AudioServiceRepeatMode.group
        ? AudioServiceRepeatMode.all
        : repeatMode;
    _unload(_o); // the next song may change
    _broadcast();
    _save();
  }

  Future<void> cycleRepeat() => setRepeatMode(switch (repeat.value) {
    AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
    AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
    _ => AudioServiceRepeatMode.none,
  });

  Future<void> setShuffle(bool on) async {
    if (on == shuffle.value) return;
    final cur = current.value;
    shuffle.value = on;
    if (_queue.isEmpty || cur == null) {
      _broadcast();
      return;
    }
    if (on) {
      _original = List.of(_queue);
      final rest = List.of(_queue)..removeAt(_index);
      rest.shuffle();
      _queue = [cur, ...rest];
      _index = 0;
    } else {
      // back to the original order (songs added meanwhile stay at the end)
      final inQueue = _queue.map((t) => t.id).toSet();
      final ordered = _original.where((t) => inQueue.remove(t.id)).toList();
      ordered.addAll(_queue.where((t) => inQueue.contains(t.id)));
      _queue = ordered;
      _index = math.max(0, _queue.indexWhere((t) => t.id == cur.id));
    }
    index.value = _index;
    _unload(_o);
    _publishQueue();
    _broadcast();
    _save();
  }

  /// Puts songs right after the current one.
  void playNext(List<Track> tracks) {
    if (tracks.isEmpty) return;
    if (_queue.isEmpty) {
      playTracks(tracks);
      return;
    }
    _queue.insertAll(_index + 1, tracks);
    final oi = _original.indexWhere((t) => t.id == current.value?.id);
    _original.insertAll(oi < 0 ? _original.length : oi + 1, tracks);
    _unload(_o);
    _publishQueue();
    _save();
  }

  /// Adds songs to the end of the queue.
  void addToQueue(List<Track> tracks) {
    if (tracks.isEmpty) return;
    if (_queue.isEmpty) {
      playTracks(tracks);
      return;
    }
    _queue.addAll(tracks);
    _original.addAll(tracks);
    if (_index == _queue.length - tracks.length - 1) _unload(_o);
    _publishQueue();
    _save();
  }

  Future<void> removeFromQueue(int i) async {
    if (i < 0 || i >= _queue.length) return;
    if (i == _index) {
      if (_queue.length == 1) {
        await clearQueue();
        return;
      }
      final wasPlaying = playing.value;
      final removed = _queue.removeAt(i);
      _original.removeWhere((t) => identical(t, removed));
      if (_index >= _queue.length) _index = 0;
      _publishQueue();
      await _advanceTo(_index, play: wasPlaying);
      return;
    }
    final removed = _queue.removeAt(i);
    _original.removeWhere((t) => identical(t, removed));
    if (i < _index) _index--;
    index.value = _index;
    if (i == _index + 1) _unload(_o);
    _publishQueue();
    _broadcast();
    _save();
  }

  void moveQueueItem(int from, int to) {
    if (from == to || from < 0 || from >= _queue.length) return;
    final t = _queue.removeAt(from);
    to = to.clamp(0, _queue.length);
    _queue.insert(to, t);
    if (from == _index) {
      _index = to;
    } else {
      if (from < _index && to >= _index) _index--;
      if (from > _index && to <= _index) _index++;
    }
    index.value = _index;
    _unload(_o);
    _publishQueue();
    _save();
  }

  Future<void> clearQueue() async {
    _finishFade();
    for (final d in _decks) {
      await _unload(d);
    }
    _queue = [];
    _original = [];
    contextName.value = '';
    _setIndex(-1);
    _publishQueue();
    playing.value = false;
    AppPlatform.keepAwake(false);
    _broadcast();
    await _deleteSaved();
  }

  /// Replaces track objects (e.g. liked changed) everywhere in the queue.
  void updateTrack(Track t) {
    var changed = false;
    for (var i = 0; i < _queue.length; i++) {
      if (_queue[i].id == t.id) {
        _queue[i].liked = t.liked;
        changed = true;
      }
    }
    if (changed) {
      if (current.value?.id == t.id) {
        current.value?.liked = t.liked;
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        current.notifyListeners();
      }
      _save();
    }
  }

  Future<void> applySettings() async {
    for (final d in _decks) {
      await _setProp(d, 'replaygain', settings.replayGain);
      await _applyAudioOutput(d);
    }
    if (_fadeTimer == null) await _d.p.setVolume(_vol(1));
    _unload(_o);
  }

  // ---------- sleep timer ----------

  void setSleepTimer(Duration? d, {bool endOfTrack = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepAt.value = null;
    sleepEndOfTrack.value = endOfTrack;
    if (d == null) return;
    sleepAt.value = DateTime.now().add(d);
    _sleepTimer = Timer(d, _sleepNow);
  }

  Future<void> _sleepNow() async {
    sleepAt.value = null;
    _sleepTimer = null;
    if (!playing.value) return;
    // fade out over 8 seconds
    _finishFade();
    _sleepFading = true;
    for (var i = 20; i >= 0; i--) {
      await _d.p.setVolume(_vol(i / 20));
      await Future.delayed(const Duration(milliseconds: 400));
    }
    _sleepFading = false;
    await pause();
    await _d.p.setVolume(_vol(1));
    _messages.add('Uyku zamanlayıcısı: müzik durduruldu');
  }

  // ---------- android task & stop ----------

  @override
  Future<void> onTaskRemoved() async {
    // swiped away from recents: keep playing, but drop the notification when paused
    if (!playing.value) await stop();
  }

  @override
  Future<void> stop() async {
    _finishFade();
    await _save(force: true);
    await _d.p.pause();
    playing.value = false;
    AppPlatform.keepAwake(false);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    await super.stop();
  }

  // ---------- saved playback state ----------

  static Future<File> _stateFile() async {
    final d = await getApplicationSupportDirectory();
    return File('${d.path}${Platform.pathSeparator}playback.json');
  }

  Future<void> _deleteSaved() async {
    try {
      final f = await _stateFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  bool _saving = false;

  /// Saves the queue, the song and the position (to continue after a restart).
  Future<void> _save({bool force = false}) async {
    if (_restoring || _queue.isEmpty || serverId.isEmpty) return;
    if (_saving && !force) return;
    _saving = true;
    _lastSave = DateTime.now();
    try {
      var start = 0;
      var end = _queue.length;
      if (_queue.length > 1000) {
        start = math.max(0, _index - 200);
        end = math.min(_queue.length, start + 1000);
      }
      final q = _queue.sublist(start, end);
      final ids = q.map((t) => t.id).toSet();
      final data = {
        'v': 1,
        'server': serverId,
        'profile': profileId,
        'queue': [for (final t in q) t.toJson()],
        'original': [
          for (final t in _original)
            if (ids.contains(t.id)) t.id,
        ],
        'index': _index - start,
        'position': position.value.inMilliseconds,
        'shuffle': shuffle.value,
        'repeat': repeat.value.name,
        'context': contextName.value,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      };
      final f = await _stateFile();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(f.path);
    } catch (_) {
    } finally {
      _saving = false;
    }
  }

  /// Saves now (app going to the background).
  Future<void> saveNow() => _save(force: true);

  /// Loads the last session paused at the same second (does not start playing).
  Future<bool> restore() async {
    if (current.value != null) return true;
    try {
      final f = await _stateFile();
      if (!await f.exists()) return false;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (j['server'] != serverId || j['profile'] != profileId) return false;
      final q = (j['queue'] as List)
          .whereType<Map<String, dynamic>>()
          .map(Track.fromJson)
          .toList();
      if (q.isEmpty) return false;
      final byId = {for (final t in q) t.id: t};
      _queue = q;
      _original = [
        for (final id in (j['original'] as List? ?? []))
          if (byId[id] != null) byId[id]!,
      ];
      if (_original.length != _queue.length) _original = List.of(_queue);
      shuffle.value = j['shuffle'] == true;
      repeat.value = AudioServiceRepeatMode.values.firstWhere(
        (m) => m.name == j['repeat'],
        orElse: () => AudioServiceRepeatMode.none,
      );
      contextName.value = '${j['context'] ?? ''}';
      final i = ((j['index'] as num?)?.toInt() ?? 0).clamp(0, q.length - 1);
      final pos = Duration(milliseconds: (j['position'] as num?)?.toInt() ?? 0);
      _publishQueue();
      _setIndex(i);
      position.value = pos;
      _lastPos = pos;
      _restoring = true;
      try {
        await _load(_d, q[i], start: pos, play: false);
      } finally {
        _restoring = false;
      }
      position.value = pos;
      playing.value = false;
      _broadcast();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Forgets the player state (profile or server change).
  Future<void> reset() async {
    _finishFade();
    for (final d in _decks) {
      await _unload(d);
    }
    _queue = [];
    _original = [];
    contextName.value = '';
    _setIndex(-1);
    _publishQueue();
    playing.value = false;
    AppPlatform.keepAwake(false);
    _broadcast();
  }
}
