import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'samsung.dart';
import 'scanner.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const RemoteApp());
}

class C {
  static const bg = Color(0xFF0D0E11);
  static const body = Color(0xFF1B1C20);
  static const body2 = Color(0xFF16171B);
  static const btn = Color(0xFF24252A);
  static const sheet = Color(0xFF1C1D22);
  static const field = Color(0xFF121317);
  static const line = Color(0xFF33353C);
  static const text = Color(0xFFE9EAEE);
  static const muted = Color(0xFF8B8E97);
  static const red = Color(0xFFFF4D4F);
  static const brand = Color(0xFF5B8CFF);
  static const green = Color(0xFF22D38A);
  static const blue = Color(0xFF5AA2FF);
  static const amber = Color(0xFFFFB020);
}

class RemoteApp extends StatelessWidget {
  const RemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'שלט סמסונג',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: C.bg,
        colorScheme: const ColorScheme.dark(primary: C.green, surface: C.sheet),
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const RemoteHome(),
    );
  }
}

class RemoteHome extends StatefulWidget {
  const RemoteHome({super.key});
  @override
  State<RemoteHome> createState() => _RemoteHomeState();
}

class _RemoteHomeState extends State<RemoteHome> with WidgetsBindingObserver {
  Store? store;
  bool loaded = false;
  List<TvDevice> tvs = [];
  List<AppButton> apps = [];
  final conns = <String, SamsungConnection>{};
  String? sel;
  String? _authPromptFor;

  SamsungConnection? get cur => sel == null ? null : conns[sel];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in conns.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      for (final c in conns.values) {
        if (!c.isReady && c.status != TvStatus.authorizing) c.connect();
      }
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final s = Store(prefs);
    tvs = s.loadTvs();
    apps = s.loadApps();
    sel = s.selected;
    if (!mounted) return;
    setState(() {
      store = s;
      loaded = true;
      if (sel == null || !tvs.any((t) => t.id == sel)) {
        sel = tvs.isEmpty ? null : tvs.first.id;
      }
    });
    for (final tv in tvs) {
      _open(tv);
    }
    if (tvs.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showTvSheet());
    }
  }

  void _open(TvDevice tv) {
    final c = SamsungConnection(tv, () => store!.saveTvs(tvs));
    c.addListener(() => _onConnChange(c));
    conns[tv.id] = c;
    c.connect();
  }

  void _onConnChange(SamsungConnection c) {
    if (!mounted) return;
    setState(() {});
    if (c.tv.id == sel &&
        c.status == TvStatus.authorizing &&
        _authPromptFor != c.tv.id) {
      _authPromptFor = c.tv.id;
      _showAuthSheet(c);
    }
    if (c.status == TvStatus.ready && _authPromptFor == c.tv.id) {
      _authPromptFor = null;
      _toast('${c.tv.name} מחובר');
    }
  }

  void _select(String? id) {
    setState(() {
      sel = id;
      _authPromptFor = null;
    });
    store?.selected = id;
  }

  // ---------- פעולות ----------

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, textAlign: TextAlign.center),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2B2D33),
        duration: const Duration(seconds: 2),
      ));
  }

  SamsungConnection? _need() {
    final c = cur;
    if (c == null) {
      _showTvSheet();
      _toast('הוסף טלוויזיה כדי להתחיל');
      return null;
    }
    if (!c.isReady) {
      if (c.status == TvStatus.authorizing) {
        _showAuthSheet(c);
      } else {
        _toast(c.status == TvStatus.connecting
            ? 'מתחבר לטלוויזיה…'
            : 'הטלוויזיה לא מחוברת. לחץ על SAMSUNG');
      }
      return null;
    }
    return c;
  }

  void _key(String key) {
    final c = _need();
    if (c == null) return;
    HapticFeedback.lightImpact();
    c.sendKey(key);
  }

  void _playPause() {
    final c = _need();
    if (c == null) return;
    HapticFeedback.lightImpact();
    c.playPause();
  }

  Future<void> _power() async {
    final c = cur;
    if (c == null) {
      _need();
      return;
    }
    HapticFeedback.mediumImpact();
    final r = await c.power();
    if (r == 'waking') _toast('מדליק את ${c.tv.name}…');
    if (r == 'failed') _toast('לא הצלחתי לשלוח פקודת הדלקה');
    if (r == 'nomac') {
      _toast('כדי להדליק מהטלפון, חבר פעם אחת כשהטלוויזיה דלוקה');
    }
  }

  void _launch(AppButton a) {
    if (a.appId.isEmpty) {
      _editApp(a);
      return;
    }
    final c = _need();
    if (c == null) return;
    HapticFeedback.lightImpact();
    c.launchApp(a.appId);
    _toast('פותח את ${a.label}');
  }

  // ---------- חלונות ----------

  Future<void> _sheet(Widget Function(BuildContext, StateSetter) builder) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.sheet,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(18, 20, 18,
              MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 20),
          child: SingleChildScrollView(child: builder(ctx, setS)),
        ),
      ),
    );
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      );

  Widget _hint(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(t, style: const TextStyle(color: C.muted, fontSize: 13.5, height: 1.6)),
      );

  Widget _field(TextEditingController ctl,
      {String? hint,
      bool ltr = false,
      TextInputType? type,
      TextAlign align = TextAlign.start,
      TextStyle? style,
      int? maxLength,
      List<TextInputFormatter>? formatters,
      TextCapitalization caps = TextCapitalization.none,
      bool autofocus = false,
      ValueChanged<String>? onSubmit}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctl,
        autofocus: autofocus,
        textDirection: ltr ? TextDirection.ltr : null,
        textAlign: align,
        keyboardType: type,
        maxLength: maxLength,
        inputFormatters: formatters,
        textCapitalization: caps,
        autocorrect: false,
        enableSuggestions: false,
        onSubmitted: onSubmit,
        style: style ?? const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          counterText: '',
          filled: true,
          fillColor: C.field,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3A3D45))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3A3D45))),
        ),
      ),
    );
  }

  Widget _primary(String label, VoidCallback? onTap) => SizedBox(
        width: double.infinity,
        height: 46,
        child: FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: C.green,
              foregroundColor: const Color(0xFF06281A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      );

  Widget _ghost(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          width: double.infinity,
          height: 42,
          child: TextButton(
            style: TextButton.styleFrom(
                backgroundColor: C.btn,
                foregroundColor: C.text,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: onTap,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      );

  static const _statusText = {
    TvStatus.ready: 'מחובר',
    TvStatus.connecting: 'מתחבר…',
    TvStatus.authorizing: 'ממתין לאישור בטלוויזיה',
    TvStatus.error: 'שגיאה',
    TvStatus.offline: 'לא מחובר',
  };

  void _showTvSheet() {
    if (!loaded) return;
    final name = TextEditingController();
    final host = TextEditingController();
    var scanning = false;
    double progress = 0;
    List<({String ip, String name})>? found;

    _sheet((ctx, setS) {
      void addTv(String n, String h) {
        h = h.trim();
        if (!RegExp(r'^[\w.-]+$').hasMatch(h)) {
          _toast('כתובת IP לא תקינה');
          return;
        }
        final tv = TvDevice(
            id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
            name: n.trim().isEmpty ? 'טלוויזיה ${tvs.length + 1}' : n.trim(),
            host: h);
        tvInfo(h).then((info) {
          if (info?.mac != null) {
            tv.mac = info!.mac;
            store!.saveTvs(tvs);
          }
        });
        tvs.add(tv);
        store!.saveTvs(tvs);
        _select(tv.id);
        _open(tv);
        Navigator.pop(ctx);
        _toast('מתחבר… אשר את הבקשה שתופיע על הטלוויזיה');
      }

      return ListenableBuilder(
        listenable: Listenable.merge(conns.values.toList()),
        builder: (ctx, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title('הטלוויזיות שלי'),
            _hint('בחר טלוויזיה לשליטה, או הוסף חדשה. הטלפון והטלוויזיה צריכים להיות באותה רשת WiFi.'),
            if (tvs.isEmpty) _hint('עדיין לא נוספו טלוויזיות.'),
            for (final tv in tvs) _tvRow(ctx, setS, tv),
            const Divider(color: C.line, height: 28),
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: C.text,
                    side: const BorderSide(color: C.line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: scanning
                    ? null
                    : () async {
                        setS(() {
                          scanning = true;
                          progress = 0;
                          found = null;
                        });
                        final r = await scanForTvs(onProgress: (p) {
                          if (ctx.mounted) setS(() => progress = p);
                        });
                        if (!ctx.mounted) return;
                        setS(() {
                          scanning = false;
                          found = r;
                        });
                      },
                icon: const Icon(Icons.wifi_find, size: 20),
                label: Text(scanning ? 'מחפש…' : 'חפש טלוויזיות ברשת'),
              ),
            ),
            if (scanning)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(value: progress, color: C.green),
              ),
            if (found != null) ...[
              const SizedBox(height: 10),
              if (found!.where((f) => !tvs.any((t) => t.host == f.ip)).isEmpty)
                _hint('לא נמצאו טלוויזיות חדשות. ודא שהטלוויזיה דלוקה, או הזן כתובת ידנית.'),
              for (final f in found!.where((f) => !tvs.any((t) => t.host == f.ip)))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    tileColor: const Color(0xFF24252B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.tv, color: C.green),
                    title: Text(f.name),
                    subtitle: Text(f.ip, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                    trailing: const Text('הוסף', style: TextStyle(color: C.green)),
                    onTap: () => addTv(name.text.trim().isEmpty ? f.name : name.text, f.ip),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            _hint('או הוספה ידנית. את הכתובת מוצאים בטלוויזיה: הגדרות ← רשת ואינטרנט ← הרשת המחוברת.'),
            _field(name, hint: 'שם (למשל: סלון)'),
            _field(host,
                hint: 'כתובת IP (למשל 192.168.1.40)',
                ltr: true,
                type: const TextInputType.numberWithOptions(decimal: true)),
            _primary('הוסף טלוויזיה', () => addTv(name.text, host.text)),
            _ghost('סגור', () => Navigator.pop(ctx)),
          ],
        ),
      );
    });
  }

  Widget _tvRow(BuildContext ctx, StateSetter setS, TvDevice tv) {
    final c = conns[tv.id];
    final st = c?.status ?? TvStatus.offline;
    final err = st == TvStatus.error && c?.error != null ? ' – ${c!.error}' : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF24252B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tv.id == sel ? C.green : Colors.transparent),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _select(tv.id);
          Navigator.pop(ctx);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            StatusDot(st),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tv.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${tv.host}  ${_statusText[st]}$err',
                    style: const TextStyle(color: C.muted, fontSize: 12)),
              ]),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: C.muted),
              color: const Color(0xFF2B2D33),
              onSelected: (v) async {
                if (v == 're') {
                  c?.connect();
                } else if (v == 'pair') {
                  tv.token = null;
                  store!.saveTvs(tvs);
                  _authPromptFor = null;
                  _select(tv.id);
                  c?.connect();
                } else if (v == 'mac') {
                  _editMac(tv);
                } else if (v == 'del') {
                  final ok = await showDialog<bool>(
                    context: ctx,
                    builder: (d) => AlertDialog(
                      backgroundColor: C.sheet,
                      title: Text('למחוק את ${tv.name}?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('ביטול')),
                        TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('מחק', style: TextStyle(color: C.red))),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  conns.remove(tv.id)?.dispose();
                  tvs.remove(tv);
                  store!.saveTvs(tvs);
                  if (sel == tv.id) _select(tvs.isEmpty ? null : tvs.first.id);
                  setS(() {});
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 're', child: Text('חבר מחדש')),
                PopupMenuItem(value: 'pair', child: Text('בקש אישור מחדש')),
                PopupMenuItem(value: 'mac', child: Text('כתובת MAC להדלקה')),
                PopupMenuItem(value: 'del', child: Text('מחק')),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  void _showAuthSheet(SamsungConnection c) {
    var closing = false;
    _sheet((ctx, setS) => ListenableBuilder(
          listenable: c,
          builder: (ctx, _) {
            if (c.status == TvStatus.ready && !closing) {
              closing = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (ctx.mounted) Navigator.of(ctx).pop();
              });
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _title('אישור בטלוויזיה'),
              _hint('על מסך ${c.tv.name} הופיעה בקשת חיבור מ-"Phone Remote". בחר בשלט הרגיל "אפשר" (Allow). צריך לעשות את זה רק פעם אחת.'),
              if (c.status == TvStatus.error && c.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(c.error!, style: const TextStyle(color: C.red, fontSize: 13.5, height: 1.5)),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(bottom: 14),
                  child: LinearProgressIndicator(color: C.green),
                ),
              if (c.status == TvStatus.error) _primary('נסה שוב', () => c.connect()),
              _ghost('סגור', () => Navigator.pop(ctx)),
            ]);
          },
        ));
  }

  void _editMac(TvDevice tv) {
    final mac = TextEditingController(text: tv.mac ?? '');
    _sheet((ctx, setS) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title('כתובת MAC של ${tv.name}'),
          _hint('בדרך כלל האפליקציה ממלאת אותה לבד. אפשר למצוא אותה בטלוויזיה: הגדרות ← תמיכה ← אודות טלוויזיה זו.'),
          _field(mac, hint: 'AA:BB:CC:DD:EE:FF', ltr: true, caps: TextCapitalization.characters),
          _primary('שמור', () {
            final v = mac.text.trim().toUpperCase().replaceAll('-', ':');
            if (v.isNotEmpty && !RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(v)) {
              _toast('כתובת MAC לא תקינה');
              return;
            }
            tv.mac = v.isEmpty ? null : v;
            store!.saveTvs(tvs);
            Navigator.pop(ctx);
            _toast('נשמר');
          }),
          _ghost('ביטול', () => Navigator.pop(ctx)),
        ]));
  }

  void _showNumpad() {
    _sheet((ctx, setS) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title('מספרים'),
          const SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.ltr,
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.8,
              children: [
                for (var d = 1; d <= 9; d++) _numKey('$d', 'KEY_$d'),
                _numKey('PRE', 'KEY_PRECH'),
                _numKey('0', 'KEY_0'),
                _numKey('↵', 'KEY_ENTER'),
              ],
            ),
          ),
          _ghost('סגור', () => Navigator.pop(ctx)),
        ]));
  }

  Widget _numKey(String label, String code) => Press(
        fireOnDown: true,
        onPress: () => _key(code),
        decoration: BoxDecoration(color: C.btn, borderRadius: BorderRadius.circular(14)),
        child: Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      );

  void _showKeyboard() {
    final text = TextEditingController();
    _sheet((ctx, setS) {
      void send() {
        final c = _need();
        if (c == null || text.text.isEmpty) return;
        c.sendText(text.text);
        text.clear();
        _toast('נשלח');
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title('הקלדה בטלוויזיה'),
        _hint('קודם בחר בטלוויזיה שדה חיפוש או הקלדה, ואז כתוב כאן. אפשר גם בעברית.'),
        _field(text, hint: 'טקסט לשליחה', autofocus: true, onSubmit: (_) => send()),
        _primary('שלח', send),
        _ghost('סגור', () => Navigator.pop(ctx)),
      ]);
    });
  }

  void _editApp(AppButton a) {
    final appId = TextEditingController(text: a.appId);
    final label = TextEditingController(text: a.label);
    List<TvApp>? list;
    var loading = false;

    _sheet((ctx, setS) {
      Future<void> load() async {
        final c = _need();
        if (c == null) return;
        setS(() => loading = true);
        final r = await c.installedApps();
        if (!ctx.mounted) return;
        setS(() {
          loading = false;
          list = r;
        });
        if (r.isEmpty) _toast('הטלוויזיה לא החזירה רשימה. אפשר להזין מזהה ידנית');
      }

      void save(String id, String? name) {
        setState(() {
          a.appId = id.trim();
          if (label.text.trim().isNotEmpty) a.label = label.text.trim();
        });
        store!.saveApps(apps);
        Navigator.pop(ctx);
        _toast('נשמר. לחיצה ארוכה על הכפתור פותחת שוב את ההגדרה');
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title('הגדרת ${a.label}'),
        _hint('בחר את האפליקציה מתוך מה שמותקן בטלוויזיה.'),
        _field(label, hint: 'שם הכפתור'),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: C.text,
                side: const BorderSide(color: C.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: loading ? null : load,
            icon: const Icon(Icons.apps, size: 20),
            label: Text(loading ? 'טוען…' : 'הצג את האפליקציות בטלוויזיה'),
          ),
        ),
        if (list != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(children: [
              for (final app in list!)
                ListTile(
                  dense: true,
                  title: Text(app.name),
                  subtitle: Text(app.id, textDirection: TextDirection.ltr, textAlign: TextAlign.right,
                      style: const TextStyle(color: C.muted, fontSize: 11)),
                  trailing: app.id == a.appId ? const Icon(Icons.check, color: C.green) : null,
                  onTap: () => save(app.id, app.name),
                ),
            ]),
          ),
        const SizedBox(height: 14),
        _hint('או הזנה ידנית של מזהה האפליקציה:'),
        _field(appId, hint: '3201907018807', ltr: true),
        _primary('שמור', () => save(appId.text, null)),
        _ghost('ביטול', () => Navigator.pop(ctx)),
      ]);
    });
  }

  // ---------- מסך השלט ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: !loaded
            ? const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: C.green),
                  SizedBox(height: 16),
                  Text('מכין את השלט…', style: TextStyle(color: C.muted)),
                ]),
              )
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: _remote(),
                ),
              ),
      ),
    );
  }

  Widget _remote() {
    final c = cur;
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.body, C.body2]),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: const Color(0xFF2A2C32)),
        boxShadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 60, offset: Offset(0, 30))],
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // שורה עליונה
          Row(children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _showTvSheet,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    const Text('SAMSUNG',
                        style: TextStyle(
                            color: C.brand, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 2.5)),
                    const SizedBox(width: 6),
                    StatusDot(c?.status),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(c?.tv.name ?? 'הוסף טלוויזיה',
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(color: C.muted, fontSize: 12)),
                    ),
                  ]),
                ),
              ),
            ),
            _round(Icons.input, () => _key('KEY_SOURCE'), 'מקור'),
            const SizedBox(width: 10),
            _round(Icons.tune, () => _key('KEY_TOOLS'), 'כלים'),
            const SizedBox(width: 10),
            Press(
              semantics: 'הדלקה וכיבוי',
              fireOnDown: true,
              onPress: _power,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF123526),
                border: Border.all(color: const Color(0xFF1D6B4A)),
                boxShadow: const [BoxShadow(color: Color(0x5922D38A), blurRadius: 16)],
              ),
              child: const Icon(Icons.bolt, color: C.green, size: 20),
            ),
          ]),
          const SizedBox(height: 22),
          const Text('אפליקציות ומקורות',
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: TextStyle(color: C.muted, fontSize: 11)),
          const SizedBox(height: 10),
          for (var r = 0; r < apps.length; r += 2) ...[
            Row(children: [
              Expanded(child: _appBtn(apps[r])),
              const SizedBox(width: 10),
              Expanded(child: r + 1 < apps.length ? _appBtn(apps[r + 1]) : const SizedBox()),
            ]),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 16),
          Center(child: _dpad()),
          const SizedBox(height: 26),
          Row(children: [
            Expanded(child: _rocker('VOL', const Text('+', style: TextStyle(fontSize: 26)), 'KEY_VOLUP',
                const Text('−', style: TextStyle(fontSize: 26)), 'KEY_VOLDOWN')),
            const SizedBox(width: 12),
            Column(children: [
              _circle(
                Icons.volume_off,
                'MUTE',
                () => _key('KEY_MUTE'),
                BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF5A1C1F),
                  border: Border.all(color: const Color(0xFF8A2A2E)),
                ),
                const Color(0xFFFF7B7D),
              ),
              const SizedBox(height: 10),
              _circle(Icons.play_arrow_rounded, 'PLAY', _playPause,
                  const BoxDecoration(shape: BoxShape.circle, color: C.btn), C.text),
            ]),
            const SizedBox(width: 12),
            Expanded(child: _rocker('CH', const Icon(Icons.arrow_drop_up, size: 34), 'KEY_CHUP',
                const Icon(Icons.arrow_drop_down, size: 34), 'KEY_CHDOWN')),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _navBtn(Icons.arrow_back, 'Back', 'KEY_RETURN', C.text, null)),
            const SizedBox(width: 8),
            Expanded(child: _navBtn(Icons.home_outlined, 'Home', 'KEY_HOME', C.green, C.green)),
            const SizedBox(width: 8),
            Expanded(child: _navBtn(Icons.view_list, 'Guide', 'KEY_GUIDE', C.blue, C.blue)),
            const SizedBox(width: 8),
            Expanded(child: _navBtn(Icons.menu, 'Menu', 'KEY_MENU', C.amber, C.amber)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _wideBtn(Icons.dialpad, '123', _showNumpad)),
            const SizedBox(width: 10),
            Expanded(child: _wideBtn(Icons.keyboard_outlined, 'Keyboard', _showKeyboard)),
          ]),
        ]),
      ),
    );
  }

  Widget _round(IconData icon, VoidCallback onTap, String label) => Press(
        semantics: label,
        fireOnDown: true,
        onPress: onTap,
        width: 44,
        height: 44,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: C.btn),
        child: Icon(icon, size: 19, color: C.text),
      );

  Widget _appBtn(AppButton a) {
    final col = Color(a.color);
    return Press(
      semantics: a.label,
      onPress: () => _launch(a),
      onLongPress: () => _editApp(a),
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.withAlpha(102)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(4)),
          child: const Icon(Icons.play_arrow_rounded, size: 14, color: Color(0xFF111111)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(a.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: col, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ]),
    );
  }

  Widget _dpad() {
    Widget arrow(IconData icon, String code, String label) => Press(
          semantics: label,
          fireOnDown: true,
          repeat: true,
          onPress: () => _key(code),
          width: 64,
          height: 64,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          child: Icon(icon, size: 26, color: const Color(0xFFCFD1D6)),
        );

    return SizedBox(
      width: 228,
      height: 228,
      child: Stack(children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
                center: Alignment(0, -0.2), colors: [Color(0xFF25262B), Color(0xFF1C1D21)]),
            border: Border.all(color: const Color(0xFF2E3036)),
          ),
        ),
        Positioned(top: 4, left: 82, child: arrow(Icons.keyboard_arrow_up, 'KEY_UP', 'למעלה')),
        Positioned(bottom: 4, left: 82, child: arrow(Icons.keyboard_arrow_down, 'KEY_DOWN', 'למטה')),
        Positioned(left: 4, top: 82, child: arrow(Icons.keyboard_arrow_left, 'KEY_LEFT', 'שמאלה')),
        Positioned(right: 4, top: 82, child: arrow(Icons.keyboard_arrow_right, 'KEY_RIGHT', 'ימינה')),
        Positioned(
          left: 57,
          top: 57,
          child: Press(
            semantics: 'אישור',
            fireOnDown: true,
            onPress: () => _key('KEY_ENTER'),
            width: 114,
            height: 114,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF141518),
              border: Border.all(color: const Color(0xFF2C2E34)),
              boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 14, offset: Offset(0, 6))],
            ),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ),
        ),
      ]),
    );
  }

  Widget _rocker(String label, Widget top, String topKey, Widget bottom, String bottomKey) {
    return Container(
      height: 118,
      decoration: BoxDecoration(color: C.btn, borderRadius: BorderRadius.circular(18)),
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Press(
            fireOnDown: true,
            repeat: true,
            onPress: () => _key(topKey),
            height: 44,
            child: DefaultTextStyle.merge(style: const TextStyle(color: Color(0xFFD7D9DE)), child: top)),
        Text(label,
            style: const TextStyle(color: C.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        Press(
            fireOnDown: true,
            repeat: true,
            onPress: () => _key(bottomKey),
            height: 44,
            child: DefaultTextStyle.merge(style: const TextStyle(color: Color(0xFFD7D9DE)), child: bottom)),
      ]),
    );
  }

  Widget _circle(IconData icon, String label, VoidCallback onTap, BoxDecoration deco, Color color) => Press(
        semantics: label,
        fireOnDown: true,
        onPress: onTap,
        width: 56,
        height: 56,
        decoration: deco,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(height: 1),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ]),
      );

  Widget _navBtn(IconData icon, String label, String code, Color color, Color? ring) => Press(
        semantics: label,
        fireOnDown: true,
        onPress: () => _key(code),
        height: 56,
        decoration: BoxDecoration(
          color: C.btn,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ring == null ? Colors.transparent : ring.withAlpha(90)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ]),
      );

  Widget _wideBtn(IconData icon, String label, VoidCallback onTap) => Press(
        semantics: label,
        onPress: onTap,
        height: 44,
        decoration: BoxDecoration(color: C.btn, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 19, color: const Color(0xFFCFD1D6)),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFCFD1D6))),
        ]),
      );
}

class StatusDot extends StatelessWidget {
  final TvStatus? status;
  const StatusDot(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TvStatus.ready => C.green,
      TvStatus.connecting || TvStatus.authorizing => C.amber,
      TvStatus.error => C.red,
      _ => const Color(0xFF555555),
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: status == TvStatus.ready ? const [BoxShadow(color: C.green, blurRadius: 8)] : null,
      ),
    );
  }
}

/// כפתור עם משוב לחיצה; fireOnDown לשליחה מיידית, repeat להחזקה, onLongPress ללחיצה ארוכה
class Press extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPress;
  final VoidCallback? onLongPress;
  final bool repeat;
  final bool fireOnDown;
  final BoxDecoration? decoration;
  final double? width;
  final double? height;
  final String? semantics;

  const Press({
    super.key,
    required this.child,
    this.onPress,
    this.onLongPress,
    this.repeat = false,
    this.fireOnDown = false,
    this.decoration,
    this.width,
    this.height,
    this.semantics,
  });

  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;
  bool _long = false;
  Timer? _t1;
  Timer? _t2;

  void _onDown(PointerDownEvent _) {
    setState(() => _down = true);
    _long = false;
    if (widget.fireOnDown) {
      widget.onPress?.call();
      if (widget.repeat) {
        _t1 = Timer(const Duration(milliseconds: 420), () {
          _t2 = Timer.periodic(const Duration(milliseconds: 140), (_) => widget.onPress?.call());
        });
      }
    } else if (widget.onLongPress != null) {
      _t1 = Timer(const Duration(milliseconds: 600), () {
        _long = true;
        HapticFeedback.mediumImpact();
        widget.onLongPress!();
      });
    }
  }

  void _onUp(PointerUpEvent _) {
    _stop();
    if (!widget.fireOnDown && !_long) widget.onPress?.call();
  }

  void _stop() {
    _t1?.cancel();
    _t2?.cancel();
    if (mounted) setState(() => _down = false);
  }

  @override
  void dispose() {
    _t1?.cancel();
    _t2?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.decoration;
    return Semantics(
      button: true,
      label: widget.semantics,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerUp: _onUp,
        onPointerCancel: (_) => _stop(),
        child: AnimatedScale(
          scale: _down ? 0.95 : 1,
          duration: const Duration(milliseconds: 80),
          child: Container(
            width: widget.width,
            height: widget.height,
            alignment: Alignment.center,
            decoration: d,
            foregroundDecoration: _down
                ? BoxDecoration(
                    color: const Color(0x14FFFFFF),
                    shape: d?.shape ?? BoxShape.rectangle,
                    borderRadius: d?.borderRadius,
                  )
                : null,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
