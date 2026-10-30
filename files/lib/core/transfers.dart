import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'api.dart';
import 'format.dart';
import 'local_fs.dart';
import 'platform.dart';
import 'prefs.dart';

enum TransferKind { upload, download }

enum TransferState {
  queued,
  running,
  waiting, // connection lost: continues by itself
  paused,
  verifying,
  done,
  failed,
  canceled,
  skipped,
}

/// What to do when the target already exists.
enum ConflictChoice { overwrite, rename, skip }

class ConflictInfo {
  final TransferTask task;
  final int existingSize;
  final DateTime? existingMtime;
  ConflictInfo(this.task, this.existingSize, this.existingMtime);
}

class TransferTask {
  final String id;
  final TransferKind kind;
  final String serverId;
  String localPath;
  String remotePath;
  final int size;
  final int mtime; // source modification time (ms)
  final String? group; // folder being transferred, for the list
  String conflict; // ask | overwrite | rename | skip
  TransferState state;
  int done;
  String? error;
  int attempts = 0;
  final int added;
  int? finished;
  double speed = 0;
  bool resumable = false;

  TransferTask({
    required this.id,
    required this.kind,
    required this.serverId,
    required this.localPath,
    required this.remotePath,
    required this.size,
    required this.mtime,
    this.group,
    this.conflict = 'ask',
    this.state = TransferState.queued,
    this.done = 0,
    int? added,
  }) : added = added ?? DateTime.now().millisecondsSinceEpoch;

  String get name => kind == TransferKind.upload
      ? p.basename(localPath)
      : remotePath.split('/').last;

  bool get active =>
      state == TransferState.queued ||
      state == TransferState.running ||
      state == TransferState.waiting ||
      state == TransferState.verifying;

  bool get finishedState =>
      state == TransferState.done ||
      state == TransferState.canceled ||
      state == TransferState.skipped;

  double get progress => size <= 0
      ? (state == TransferState.done ? 1 : 0)
      : (done / size).clamp(0, 1).toDouble();

  Map<String, dynamic> toJson() => {
    'id': id,
    'k': kind.index,
    'sv': serverId,
    'l': localPath,
    'r': remotePath,
    's': size,
    'm': mtime,
    'g': group,
    'c': conflict,
    'st': state.index,
    'd': done,
    'e': error,
    'a': added,
    'rs': resumable,
  };

  factory TransferTask.fromJson(Map<String, dynamic> j) =>
      TransferTask(
          id: '${j['id']}',
          kind: TransferKind.values[(j['k'] as num).toInt()],
          serverId: '${j['sv']}',
          localPath: '${j['l']}',
          remotePath: '${j['r']}',
          size: (j['s'] as num).toInt(),
          mtime: (j['m'] as num).toInt(),
          group: j['g'] as String?,
          conflict: '${j['c'] ?? 'ask'}',
          state: TransferState.values[(j['st'] as num).toInt()],
          done: (j['d'] as num?)?.toInt() ?? 0,
          added: (j['a'] as num?)?.toInt(),
        )
        ..error = j['e'] as String?
        ..resumable = j['rs'] == true;
}

class _Fatal implements Exception {
  final String message;
  _Fatal(this.message);
  @override
  String toString() => message;
}

class _Retry implements Exception {
  final String message;
  _Retry(this.message);
  @override
  String toString() => message;
}

class _Stop implements Exception {}

/// Runs uploads and downloads: a few at a time, each one resumable from the
/// byte where it stopped (connection drop, app closed, server restarted).
class TransferManager extends ChangeNotifier {
  final Prefs prefs;
  TransferManager(this.prefs) {
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  final List<TransferTask> tasks = [];
  FilesApi? _api;
  String? _serverId;
  bool online = false;

  /// Asked when a target exists and the setting is "ask". The UI returns the
  /// choice and whether to use it for the rest of the batch.
  Future<(ConflictChoice, bool)?> Function(ConflictInfo info)? onConflict;

  /// Called after a file finished (to refresh the panes).
  void Function(TransferTask t)? onFinished;

  final Map<String, _Running> _running = {};
  final Map<String, ConflictChoice> _batchChoice = {};
  Future<void>? _asking;
  Timer? _ticker;
  Timer? _saveTimer;
  int _rev = 0;
  int get rev => _rev;

  // ---- connection ----

  void attach(FilesApi? api, String? serverId) {
    if (_api == api) return;
    _api = api;
    _serverId = serverId;
    if (api == null) {
      for (final r in _running.values) {
        r.abort();
        // continues when the server is back
        if (r.task.active) r.task.state = TransferState.queued;
        r.task.speed = 0;
      }
    }
    _pump();
    notifyListeners();
  }

  void setOnline(bool v) {
    if (online == v) return;
    online = v;
    if (v) {
      for (final t in tasks) {
        if (t.state == TransferState.waiting) t.state = TransferState.queued;
      }
    }
    _pump();
    _changed();
  }

  // ---- queue ----

  List<TransferTask> get visible => tasks;

  int get activeCount => tasks.where((t) => t.active).length;
  bool get hasActive => activeCount > 0;

  int get totalBytes =>
      tasks.where((t) => t.active).fold(0, (a, t) => a + t.size);
  int get doneBytes =>
      tasks.where((t) => t.active).fold(0, (a, t) => a + t.done);
  double get speed => _running.values.fold(0.0, (a, r) => a + r.task.speed);

  Duration? get eta {
    final s = speed;
    if (s < 1) return null;
    return Duration(seconds: ((totalBytes - doneBytes) / s).round());
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}';

  /// Sends local files/folders into [remoteDir].
  Future<int> upload(List<String> localPaths, String remoteDir) async {
    final sid = _serverId;
    final api = _api;
    if (sid == null || api == null) throw ApiException('Sunucuya bağlı değil');
    var n = 0;
    final dirsToMake = <String>[];
    for (final lp in localPaths) {
      final type = FileSystemEntity.typeSync(lp);
      if (type == FileSystemEntityType.directory) {
        final name = p.basename(lp);
        final base = _rjoin(remoteDir, name);
        final w = await LocalFs.walk(lp, hidden: prefs.showHidden);
        dirsToMake.add(base);
        for (final d in w.dirs) {
          dirsToMake.add(_rjoin(base, p.split(d).join('/')));
        }
        for (final f in w.files) {
          final rel = p.split(p.relative(f.path, from: lp)).join('/');
          final st = f.statSync();
          tasks.add(
            TransferTask(
              id: _newId(),
              kind: TransferKind.upload,
              serverId: sid,
              localPath: f.path,
              remotePath: _rjoin(base, rel),
              size: st.size,
              mtime: st.modified.millisecondsSinceEpoch,
              group: name,
              conflict: prefs.conflict,
            ),
          );
          n++;
        }
      } else if (type == FileSystemEntityType.file) {
        final st = File(lp).statSync();
        tasks.add(
          TransferTask(
            id: _newId(),
            kind: TransferKind.upload,
            serverId: sid,
            localPath: lp,
            remotePath: _rjoin(remoteDir, p.basename(lp)),
            size: st.size,
            mtime: st.modified.millisecondsSinceEpoch,
            conflict: prefs.conflict,
          ),
        );
        n++;
      }
    }
    // empty folders too (files create their folders by themselves)
    for (final d in dirsToMake) {
      try {
        await api.mkdir(d);
      } catch (_) {}
    }
    _changed();
    _pump();
    return n;
  }

  /// Receives server files/folders into [localDir].
  Future<int> download(
    List<({String path, bool isDir, int size, int mtime})> items,
    String localDir,
  ) async {
    final sid = _serverId;
    final api = _api;
    if (sid == null || api == null) throw ApiException('Sunucuya bağlı değil');
    var n = 0;
    for (final it in items) {
      final name = LocalFs.safeName(it.path.split('/').last);
      if (it.isDir) {
        final tree = await api.tree(it.path, hidden: prefs.showHidden);
        final base = p.join(localDir, name);
        await Directory(base).create(recursive: true);
        for (final d in tree.dirs) {
          await Directory(
            p.joinAll([base, ...d.split('/').map(LocalFs.safeName)]),
          ).create(recursive: true);
        }
        for (final f in tree.files) {
          tasks.add(
            TransferTask(
              id: _newId(),
              kind: TransferKind.download,
              serverId: sid,
              localPath: p.joinAll([
                base,
                ...f.rel.split('/').map(LocalFs.safeName),
              ]),
              remotePath: _rjoin(it.path, f.rel),
              size: f.size,
              mtime: f.mtime,
              group: name,
              conflict: prefs.conflict,
            ),
          );
          n++;
        }
      } else {
        tasks.add(
          TransferTask(
            id: _newId(),
            kind: TransferKind.download,
            serverId: sid,
            localPath: p.join(localDir, name),
            remotePath: it.path,
            size: it.size,
            mtime: it.mtime,
            conflict: prefs.conflict,
          ),
        );
        n++;
      }
    }
    _changed();
    _pump();
    return n;
  }

  static String _rjoin(String dir, String name) =>
      dir.endsWith('/') ? '$dir$name' : '$dir/$name';

  void pause(TransferTask t) {
    if (!t.active) return;
    _running[t.id]?.abort();
    t.state = TransferState.paused;
    t.speed = 0;
    _changed();
    _pump();
  }

  void resume(TransferTask t) {
    if (t.state == TransferState.paused || t.state == TransferState.failed) {
      t.state = TransferState.queued;
      t.error = null;
      t.attempts = 0;
      _changed();
      _pump();
    }
  }

  void cancel(TransferTask t) {
    _running[t.id]?.abort();
    final wasActive = !t.finishedState;
    t.state = TransferState.canceled;
    t.speed = 0;
    if (wasActive) _cleanupPartial(t);
    _changed();
    _pump();
  }

  void pauseAll() {
    for (final t in tasks.where((t) => t.active).toList()) {
      pause(t);
    }
  }

  void resumeAll() {
    for (final t in tasks) {
      if (t.state == TransferState.paused || t.state == TransferState.failed) {
        t.state = TransferState.queued;
        t.error = null;
        t.attempts = 0;
      }
    }
    _changed();
    _pump();
  }

  void cancelAll() {
    for (final t in tasks.where((t) => !t.finishedState).toList()) {
      cancel(t);
    }
  }

  void clearFinished() {
    tasks.removeWhere((t) => t.finishedState);
    _changed();
  }

  void retryFailed() => resumeAll();

  Future<void> _cleanupPartial(TransferTask t) async {
    if (t.kind == TransferKind.download) {
      try {
        await File('${t.localPath}.hspart').delete();
      } catch (_) {}
    } else if (t.serverId == _serverId) {
      await _api?.cancelUpload(t.remotePath);
    }
  }

  // ---- scheduler ----

  void _pump() {
    final api = _api;
    if (api == null || !online) {
      _updateNotice();
      return;
    }
    if (!tasks.any((t) => t.active)) _batchChoice.clear();
    final limit = prefs.parallel;
    for (final t in tasks) {
      if (_running.length >= limit) break;
      if (t.state != TransferState.queued || t.serverId != _serverId) continue;
      if (_running.containsKey(t.id)) continue;
      final r = _Running(t);
      _running[t.id] = r;
      t.state = TransferState.running;
      _run(api, r);
    }
    _updateNotice();
  }

  Future<void> _run(FilesApi api, _Running r) async {
    final t = r.task;
    t.attempts++;
    try {
      if (t.kind == TransferKind.upload) {
        await _upload(api, r);
      } else {
        await _download(api, r);
      }
      if (t.state == TransferState.running ||
          t.state == TransferState.verifying) {
        t.state = TransferState.done;
        t.finished = DateTime.now().millisecondsSinceEpoch;
        t.done = t.size;
        _record(t);
      }
    } on _Stop {
      // paused or canceled by the user (state set already)
    } on _Fatal catch (e) {
      t.state = TransferState.failed;
      t.error = e.message;
    } catch (e) {
      if (r.aborted) {
        // paused / canceled
      } else {
        final msg = e is _Retry ? e.message : _netText(e);
        t.error = msg;
        if (t.attempts >= 40) {
          t.state = TransferState.failed;
        } else {
          // waits for the connection (or tries again in a few seconds)
          t.state = TransferState.waiting;
          final delay = Duration(seconds: min(30, 2 * t.attempts));
          Timer(delay, () {
            if (t.state == TransferState.waiting && online) {
              t.state = TransferState.queued;
              _pump();
              _changed();
            }
          });
        }
      }
    } finally {
      t.speed = 0;
      _running.remove(t.id);
      if (t.state == TransferState.done) onFinished?.call(t);
      _changed();
      _pump();
    }
  }

  String _netText(Object e) {
    if (e is ApiException) return e.message;
    if (e is SocketException || e is HttpException || e is TimeoutException) {
      return 'Bağlantı koptu, kaldığı yerden devam edecek';
    }
    if (e is FileSystemException) return LocalFs.errorText(e);
    return '$e';
  }

  Future<ConflictChoice?> _resolve(TransferTask t, int size, int? mtime) async {
    switch (t.conflict) {
      case 'overwrite':
        return ConflictChoice.overwrite;
      case 'rename':
        return ConflictChoice.rename;
      case 'skip':
        return ConflictChoice.skip;
    }
    final key = '${t.kind.index}:${t.group ?? t.id}';
    if (_batchChoice[key] != null) return _batchChoice[key];
    // one question at a time
    while (_asking != null) {
      await _asking;
      if (_batchChoice[key] != null) return _batchChoice[key];
    }
    final cb = onConflict;
    if (cb == null) return ConflictChoice.rename;
    final c = Completer<void>();
    _asking = c.future;
    try {
      final res = await cb(
        ConflictInfo(
          t,
          size,
          mtime == null ? null : DateTime.fromMillisecondsSinceEpoch(mtime),
        ),
      );
      if (res == null) return null;
      if (res.$2) {
        _batchChoice[key] = res.$1;
        // the rest of the queue too
        _batchChoice['${t.kind.index}:*'] = res.$1;
      }
      return res.$1;
    } finally {
      _asking = null;
      c.complete();
    }
  }

  // ---- upload ----

  Future<void> _upload(FilesApi api, _Running r) async {
    final t = r.task;
    final file = File(t.localPath);
    if (!await file.exists()) throw _Fatal('Dosya bu cihazda artık yok');
    final st = await file.stat();
    final changed =
        st.size != t.size || st.modified.millisecondsSinceEpoch != t.mtime;
    if (changed) {
      // the file changed since it was queued: start over with the new one
      throw _Fatal(
        'Dosya aktarım sırasında değişti. Tekrar gönder.',
      );
    }
    final status = await api.uploadStatus(t.remotePath);
    if (r.aborted) throw _Stop();
    var offset = (status['offset'] as num?)?.toInt() ?? 0;
    if (!t.resumable || offset > t.size) offset = 0;
    var conflict = t.conflict == 'ask' ? '' : t.conflict;
    if (status['exists'] == true && offset == 0) {
      if (status['dir'] == true) {
        throw _Fatal('Sunucuda aynı adda bir klasör var');
      }
      var choice = _batchChoice['${t.kind.index}:*'];
      choice ??= await _resolve(
        t,
        (status['size'] as num?)?.toInt() ?? 0,
        (status['mtime'] as num?)?.toInt(),
      );
      if (choice == null || choice == ConflictChoice.skip) {
        t.state = TransferState.skipped;
        t.finished = DateTime.now().millisecondsSinceEpoch;
        throw _Stop();
      }
      conflict = choice == ConflictChoice.overwrite ? 'overwrite' : 'rename';
      t.conflict = conflict;
    }
    final free = (status['free'] as num?)?.toInt() ?? 0;
    if (free > 0 && free < t.size - offset) {
      throw _Fatal(
        'Sunucuda yer yok: ${formatBytes(t.size - offset)} gerekli, ${formatBytes(free)} boş',
      );
    }
    if (status['writable'] == false) {
      throw _Fatal('Bu sunucu klasörüne yazma izni yok');
    }

    for (var round = 0; round < 5; round++) {
      t.done = offset;
      t.resumable = true;
      final res = await _put(api, r, offset, conflict);
      if (res.done) {
        if (res.path != null && res.path != t.remotePath) {
          t.remotePath = res.path!;
        }
        break;
      }
      offset = res.offset;
      if (round == 4) throw _Retry('Yükleme tamamlanamadı');
    }
    if (prefs.verify) {
      t.state = TransferState.verifying;
      _changed();
      final local = await _sha256(file, r);
      final remote = await api.hash(t.remotePath);
      if (local != remote) {
        await api.cancelUpload(t.remotePath);
        t.resumable = false;
        throw _Fatal('Doğrulama başarısız: dosya bozuk geldi. Tekrar gönder.');
      }
    }
  }

  Future<({bool done, int offset, String? path})> _put(
    FilesApi api,
    _Running r,
    int offset,
    String conflict,
  ) async {
    final t = r.task;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 20);
    r.client = client;
    try {
      final u = api.uri('/api/files/upload', {
        'path': t.remotePath,
        'offset': '$offset',
        'size': '${t.size}',
        if (prefs.keepMtime) 'mtime': '${t.mtime}',
        if (conflict.isNotEmpty) 'conflict': conflict,
      });
      final req = await client.putUrl(u);
      api.authHeaders.forEach(req.headers.set);
      req.headers.contentType = ContentType.binary;
      req.contentLength = t.size - offset;
      req.bufferOutput = false;
      var sent = offset;
      final meter = _Meter();
      final stream = File(t.localPath).openRead(offset).map((chunk) {
        if (r.aborted) throw _Stop();
        sent += chunk.length;
        t.done = sent;
        t.speed = meter.add(chunk.length);
        r.lastProgress = DateTime.now();
        return chunk;
      });
      await req.addStream(stream);
      final resp = await req.close().timeout(const Duration(minutes: 2));
      final text = await resp.transform(utf8.decoder).join();
      Map<String, dynamic> j = {};
      try {
        j = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {}
      if (resp.statusCode == 200) {
        return (
          done: j['done'] == true,
          offset: (j['offset'] as num?)?.toInt() ?? sent,
          path: j['path'] as String?,
        );
      }
      if (resp.statusCode == 409 && j['offset'] != null) {
        return (
          done: false,
          offset: (j['offset'] as num).toInt(),
          path: null,
        );
      }
      final msg = '${j['error'] ?? 'Sunucu hatası (${resp.statusCode})'}';
      if (resp.statusCode == 401) throw ApiException(msg, 401);
      if (resp.statusCode == 409 && j['exists'] == true) {
        // created by someone else meanwhile
        t.resumable = false;
        throw _Retry(msg);
      }
      if (resp.statusCode >= 500 && resp.statusCode != 507) throw _Retry(msg);
      throw _Fatal(msg);
    } catch (e) {
      if (r.aborted) throw _Stop();
      rethrow;
    } finally {
      client.close(force: true);
      r.client = null;
    }
  }

  // ---- download ----

  Future<void> _download(FilesApi api, _Running r) async {
    final t = r.task;
    final dir = Directory(p.dirname(t.localPath));
    try {
      await dir.create(recursive: true);
    } catch (e) {
      throw _Fatal(LocalFs.errorText(e));
    }
    final part = File('${t.localPath}.hspart');
    var offset = 0;
    if (t.resumable && await part.exists()) {
      offset = await part.length();
      if (offset > t.size) offset = 0;
    }
    if (offset == 0 &&
        FileSystemEntity.typeSync(t.localPath) !=
            FileSystemEntityType.notFound) {
      final st = FileStat.statSync(t.localPath);
      if (st.type == FileSystemEntityType.directory) {
        throw _Fatal('Bu cihazda aynı adda bir klasör var');
      }
      var choice = _batchChoice['${t.kind.index}:*'];
      choice ??= await _resolve(
        t,
        st.size,
        st.modified.millisecondsSinceEpoch,
      );
      if (choice == null || choice == ConflictChoice.skip) {
        t.state = TransferState.skipped;
        t.finished = DateTime.now().millisecondsSinceEpoch;
        throw _Stop();
      }
      if (choice == ConflictChoice.rename) {
        t.localPath = LocalFs.uniquePath(t.localPath);
      }
      t.conflict = choice == ConflictChoice.overwrite ? 'overwrite' : 'rename';
    }
    final partFile = File('${t.localPath}.hspart');

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 20);
    r.client = client;
    RandomAccessFile? raf;
    try {
      final req = await client.getUrl(api.downloadUri(t.remotePath));
      api.authHeaders.forEach(req.headers.set);
      if (offset > 0) {
        req.headers.set('Range', 'bytes=$offset-');
        // only continue when the server file did not change
        req.headers.set(
          'If-Range',
          HttpDate.format(
            DateTime.fromMillisecondsSinceEpoch(t.mtime, isUtc: true),
          ),
        );
      }
      final resp = await req.close().timeout(const Duration(seconds: 30));
      if (resp.statusCode == 401) {
        await resp.drain<void>();
        throw ApiException('Oturum kapandı', 401);
      }
      if (resp.statusCode == 404) {
        await resp.drain<void>();
        throw _Fatal('Dosya sunucuda artık yok');
      }
      if (resp.statusCode == 416) {
        await resp.drain<void>();
        offset = 0;
        t.resumable = false;
        throw _Retry('Baştan indirilecek');
      }
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        final text = await resp.transform(utf8.decoder).join();
        String msg = 'Sunucu hatası (${resp.statusCode})';
        try {
          msg = '${(jsonDecode(text) as Map)['error']}';
        } catch (_) {}
        if (resp.statusCode >= 500) throw _Retry(msg);
        throw _Fatal(msg);
      }
      if (resp.statusCode == 200) offset = 0; // the server file changed
      final serverSize = int.tryParse(resp.headers.value('x-file-size') ?? '');
      final total = serverSize ?? t.size;
      try {
        raf = await partFile.open(
          mode: offset > 0 ? FileMode.append : FileMode.write,
        );
        if (offset == 0) await raf.truncate(0);
      } catch (e) {
        throw _Fatal(LocalFs.errorText(e));
      }
      t.resumable = true;
      var got = offset;
      t.done = got;
      final meter = _Meter();
      final buf = BytesBuilder(copy: false);
      Future<void> flush() async {
        if (buf.isEmpty) return;
        try {
          await raf!.writeFrom(buf.takeBytes());
        } catch (e) {
          throw _Fatal(LocalFs.errorText(e));
        }
      }

      await for (final chunk in resp) {
        if (r.aborted) throw _Stop();
        buf.add(chunk);
        got += chunk.length;
        t.done = got;
        t.speed = meter.add(chunk.length);
        r.lastProgress = DateTime.now();
        if (buf.length >= 1 << 20) await flush();
      }
      await flush();
      await raf.flush();
      await raf.close();
      raf = null;
      if (got < total) throw _Retry('İndirme yarıda kaldı');
      if (t.conflict == 'overwrite' &&
          FileSystemEntity.typeSync(t.localPath) ==
              FileSystemEntityType.file) {
        await File(t.localPath).delete();
      }
      final finalFile = await partFile.rename(t.localPath);
      if (prefs.keepMtime && t.mtime > 0) {
        try {
          await finalFile.setLastModified(
            DateTime.fromMillisecondsSinceEpoch(t.mtime),
          );
        } catch (_) {}
      }
      if (prefs.verify) {
        t.state = TransferState.verifying;
        _changed();
        final local = await _sha256(finalFile, r);
        final remote = await api.hash(t.remotePath);
        if (local != remote) {
          t.resumable = false;
          try {
            await finalFile.delete();
          } catch (_) {}
          throw _Fatal('Doğrulama başarısız: dosya bozuk geldi. Tekrar indir.');
        }
      }
    } catch (e) {
      if (r.aborted) throw _Stop();
      rethrow;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
      client.close(force: true);
      r.client = null;
    }
  }

  Future<String> _sha256(File f, _Running r) async {
    final out = await sha256.bind(f.openRead().map((c) {
      if (r.aborted) throw _Stop();
      r.lastProgress = DateTime.now();
      return c;
    })).first;
    return out.toString();
  }

  // ---- bookkeeping ----

  void _record(TransferTask t) {
    final h = prefs.history;
    h.insert(
      0,
      HistoryEntry(
        name: t.name,
        upload: t.kind == TransferKind.upload,
        size: t.size,
        at: DateTime.now().millisecondsSinceEpoch,
        localPath: t.localPath,
        remotePath: t.remotePath,
        serverId: t.serverId,
      ),
    );
    prefs.history = h;
    if (t.kind == TransferKind.upload) {
      prefs.totalSent = prefs.totalSent + t.size;
      prefs.filesSent = prefs.filesSent + 1;
    } else {
      prefs.totalReceived = prefs.totalReceived + t.size;
      prefs.filesReceived = prefs.filesReceived + 1;
    }
  }

  void _tick() {
    // a transfer that does not move for 45 s is restarted (the link is
    // probably dead even if the socket did not notice)
    final now = DateTime.now();
    for (final r in _running.values.toList()) {
      if (now.difference(r.lastProgress).inSeconds > 45 &&
          r.task.state == TransferState.running) {
        r.stall();
      }
      if (now.difference(r.lastProgress).inSeconds > 2) r.task.speed = 0;
    }
    if (_running.isNotEmpty) {
      _rev++;
      notifyListeners();
      _updateNotice();
    }
    // finished ones disappear from the list after a while
    final cutoff = now.millisecondsSinceEpoch - 10 * 60 * 1000;
    final before = tasks.length;
    tasks.removeWhere(
      (t) =>
          (t.state == TransferState.done || t.state == TransferState.skipped) &&
          (t.finished ?? now.millisecondsSinceEpoch) < cutoff,
    );
    if (tasks.length != before) _changed();
  }

  void _updateNotice() {
    final active = tasks.where((t) => t.active).toList();
    if (active.isEmpty) {
      AppPlatform.transferNotice(false);
      return;
    }
    final total = active.fold<int>(0, (a, t) => a + t.size);
    final done = active.fold<int>(0, (a, t) => a + t.done);
    final pct = total <= 0 ? 0 : (done * 100 ~/ total);
    final ups = active.where((t) => t.kind == TransferKind.upload).length;
    final title = !online
        ? 'Bağlantı bekleniyor'
        : (ups == active.length
              ? '${active.length} dosya gönderiliyor'
              : (ups == 0
                    ? '${active.length} dosya alınıyor'
                    : '${active.length} dosya aktarılıyor'));
    AppPlatform.transferNotice(
      true,
      title: title,
      text: '${formatBytes(done)} / ${formatBytes(total)} · ${formatSpeed(speed)}',
      progress: pct,
    );
  }

  void _changed() {
    _rev++;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _save);
  }

  void _save() {
    final keep = tasks
        .where(
          (t) =>
              t.state != TransferState.done &&
              t.state != TransferState.canceled &&
              t.state != TransferState.skipped,
        )
        .map((t) => t.toJson())
        .toList();
    prefs.pendingTransfers = jsonEncode(keep);
  }

  void _load() {
    try {
      final list = jsonDecode(prefs.pendingTransfers) as List;
      for (final e in list) {
        final t = TransferTask.fromJson(e as Map<String, dynamic>);
        if (t.state == TransferState.running ||
            t.state == TransferState.verifying ||
            t.state == TransferState.waiting ||
            t.state == TransferState.queued) {
          t.state = prefs.autoResume
              ? TransferState.queued
              : TransferState.paused;
        }
        tasks.add(t);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _save();
    for (final r in _running.values) {
      r.abort();
    }
    super.dispose();
  }
}

class _Running {
  final TransferTask task;
  _Running(this.task);
  HttpClient? client;
  bool aborted = false;
  DateTime lastProgress = DateTime.now();

  void abort() {
    aborted = true;
    client?.close(force: true);
  }

  /// Drop the connection but let the retry logic continue.
  void stall() {
    lastProgress = DateTime.now();
    client?.close(force: true);
  }
}

/// Speed over the last ~3 seconds.
class _Meter {
  final _samples = <(DateTime, int)>[];
  double add(int n) {
    final now = DateTime.now();
    _samples.add((now, n));
    while (_samples.length > 2 &&
        now.difference(_samples.first.$1).inMilliseconds > 3000) {
      _samples.removeAt(0);
    }
    final ms = now.difference(_samples.first.$1).inMilliseconds;
    if (ms < 200) return 0;
    final sum = _samples.skip(1).fold<int>(0, (a, s) => a + s.$2);
    return sum * 1000 / ms;
  }
}
