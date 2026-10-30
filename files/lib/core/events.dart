import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

enum LinkState { connecting, online, offline }

class ServerEvent {
  final String name;
  final dynamic data;
  ServerEvent(this.name, this.data);
}

/// Live link to the server (Server-Sent Events). It notices a dead
/// connection within ~25 s (the server pings every 10 s) and reconnects by
/// itself with a growing delay.
class ServerEvents {
  final String baseUrl;
  final String token;
  ServerEvents(this.baseUrl, this.token);

  final state = ValueNotifier<LinkState>(LinkState.connecting);
  final _events = StreamController<ServerEvent>.broadcast();
  Stream<ServerEvent> get events => _events.stream;

  /// The connection's id on the server (to change the watched folders).
  String? connId;
  DateTime? offlineSince;
  String? lastError;

  Set<String> _watch = {};
  HttpClient? _client;
  HttpClientRequest? _req;
  Timer? _watchdog;
  Timer? _retry;
  DateTime _lastData = DateTime.now();
  int _failures = 0;
  bool _stopped = false;
  void Function(String connId, List<String> dirs)? onWatchChanged;

  void start() {
    _stopped = false;
    _connect();
    _watchdog ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (state.value == LinkState.online &&
          DateTime.now().difference(_lastData).inSeconds > 25) {
        _drop('Sunucudan ses gelmiyor');
      }
    });
  }

  void stop() {
    _stopped = true;
    _watchdog?.cancel();
    _watchdog = null;
    _retry?.cancel();
    _client?.close(force: true);
    _client = null;
  }

  void dispose() {
    stop();
    _events.close();
    state.dispose();
  }

  /// Reconnect now (e.g. after the network came back or the app resumed).
  void kick() {
    if (_stopped) return;
    if (state.value == LinkState.online) {
      if (DateTime.now().difference(_lastData).inSeconds > 15) {
        _drop('Bağlantı yenileniyor');
      }
      return;
    }
    _retry?.cancel();
    _failures = 0;
    _connect();
  }

  void setWatch(Set<String> dirs) {
    if (setEquals(dirs, _watch)) return;
    _watch = {...dirs};
    final id = connId;
    if (id != null && state.value == LinkState.online) {
      onWatchChanged?.call(id, _watch.toList());
    }
  }

  void _setState(LinkState s) {
    if (s == LinkState.offline && state.value != LinkState.offline) {
      offlineSince = DateTime.now();
    }
    if (s == LinkState.online) offlineSince = null;
    state.value = s;
  }

  Future<void> _connect() async {
    if (_stopped) return;
    _client?.close(force: true);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 30);
    _client = client;
    if (state.value != LinkState.offline) _setState(LinkState.connecting);
    try {
      final u = Uri.parse('$baseUrl/api/files/events').replace(
        queryParameters: {
          if (_watch.isNotEmpty) 'watch': _watch.toList(),
        },
      );
      final req = await client.getUrl(u);
      _req = req;
      req.headers.set('Authorization', 'Bearer $token');
      req.headers.set('Accept', 'text/event-stream');
      final resp = await req.close().timeout(const Duration(seconds: 12));
      if (resp.statusCode == 401) {
        _events.add(ServerEvent('unauthorized', null));
        await resp.drain<void>();
        _setState(LinkState.offline);
        lastError = 'Oturum kapatıldı';
        _schedule(long: true);
        return;
      }
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        throw HttpException('HTTP ${resp.statusCode}');
      }
      _lastData = DateTime.now();
      String? event;
      final data = StringBuffer();
      await for (final line
          in resp.transform(utf8.decoder).transform(const LineSplitter())) {
        _lastData = DateTime.now();
        if (line.isEmpty) {
          if (event != null) _dispatch(event, data.toString());
          event = null;
          data.clear();
        } else if (line.startsWith('event: ')) {
          event = line.substring(7);
        } else if (line.startsWith('data: ')) {
          data.write(line.substring(6));
        }
      }
      throw const SocketException('Bağlantı kapandı');
    } catch (e) {
      if (_stopped || !identical(client, _client)) return;
      lastError = e is TimeoutException
          ? 'Zaman aşımı'
          : (e is SocketException ? 'Sunucuya ulaşılamıyor' : '$e');
      final wasOnline = state.value == LinkState.online;
      _setState(LinkState.offline);
      connId = null;
      if (wasOnline) _events.add(ServerEvent('lost', null));
      _schedule();
    }
  }

  void _dispatch(String name, String raw) {
    dynamic data;
    try {
      data = raw.isEmpty ? null : jsonDecode(raw);
    } catch (_) {}
    if (name == 'hello') {
      connId = data is Map ? '${data['id']}' : null;
      final wasOffline = state.value == LinkState.offline;
      _failures = 0;
      _setState(LinkState.online);
      lastError = null;
      if (wasOffline) _events.add(ServerEvent('reconnected', null));
    }
    if (name == 'ping') return;
    _events.add(ServerEvent(name, data));
  }

  void _drop(String why) {
    lastError = why;
    final c = _client;
    _client = null;
    c?.close(force: true);
    try {
      _req?.abort();
    } catch (_) {}
    _setState(LinkState.offline);
    connId = null;
    _events.add(ServerEvent('lost', null));
    _schedule();
  }

  void _schedule({bool long = false}) {
    if (_stopped) return;
    _retry?.cancel();
    _failures++;
    final secs = long ? 60 : min(20, pow(2, min(_failures, 5)).toInt());
    _retry = Timer(Duration(seconds: secs), _connect);
  }
}
