// הדלקה דרך הרשת (Wake-on-LAN)
import 'dart:io';

Future<bool> wakeOnLan(String mac, String host) async {
  final parts = mac.split(RegExp('[:-]'));
  if (parts.length != 6) return false;
  final m = parts.map((h) => int.parse(h, radix: 16)).toList();
  final packet = <int>[...List.filled(6, 0xff), for (var i = 0; i < 16; i++) ...m];

  final p = host.split('.');
  final targets = <String>[
    '255.255.255.255',
    if (p.length == 4) '${p[0]}.${p[1]}.${p[2]}.255',
    host,
  ];

  var sent = false;
  RawDatagramSocket? sock;
  try {
    sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    sock.broadcastEnabled = true;
    for (var round = 0; round < 3; round++) {
      for (final t in targets) {
        for (final port in [9, 7]) {
          try {
            if (sock.send(packet, InternetAddress(t), port) > 0) sent = true;
          } catch (_) {}
        }
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }
  } catch (_) {
  } finally {
    sock?.close();
  }
  return sent;
}
