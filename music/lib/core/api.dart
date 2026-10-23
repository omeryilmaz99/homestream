import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);

  /// True when the server could not be reached at all.
  bool get offline => status == null;
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

class ApiClient {
  final String baseUrl;
  String? profileId;
  final http.Client _http = http.Client();

  ApiClient(this.baseUrl, {this.profileId});

  void close() => _http.close();

  /// Absolute URL for a server path such as "/api/music/covers/x?v=1".
  String url(String path, [Map<String, String>? query]) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final u = Uri.parse('$baseUrl$path');
    if (query == null || query.isEmpty) return u.toString();
    return u
        .replace(queryParameters: {...u.queryParameters, ...query})
        .toString();
  }

  String coverUrl(String path, {int width = 320}) => url(path, {'w': '$width'});

  String streamUrl(String trackId) => url('/api/music/stream/$trackId');

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
    String? adminPassword,
  }) async {
    final uri = Uri.parse(url(path, query));
    final req = http.Request(method, uri);
    req.headers.addAll(_headers);
    if (adminPassword != null) req.headers['X-Admin-Password'] = adminPassword;
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
        'Sunucuya bağlanılamadı. Sunucu açık mı, aynı ağda mısın?',
      );
    } on http.ClientException catch (e) {
      throw ApiException('Bağlantı hatası: ${e.message}');
    } on HandshakeException {
      throw ApiException('Bağlantı hatası (güvenli bağlantı kurulamadı).');
    }
    final String text;
    try {
      text = await resp.stream.bytesToString().timeout(
        const Duration(seconds: 60),
      );
    } catch (_) {
      throw ApiException('Bağlantı koptu.');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String msg = 'Sunucu hatası (${resp.statusCode})';
      try {
        final j = jsonDecode(text);
        if (j is Map && j['error'] != null) msg = '${j['error']}';
      } catch (_) {}
      if (resp.statusCode == 404 &&
          path.startsWith('/api/music/') &&
          !text.contains('error')) {
        msg = 'Sunucu müzik uygulamasını desteklemiyor. Sunucuyu güncelleyin.';
      }
      throw ApiException(msg, resp.statusCode);
    }
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      throw ApiException('Sunucudan geçersiz yanıt geldi.', resp.statusCode);
    }
  }

  Future<dynamic> _get(String path, [Map<String, String>? q]) =>
      _send('GET', path, query: q);
  Future<dynamic> _post(String path, [Object? body]) =>
      _send('POST', path, body: body ?? {});

  List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
      ((v as List?) ?? []).whereType<Map<String, dynamic>>().map(f).toList();

  // ---- server ----
  Future<ServerInfo> info({Duration? timeout}) async {
    final j = await _send('GET', '/api/music/info', timeout: timeout);
    return ServerInfo.fromJson(j as Map<String, dynamic>);
  }

  // ---- profiles ----
  Future<List<Profile>> profiles() async =>
      _list(await _get('/api/profiles'), Profile.fromJson);
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
      HomeData.fromJson(await _get('/api/music/home') as Map<String, dynamic>);

  /// "Sana Özel Mix". Older servers have no mix: shuffle the library.
  Future<List<Track>> mix({int n = 50}) async {
    try {
      return _list(await _get('/api/music/mix', {'n': '$n'}), Track.fromJson);
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
      final all = await tracks()
        ..shuffle();
      return all.take(n).toList();
    }
  }

  /// Profile page numbers. Older servers: worked out from the song list.
  Future<ProfileStats> stats() async {
    try {
      return ProfileStats.fromJson(
        await _get('/api/music/stats') as Map<String, dynamic>,
      );
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
      return ProfileStats.fromTracks(await tracks(sort: 'recent'));
    }
  }

  Future<List<Track>> tracks({String sort = 'title', String? genre}) async =>
      _list(
        await _get('/api/music/tracks', {'sort': sort, 'genre': ?genre}),
        Track.fromJson,
      );

  Future<List<Track>> tracksByIds(List<String> ids) async => _list(
    await _post('/api/music/tracks/batch', {'ids': ids}),
    Track.fromJson,
  );

  Future<void> reportPlayed(String id, int at) =>
      _post('/api/music/tracks/$id/played', {'at': at});

  Future<List<Album>> albums({String sort = 'title'}) async =>
      _list(await _get('/api/music/albums', {'sort': sort}), Album.fromJson);

  Future<AlbumDetail> album(String id) async => AlbumDetail.fromJson(
    await _get('/api/music/albums/$id') as Map<String, dynamic>,
  );

  Future<List<Artist>> artists() async =>
      _list(await _get('/api/music/artists'), Artist.fromJson);

  Future<ArtistDetail> artist(String id) async => ArtistDetail.fromJson(
    await _get('/api/music/artists/$id') as Map<String, dynamic>,
  );

  Future<List<Genre>> genres() async =>
      _list(await _get('/api/music/genres'), Genre.fromJson);

  Future<SearchResults> search(String q) async => SearchResults.fromJson(
    await _get('/api/music/search', {'q': q}) as Map<String, dynamic>,
  );

  Future<BrowseResult> browse(String path, {bool recursive = false}) async =>
      BrowseResult.fromJson(
        await _get('/api/music/browse', {
              'path': path,
              if (recursive) 'recursive': '1',
            })
            as Map<String, dynamic>,
      );

  Future<List<Track>> liked() async =>
      _list(await _get('/api/music/liked'), Track.fromJson);

  Future<void> setLiked(List<String> ids, bool liked) =>
      _post('/api/music/like', {'ids': ids, 'liked': liked});

  // ---- playlists ----
  Future<List<Playlist>> playlists() async =>
      _list(await _get('/api/music/playlists'), Playlist.fromJson);
  Future<Playlist> playlist(String id) async => Playlist.fromJson(
    await _get('/api/music/playlists/$id') as Map<String, dynamic>,
  );
  Future<Playlist> createPlaylist(
    String name, [
    List<String> ids = const [],
  ]) async => Playlist.fromJson(
    await _post('/api/music/playlists', {'name': name, 'ids': ids})
        as Map<String, dynamic>,
  );
  Future<Playlist> renamePlaylist(String id, String name) async =>
      Playlist.fromJson(
        await _send('PUT', '/api/music/playlists/$id', body: {'name': name})
            as Map<String, dynamic>,
      );
  Future<void> deletePlaylist(String id) =>
      _send('DELETE', '/api/music/playlists/$id');
  Future<Playlist> setPlaylistTracks(String id, List<String> ids) async =>
      Playlist.fromJson(
        await _send(
              'PUT',
              '/api/music/playlists/$id/tracks',
              body: {'ids': ids},
            )
            as Map<String, dynamic>,
      );

  /// Returns how many songs were added.
  Future<int> addToPlaylist(
    String id,
    List<String> ids, {
    bool skipDuplicates = true,
  }) async {
    final j =
        await _post('/api/music/playlists/$id/tracks', {
              'ids': ids,
              'skipDuplicates': skipDuplicates,
            })
            as Map<String, dynamic>;
    return (j['added'] as num?)?.toInt() ?? 0;
  }

  // ---- server settings (password) ----
  Future<MusicSettings> settings() async => MusicSettings.fromJson(
    await _get('/api/music/settings') as Map<String, dynamic>,
  );
  Future<void> checkAdmin(String password) => _send(
    'POST',
    '/api/music/admin/check',
    body: {},
    adminPassword: password,
  );
  Future<MusicSettings> updateSettings(
    Map<String, dynamic> patch,
    String password,
  ) async => MusicSettings.fromJson(
    await _send(
          'PUT',
          '/api/music/settings',
          body: patch,
          adminPassword: password,
        )
        as Map<String, dynamic>,
  );
  Future<void> addFolder(String path, String name, String password) => _send(
    'POST',
    '/api/music/folders',
    body: {'path': path, 'name': name},
    adminPassword: password,
  );
  Future<void> removeFolder(int id, String password) =>
      _send('DELETE', '/api/music/folders/$id', adminPassword: password);
  Future<FsListing> fs(String path) async => FsListing.fromJson(
    await _get('/api/fs', {'path': path}) as Map<String, dynamic>,
  );
  Future<void> scan({bool refreshCovers = false}) =>
      _post('/api/music/scan', {'refreshCovers': refreshCovers});
  Future<ScanStatus> scanStatus() async => ScanStatus.fromJson(
    await _get('/api/music/scan/status') as Map<String, dynamic>,
  );
}
