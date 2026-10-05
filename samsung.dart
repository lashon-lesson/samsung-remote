// חיבור לטלוויזיית סמסונג (Tizen) דרך WebSocket – פורט 8002 מוצפן, 8001 לדגמים ישנים
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'scanner.dart';
import 'store.dart';
import 'wol.dart';

enum TvStatus { offline, connecting, authorizing, ready, error }

class TvApp {
  final String id;
  final String name;
  TvApp(this.id, this.name);
}

class SamsungConnection extends ChangeNotifier {
  final TvDevice tv;
  final VoidCallback onSave;
  SamsungConnection(this.tv, this.onSave);

  TvStatus status = TvStatus.offline;
  String? error;

  WebSocket? _ws;
  Timer? _retry;
  Timer? _authTimer;
  int _fails = 0;
  bool _disposed = false;
  bool _playing = false;
  Completer<List<TvApp>>? _appsWaiter;

  static final _name = base64.encode(utf8.encode('Phone Remote'));

  bool get isReady => status == TvStatus.ready;

  void _set(TvStatus s, {String? err}) {
    if (_disposed) return;
    status = s;
    error = err;
    notifyListeners();
  }

  Future<WebSocket> _open() async {
    final token = tv.token == null ? '' : '&token=${tv.token}';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..badCertificateCallback = (cert, host, port) => true;
    try {
      return await WebSocket.connect(
        'wss://${tv.host}:8002/api/v2/channels/samsung.remote.control?name=$_name$token',
        customClient: client,
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      // דגמים ישנים (2016–2017) – בלי הצפנה
      return await WebSocket.connect(
        'ws://${tv.host}:8001/api/v2/channels/samsung.remote.control?name=$_name',
      ).timeout(const Duration(seconds: 8));
    }
  }

  Future<void> connect() async {
    _retry?.cancel();
    _authTimer?.cancel();
    _close();
    if (_disposed) return;
    _set(TvStatus.connecting);
    try {
      final ws = await _open();
      if (_disposed) {
        ws.close();
        return;
      }
      _ws = ws;
      ws.pingInterval = const Duration(seconds: 20);
      ws.listen(_onMsg,
          onDone: () => _onClosed(ws), onError: (_) => _onClosed(ws), cancelOnError: true);
      // אם הטלוויזיה לא אישרה מיד – כנראה מוצגת עליה בקשת אישור
      _authTimer = Timer(const Duration(milliseconds: 1500), () {
        if (status == TvStatus.connecting && _ws == ws) _set(TvStatus.authorizing);
      });
    } catch (_) {
      _scheduleRetry('הטלוויזיה לא עונה – בדוק שהיא דלוקה ושהכתובת נכונה');
    }
  }

  void _onMsg(dynamic raw) {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final event = m['event'];
    final data = m['data'];
    switch (event) {
      case 'ms.channel.connect':
        _authTimer?.cancel();
        final token = data is Map ? data['token']?.toString() : null;
        if (token != null && token.isNotEmpty && token != tv.token) {
          tv.token = token;
          onSave();
        }
        _fails = 0;
        _set(TvStatus.ready);
        _refreshMac();
        break;
      case 'ms.channel.unauthorized':
        _authTimer?.cancel();
        tv.token = null;
        onSave();
        _close();
        _set(TvStatus.error,
            err: 'הטלוויזיה חסמה את החיבור. בטלוויזיה: הגדרות ← כללי ← מנהל התקנים חיצוניים ← רשימת התקנים, ואפשר את "Phone Remote"');
        break;
      case 'ms.channel.timeOut':
        _authTimer?.cancel();
        _close();
        _set(TvStatus.error, err: 'לא אושר בזמן בטלוויזיה – נסה שוב');
        break;
      case 'ed.installedApp.get':
        final list = <TvApp>[];
        final items = data is Map ? data['data'] : null;
        if (items is List) {
          for (final a in items) {
            if (a is Map && a['appId'] != null) {
              list.add(TvApp(a['appId'].toString(), (a['name'] ?? a['appId']).toString()));
            }
          }
        }
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _appsWaiter?.complete(list);
        _appsWaiter = null;
        break;
    }
  }

  Future<void> _refreshMac() async {
    final info = await tvInfo(tv.host);
    if (info?.mac != null && info!.mac != tv.mac) {
      tv.mac = info.mac;
      onSave();
    }
  }

  void _onClosed(WebSocket ws) {
    if (_ws != ws) return;
    _ws = null;
    _authTimer?.cancel();
    if (_disposed || status == TvStatus.error) return;
    _scheduleRetry(status == TvStatus.ready ? null : 'החיבור נסגר');
  }

  void _scheduleRetry(String? err) {
    if (_disposed) return;
    _fails++;
    _set(_fails > 2 ? TvStatus.error : TvStatus.connecting, err: err);
    _retry?.cancel();
    _retry = Timer(Duration(seconds: min(20, max(2, _fails * 3))), connect);
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _ws?.add(jsonEncode(msg));
    } catch (_) {}
  }

  // ---------- פקודות ----------

  void sendKey(String key, {String cmd = 'Click'}) => _send({
        'method': 'ms.remote.control',
        'params': {
          'Cmd': cmd,
          'DataOfCmd': key,
          'Option': 'false',
          'TypeOfRemote': 'SendRemoteKey',
        }
      });

  void playPause() {
    _playing = !_playing;
    sendKey(_playing ? 'KEY_PLAY' : 'KEY_PAUSE');
  }

  /// הדלקה: אם מחובר – מקש הפעלה; אחרת – Wake-on-LAN
  Future<String> power() async {
    if (isReady) {
      sendKey('KEY_POWER');
      return 'off';
    }
    final mac = tv.mac;
    if (mac == null) return 'nomac';
    final ok = await wakeOnLan(mac, tv.host);
    for (final s in [3, 6, 10, 15]) {
      Timer(Duration(seconds: s), () {
        if (!_disposed && !isReady) connect();
      });
    }
    return ok ? 'waking' : 'failed';
  }

  /// פתיחת אפליקציה – קודם דרך REST, ואם נכשל דרך WebSocket
  Future<void> launchApp(String appId) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    var ok = false;
    try {
      final req = await client.postUrl(Uri.parse('http://${tv.host}:8001/api/v2/applications/$appId'));
      final res = await req.close().timeout(const Duration(seconds: 4));
      await res.drain();
      ok = res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
    } finally {
      client.close(force: true);
    }
    if (!ok) {
      _send({
        'method': 'ms.channel.emit',
        'params': {
          'event': 'ed.apps.launch',
          'to': 'host',
          'data': {'appId': appId, 'action_type': 'DEEP_LINK'},
        }
      });
    }
  }

  Future<List<TvApp>> installedApps() {
    _appsWaiter?.complete([]);
    final c = Completer<List<TvApp>>();
    _appsWaiter = c;
    _send({
      'method': 'ms.channel.emit',
      'params': {'event': 'ed.installedApp.get', 'to': 'host'}
    });
    return c.future.timeout(const Duration(seconds: 6), onTimeout: () {
      if (_appsWaiter == c) _appsWaiter = null;
      return <TvApp>[];
    });
  }

  /// שליחת טקסט לשדה שפתוח בטלוויזיה (כולל עברית)
  void sendText(String text) {
    _send({
      'method': 'ms.remote.control',
      'params': {
        'Cmd': base64.encode(utf8.encode(text)),
        'DataOfCmd': 'base64',
        'TypeOfRemote': 'SendInputString',
      }
    });
    _send({
      'method': 'ms.remote.control',
      'params': {'TypeOfRemote': 'SendInputEnd'}
    });
  }

  // ---------- כללי ----------

  void _close() {
    final w = _ws;
    _ws = null;
    try {
      w?.close();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _authTimer?.cancel();
    _close();
    super.dispose();
  }
}
