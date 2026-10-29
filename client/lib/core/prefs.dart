import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ServerConfig {
  final String id; // local id
  String name;
  String url;
  ServerConfig({required this.id, required this.name, required this.url});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url};
  factory ServerConfig.fromJson(Map<String, dynamic> j) =>
      ServerConfig(id: '${j['id']}', name: '${j['name']}', url: '${j['url']}');
}

/// How a title should be opened.
enum PlayerMode { ask, internal, external }

class ExternalPlayerConfig {
  final String name;
  final String path;
  const ExternalPlayerConfig(this.name, this.path);
  Map<String, dynamic> toJson() => {'name': name, 'path': path};
  factory ExternalPlayerConfig.fromJson(Map<String, dynamic> j) =>
      ExternalPlayerConfig('${j['name']}', '${j['path']}');
}

/// Device-local settings (each PC/TV/phone has its own).
class Prefs {
  final SharedPreferences _p;
  Prefs(this._p);

  static Future<Prefs> load() async =>
      Prefs(await SharedPreferences.getInstance());

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

  /// Profile order chosen on this device (ids), per server.
  List<String> profileOrder(String serverId) =>
      _p.getStringList('profileOrder.$serverId') ?? const [];
  void setProfileOrder(String serverId, List<String> ids) =>
      _p.setStringList('profileOrder.$serverId', ids);

  String? lastProfile(String serverId) => _p.getString('lastProfile.$serverId');
  void setLastProfile(String serverId, String? profileId) => profileId == null
      ? _p.remove('lastProfile.$serverId')
      : _p.setString('lastProfile.$serverId', profileId);

  String? get theme => _p.getString('theme');
  set theme(String? v) =>
      v == null ? _p.remove('theme') : _p.setString('theme', v);

  bool get askProfileOnStart => _p.getBool('askProfileOnStart') ?? true;
  set askProfileOnStart(bool v) => _p.setBool('askProfileOnStart', v);

  // ---- playback ----
  PlayerMode get playerMode =>
      PlayerMode.values[(_p.getInt('playerMode') ?? 0).clamp(0, 2)];
  set playerMode(PlayerMode v) => _p.setInt('playerMode', v.index);

  ExternalPlayerConfig? get externalPlayer {
    final raw = _p.getString('externalPlayer');
    if (raw == null) return null;
    try {
      return ExternalPlayerConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  set externalPlayer(ExternalPlayerConfig? v) => v == null
      ? _p.remove('externalPlayer')
      : _p.setString('externalPlayer', jsonEncode(v.toJson()));

  bool get hardwareDecoding => _p.getBool('hwdec') ?? true;
  set hardwareDecoding(bool v) => _p.setBool('hwdec', v);

  /// 'tur', 'eng' or 'off'
  String get subtitleLanguage => _p.getString('subLang') ?? 'tur';
  set subtitleLanguage(String v) => _p.setString('subLang', v);

  /// 'original', 'tur', 'eng'
  String get audioLanguage => _p.getString('audioLang') ?? 'original';
  set audioLanguage(String v) => _p.setString('audioLang', v);

  /// Subtitle scale in percent (100 = mpv default size).
  int get subtitleScale => _p.getInt('subScale') ?? 100;
  set subtitleScale(int v) => _p.setInt('subScale', v);

  double get volume => _p.getDouble('volume') ?? 100;
  set volume(double v) => _p.setDouble('volume', v);

  bool get autoPlayNext => _p.getBool('autoPlayNext') ?? true;
  set autoPlayNext(bool v) => _p.setBool('autoPlayNext', v);

  int get nextCountdown => _p.getInt('nextCountdown') ?? 15;
  set nextCountdown(int v) => _p.setInt('nextCountdown', v);

  /// Start the player in full screen.
  /// Settings need the password on this device.
  bool get settingsLocked => _p.getBool('settingsLocked') ?? false;
  set settingsLocked(bool v) => _p.setBool('settingsLocked', v);

  /// Phones: false = player locked to landscape, true = turns with the phone.
  bool get playerAutoRotate => _p.getBool('playerAutoRotate') ?? false;
  set playerAutoRotate(bool v) => _p.setBool('playerAutoRotate', v);

  bool get playerFullscreen => _p.getBool('playerFullscreen') ?? true;
  set playerFullscreen(bool v) => _p.setBool('playerFullscreen', v);

  int get seekStep => _p.getInt('seekStep') ?? 10;
  set seekStep(int v) => _p.setInt('seekStep', v);
}
