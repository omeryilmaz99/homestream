import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveredServer {
  final String id;
  final String name;
  final String url;
  final String version;
  DiscoveredServer(this.id, this.name, this.url, this.version);
}

/// Finds Home Stream servers on the local network via UDP broadcast (port 8421).
Future<List<DiscoveredServer>> discoverServers({
  Duration timeout = const Duration(seconds: 3),
}) async {
  final found = <String, DiscoveredServer>{};
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final msg = utf8.encode('HOMESTREAM_DISCOVER');
    final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
    try {
      for (final ni in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        for (final a in ni.addresses) {
          final p = a.address.split('.');
          if (p.length == 4) {
            targets.add(InternetAddress('${p[0]}.${p[1]}.${p[2]}.255'));
          }
        }
      }
    } catch (_) {}
    final completer = Completer<void>();
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket!.receive();
      if (dg == null) return;
      try {
        final j = jsonDecode(utf8.decode(dg.data));
        if (j is Map && j['app'] == 'homestream') {
          final port = (j['port'] as num?)?.toInt() ?? 8420;
          final url = 'http://${dg.address.address}:$port';
          final id = '${j['id'] ?? url}';
          found[id] = DiscoveredServer(
            id,
            '${j['name'] ?? dg.address.address}',
            url,
            '${j['version'] ?? ''}',
          );
        }
      } catch (_) {}
    });
    // Send a few times; UDP can drop packets.
    for (var i = 0; i < 3; i++) {
      for (final t in targets) {
        try {
          socket.send(msg, t, 8421);
        } catch (_) {}
      }
      await Future.any([completer.future, Future.delayed(timeout ~/ 3)]);
    }
  } catch (_) {
    // Discovery is best effort.
  } finally {
    socket?.close();
  }
  return found.values.toList();
}
