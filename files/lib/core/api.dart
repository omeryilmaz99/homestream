import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  final Map<String, dynamic>? body;
  ApiException(this.message, [this.status, this.body]);

  /// The server could not be reached at all.
  bool get offline => status == null;

  /// The login was removed or expired.
  bool get unauthorized => status == 401;
  @override
  String toString() => message;
}

/// "192.168.1.5", "192.168.1.5:8420", "http://host:8420/" → "http://host:8420".
String normalizeServerUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) return s;
  if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
  var uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return s;
  if (!uri.hasPort) uri = uri.replace(port: 8420);
  return '${uri.scheme}://${uri.host}:${uri.port}';
}

String offlineMessage(Object e) {
  if (e is TimeoutException) return 'Sunucu yanıt vermedi (zaman aşımı).';
  if (e is SocketException) {
    final code = e.osError?.errorCode;
    // 111/10061 refused: the machine is there, the server program is not
    if (code == 111 || code == 10061) {
      return 'Sunucu programı çalışmıyor (bağlantı reddedildi).';
    }
    return 'Sunucuya ulaşılamıyor. Sunucu açık mı, aynı ağda mısın?';
  }
  if (e is HandshakeException) return 'Güvenli bağlantı kurulamadı.';
  if (e is http.ClientException) return 'Bağlantı hatası: ${e.message}';
  return 'Bağlantı hatası: $e';
}

class LoginResult {
  final String token;
  final String serverId;
  final String serverName;
  LoginResult(this.token, this.serverId, this.serverName);
}

/// Client for /api/files on one server.
class FilesApi {
  final String baseUrl;
  String? token;
  final http.Client _http = http.Client();

  FilesApi(this.baseUrl, {this.token});

  void close() => _http.close();

  Uri uri(String path, [Map<String, dynamic>? query]) {
    final u = Uri.parse('$baseUrl$path');
    return query == null ? u : u.replace(queryParameters: query);
  }

  Map<String, String> get authHeaders => {
    if (token != null) 'Authorization': 'Bearer $token',
  };

  /// URL usable without headers (images).
  String thumbUrl(String path, {int width = 256}) =>
      uri('/api/files/thumb', {
        'path': path,
        'w': '$width',
        'token': token ?? '',
      }).toString();

  Uri downloadUri(String path) => uri('/api/files/download', {'path': path});

  Future<dynamic> send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final req = http.Request(method, uri(path, query));
    req.headers['Accept'] = 'application/json';
    req.headers.addAll(authHeaders);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json; charset=utf-8';
      req.body = jsonEncode(body);
    }
    http.StreamedResponse resp;
    String text;
    try {
      resp = await _http.send(req).timeout(timeout);
      text = await resp.stream.bytesToString().timeout(
        const Duration(seconds: 90),
      );
    } catch (e) {
      throw ApiException(offlineMessage(e));
    }
    dynamic j;
    if (text.isNotEmpty) {
      try {
        j = jsonDecode(text);
      } catch (_) {
        j = null;
      }
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      var msg = 'Sunucu hatası (${resp.statusCode})';
      if (j is Map && j['error'] != null) {
        msg = '${j['error']}';
      } else if (resp.statusCode == 404 && path.startsWith('/api/files')) {
        msg =
            'Sunucu dosya aktarımını desteklemiyor. Sunucuyu güncelle (install.sh).';
      }
      throw ApiException(
        msg,
        resp.statusCode,
        j is Map<String, dynamic> ? j : null,
      );
    }
    return j;
  }

  // ---- server / login ----

  /// GET /api/info (no login needed) – checks that a Home Stream server is there.
  Future<Map<String, dynamic>> info() async {
    final j = await send(
      'GET',
      '/api/info',
      timeout: const Duration(seconds: 6),
    );
    if (j is! Map<String, dynamic> || j['app'] != 'homestream') {
      throw ApiException('Bu adreste bir Home Stream sunucusu yok.');
    }
    return j;
  }

  Future<LoginResult> login(
    String password,
    String device,
    String platform,
  ) async {
    final j = await send(
      'POST',
      '/api/files/login',
      body: {'password': password, 'device': device, 'platform': platform},
    );
    final s = (j['server'] as Map?) ?? {};
    token = '${j['token']}';
    return LoginResult(token!, '${s['id'] ?? ''}', '${s['name'] ?? ''}');
  }

  Future<void> logout() async {
    try {
      await send('POST', '/api/files/logout');
    } catch (_) {}
  }

  Future<Map<String, dynamic>> session() async =>
      (await send(
            'GET',
            '/api/files/session',
            timeout: const Duration(seconds: 8),
          ))
          as Map<String, dynamic>;

  // ---- browsing ----

  Future<({String home, List<Place> places})> roots() async {
    final j = await send('GET', '/api/files/roots');
    return (
      home: '${j['home']}',
      places: ((j['places'] as List?) ?? const [])
          .map((e) => Place.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<Listing> list(String path) async {
    final j = await send('GET', '/api/files/list', query: {'path': path});
    final dir = '${j['path']}';
    return Listing(
      path: dir,
      parent: j['parent'] as String?,
      items: ((j['entries'] as List?) ?? const [])
          .map((e) => FileItem.remote(e as Map<String, dynamic>, dir))
          .toList(),
      total: (j['total'] as num?)?.toInt() ?? 0,
      free: (j['free'] as num?)?.toInt() ?? 0,
      writable: j['writable'] != false,
    );
  }

  Future<Map<String, dynamic>> stat(String path, {bool deep = false}) async =>
      (await send(
            'GET',
            '/api/files/stat',
            query: {'path': path, if (deep) 'deep': '1'},
            timeout: const Duration(seconds: 30),
          ))
          as Map<String, dynamic>;

  /// Every file below a folder (for downloading it).
  Future<({List<({String rel, int size, int mtime})> files, List<String> dirs})>
  tree(String path, {bool hidden = false}) async {
    final j = await send(
      'GET',
      '/api/files/tree',
      query: {'path': path, if (hidden) 'hidden': '1'},
      timeout: const Duration(seconds: 120),
    );
    return (
      files: ((j['files'] as List?) ?? const [])
          .map(
            (e) => (
              rel: '${e['rel']}',
              size: (e['size'] as num).toInt(),
              mtime: (e['mtime'] as num).toInt(),
            ),
          )
          .toList(),
      dirs: ((j['dirs'] as List?) ?? const []).map((e) => '$e').toList(),
    );
  }

  Future<({List<FileItem> results, bool complete})> search(
    String path,
    String q,
  ) async {
    final j = await send(
      'GET',
      '/api/files/search',
      query: {'path': path, 'q': q},
      timeout: const Duration(seconds: 30),
    );
    return (
      results: ((j['results'] as List?) ?? const [])
          .map((e) => FileItem.remote(e as Map<String, dynamic>, path))
          .toList(),
      complete: j['complete'] == true,
    );
  }

  Future<String> hash(String path) async {
    final j = await send(
      'GET',
      '/api/files/hash',
      query: {'path': path},
      timeout: const Duration(hours: 2),
    );
    return '${j['sha256']}';
  }

  /// First bytes of a text file (preview).
  Future<String> readText(String path, {int max = 256 * 1024}) async {
    final req = http.Request('GET', downloadUri(path));
    req.headers.addAll(authHeaders);
    req.headers['Range'] = 'bytes=0-${max - 1}';
    try {
      final resp = await _http.send(req).timeout(const Duration(seconds: 20));
      if (resp.statusCode >= 300) {
        throw ApiException('Dosya okunamadı (${resp.statusCode})');
      }
      final bytes = await resp.stream.toBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(offlineMessage(e));
    }
  }

  // ---- operations ----

  Future<void> mkdir(String path) =>
      send('POST', '/api/files/mkdir', body: {'path': path});

  Future<String> rename(String path, String name) async {
    final j = await send(
      'POST',
      '/api/files/rename',
      body: {'path': path, 'name': name},
    );
    return '${j['path']}';
  }

  /// Returns the paths that could not go to the trash (need permanent delete)
  /// and the errors.
  Future<({List<String> noTrash, List<String> errors})> delete(
    List<String> paths, {
    bool permanent = false,
  }) async {
    final j = await send(
      'POST',
      '/api/files/delete',
      body: {'paths': paths, 'permanent': permanent},
      timeout: const Duration(minutes: 10),
    );
    final errors = <String>[];
    for (final r in (j['results'] as List?) ?? const []) {
      if (r['error'] != null) {
        errors.add('${'${r['path']}'.split('/').last}: ${r['error']}');
      }
    }
    return (
      noTrash: ((j['noTrash'] as List?) ?? const []).map((e) => '$e').toList(),
      errors: errors,
    );
  }

  Future<ServerJob> copy(
    List<String> paths,
    String dest, {
    bool move = false,
    String conflict = 'rename',
  }) async {
    final j = await send(
      'POST',
      '/api/files/copy',
      body: {
        'paths': paths,
        'dest': dest,
        'move': move,
        'conflict': conflict,
      },
    );
    return ServerJob.fromJson(j as Map<String, dynamic>);
  }

  Future<List<ServerJob>> jobs() async =>
      ((await send('GET', '/api/files/jobs')) as List? ?? const [])
          .map((e) => ServerJob.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<void> cancelJob(String id) => send('DELETE', '/api/files/jobs/$id');

  Future<({List<TrashItem> items, int size})> trash() async {
    final j = await send('GET', '/api/files/trash');
    return (
      items: ((j['items'] as List?) ?? const [])
          .map((e) => TrashItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      size: (j['size'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> restore(List<String> ids) =>
      send('POST', '/api/files/trash/restore', body: {'ids': ids});

  Future<void> deleteTrash({List<String> ids = const [], bool all = false}) =>
      send(
        'POST',
        '/api/files/trash/delete',
        body: {'ids': ids, 'all': all},
        timeout: const Duration(minutes: 10),
      );

  // ---- server status ----

  Future<SystemInfo> system() async => SystemInfo.fromJson(
    (await send('GET', '/api/files/system')) as Map<String, dynamic>,
  );

  Future<({List<DiskInfo> disks, List<SessionInfo> sessions})> devices() async {
    final j = await send('GET', '/api/files/devices');
    return (
      disks: ((j['disks'] as List?) ?? const [])
          .map((e) => DiskInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      sessions: ((j['sessions'] as List?) ?? const [])
          .map((e) => SessionInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> eject(String mountpoint) => send(
    'POST',
    '/api/files/devices/eject',
    body: {'path': mountpoint},
    timeout: const Duration(seconds: 70),
  );

  Future<void> mountDisk(String device) => send(
    'POST',
    '/api/files/devices/mount',
    body: {'device': device},
    timeout: const Duration(seconds: 70),
  );

  Future<void> revoke(String sessionId) =>
      send('DELETE', '/api/files/sessions/$sessionId');

  Future<void> setWatch(String connId, List<String> dirs) =>
      send('PUT', '/api/files/events/$connId/watch', body: {'dirs': dirs});

  // ---- uploads ----

  Future<Map<String, dynamic>> uploadStatus(String path) async =>
      (await send('GET', '/api/files/upload', query: {'path': path}))
          as Map<String, dynamic>;

  Future<void> cancelUpload(String path) async {
    try {
      await send('DELETE', '/api/files/upload', query: {'path': path});
    } catch (_) {}
  }
}
