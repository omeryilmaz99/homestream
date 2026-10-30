import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/discovery.dart';
import '../core/events.dart';
import '../core/platform.dart';
import '../core/prefs.dart';
import '../core/transfers.dart';

enum Phase { start, connecting, needLogin, ready, unreachable }

class AppState extends ChangeNotifier {
  final Prefs prefs;
  final TransferManager transfers;
  AppState(this.prefs) : transfers = TransferManager(prefs);

  List<ServerConfig> servers = [];
  ServerConfig? server;
  FilesApi? api;
  ServerEvents? _events;
  Phase phase = Phase.start;
  String? error;
  String deviceName = '';
  LinkState link = LinkState.offline;

  /// Tokens of logins without "Beni hatırla" (only while the app runs).
  final Map<String, String> _memTokens = {};
  final _relay = StreamController<ServerEvent>.broadcast();
  StreamSubscription<ServerEvent>? _sub;
  Timer? _retry;
  int _connectGen = 0;

  /// Events from the active server: change, job, disks, sessions, reconnected, lost.
  Stream<ServerEvent> get events => _relay.stream;
  ServerEvents? get serverEvents => _events;
  DateTime? get offlineSince => _events?.offlineSince;
  bool get online => phase == Phase.ready && link == LinkState.online;

  Future<void> init() async {
    deviceName = prefs.deviceName ?? await AppPlatform.defaultDeviceName();
    servers = prefs.servers..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    final active = prefs.activeServerId;
    final s = servers.where((e) => e.id == active).firstOrNull;
    if (s != null && s.token != null) {
      unawaited(connect(s));
    } else {
      phase = Phase.needLogin;
      server = s;
      notifyListeners();
    }
  }

  void setDeviceName(String v) {
    deviceName = v.trim().isEmpty ? deviceName : v.trim();
    prefs.deviceName = deviceName;
    notifyListeners();
  }

  void _saveServers() {
    prefs.servers = servers;
    notifyListeners();
  }

  String? tokenFor(ServerConfig s) => s.token ?? _memTokens[s.id];
  bool remembered(ServerConfig s) => s.token != null;

  /// Opens a known server with its saved login.
  Future<void> connect(ServerConfig s) async {
    final gen = ++_connectGen;
    _retry?.cancel();
    _closeConnection();
    server = s;
    error = null;
    final tok = tokenFor(s);
    if (tok == null) {
      phase = Phase.needLogin;
      notifyListeners();
      return;
    }
    phase = Phase.connecting;
    notifyListeners();
    var a = FilesApi(s.url, token: tok);
    try {
      await a.session();
    } on ApiException catch (e) {
      if (gen != _connectGen) return;
      if (e.unauthorized) {
        _forgetToken(s);
        phase = Phase.needLogin;
        error = 'Oturumun süresi doldu, şifreyi tekrar gir.';
        notifyListeners();
        return;
      }
      if (e.offline) {
        // the server may have a new address (e.g. moved to another network)
        final moved = await _findMoved(s);
        if (gen != _connectGen) return;
        if (moved != null) {
          a.close();
          a = FilesApi(moved, token: tok);
          try {
            await a.session();
            s.url = moved;
            _saveServers();
          } catch (_) {
            return _unreachable(s, gen, e.message);
          }
        } else {
          return _unreachable(s, gen, e.message);
        }
      } else {
        return _unreachable(s, gen, e.message);
      }
    }
    if (gen != _connectGen) {
      a.close();
      return;
    }
    _ready(s, a);
  }

  void _unreachable(ServerConfig s, int gen, String msg) {
    if (gen != _connectGen) return;
    phase = Phase.unreachable;
    error = msg;
    notifyListeners();
    // keeps trying in the background
    _retry = Timer(const Duration(seconds: 10), () {
      if (phase == Phase.unreachable && server?.id == s.id) connect(s);
    });
  }

  Future<String?> _findMoved(ServerConfig s) async {
    try {
      final found = await discoverServers(
        timeout: const Duration(seconds: 2),
      );
      for (final f in found) {
        if (f.id == s.id && f.url != s.url) return f.url;
      }
    } catch (_) {}
    return null;
  }

  void _ready(ServerConfig s, FilesApi a) {
    api = a;
    phase = Phase.ready;
    error = null;
    s.lastUsed = DateTime.now().millisecondsSinceEpoch;
    prefs.activeServerId = s.id;
    _saveServers();
    final ev = ServerEvents(s.url, a.token!);
    _events = ev;
    ev.onWatchChanged = (id, dirs) {
      a.setWatch(id, dirs).catchError((_) {});
    };
    ev.state.addListener(() {
      link = ev.state.value;
      transfers.setOnline(link == LinkState.online);
      notifyListeners();
    });
    _sub = ev.events.listen((e) {
      if (e.name == 'unauthorized' || e.name == 'revoked') {
        _forgetToken(s);
        _closeConnection();
        phase = Phase.needLogin;
        error = e.name == 'revoked'
            ? 'Bu cihazın oturumu sunucudan kapatıldı.'
            : 'Oturumun süresi doldu, şifreyi tekrar gir.';
        notifyListeners();
        return;
      }
      _relay.add(e);
    });
    ev.start();
    transfers.attach(a, s.id);
    notifyListeners();
  }

  void _closeConnection() {
    _sub?.cancel();
    _sub = null;
    _events?.dispose();
    _events = null;
    transfers.attach(null, null);
    transfers.setOnline(false);
    api?.close();
    api = null;
    link = LinkState.offline;
  }

  void _forgetToken(ServerConfig s) {
    _memTokens.remove(s.id);
    if (s.token != null) {
      s.token = null;
      _saveServers();
    }
  }

  /// Checks an address and logs in. Throws ApiException with a Turkish message.
  Future<void> login(String url, String password, {bool remember = true}) async {
    final base = normalizeServerUrl(url);
    if (base.isEmpty) throw ApiException('Sunucu adresini yaz');
    final a = FilesApi(base);
    final info = await a.info();
    if (info['files'] != true) {
      a.close();
      throw ApiException(
        'Bu sunucu dosya aktarımını desteklemiyor. Sunucuyu güncelle (kurulum komutunu tekrar çalıştır).',
      );
    }
    final res = await a.login(password, deviceName, AppPlatform.platformName);
    final id = res.serverId.isNotEmpty ? res.serverId : '${info['id'] ?? base}';
    var s = servers.where((e) => e.id == id).firstOrNull;
    if (s == null) {
      s = ServerConfig(id: id, name: res.serverName, url: base);
      servers.insert(0, s);
    }
    s.url = base;
    if (res.serverName.isNotEmpty) s.name = res.serverName;
    if (remember) {
      s.token = res.token;
      _memTokens.remove(id);
    } else {
      s.token = null;
      _memTokens[id] = res.token;
    }
    _saveServers();
    ++_connectGen;
    _retry?.cancel();
    _closeConnection();
    server = s;
    _ready(s, a);
  }

  Future<void> logout() async {
    final s = server;
    if (s == null) return;
    await api?.logout();
    _forgetToken(s);
    _closeConnection();
    phase = Phase.needLogin;
    error = null;
    notifyListeners();
  }

  void forgetServer(ServerConfig s) {
    if (server?.id == s.id) {
      api?.logout();
      _closeConnection();
      server = null;
      phase = Phase.needLogin;
      prefs.activeServerId = null;
    }
    _memTokens.remove(s.id);
    servers.removeWhere((e) => e.id == s.id);
    _saveServers();
  }

  void renameServer(ServerConfig s, String name) {
    s.name = name.trim().isEmpty ? s.name : name.trim();
    _saveServers();
  }

  /// Stop using the current server (go to the server list).
  void disconnect() {
    ++_connectGen;
    _retry?.cancel();
    _closeConnection();
    phase = Phase.needLogin;
    notifyListeners();
  }

  void retryNow() {
    final s = server;
    if (s == null) return;
    if (phase == Phase.ready) {
      _events?.kick();
    } else {
      connect(s);
    }
  }

  /// The app came back to the foreground.
  void resumed() {
    if (phase == Phase.ready) {
      _events?.kick();
    } else if (phase == Phase.unreachable) {
      retryNow();
    }
  }

  void setWatch(Set<String> dirs) => _events?.setWatch(dirs);

  @override
  void dispose() {
    _closeConnection();
    transfers.dispose();
    _relay.close();
    super.dispose();
  }
}
