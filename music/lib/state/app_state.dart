import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../audio/handler.dart';
import '../core/api.dart';
import '../core/discovery.dart';
import '../core/downloads.dart';
import '../core/image_cache.dart';
import '../core/models.dart';
import '../core/prefs.dart';

enum Stage { loading, setup, profiles, shell }

/// App-wide state: server connection, profile, likes, playlists and the
/// link between the player and the downloads.
class AppState extends ChangeNotifier {
  final Prefs prefs;
  final MusicHandler player;
  final Downloads downloads;

  AppState(this.prefs, this.player, this.downloads) {
    final s = player.settings;
    s.crossfade = prefs.crossfade;
    s.smartCrossfade = prefs.smartCrossfade;
    s.replayGain = prefs.replayGain;
    s.hiFi = prefs.hiFiOutput;
    s.volume = prefs.volume;
    s.pauseOnUnplug = prefs.pauseOnUnplug;
    player.resolver = _resolve;
    player.artResolver = _art;
    player.onPlayed = _played;
  }

  Stage stage = Stage.loading;
  ServerConfig? server;
  ApiClient? api;
  Profile? profile;
  List<Profile> profiles = [];
  bool online = false;
  String? error;

  /// Liked song ids of the profile (kept in sync locally).
  final liked = ValueNotifier<Set<String>>(<String>{});

  /// Playlists of the profile.
  final playlists = ValueNotifier<List<Playlist>>(const []);

  /// Bumped when library data changed (screens reload).
  final libraryVersion = ValueNotifier<int>(0);

  final _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;
  void toast(String m) => _messages.add(m);

  Timer? _pingTimer;

  // ---------- start ----------

  Future<void> start() async {
    final servers = prefs.servers;
    final active =
        servers.where((s) => s.id == prefs.activeServerId).firstOrNull ??
        servers.firstOrNull;
    if (active == null) {
      stage = Stage.setup;
      notifyListeners();
      return;
    }
    await connect(active, silent: true);
  }

  /// Connects to a server; without a connection it opens offline with the
  /// last profile, so downloaded music can still be played.
  Future<bool> connect(ServerConfig s, {bool silent = false}) async {
    server = s;
    error = null;
    api?.close();
    api = ApiClient(s.url);
    await downloads.open(s.id);
    try {
      final info = await api!.info(timeout: const Duration(seconds: 5));
      if (!info.music) {
        throw ApiException(
          'Bu sunucu müzik uygulamasını desteklemiyor. Sunucuyu güncelleyin.',
          400,
        );
      }
      if (info.name.isNotEmpty && info.name != s.name) {
        s.name = info.name;
        _saveServer(s);
      }
      profiles = await api!.profiles();
      _setOnline(true);
    } on ApiException catch (e) {
      _setOnline(false);
      error = e.message;
      if (!e.offline) {
        // reachable but wrong / old server
        stage = silent ? Stage.setup : stage;
        notifyListeners();
        return false;
      }
      // offline: open with the last profile when we know one
      final last = prefs.lastProfileJson(s.id);
      if (last != null) {
        try {
          final p = Profile.fromJson(jsonDecode(last) as Map<String, dynamic>);
          await _enterProfile(p);
          return true;
        } catch (_) {}
      }
      stage = Stage.setup;
      notifyListeners();
      return false;
    }
    prefs.activeServerId = s.id;
    final remembered = prefs.rememberedProfile(s.id);
    final p = profiles.where((x) => x.id == remembered).firstOrNull;
    if (p != null) {
      await _enterProfile(p);
    } else {
      stage = Stage.profiles;
      notifyListeners();
    }
    return true;
  }

  void _saveServer(ServerConfig s) {
    final list = prefs.servers;
    final i = list.indexWhere((x) => x.id == s.id || x.url == s.url);
    if (i >= 0) {
      list[i] = s;
    } else {
      list.add(s);
    }
    prefs.servers = list;
  }

  /// Adds (or updates) a server by URL and connects.
  Future<String?> addServer(String url, {String? name}) async {
    final u = normalizeServerUrl(url);
    if (u.isEmpty) return 'Adres girin';
    final probe = ApiClient(u);
    try {
      final info = await probe.info(timeout: const Duration(seconds: 6));
      if (!info.music) {
        return 'Bu sunucu müzik uygulamasını desteklemiyor. Sunucuyu güncelleyin.';
      }
      final s = ServerConfig(
        id: info.id.isEmpty ? u : info.id,
        name: name ?? info.name,
        url: u,
      );
      // a server that moved to a new address keeps its downloads and profile
      final list = prefs.servers
        ..removeWhere((x) => x.id == s.id || x.url == u);
      list.add(s);
      prefs.servers = list;
      prefs.activeServerId = s.id;
      if (server != null && server!.id != s.id) await player.reset();
      final ok = await connect(s);
      return ok ? null : error;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      probe.close();
    }
  }

  Future<List<DiscoveredServer>> discover() => discoverServers();

  void forgetServer(ServerConfig s) {
    prefs.servers = prefs.servers.where((x) => x.id != s.id).toList();
    if (prefs.activeServerId == s.id) prefs.activeServerId = null;
    notifyListeners();
  }

  void openSetup() {
    stage = Stage.setup;
    notifyListeners();
  }

  // ---------- profiles ----------

  Future<void> refreshProfiles() async {
    if (api == null) return;
    try {
      profiles = await api!.profiles();
      _setOnline(true);
    } on ApiException catch (e) {
      _handle(e);
    }
    notifyListeners();
  }

  Future<void> selectProfile(Profile p, {required bool remember}) async {
    if (server != null) {
      prefs.setRememberedProfile(server!.id, remember ? p.id : null);
    }
    await _enterProfile(p);
  }

  Future<void> _enterProfile(Profile p) async {
    final changed = profile?.id != p.id || player.serverId != server?.id;
    profile = p;
    api?.profileId = p.id;
    if (server != null) {
      prefs.setLastProfileJson(server!.id, jsonEncode(p.toJson()));
    }
    if (changed) {
      if (player.current.value != null) await player.reset();
      player.serverId = server?.id ?? '';
      player.profileId = p.id;
      liked.value = {};
      playlists.value = const [];
      // continue where the last session stopped (paused, not playing)
      await player.restore();
    }
    stage = Stage.shell;
    notifyListeners();
    if (online) {
      unawaited(refreshUserData());
      unawaited(_flushPlays());
    }
  }

  void switchProfile() {
    if (server != null) prefs.setRememberedProfile(server!.id, null);
    stage = Stage.profiles;
    if (online) refreshProfiles();
    notifyListeners();
  }

  // ---------- connection ----------

  void _setOnline(bool v) {
    final was = online;
    online = v;
    downloads.setConnection(api, v);
    _pingTimer?.cancel();
    if (!v) {
      _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) => ping());
    }
    if (v != was) {
      notifyListeners();
      if (v && profile != null) {
        unawaited(refreshUserData());
        unawaited(_flushPlays());
        libraryVersion.value++;
      }
    }
  }

  /// Checks the server again (pull to refresh, retry buttons, timer).
  Future<bool> ping() async {
    final a = api;
    if (a == null) return false;
    try {
      await a.info(timeout: const Duration(seconds: 4));
      _setOnline(true);
      if (stage == Stage.setup && profile == null) {
        profiles = await a.profiles();
        stage = Stage.profiles;
        notifyListeners();
      }
      return true;
    } on ApiException catch (e) {
      if (e.offline) _setOnline(false);
      return false;
    }
  }

  /// Marks the app offline when a request couldn't reach the server.
  void _handle(ApiException e) {
    if (e.offline) _setOnline(false);
  }

  /// Runs an API call; network failures flip the app to offline mode.
  Future<T?> call<T>(
    Future<T> Function(ApiClient api) f, {
    bool quiet = false,
  }) async {
    final a = api;
    if (a == null) return null;
    try {
      final r = await f(a);
      if (!online) _setOnline(true);
      return r;
    } on ApiException catch (e) {
      _handle(e);
      if (!quiet) toast(e.offline ? 'Sunucuya bağlanılamıyor' : e.message);
      return null;
    }
  }

  Future<void> refreshUserData() async {
    final a = api;
    if (a == null) return;
    try {
      final l = await a.liked();
      liked.value = {for (final t in l) t.id};
      playlists.value = await a.playlists();
      _syncDownloadedCollections(l);
    } on ApiException catch (e) {
      _handle(e);
    }
  }

  Future<void> refreshPlaylists() async {
    final r = await call((a) => a.playlists(), quiet: true);
    if (r != null) playlists.value = r;
  }

  /// Keeps downloaded playlists / liked songs up to date (new songs get downloaded).
  void _syncDownloadedCollections(List<Track> likedTracks) {
    final lc = downloads.collection('liked');
    if (lc != null) {
      lc.trackIds = [for (final t in likedTracks) t.id];
      downloads.download(likedTracks, collection: lc);
    }
  }

  // ---------- likes ----------

  bool isLiked(Track t) => liked.value.contains(t.id);

  Future<void> toggleLike(Track t) => setLiked([t], !isLiked(t));

  Future<void> setLiked(List<Track> tracks, bool on) async {
    if (tracks.isEmpty) return;
    if (!online) {
      toast('Beğenmek için sunucuya bağlı olmalısın');
      return;
    }
    final ids = tracks.map((t) => t.id).toList();
    final before = liked.value;
    final next = {...before};
    on ? next.addAll(ids) : next.removeAll(ids);
    liked.value = next;
    for (final t in tracks) {
      t.liked = on;
      player.updateTrack(t);
    }
    final ok = await call((a) => a.setLiked(ids, on).then((_) => true));
    if (ok != true) {
      liked.value = before;
      for (final t in tracks) {
        t.liked = !on;
        player.updateTrack(t);
      }
      return;
    }
    // a downloaded "Beğenilenler" follows the likes
    final lc = downloads.collection('liked');
    if (lc != null && on) {
      lc.trackIds = [...ids, ...lc.trackIds.where((x) => !ids.contains(x))];
      downloads.download(tracks, collection: lc);
    }
  }

  // ---------- playlists ----------

  Future<Playlist?> createPlaylist(
    String name, [
    List<Track> tracks = const [],
  ]) async {
    final p = await call(
      (a) => a.createPlaylist(name, tracks.map((t) => t.id).toList()),
    );
    if (p != null) {
      await refreshPlaylists();
      toast('"${p.name}" oluşturuldu');
    }
    return p;
  }

  Future<void> addToPlaylist(Playlist p, List<Track> tracks) async {
    final n = await call(
      (a) => a.addToPlaylist(p.id, tracks.map((t) => t.id).toList()),
    );
    if (n == null) return;
    await refreshPlaylists();
    if (n == 0) {
      toast('Zaten "${p.name}" listesinde');
    } else {
      toast(
        n == 1
            ? '"${p.name}" listesine eklendi'
            : '$n şarkı "${p.name}" listesine eklendi',
      );
      final dc = downloads.collection('playlist:${p.id}');
      if (dc != null) {
        dc.trackIds = [...dc.trackIds, ...tracks.map((t) => t.id)];
        downloads.download(tracks, collection: dc);
      }
    }
    libraryVersion.value++;
  }

  Future<bool> deletePlaylist(Playlist p) async {
    final ok = await call((a) => a.deletePlaylist(p.id).then((_) => true));
    if (ok == true) {
      await refreshPlaylists();
      libraryVersion.value++;
      return true;
    }
    return false;
  }

  // ---------- player glue ----------

  Future<String?> _resolve(Track t) async {
    final local = downloads.localPath(t.id);
    if (local != null && (prefs.preferDownloads || !online)) return local;
    final a = api;
    if (a != null && online) return a.streamUrl(t.id);
    if (local != null) return local;
    // maybe the connection came back: one quick check
    if (a != null && await ping()) return a.streamUrl(t.id);
    return null;
  }

  Future<Uri?> _art(Track t) async {
    final f = downloads.coverFile(t.coverId.isNotEmpty ? t.coverId : t.id);
    if (f != null) return Uri.file(f);
    final a = api;
    if (a == null || t.cover.isEmpty) return null;
    final url = a.coverUrl(t.cover, width: 640);
    final file = online
        ? await DiskCache.fileFor(url)
        : await DiskCache.cachedFile(url);
    return file == null ? null : Uri.file(file.path);
  }

  void _played(Track t) {
    final at = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sid = server?.id;
    final pid = profile?.id;
    if (sid == null || pid == null) return;
    if (online && api != null) {
      api!.reportPlayed(t.id, at).catchError((Object _) {
        _queuePlay(sid, pid, t.id, at);
      });
    } else {
      _queuePlay(sid, pid, t.id, at);
    }
  }

  void _queuePlay(String sid, String pid, String id, int at) {
    prefs.pendingPlays = [
      ...prefs.pendingPlays,
      {'s': sid, 'p': pid, 'id': id, 'at': at},
    ];
  }

  Future<void> _flushPlays() async {
    final all = prefs.pendingPlays;
    if (all.isEmpty || api == null || profile == null) return;
    final rest = <Map<String, dynamic>>[];
    for (final p in all) {
      if (p['s'] != server?.id || p['p'] != profile?.id) {
        rest.add(p);
        continue;
      }
      try {
        await api!.reportPlayed('${p['id']}', (p['at'] as num).toInt());
      } on ApiException catch (e) {
        if (e.offline) {
          rest.add(p);
        }
        // other errors (song gone): drop it
      }
    }
    prefs.pendingPlays = rest;
  }

  // ---------- settings ----------

  Future<void> applyPlayerSettings() async {
    final s = player.settings;
    prefs.crossfade = s.crossfade;
    prefs.smartCrossfade = s.smartCrossfade;
    prefs.replayGain = s.replayGain;
    prefs.hiFiOutput = s.hiFi;
    prefs.pauseOnUnplug = s.pauseOnUnplug;
    await player.applySettings();
    notifyListeners();
  }

  void clearRecentSearches() {
    prefs.recentSearches = [];
    notifyListeners();
  }

  /// Settings password for this run (server settings).
  String? adminPassword;

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }
}
