// חיפוש טלוויזיות סמסונג ברשת: פורט 8001 + בדיקת פרטי המכשיר
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// מחזיר את פרטי הטלוויזיה (שם, MAC) או null אם זו לא טלוויזיית סמסונג
Future<({String name, String? mac, bool on})?> tvInfo(String host) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final req = await client
        .getUrl(Uri.parse('http://$host:8001/api/v2/'))
        .timeout(const Duration(seconds: 3));
    final res = await req.close().timeout(const Duration(seconds: 3));
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 3));
    final j = jsonDecode(body) as Map<String, dynamic>;
    final d = (j['device'] ?? {}) as Map<String, dynamic>;
    final name = (d['name'] ?? j['name'] ?? 'Samsung TV').toString();
    final mac = d['wifiMac']?.toString();
    final on = (d['PowerState'] ?? 'on').toString().toLowerCase() == 'on';
    return (name: name, mac: (mac == null || mac.isEmpty) ? null : mac, on: on);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<List<({String ip, String name})>> scanForTvs({void Function(double)? onProgress}) async {
  final ifaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4, includeLoopback: false);

  bool isPrivate(String ip) =>
      ip.startsWith('192.168.') ||
      ip.startsWith('10.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
  bool isWifi(String name) =>
      name.startsWith('wlan') || name.startsWith('en') || name.startsWith('eth');

  final prefixes = <String>{};
  for (final wifiOnly in [true, false]) {
    for (final i in ifaces) {
      if (wifiOnly && !isWifi(i.name)) continue;
      for (final a in i.addresses) {
        if (!isPrivate(a.address)) continue;
        final p = a.address.split('.');
        prefixes.add('${p[0]}.${p[1]}.${p[2]}');
      }
    }
    if (prefixes.isNotEmpty) break;
  }

  final hosts = [
    for (final p in prefixes)
      for (var n = 1; n < 255; n++) '$p.$n'
  ];
  final open = <String>[];
  var done = 0;
  const batch = 48;
  for (var i = 0; i < hosts.length; i += batch) {
    final chunk = hosts.sublist(i, min(i + batch, hosts.length));
    await Future.wait(chunk.map((ip) async {
      try {
        final s = await Socket.connect(ip, 8001, timeout: const Duration(milliseconds: 700));
        s.destroy();
        open.add(ip);
      } catch (_) {}
    }));
    done += chunk.length;
    onProgress?.call(done / hosts.length);
  }

  final found = <({String ip, String name})>[];
  await Future.wait(open.map((ip) async {
    final info = await tvInfo(ip);
    if (info != null) found.add((ip: ip, name: info.name));
  }));
  found.sort((a, b) =>
      int.parse(a.ip.split('.').last).compareTo(int.parse(b.ip.split('.').last)));
  return found;
}
