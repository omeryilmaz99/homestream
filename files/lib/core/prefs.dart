import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A server this device knows. The token is kept only with "Beni hatırla".
class ServerConfig {
  final String id; // server id (stays the same when the IP changes)
  String name;
  String url;
  String? token;
  int lastUsed;
  ServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.token,
    this.lastUsed = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'token': ?token,
    'lastUsed': lastUsed,
  };

  factory ServerConfig.fromJson(Map<String, dynamic> j) => ServerConfig(
    id: '${j['id']}',
    name: '${j['name']}',
    url: '${j['url']}',
    token: j['token'] as String?,
    lastUsed: (j['lastUsed'] as num?)?.toInt() ?? 0,
  );

  String get host => Uri.tryParse(url)?.host ?? url;
}

/// A finished transfer, for "Son aktarımlar".
class HistoryEntry {
  final String name;
  final bool upload;
  final int size;
  final int at; // ms
  final String localPath;
  final String remotePath;
  final String serverId;
  final bool ok;
  HistoryEntry({
    required this.name,
    required this.upload,
    required this.size,
    required this.at,
    required this.localPath,
    required this.remotePath,
    required this.serverId,
    this.ok = true,
  });
  Map<String, dynamic> toJson() => {
    'n': name,
    'u': upload,
    's': size,
    'a': at,
    'l': localPath,
    'r': remotePath,
    'sv': serverId,
    'ok': ok,
  };
  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    name: '${j['n']}',
    upload: j['u'] == true,
    size: (j['s'] as num?)?.toInt() ?? 0,
    at: (j['a'] as num?)?.toInt() ?? 0,
    localPath: '${j['l'] ?? ''}',
    remotePath: '${j['r'] ?? ''}',
    serverId: '${j['sv'] ?? ''}',
    ok: j['ok'] != false,
  );
}

/// Settings of this device only.
class Prefs {
  final SharedPreferences _p;
  Prefs(this._p);

  static Future<Prefs> load() async =>
      Prefs(await SharedPreferences.getInstance());

  List<ServerConfig> get servers {
    try {
      return (jsonDecode(_p.getString('servers') ?? '[]') as List)
          .map((e) => ServerConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  set servers(List<ServerConfig> v) =>
      _p.setString('servers', jsonEncode(v.map((e) => e.toJson()).toList()));

  String? get activeServerId => _p.getString('activeServer');
  set activeServerId(String? v) =>
      v == null ? _p.remove('activeServer') : _p.setString('activeServer', v);

  /// Name shown on the server's "Bağlı cihazlar" list.
  String? get deviceName => _p.getString('deviceName');
  set deviceName(String? v) =>
      v == null ? _p.remove('deviceName') : _p.setString('deviceName', v);

  // ---- transfers ----
  int get parallel => (_p.getInt('parallel') ?? 2).clamp(1, 4);
  set parallel(int v) => _p.setInt('parallel', v.clamp(1, 4));

  /// Compare SHA-256 after each transfer.
  bool get verify => _p.getBool('verify') ?? false;
  set verify(bool v) => _p.setBool('verify', v);

  /// ask | overwrite | rename | skip
  String get conflict => _p.getString('conflict') ?? 'ask';
  set conflict(String v) => _p.setString('conflict', v);

  /// Continue unfinished transfers when the app starts.
  bool get autoResume => _p.getBool('autoResume') ?? true;
  set autoResume(bool v) => _p.setBool('autoResume', v);

  bool get keepMtime => _p.getBool('keepMtime') ?? true;
  set keepMtime(bool v) => _p.setBool('keepMtime', v);

  String? get downloadDir => _p.getString('downloadDir');
  set downloadDir(String? v) =>
      v == null ? _p.remove('downloadDir') : _p.setString('downloadDir', v);

  String get pendingTransfers => _p.getString('pendingTransfers') ?? '[]';
  set pendingTransfers(String v) => _p.setString('pendingTransfers', v);

  // ---- browsing ----
  bool get showHidden => _p.getBool('showHidden') ?? false;
  set showHidden(bool v) => _p.setBool('showHidden', v);

  /// name | size | date | type
  String get sortBy => _p.getString('sortBy') ?? 'name';
  set sortBy(String v) => _p.setString('sortBy', v);
  bool get sortAsc => _p.getBool('sortAsc') ?? true;
  set sortAsc(bool v) => _p.setBool('sortAsc', v);

  bool get gridView => _p.getBool('gridView') ?? false;
  set gridView(bool v) => _p.setBool('gridView', v);

  /// Last folder per side (server one is per server).
  String? lastPath(String key) => _p.getString('lastPath.$key');
  void setLastPath(String key, String path) =>
      _p.setString('lastPath.$key', path);

  /// Bookmarks: "local" or a server id.
  List<String> bookmarks(String key) =>
      _p.getStringList('bookmarks.$key') ?? const [];
  void setBookmarks(String key, List<String> v) =>
      _p.setStringList('bookmarks.$key', v);

  double get splitRatio => (_p.getDouble('split') ?? 0.5).clamp(0.2, 0.8);
  set splitRatio(double v) => _p.setDouble('split', v);

  // ---- history ----
  List<HistoryEntry> get history {
    try {
      return (jsonDecode(_p.getString('history') ?? '[]') as List)
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  set history(List<HistoryEntry> v) => _p.setString(
    'history',
    jsonEncode(
      (v.length > 300 ? v.sublist(0, 300) : v).map((e) => e.toJson()).toList(),
    ),
  );

  int get totalSent => _p.getInt('totalSent') ?? 0;
  set totalSent(int v) => _p.setInt('totalSent', v);
  int get totalReceived => _p.getInt('totalReceived') ?? 0;
  set totalReceived(int v) => _p.setInt('totalReceived', v);
  int get filesSent => _p.getInt('filesSent') ?? 0;
  set filesSent(int v) => _p.setInt('filesSent', v);
  int get filesReceived => _p.getInt('filesReceived') ?? 0;
  set filesReceived(int v) => _p.setInt('filesReceived', v);
}
