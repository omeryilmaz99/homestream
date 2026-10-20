import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  @override
  String toString() => message;
}

/// Normalizes user input like "192.168.50.200", "192.168.50.200:8420",
/// "http://host:8420/" into "http://host:8420".
String normalizeServerUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) return s;
  if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
  var uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return s;
  if (!uri.hasPort) uri = uri.replace(port: 8420);
  return '${uri.scheme}://${uri.host}:${uri.port}';
}

class ApiClient {
  final String baseUrl;
  String? profileId;
  final http.Client _http = http.Client();

  ApiClient(this.baseUrl, {this.profileId});

  void close() => _http.close();

  /// Absolute URL for a server-relative path such as "/api/images/x/poster".
  String url(String path, [Map<String, String>? query]) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final u = Uri.parse('$baseUrl$path');
    if (query == null || query.isEmpty) return u.toString();
    return u
        .replace(queryParameters: {...u.queryParameters, ...query})
        .toString();
  }

  String imageUrl(String path, {int? width}) =>
      url(path, width == null ? null : {'w': '$width'});

  /// Stream URL with the profile in the query (for external players).
  String streamUrl(MediaItem item) {
    final p = item.file?.streamUrl.isNotEmpty == true
        ? item.file!.streamUrl
        : '/api/stream/${item.id}';
    return url(p);
  }

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'X-Profile': ?profileId,
  };

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration? timeout,
  }) async {
    final uri = Uri.parse(url(path, query));
    final req = http.Request(method, uri);
    req.headers.addAll(_headers);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json; charset=utf-8';
      req.body = jsonEncode(body);
    }
    http.StreamedResponse resp;
    try {
      resp = await _http
          .send(req)
          .timeout(timeout ?? const Duration(seconds: 15));
    } on TimeoutException {
      throw ApiException('Sunucu yanıt vermedi (zaman aşımı).');
    } on SocketException {
      throw ApiException(
        'Sunucuya bağlanılamadı. Sunucu açık mı ve adres doğru mu?',
      );
    } on http.ClientException catch (e) {
      throw ApiException('Bağlantı hatası: ${e.message}');
    }
    final text = await resp.stream.bytesToString();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String msg = 'Sunucu hatası (${resp.statusCode})';
      try {
        final j = jsonDecode(text);
        if (j is Map && j['error'] != null) msg = '${j['error']}';
      } catch (_) {}
      throw ApiException(msg, resp.statusCode);
    }
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      throw ApiException('Sunucudan geçersiz yanıt geldi.');
    }
  }

  Future<dynamic> _get(String path, [Map<String, String>? q]) =>
      _send('GET', path, query: q);
  Future<dynamic> _post(String path, [Object? body]) =>
      _send('POST', path, body: body ?? {});

  // ---- server ----
  Future<ServerInfo> info({Duration? timeout}) async => ServerInfo.fromJson(
    await _send('GET', '/api/info', timeout: timeout) as Map<String, dynamic>,
  );

  // ---- profiles ----
  Future<List<Profile>> profiles() async =>
      ((await _get('/api/profiles')) as List)
          .map((e) => Profile.fromJson(e as Map<String, dynamic>))
          .toList();
  Future<Profile> createProfile(
    String name,
    String color,
    String avatar,
  ) async => Profile.fromJson(
    await _post('/api/profiles', {
          'name': name,
          'color': color,
          'avatar': avatar,
        })
        as Map<String, dynamic>,
  );
  Future<Profile> updateProfile(
    String id,
    String name,
    String color,
    String avatar,
  ) async => Profile.fromJson(
    await _send(
          'PUT',
          '/api/profiles/$id',
          body: {'name': name, 'color': color, 'avatar': avatar},
        )
        as Map<String, dynamic>,
  );
  Future<void> deleteProfile(String id) => _send('DELETE', '/api/profiles/$id');

  // ---- library ----
  Future<HomeData> home() async =>
      HomeData.fromJson(await _get('/api/home') as Map<String, dynamic>);

  Future<List<MediaItem>> movies({
    String sort = 'added',
    String? genre,
    String? filter,
  }) async => _items(
    await _get('/api/movies', {
      'sort': sort,
      'order': sort == 'title' ? 'asc' : 'desc',
      'genre': ?genre,
      'filter': ?filter,
    }),
  );

  Future<List<MediaItem>> series({
    String sort = 'added',
    String? genre,
    String? filter,
  }) async => _items(
    await _get('/api/series', {
      'sort': sort,
      'order': sort == 'title' ? 'asc' : 'desc',
      'genre': ?genre,
      'filter': ?filter,
    }),
  );

  Future<List<String>> genres() async =>
      ((await _get('/api/genres')) as List? ?? []).map((e) => '$e').toList();

  Future<MediaItem> item(String id) async =>
      MediaItem.fromJson(await _get('/api/items/$id') as Map<String, dynamic>);

  Future<Related> related(String id) async => Related.fromJson(
    await _get('/api/items/$id/related') as Map<String, dynamic>,
  );

  Future<UserData> reportProgress(
    String id,
    double position,
    double duration,
  ) async => UserData.fromJson(
    await _post('/api/items/$id/progress', {
          'position': position,
          'duration': duration,
        })
        as Map<String, dynamic>?,
  );

  Future<UserData> setPlayed(String id, bool played) async => UserData.fromJson(
    await _post('/api/items/$id/played', {'played': played})
        as Map<String, dynamic>?,
  );

  Future<UserData> setLiked(String id, bool liked) async => UserData.fromJson(
    await _post('/api/items/$id/like', {'liked': liked})
        as Map<String, dynamic>?,
  );

  Future<void> clearProgress(String id) =>
      _send('DELETE', '/api/items/$id/progress');

  Future<SearchResults> search(String q) async => SearchResults.fromJson(
    await _get('/api/search', {'q': q}) as Map<String, dynamic>,
  );

  Future<BrowseResult> browse(String path) async => BrowseResult.fromJson(
    await _get('/api/browse', {'path': path}) as Map<String, dynamic>,
  );

  // ---- admin ----
  Future<ServerSettings> settings() async => ServerSettings.fromJson(
    await _get('/api/settings') as Map<String, dynamic>,
  );
  Future<void> updateSettings(Map<String, dynamic> patch) =>
      _send('PUT', '/api/settings', body: patch);
  Future<void> addFolder(String path, String name, {String kind = 'auto'}) =>
      _post('/api/folders', {'path': path, 'name': name, 'kind': kind});
  Future<void> setFolderKind(String id, String kind) =>
      _send('PATCH', '/api/folders/$id', body: {'kind': kind});
  Future<void> removeFolder(String id) => _send('DELETE', '/api/folders/$id');
  Future<FsListing> fs(String path) async => FsListing.fromJson(
    await _get('/api/fs', {'path': path}) as Map<String, dynamic>,
  );
  Future<void> scan({bool refreshMetadata = false}) =>
      _post('/api/scan', {'refreshMetadata': refreshMetadata});
  Future<ScanStatus> scanStatus() async => ScanStatus.fromJson(
    await _get('/api/scan/status') as Map<String, dynamic>,
  );

  List<MediaItem> _items(dynamic v) => ((v as List?) ?? [])
      .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
      .toList();
}
