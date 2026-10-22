import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'models.dart';

/// A downloaded group shown as one item (playlist, album, folder, liked).
class DownloadCollection {
  final String key; // "playlist:<id>", "album:<id>", "folder:<path>", "liked"
  final String type;
  final String id;
  String name;
  String subtitle;
  List<String> trackIds;
  final int at;
  DownloadCollection({
    required this.key,
    required this.type,
    required this.id,
    required this.name,
    this.subtitle = '',
    required this.trackIds,
    required this.at,
  });
  Map<String, dynamic> toJson() => {
    'key': key,
    'type': type,
    'id': id,
    'name': name,
    'subtitle': subtitle,
    'trackIds': trackIds,
    'at': at,
  };
  factory DownloadCollection.fromJson(Map<String, dynamic> j) =>
      DownloadCollection(
        key: '${j['key']}',
        type: '${j['type']}',
        id: '${j['id']}',
        name: '${j['name']}',
        subtitle: '${j['subtitle'] ?? ''}',
        trackIds: (j['trackIds'] as List? ?? []).map((e) => '$e').toList(),
        at: (j['at'] as num?)?.toInt() ?? 0,
      );
}

class DownloadedTrack {
  final Track track;
  final String file; // name inside the tracks folder
  final int size;
  final int at;
  DownloadedTrack(this.track, this.file, this.size, this.at);
  Map<String, dynamic> toJson() => {
    'track': track.toJson(),
    'file': file,
    'size': size,
    'at': at,
  };
  factory DownloadedTrack.fromJson(Map<String, dynamic> j) => DownloadedTrack(
    Track.fromJson(j['track'] as Map<String, dynamic>),
    '${j['file']}',
    (j['size'] as num?)?.toInt() ?? 0,
    (j['at'] as num?)?.toInt() ?? 0,
  );
}

enum DlState { queued, running, failed }

class DownloadTask {
  final Track track;
  DlState state;
  int received = 0;
  int total = 0;
  String? error;
  DownloadTask(this.track, [this.state = DlState.queued]);
  double get progress => total > 0 ? received / total : 0;
}

/// Downloads songs into the app's private storage so they play without the
/// server ("Program içinden dinlenecek"). One store per server.
class Downloads extends ChangeNotifier {
  Directory? _root;
  String _serverId = '';
  ApiClient? _api;
  bool _online = false;

  final Map<String, DownloadedTrack> _done = {};
  final Map<String, DownloadCollection> _collections = {};
  final Map<String, DownloadTask> _tasks = {}; // queued, running, failed
  final Map<String, String> _covers = {}; // coverId → file path
  int _running = 0;
  Timer? _saveTimer;
  final http.Client _http = http.Client();
  final _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  static const _parallel = 2;

  Future<Directory> _base() async {
    final d = await getApplicationSupportDirectory();
    return Directory('${d.path}${Platform.pathSeparator}downloads');
  }

  Directory get _tracksDir => Directory('${_root!.path}/tracks');
  Directory get _coversDir => Directory('${_root!.path}/covers');
  File get _indexFile => File('${_root!.path}/index.json');

  /// Opens the store of a server (keeps working without a connection).
  Future<void> open(String serverId) async {
    if (_serverId == serverId && _root != null) return;
    await _flush();
    _serverId = serverId;
    _done.clear();
    _collections.clear();
    _tasks.clear();
    _covers.clear();
    final safe = serverId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    _root = Directory('${(await _base()).path}/$safe');
    await _tracksDir.create(recursive: true);
    await _coversDir.create(recursive: true);
    try {
      if (await _indexFile.exists()) {
        final j =
            jsonDecode(await _indexFile.readAsString()) as Map<String, dynamic>;
        for (final e
            in (j['tracks'] as List? ?? []).whereType<Map<String, dynamic>>()) {
          final d = DownloadedTrack.fromJson(e);
          if (await File('${_tracksDir.path}/${d.file}').exists()) {
            _done[d.track.id] = d;
          }
        }
        for (final e
            in (j['collections'] as List? ?? [])
                .whereType<Map<String, dynamic>>()) {
          final c = DownloadCollection.fromJson(e);
          _collections[c.key] = c;
        }
        for (final e
            in (j['pending'] as List? ?? [])
                .whereType<Map<String, dynamic>>()) {
          final t = Track.fromJson(e);
          if (!_done.containsKey(t.id)) _tasks[t.id] = DownloadTask(t);
        }
      }
    } catch (_) {
      // a broken index: keep the files, rebuild what we can next time
    }
    try {
      await for (final f in _coversDir.list()) {
        if (f is File && f.path.endsWith('.jpg')) {
          final name = f.uri.pathSegments.last;
          _covers[name.substring(0, name.length - 4)] = f.path;
        }
      }
    } catch (_) {}
    notifyListeners();
    _pump();
  }

  /// The API to download with (null or offline pauses the queue).
  void setConnection(ApiClient? api, bool online) {
    _api = api;
    final wasOnline = _online;
    _online = online && api != null;
    if (_online && !wasOnline) {
      // retry failed downloads after the connection came back
      for (final t in _tasks.values) {
        if (t.state == DlState.failed) t.state = DlState.queued;
      }
      _pump();
    }
  }

  bool isDownloaded(String trackId) => _done.containsKey(trackId);
  DownloadTask? task(String trackId) => _tasks[trackId];
  bool get hasActive => _tasks.values.any((t) => t.state != DlState.failed);
  int get activeCount =>
      _tasks.values.where((t) => t.state != DlState.failed).length;
  List<DownloadTask> get tasks => _tasks.values.toList();

  String? localPath(String trackId) {
    final d = _done[trackId];
    if (d == null || _root == null) return null;
    return '${_tracksDir.path}/${d.file}';
  }

  String? coverFile(String coverId) => _covers[coverId];

  List<Track> get tracks {
    final l = _done.values.toList()..sort((a, b) => b.at.compareTo(a.at));
    return [for (final d in l) d.track];
  }

  Track? track(String id) => _done[id]?.track;

  List<DownloadCollection> get collections {
    final l = _collections.values.toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return l;
  }

  DownloadCollection? collection(String key) => _collections[key];

  List<Track> collectionTracks(DownloadCollection c) => [
    for (final id in c.trackIds)
      if (_done[id] != null) _done[id]!.track,
  ];

  /// 0..1 for a group of songs; 1 when all are downloaded.
  double progressOf(Iterable<String> ids) {
    var n = 0, done = 0;
    var part = 0.0;
    for (final id in ids) {
      n++;
      if (_done.containsKey(id)) {
        done++;
      } else if (_tasks[id] != null) {
        part += _tasks[id]!.progress;
      }
    }
    if (n == 0) return 0;
    return (done + part) / n;
  }

  bool allDownloaded(Iterable<String> ids) =>
      ids.isNotEmpty && ids.every(_done.containsKey);
  bool anyQueued(Iterable<String> ids) => ids.any(_tasks.containsKey);

  int get totalBytes => _done.values.fold(0, (a, d) => a + d.size);

  /// Queues songs; [collection] also remembers them as a group.
  void download(List<Track> tracks, {DownloadCollection? collection}) {
    if (_root == null) return;
    if (collection != null) {
      final old = _collections[collection.key];
      if (old != null) {
        final ids = {...old.trackIds};
        collection.trackIds = [
          ...collection.trackIds,
          ...old.trackIds.where(
            (id) => !collection.trackIds.contains(id) && !ids.contains(id),
          ),
        ];
      }
      _collections[collection.key] = collection;
    }
    var added = 0;
    for (final t in tracks) {
      if (_done.containsKey(t.id) || _tasks.containsKey(t.id)) continue;
      _tasks[t.id] = DownloadTask(t);
      added++;
    }
    if (added > 0 && !_online) {
      _messages.add('Sunucuya bağlanınca indirilecek');
    }
    _scheduleSave();
    notifyListeners();
    _pump();
  }

  /// Saves a changed collection (name, song order).
  void updated() {
    _scheduleSave();
    notifyListeners();
  }

  /// Starts the failed downloads again.
  void retryFailed() {
    for (final t in _tasks.values) {
      if (t.state == DlState.failed) {
        t.state = DlState.queued;
        t.error = null;
      }
    }
    notifyListeners();
    _pump();
  }

  /// Cancels every queued / failed download.
  void cancelAll() {
    for (final id in _tasks.keys.toList()) {
      cancel(id);
    }
  }

  void cancel(String trackId) {
    final t = _tasks.remove(trackId);
    if (t != null) {
      _deletePart(t.track);
      _scheduleSave();
      notifyListeners();
    }
  }

  Future<void> remove(Iterable<String> trackIds) async {
    for (final id in trackIds.toList()) {
      _tasks.remove(id);
      final d = _done.remove(id);
      if (d != null) {
        try {
          await File('${_tracksDir.path}/${d.file}').delete();
        } catch (_) {}
      }
    }
    for (final c in _collections.values.toList()) {
      c.trackIds.removeWhere(
        (id) => !_done.containsKey(id) && !_tasks.containsKey(id),
      );
      if (c.trackIds.isEmpty) _collections.remove(c.key);
    }
    await _cleanCovers();
    _scheduleSave();
    notifyListeners();
  }

  /// Removes a group; songs that another group still uses stay.
  Future<void> removeCollection(String key) async {
    final c = _collections.remove(key);
    if (c == null) return;
    final keep = <String>{};
    for (final o in _collections.values) {
      keep.addAll(o.trackIds);
    }
    await remove(c.trackIds.where((id) => !keep.contains(id)));
    _scheduleSave();
    notifyListeners();
  }

  /// "İndirilenleri sil": deletes every downloaded song of every server.
  Future<void> removeAll() async {
    _tasks.clear();
    _done.clear();
    _collections.clear();
    _covers.clear();
    try {
      final b = await _base();
      if (await b.exists()) await b.delete(recursive: true);
    } catch (_) {}
    if (_root != null) {
      await _tracksDir.create(recursive: true);
      await _coversDir.create(recursive: true);
    }
    await _flush();
    notifyListeners();
  }

  /// Size of all downloads of all servers on this phone.
  Future<int> diskUsage() async {
    var total = 0;
    try {
      final b = await _base();
      if (!await b.exists()) return 0;
      await for (final e in b.list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  // ---------- worker ----------

  void _pump() {
    if (!_online || _api == null || _root == null) return;
    for (final t in _tasks.values) {
      if (_running >= _parallel) break;
      if (t.state == DlState.queued) {
        _running++;
        t.state = DlState.running;
        _run(t).whenComplete(() {
          _running--;
          _pump();
        });
      }
    }
  }

  File _partFile(Track t) => File('${_tracksDir.path}/${t.id}.part');

  Future<void> _deletePart(Track t) async {
    try {
      final f = _partFile(t);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> _run(DownloadTask task) async {
    final api = _api;
    if (api == null) {
      task.state = DlState.queued;
      return;
    }
    final t = task.track;
    final part = _partFile(t);
    IOSink? sink;
    try {
      var have = await part.exists() ? await part.length() : 0;
      final req = http.Request('GET', Uri.parse(api.streamUrl(t.id)));
      if (have > 0) req.headers['Range'] = 'bytes=$have-';
      final resp = await _http.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        have = 0; // the server sent everything again
      } else if (resp.statusCode == 416) {
        await part.delete();
        throw const HttpException('yeniden başlatılıyor');
      } else if (resp.statusCode != 206) {
        throw HttpException(
          resp.statusCode == 404
              ? 'şarkı sunucuda yok'
              : 'sunucu hatası ${resp.statusCode}',
        );
      }
      final len = resp.contentLength ?? -1;
      task.total = len >= 0 ? have + len : t.size;
      task.received = have;
      final out = part.openWrite(
        mode: have > 0 ? FileMode.append : FileMode.write,
      );
      sink = out;
      var last = DateTime.now();
      await for (final chunk in resp.stream.timeout(
        const Duration(seconds: 45),
      )) {
        if (!_tasks.containsKey(t.id)) {
          await out.close();
          sink = null;
          await _deletePart(t);
          return; // cancelled
        }
        out.add(chunk);
        task.received += chunk.length;
        if (DateTime.now().difference(last).inMilliseconds > 400) {
          last = DateTime.now();
          notifyListeners();
        }
      }
      await out.flush();
      await out.close();
      sink = null;
      final size = await part.length();
      if (task.total > 0 && size != task.total) {
        throw const HttpException('eksik indirildi');
      }
      var ext = t.ext.isNotEmpty ? t.ext : '.bin';
      if (!ext.startsWith('.')) ext = '.$ext';
      final name = '${t.id}$ext';
      await part.rename('${_tracksDir.path}/$name');
      await _downloadCover(api, t);
      _tasks.remove(t.id);
      _done[t.id] = DownloadedTrack(
        t,
        name,
        size,
        DateTime.now().millisecondsSinceEpoch,
      );
      _scheduleSave();
      notifyListeners();
    } on FileSystemException catch (e) {
      await sink?.close();
      task.state = DlState.failed;
      final full =
          e.osError?.errorCode == 28 ||
          '${e.osError?.message}'.contains('space');
      task.error = full ? 'Telefonda yer kalmadı' : 'Dosya yazılamadı';
      if (full) {
        // no point in trying the others now
        for (final o in _tasks.values) {
          if (o.state == DlState.queued) {
            o.state = DlState.failed;
            o.error = task.error;
          }
        }
        _messages.add('İndirme durdu: telefonda yer kalmadı');
      }
      notifyListeners();
    } catch (e) {
      await sink?.close();
      task.state = DlState.failed;
      task.error = e is HttpException ? e.message : 'bağlantı koptu';
      notifyListeners();
      // network trouble: try again a bit later while online
      Timer(const Duration(seconds: 20), () {
        if (_tasks[t.id] == task && task.state == DlState.failed && _online) {
          task.state = DlState.queued;
          _pump();
        }
      });
    }
  }

  Future<void> _downloadCover(ApiClient api, Track t) async {
    final id = t.coverId.isNotEmpty ? t.coverId : t.id;
    if (_covers.containsKey(id) || t.cover.isEmpty) return;
    try {
      final resp = await _http
          .get(Uri.parse(api.coverUrl(t.cover, width: 640)))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return;
      final f = File('${_coversDir.path}/$id.jpg');
      await f.writeAsBytes(resp.bodyBytes, flush: true);
      _covers[id] = f.path;
    } catch (_) {}
  }

  Future<void> _cleanCovers() async {
    final used = {
      for (final d in _done.values)
        d.track.coverId.isNotEmpty ? d.track.coverId : d.track.id,
    };
    for (final id in _covers.keys.toList()) {
      if (!used.contains(id)) {
        try {
          await File(_covers[id]!).delete();
        } catch (_) {}
        _covers.remove(id);
      }
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _flush);
  }

  Future<void> _flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final root = _root;
    if (root == null) return;
    try {
      final data = {
        'v': 1,
        'tracks': [for (final d in _done.values) d.toJson()],
        'collections': [for (final c in _collections.values) c.toJson()],
        'pending': [for (final t in _tasks.values) t.track.toJson()],
      };
      await root.create(recursive: true);
      final tmp = File('${root.path}/index.json.tmp');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename('${root.path}/index.json');
    } catch (_) {}
  }
}
