import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TvDevice {
  final String id;
  String name;
  String host;
  String? token; // אישור החיבור שהטלוויזיה נתנה
  String? mac; // להדלקה דרך הרשת
  TvDevice({required this.id, required this.name, required this.host, this.token, this.mac});

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'host': host, 'token': token, 'mac': mac};
  factory TvDevice.fromJson(Map<String, dynamic> j) => TvDevice(
      id: j['id'], name: j['name'], host: j['host'], token: j['token'], mac: j['mac']);
}

class AppButton {
  final String id;
  String label;
  final int color;
  String appId;
  AppButton(this.id, this.label, this.color, this.appId);

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'color': color, 'appId': appId};
  factory AppButton.fromJson(Map<String, dynamic> j) =>
      AppButton(j['id'], j['label'], j['color'], j['appId'] ?? '');
}

List<AppButton> defaultApps() => [
      AppButton('freetv', 'FreeTV', 0xFFFF8A1F, ''),
      AppButton('cellcom', 'Cellcom tv', 0xFFB07CFF, ''),
      AppButton('youtube', 'YouTube', 0xFFFF3B3B, '111299001912'),
      AppButton('netflix', 'Netflix', 0xFFE50914, '3201907018807'),
    ];

class Store {
  final SharedPreferences prefs;
  Store(this.prefs);

  List<TvDevice> loadTvs() {
    final s = prefs.getString('tvs');
    if (s == null) return [];
    return (jsonDecode(s) as List).map((e) => TvDevice.fromJson(e)).toList();
  }

  Future<void> saveTvs(List<TvDevice> tvs) =>
      prefs.setString('tvs', jsonEncode(tvs.map((t) => t.toJson()).toList()));

  List<AppButton> loadApps() {
    final s = prefs.getString('apps');
    if (s == null) return defaultApps();
    return (jsonDecode(s) as List).map((e) => AppButton.fromJson(e)).toList();
  }

  Future<void> saveApps(List<AppButton> apps) =>
      prefs.setString('apps', jsonEncode(apps.map((a) => a.toJson()).toList()));

  String? get selected => prefs.getString('selected');
  set selected(String? id) =>
      id == null ? prefs.remove('selected') : prefs.setString('selected', id);
}
