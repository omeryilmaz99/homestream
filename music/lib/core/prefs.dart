import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ServerConfig {
  final String id; // server id reported by the server (or the URL)
  String name;
  String url;
  ServerConfig({required this.id, required this.name, required this.url});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url};
  factory ServerConfig.fromJson(Map<String, dynamic> j) =>
      ServerConfig(id: '${j['id']}', name: '${j['name']}', url: '${j['url']}');
}

/// Device settings: every phone has its own, no password needed.
class Prefs {
  final SharedPreferences _p;
  Prefs(this._p);

  static Future<Prefs> load() async =>
      Prefs(await SharedPreferences.getInstance());

  // ---- server & profile ----
  List<ServerConfig> get servers {
    final raw = _p.getString('servers');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
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

  /// "Beni hatırla": the profile opened without asking (per server).
  String? rememberedProfile(String serverId) =>
      _p.getString('rememberProfile.$serverId');
  void setRememberedProfile(String serverId, String? profileId) =>
      profileId == null
      ? _p.remove('rememberProfile.$serverId')
      : _p.setString('rememberProfile.$serverId', profileId);

  /// The last used profile (kept for offline use even without "remember me").
  String? lastProfileJson(String serverId) =>
      _p.getString('lastProfile.$serverId');
  void setLastProfileJson(String serverId, String json) =>
      _p.setString('lastProfile.$serverId', json);

  // ---- playback ----
  /// Crossfade between songs in seconds (0 = off).
  int get crossfade => (_p.getInt('crossfade') ?? 0).clamp(0, 12);
  set crossfade(int v) => _p.setInt('crossfade', v.clamp(0, 12));

  /// Skip the crossfade between songs of the same album (live albums, DJ mixes).
  bool get smartCrossfade => _p.getBool('smartCrossfade') ?? true;
  set smartCrossfade(bool v) => _p.setBool('smartCrossfade', v);

  /// 'off' | 'track' | 'album'
  String get replayGain => _p.getString('replayGain') ?? 'off';
  set replayGain(String v) => _p.setString('replayGain', v);

  /// AudioTrack output with floating point samples (better quality).
  bool get hiFiOutput => _p.getBool('hiFiOutput') ?? true;
  set hiFiOutput(bool v) => _p.setBool('hiFiOutput', v);

  double get volume => _p.getDouble('volume') ?? 100;
  set volume(double v) => _p.setDouble('volume', v);

  /// Prefer downloaded files even when the server is reachable.
  bool get preferDownloads => _p.getBool('preferDownloads') ?? true;
  set preferDownloads(bool v) => _p.setBool('preferDownloads', v);

  /// Pause when headphones are unplugged / bluetooth disconnects.
  bool get pauseOnUnplug => _p.getBool('pauseOnUnplug') ?? true;
  set pauseOnUnplug(bool v) => _p.setBool('pauseOnUnplug', v);

  /// Show the moving background on the player screen.
  bool get animations => _p.getBool('animations') ?? true;
  set animations(bool v) => _p.setBool('animations', v);

  bool get askedBattery => _p.getBool('askedBattery') ?? false;
  set askedBattery(bool v) => _p.setBool('askedBattery', v);

  // ---- offline play counts ----
  List<Map<String, dynamic>> get pendingPlays {
    try {
      return (jsonDecode(_p.getString('pendingPlays') ?? '[]') as List)
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  set pendingPlays(List<Map<String, dynamic>> v) => _p.setString(
    'pendingPlays',
    jsonEncode(v.length > 2000 ? v.sublist(v.length - 2000) : v),
  );

  // ---- recent searches ----
  List<String> get recentSearches =>
      _p.getStringList('recentSearches') ?? const [];
  set recentSearches(List<String> v) =>
      _p.setStringList('recentSearches', v.take(12).toList());
}
