import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/prefs.dart';

enum AppStage { noServer, connecting, connectError, chooseProfile, ready }

class AppState extends ChangeNotifier {
  final Prefs prefs;
  AppState(this.prefs);

  AppStage stage = AppStage.noServer;
  ServerConfig? server;
  ServerInfo? serverInfo;
  ApiClient? api;
  Profile? profile;
  List<Profile> profiles = [];
  String? error;

  /// Incremented whenever library or user data may have changed; screens
  /// listening to it refetch.
  final ValueNotifier<int> dataVersion = ValueNotifier(0);

  void bumpData() => dataVersion.value++;

  List<ServerConfig> get servers => prefs.servers;

  // Compile-time hooks used only by the CI memory test build.
  static const _testServer = String.fromEnvironment('HS_TEST_SERVER');
  static const _testScreen = String.fromEnvironment('HS_TEST_SCREEN');

  Future<void> start() async {
    if (_testServer.isNotEmpty) {
      await connect(ServerConfig(id: 'test', name: '', url: _testServer));
      if (_testScreen == 'home' && profiles.isNotEmpty) {
        selectProfile(profiles.first);
      }
      return;
    }
    final list = prefs.servers;
    if (list.isEmpty) {
      stage = AppStage.noServer;
      notifyListeners();
      return;
    }
    final active = list.firstWhere(
      (s) => s.id == prefs.activeServerId,
      orElse: () => list.first,
    );
    await connect(active);
  }

  Future<void> connect(
    ServerConfig s, {
    bool forceProfilePicker = false,
  }) async {
    api?.close();
    server = s;
    stage = AppStage.connecting;
    error = null;
    profile = null;
    notifyListeners();
    final client = ApiClient(s.url);
    try {
      serverInfo = await client.info(timeout: const Duration(seconds: 6));
      profiles = _ordered(await client.profiles());
      api = client;
      prefs.activeServerId = s.id;
      if (serverInfo!.name.isNotEmpty && s.name.isEmpty) {
        s.name = serverInfo!.name;
        _saveServer(s);
      }
      final last = prefs.lastProfile(s.id);
      final lastProfile = profiles.where((p) => p.id == last).firstOrNull;
      if (!forceProfilePicker &&
          lastProfile != null &&
          !prefs.askProfileOnStart) {
        selectProfile(lastProfile);
      } else {
        stage = AppStage.chooseProfile;
        notifyListeners();
      }
    } catch (e) {
      client.close();
      error = e.toString();
      stage = AppStage.connectError;
      notifyListeners();
    }
  }

  Future<void> retry() async {
    if (server != null) await connect(server!);
  }

  void selectProfile(Profile p) {
    profile = p;
    api?.profileId = p.id;
    if (server != null) prefs.setLastProfile(server!.id, p.id);
    stage = AppStage.ready;
    bumpData();
    notifyListeners();
  }

  void switchProfile() {
    stage = AppStage.chooseProfile;
    profile = null;
    api?.profileId = null;
    notifyListeners();
    refreshProfiles();
  }

  /// Applies this device's profile order; profiles it doesn't know yet
  /// (new ones) keep the server order after the ordered ones.
  List<Profile> _ordered(List<Profile> list) {
    final order = server == null
        ? const <String>[]
        : prefs.profileOrder(server!.id);
    if (order.isEmpty) return list;
    final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
    final out = [...list];
    final pos = {for (var i = 0; i < list.length; i++) list[i].id: i};
    out.sort((a, b) {
      final ra = rank[a.id], rb = rank[b.id];
      if (ra != null && rb != null) return ra.compareTo(rb);
      if (ra != null) return -1;
      if (rb != null) return 1;
      return pos[a.id]!.compareTo(pos[b.id]!);
    });
    return out;
  }

  /// Saves the profile order for this device only.
  void setProfileOrder(List<Profile> ordered) {
    if (server == null) return;
    prefs.setProfileOrder(server!.id, [for (final p in ordered) p.id]);
    profiles = _ordered(profiles);
    notifyListeners();
  }

  Future<void> refreshProfiles() async {
    if (api == null) return;
    try {
      profiles = _ordered(await api!.profiles());
      // keep the signed-in profile's name/photo up to date
      final cur = profile;
      if (cur != null) {
        profile = profiles.where((p) => p.id == cur.id).firstOrNull ?? cur;
      }
      notifyListeners();
    } catch (_) {}
  }

  // ---- server list management ----
  ServerConfig addServer(String name, String url) {
    final list = prefs.servers;
    final normalized = normalizeServerUrl(url);
    final existing = list.where((s) => s.url == normalized).firstOrNull;
    if (existing != null) {
      if (name.isNotEmpty) existing.name = name;
      prefs.servers = list;
      notifyListeners();
      return existing;
    }
    final s = ServerConfig(
      id: '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(999)}',
      name: name,
      url: normalized,
    );
    prefs.servers = [...list, s];
    notifyListeners();
    return s;
  }

  void _saveServer(ServerConfig s) {
    final list = prefs.servers;
    final i = list.indexWhere((e) => e.id == s.id);
    if (i >= 0) {
      list[i] = s;
      prefs.servers = list;
    }
  }

  void updateServer(ServerConfig s, {String? name, String? url}) {
    if (name != null) s.name = name;
    if (url != null) s.url = normalizeServerUrl(url);
    _saveServer(s);
    notifyListeners();
  }

  Future<void> removeServer(ServerConfig s) async {
    prefs.servers = prefs.servers.where((e) => e.id != s.id).toList();
    prefs.setLastProfile(s.id, null);
    if (server?.id == s.id) {
      api?.close();
      api = null;
      server = null;
      profile = null;
      final rest = prefs.servers;
      if (rest.isEmpty) {
        prefs.activeServerId = null;
        stage = AppStage.noServer;
        notifyListeners();
      } else {
        await connect(rest.first);
      }
    } else {
      notifyListeners();
    }
  }

  void showServerSetup() {
    stage = AppStage.noServer;
    notifyListeners();
  }
}
