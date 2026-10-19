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

  Future<void> start() async {
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
      profiles = await client.profiles();
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

  Future<void> refreshProfiles() async {
    if (api == null) return;
    try {
      profiles = await api!.profiles();
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
