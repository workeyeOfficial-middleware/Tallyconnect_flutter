// The app controller: a 1:1 port of `class Component` in Main.dc.html
// (state 1916–1955, methods 1956–2258 and the handlers built in renderVals).
// One ChangeNotifier holds every piece of UI state, exactly like the
// prototype's single component state; widgets read it and call methods.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/design/tc_color_math.dart';
import '../core/design/tc_palette.dart';
import '../core/storage/local_storage.dart';
import '../core/utils/format.dart';
import '../data/mock/mock_data.dart';
import '../data/models/models.dart';
import '../data/repositories/tally_repository.dart';
import '../core/share/doc_exporter.dart';
import '../core/share/report_data.dart';
import '../core/share/share_doc.dart';

class ListRef {
  const ListRef(this.list, this.id);
  final String list, id;
  bool matches(String l, String i) => list == l && id == i;
}

class CMenu {
  const CMenu(this.list, this.id, this.x, this.y);
  final String list, id;
  final double x, y;
}

class DragPt {
  const DragPt(this.list, this.id, this.x, this.y);
  final String list, id;
  final double x, y;
}

class HiddenCard {
  HiddenCard(this.id, this.page, this.index, this.snap);
  final String id;
  int page;
  final int index;
  final List<String> snap;

  HiddenCard copy() => HiddenCard(id, page, index, List<String>.of(snap));
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'page': page,
    'index': index,
    'snap': snap,
  };
  static HiddenCard? fromJson(Object? o) {
    if (o is! Map) return null;
    final Object? id = o['id'];
    if (id is! String) return null;
    return HiddenCard(
      id,
      (o['page'] as num?)?.toInt() ?? 0,
      (o['index'] as num?)?.toInt() ?? 0,
      (o['snap'] is List)
          ? (o['snap'] as List<dynamic>).whereType<String>().toList()
          : <String>[],
    );
  }
}

class ListPref {
  ListPref([List<String>? order, List<String>? pinned, List<String>? hidden])
    : order = order ?? <String>[],
      pinned = pinned ?? <String>[],
      hidden = hidden ?? <String>[];
  List<String> order, pinned, hidden;

  ListPref copy() => ListPref(
    List<String>.of(order),
    List<String>.of(pinned),
    List<String>.of(hidden),
  );
  Map<String, Object?> toJson() => <String, Object?>{
    'order': order,
    'pinned': pinned,
    'hidden': hidden,
  };
  static ListPref fromJson(Object? o) {
    if (o is! Map) return ListPref();
    List<String> l(Object? v) =>
        v is List ? v.whereType<String>().toList() : <String>[];
    return ListPref(l(o['order']), l(o['pinned']), l(o['hidden']));
  }
}

class PickSheet {
  const PickSheet(this.title, this.key, this.opts);
  final String title, key;
  final List<Opt> opts;
}

class Photo {
  const Photo(this.path, this.lum);
  final String path;
  final double lum;
  Map<String, Object?> toJson() => <String, Object?>{'path': path, 'lum': lum};
}

/// Card-menu / ghost metadata for one card (`reg[list|key]`).
class CardInfo {
  const CardInfo(this.label, this.ic, this.c, this.open);
  final String label, ic, c;
  final VoidCallback open;
}

enum PillTr { none, stretch, settle, reorder }

/// Registry of on-screen geometry used for drag hit-testing
/// (`document.elementFromPoint` in the prototype).
class HitRegistry {
  final Map<String, GlobalKey> cards = <String, GlobalKey>{};
  final Map<int, GlobalKey> ends = <int, GlobalKey>{};
  final Map<String, GlobalKey> rows = <String, GlobalKey>{};
  ScrollController? screenScroll;
  GlobalKey? screenViewport;
  GlobalKey? tabBar;

  GlobalKey card(String id) => cards.putIfAbsent(id, GlobalKey.new);
  GlobalKey end(int i) => ends.putIfAbsent(i, GlobalKey.new);
  GlobalKey row(String list, String lk) =>
      rows.putIfAbsent('$list|$lk', GlobalKey.new);

  static Rect? rectOf(GlobalKey k) {
    final BuildContext? c = k.currentContext;
    if (c == null || !c.mounted) return null;
    final RenderObject? ro = c.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    return ro.localToGlobal(Offset.zero) & ro.size;
  }
}

class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    this.repo = const MockTallyRepository(),
    String startScreen = 'login',
    double glassLevel = 60,
    DocExporter? exporter,
  }) : exporter = exporter ?? PlatformDocExporter() {
    final int ti = kTabs.indexWhere(
      (({String k, String t, String ic}) t) => t.k == startScreen,
    );
    screen = startScreen;
    loggedIn = startScreen != 'login' && startScreen != 'forgot';
    tab = ti < 0 ? 0 : ti;
    glass = glassLevel;
    _load();
    pillPos = tabOrder.indexOf(tab).toDouble();
  }

  final LocalStorage store;
  final TallyRepository repo;

  /// Share / PDF / Download platform side (NEW feature).
  final DocExporter exporter;
  final HitRegistry reg = HitRegistry();

  // ---------------------------------------------------------------- state
  late String screen;
  List<String> history = <String>[];
  String dir = 'fwd';
  bool loggedIn = false;
  int tab = 0;
  double pillPos = 0, pillSpan = 1, pillS = 1;
  PillTr pillT = PillTr.none;
  String? overlay;
  String company = 'gi';
  double glass = 60;

  Map<String, List<List<String>>> pagesByWs = <String, List<List<String>>>{};
  int page = 0;
  DragPt? drag;
  String? edge;
  List<int> tabOrder = <int>[0, 1, 2, 3, 4];
  ({int i, double x})? tdrag;
  ListRef? armed;
  CMenu? cmenu;
  List<String> pinned = <String>[];
  Map<String, ListPref> listPrefs = <String, ListPref>{};
  DragPt? ldrag;
  int hovPos = 0;
  bool hovOn = false, dwell = false;
  Map<String, List<HiddenCard>> hiddenW = <String, List<HiddenCard>>{};
  int hidPage = 0;
  List<String> flash = <String>[];

  String preset = 'aurora', accent = 'look', mode = 'look';
  String customBase = '#8C1D3F';
  int customCombo = 0;
  String? cpHexTyping;
  String wallK = 'theme';
  Photo? photo;
  String? pendWall;
  Photo? pendPhoto;
  int cpH = 0, cpS = 0, cpV = 0;
  String? cpExact;

  late List<Workspace> wsList = List<Workspace>.of(repo.workspaces());
  String activeWs = 'def';
  String? wsEdit;
  String wsTab = 'f';
  List<String> wsSel = <String>[], wsSums = <String>[];

  String flowType = 'sales';
  int flowStep = 0;
  Map<String, List<Line>> lines = <String, List<Line>>{
    for (final MapEntry<String, List<Line>> e in kInitLines.entries)
      e.key: List<Line>.of(e.value),
  };
  Map<String, String> modes = <String, String>{
    'sales': 'cash',
    'purchase': 'bank',
    'receipt': 'bank',
    'payment': 'bank',
  };
  List<JLine> jl = List<JLine>.of(kInitJl);
  Map<String, String> form = Map<String, String>.of(kForm);
  PickSheet? pick;
  String? npKey;
  String npType = 'c';
  List<Party> extraParties = <Party>[];
  String niCat = 'General', niUnit = 'PCS';
  int niGst = 18;

  String vFilter = 'all', vPeriod = 'month';
  Voucher? entry;
  String outKind = 'recv', outFilter = 'all';
  Bill? bill;
  bool autoRemind = true;
  String itemsFilter = 'all',
      partyFilter = 'all',
      partySort = 'amt',
      party = 'Shree Balaji Traders',
      partyTab = 'summary';
  String repCat = 'all', report = 'top';

  /// NEW: chosen chart per report (bar | pie | line).
  final Map<String, String> chartType = <String, String>{};
  String actFilter = 'all';
  late List<Act> acts = List<Act>.of(repo.activity());
  String act = 'a2';
  late List<Member> team = List<Member>.of(repo.team());
  String teamFilter = 'all';
  String? member;
  String setTab = 'profile';
  Map<String, bool> prefs = <String, bool>{
    'pay': true,
    'sync': true,
    'due': true,
    'team': true,
    'wa': true,
  };
  bool yearly = true;
  int faq = 0;
  late List<Notif> notifs = List<Notif>.of(repo.notifications());
  String nFilter = 'all';
  bool showPass = false, forgotSent = false;
  PdfInfo? pdf;
  int zoom = 100;
  String? toast;
  int toastSeq = 0;

  // private (the prototype's `this._x` fields)
  Timer? _t, _p, _lp, _et, _tlp, _fl, _dw, _dw0, _hb;
  bool lpFired = false;
  bool tabLp = false;
  final Map<String, List<String>> _seq = <String, List<String>>{};
  String? _lastKey;
  String? _edge, _flipped;
  Offset? _d0;
  String? _snap;
  bool _lpActive = false;
  PageController? pager;
  bool _disposed = false;

  void _set([VoidCallback? f]) {
    f?.call();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final Timer? t in <Timer?>[
      _t,
      _p,
      _lp,
      _et,
      _tlp,
      _fl,
      _dw,
      _dw0,
      _hb,
    ]) {
      t?.cancel();
    }
    _stopRoute();
    super.dispose();
  }

  void _load() {
    final Object? pg = store.load<Object?>(LocalStorage.kPages, null);
    if (pg is Map) {
      pg.forEach((Object? k, Object? v) {
        if (k is String && v is List) {
          pagesByWs[k] = v
              .map(
                (Object? e) =>
                    e is List ? e.whereType<String>().toList() : <String>[],
              )
              .toList();
        }
      });
    }
    page = (store.load<Object?>(LocalStorage.kPage, 0) as num?)?.toInt() ?? 0;
    tabOrder = store.loadTabOrder();
    final Object? pn = store.load<Object?>(LocalStorage.kPinned, null);
    pinned = pn is List ? pn.whereType<String>().toList() : <String>[];
    final Object? lp = store.load<Object?>(LocalStorage.kLists, null);
    if (lp is Map) {
      lp.forEach((Object? k, Object? v) {
        if (k is String) listPrefs[k] = ListPref.fromJson(v);
      });
    }
    final Object? hw = store.load<Object?>(LocalStorage.kHidden, null);
    if (hw is Map) {
      hw.forEach((Object? k, Object? v) {
        if (k is String && v is List) {
          hiddenW[k] = v
              .map(HiddenCard.fromJson)
              .whereType<HiddenCard>()
              .toList();
        }
      });
    }
    preset = store.load<String>(LocalStorage.kPreset, 'aurora');
    if (!kLookDefs.containsKey(preset)) preset = 'aurora';
    accent = store.load<String>(LocalStorage.kAccent, 'look');
    mode = store.load<String>(LocalStorage.kMode, 'look');
    final Object? cu = store.load<Object?>(LocalStorage.kCustom, null);
    if (cu is Map) {
      customBase = (cu['base'] as String?) ?? '#8C1D3F';
      customCombo = (cu['combo'] as num?)?.toInt() ?? 0;
    }
    wallK = store.load<String>(LocalStorage.kWall, 'theme');
    final Object? ph = store.load<Object?>(LocalStorage.kPhoto, null);
    if (ph is Map &&
        ph['path'] is String &&
        File(ph['path'] as String).existsSync()) {
      photo = Photo(ph['path'] as String, (ph['lum'] as num?)?.toDouble() ?? 1);
    }
    final List<int> hsv0 = hex2hsv(customBase);
    cpH = hsv0[0];
    cpS = hsv0[1];
    cpV = hsv0[2];
    cpExact = customBase.toUpperCase();
    if (wallK == 'photo' && photo == null) wallK = 'theme';
    if (!okAccent(preset, accent)) accent = 'look';
  }

  // ------------------------------------------------------------- derived
  TcPalette get palette => resolvePalette(
    preset: preset,
    accent: accent,
    mode: mode,
    customBase: customBase,
    customCombo: customCombo,
    wallK: wallK,
    photoPath: photo?.path,
    photoLum: photo?.lum ?? 1,
    glass: glass,
  );

  bool get showTabs => loggedIn && !kNoTab.contains(screen);
  String get backLabel =>
      kTitles[history.isNotEmpty ? history.last : 'home'] ?? 'Home';
  Company get companyObj => repo.companies().firstWhere(
    (Company c) => c.id == company,
    orElse: () => repo.companies()[1],
  );
  String get companyName => companyObj.short;
  int get unread => notifs.where((Notif n) => n.unread).length;
  bool get scrollLock =>
      drag != null || ldrag != null || _lpActive || tdrag != null;
  int posOf(int i) => tabOrder.indexOf(i);

  // ------------------------------------------------------------ toast/nav
  /// `say(msg)`: toast for 2600 ms.
  void say(String msg) {
    _set(() {
      toast = msg;
      toastSeq++;
    });
    _t?.cancel();
    _t = Timer(
      const Duration(milliseconds: 2600),
      () => _set(() => toast = null),
    );
  }

  void setF(String k, String v) => _set(() => form[k] = v);
  String f(String k) => form[k] ?? '';

  void jump(String s) {
    final int ti = kTabs.indexWhere(
      (({String k, String t, String ic}) t) => t.k == s,
    );
    if (ti >= 0) {
      loggedIn = true;
      selectTab(ti);
      return;
    }
    _set(() {
      screen = s;
      history = <String>[];
      overlay = null;
      dir = 'fwd';
      loggedIn = s != 'login' && s != 'forgot';
      flowType = 'sales';
      flowStep = 0;
    });
  }

  void selectTab(int i, [Map<String, Object?>? extra]) {
    final int cur = tab;
    final double a = posOf(cur).toDouble(), b = posOf(i).toDouble();
    _p?.cancel();
    _set(() {
      tab = i;
      screen = kTabs[i].k;
      history = <String>[];
      overlay = null;
      dir = posOf(i) >= posOf(cur) ? 'fwd' : 'bk';
      drag = null;
      armed = null;
      cmenu = null;
      if (extra != null) _applyExtra(extra);
      if (i == cur) {
        pillPos = b;
        pillSpan = 1;
        return;
      }
      pillPos = a < b ? a : b;
      pillSpan = (b - a).abs() + 1;
      pillS = .84;
      pillT = PillTr.stretch;
    });
    if (i == cur) return;
    _p = Timer(const Duration(milliseconds: 200), () {
      _set(() {
        pillPos = b;
        pillSpan = 1;
        pillS = 1;
        pillT = PillTr.settle;
      });
    });
  }

  void go(String s, [Map<String, Object?>? extra]) {
    final int ti = kTabs.indexWhere(
      (({String k, String t, String ic}) t) => t.k == s,
    );
    if (ti >= 0) {
      selectTab(ti, extra);
      return;
    }
    _set(() {
      history = <String>[...history, screen];
      screen = s;
      dir = 'fwd';
      overlay = null;
      armed = null;
      cmenu = null;
      if (extra != null) _applyExtra(extra);
    });
  }

  void run(NavTo a) => go(a.screen, a.extra.isEmpty ? null : a.extra);

  void back() {
    if (history.isEmpty) {
      if (screen == 'forgot') {
        _set(() {
          screen = 'login';
          dir = 'bk';
        });
        return;
      }
      selectTab(0);
      return;
    }
    _set(() {
      final List<String> h = List<String>.of(history);
      screen = h.removeLast();
      history = h;
      dir = 'bk';
      overlay = null;
    });
  }

  void _applyExtra(Map<String, Object?> x) {
    x.forEach((String k, Object? v) {
      switch (k) {
        case 'vFilter':
          vFilter = v! as String;
        case 'vPeriod':
          vPeriod = v! as String;
        case 'outKind':
          outKind = v! as String;
        case 'outFilter':
          outFilter = v! as String;
        case 'entry':
          entry = v as Voucher?;
        case 'bill':
          bill = v as Bill?;
        case 'party':
          party = v! as String;
        case 'partyTab':
          partyTab = v! as String;
        case 'report':
          report = v! as String;
        case 'act':
          act = v! as String;
        case 'setTab':
          setTab = v! as String;
        case 'flowType':
          flowType = v! as String;
        case 'flowStep':
          flowStep = v! as int;
        case 'acts':
          acts = v! as List<Act>;
      }
    });
  }

  void openOverlay(String o) => _set(() => overlay = o);
  void closeOv() => _set(() => overlay = null);

  // ---------------------------------------------------------- nav actions
  void doLogin() {
    _set(() {
      loggedIn = true;
      tab = 0;
      pillPos = posOf(0).toDouble();
      pillSpan = 1;
      pillT = PillTr.none;
      screen = 'home';
      history = <String>[];
      dir = 'fwd';
    });
    say('Welcome back, workk72002');
  }

  void logout() {
    _set(() {
      screen = 'login';
      history = <String>[];
      loggedIn = false;
      overlay = null;
      tab = 0;
      pillPos = posOf(0).toDouble();
      pillSpan = 1;
      pillT = PillTr.none;
      dir = 'bk';
    });
    say('You are logged out');
  }

  void goForgot() {
    forgotSent = false;
    go('forgot');
  }

  void goCreateWs() {
    _set(() {
      wsEdit = null;
      wsSel = <String>[];
      wsSums = <String>[];
      wsTab = 'f';
      form['wsName'] = '';
    });
    go('createWs');
  }

  void pickCompany(Company c) {
    _set(() {
      company = c.id;
      overlay = null;
    });
    say('Now showing ${c.short}');
  }

  // ------------------------------------------------------------------ flow
  void startFlow(String type, [Map<String, String>? patch]) {
    if (patch != null) _set(() => form.addAll(patch));
    go('flow', <String, Object?>{'flowType': type, 'flowStep': 0});
  }

  ({int sub, int gst, int total}) totals(List<Line> ls) {
    double sub = 0, gst = 0;
    for (final Line l in ls) {
      final double a = (l.rate * l.qty).toDouble();
      sub += a;
      gst += a * l.gst / 100;
    }
    final int s = sub.round(), g = gst.round();
    return (sub: s, gst: g, total: s + g);
  }

  List<Party> partyPool() => <Party>[...repo.parties(), ...extraParties];

  int get drSum => jl
      .where((JLine j) => j.side == 'Dr')
      .fold(0, (int s, JLine j) => s + j.amt);
  int get crSum => jl
      .where((JLine j) => j.side == 'Cr')
      .fold(0, (int s, JLine j) => s + j.amt);

  void setStep(int n) => _set(() => flowStep = n);

  void flowPrev() {
    if (flowStep > 0) {
      _set(() => flowStep--);
    } else {
      back();
    }
  }

  void flowNext() => _set(
    () => flowStep = (flowStep + 1).clamp(
      0,
      kFlowTypes[flowType]!.steps.length - 1,
    ),
  );

  void saveFlow(bool draft) {
    final FlowType cfg = kFlowTypes[flowType]!;
    final String pf = cfg.p;
    int amt;
    if (cfg.items) {
      amt = totals(lines[flowType] ?? <Line>[]).total;
    } else if (flowType == 'journal') {
      amt = drSum;
    } else {
      amt = numOf(form['${pf}Amt']).toInt();
    }
    if (draft) {
      selectTab(0);
      say('Draft saved on this phone');
      return;
    }
    final String no = flowType == 'sales'
        ? 'Sales ${form['sNo']}'
        : (form['${pf}No'] ?? '');
    final String id = 'n${DateTime.now().millisecondsSinceEpoch}';
    final Act e = Act(
      id,
      flowType,
      no,
      form['${pf}Party'] ?? '',
      amt,
      'Just now',
      'wait',
    );
    selectTab(0, <String, Object?>{
      'acts': <Act>[e, ...acts],
    });
    say('Saved! It will reach Tally by itself');
    repo.pushEntry(e).then((_) {
      _set(
        () => acts = acts
            .map(
              (Act a) =>
                  a.id == id ? a.copyWith(status: 'ok', time: 'Just now') : a,
            )
            .toList(),
      );
    });
  }

  void retry(String id) {
    _set(
      () => acts = acts
          .map(
            (Act a) => a.id == id
                ? a.copyWith(status: 'wait', note: 'Trying again…')
                : a,
          )
          .toList(),
    );
    say('Trying again…');
    Timer(const Duration(milliseconds: 1600), () {
      _set(
        () => acts = acts
            .map((Act a) => a.id == id ? a.copyWith(status: 'ok', note: '') : a)
            .toList(),
      );
      say('Sent to Tally');
    });
  }

  void syncAll() {
    final Act? f1 = acts.where((Act a) => a.status == 'fail').firstOrNull;
    if (f1 != null) {
      retry(f1.id);
    } else {
      say('Everything is up to date');
    }
  }

  void openPick(String title, String key, List<Opt> opts) => _set(() {
    overlay = 'pick';
    pick = PickSheet(title, key, opts);
    form['pq'] = '';
  });

  void choosePick(String t, String s) {
    final PickSheet? pk = pick;
    if (pk == null) return;
    if (pk.key == '__jl') {
      _set(() {
        overlay = null;
        jl = <JLine>[...jl, JLine('Dr', t, s, 0)];
      });
      return;
    }
    _set(() {
      form[pk.key] = t;
      overlay = null;
    });
  }

  void openNewParty({String? key, String type = 'c'}) => _set(() {
    overlay = 'newParty';
    npKey = key;
    npType = type;
    form['npName'] = '';
    form['npPhone'] = '';
    form['npCity'] = '';
  });

  void saveParty() {
    final String nm = (form['npName'] ?? '').trim();
    if (nm.isEmpty) return;
    final String city = form['npCity'] ?? '';
    final Party np = Party(nm, npType, city.isEmpty ? '—' : city, 0);
    _set(() {
      if (npKey != null) form[npKey!] = nm;
      extraParties = <Party>[...extraParties, np];
      overlay = null;
    });
    say('$nm added');
  }

  void setMode(String m) => _set(() {
    modes[flowType] = m;
    if (flowType == 'receipt' || flowType == 'payment') {
      form['${kFlowTypes[flowType]!.p}Acc'] = m == 'cash'
          ? 'Cash in hand'
          : (flowType == 'receipt'
                ? 'HDFC Bank – Current'
                : 'ICICI Bank – Current');
    }
  });

  void updLine(int i, int Function(int q) fn) => _set(() {
    final List<Line> cur = lines[flowType] ?? <Line>[];
    lines[flowType] = <Line>[
      for (int j = 0; j < cur.length; j++)
        j == i ? cur[j].withQty(fn(cur[j].qty)) : cur[j],
    ].where((Line x) => x.qty > 0).toList();
  });

  void delLine(int i) {
    updLine(i, (_) => 0);
    say('Item removed');
  }

  void togglePickItem(Item it) => _set(() {
    final List<Line> l = lines[flowType] ?? <Line>[];
    final int i = l.indexWhere((Line x) => x.name == it.name);
    lines[flowType] = i >= 0
        ? (List<Line>.of(l)..removeAt(i))
        : <Line>[...l, Line(it.name, it.rate, 1, it.unit, 18)];
  });

  void stepPickItem(Item it, int d) => _set(() {
    lines[flowType] = (lines[flowType] ?? <Line>[])
        .map(
          (Line l) => l.name == it.name
              ? l.withQty(d > 0 ? l.qty + 1 : (l.qty - 1 < 1 ? 1 : l.qty - 1))
              : l,
        )
        .toList();
  });

  void addNewItem() {
    final String nm = (form['niName'] ?? '').trim();
    final num nq = numOf(form['niQty']),
        nr = numOf(form['niRate']),
        nd = numOf(form['niDisc']);
    _set(() {
      lines[flowType] = <Line>[
        ...(lines[flowType] ?? <Line>[]),
        Line(
          nm,
          (nr * (1 - nd / 100) * 100).round() / 100,
          nq.toInt(),
          niUnit.toLowerCase(),
          niGst,
        ),
      ];
      overlay = null;
      form.addAll(<String, String>{
        'niName': '',
        'niRate': '',
        'niQty': '1',
        'niDisc': '0',
        'niHsn': '',
      });
    });
    say('$nm added to bill');
  }

  void updJl(int i, JLine? Function(JLine) fn) => _set(() {
    jl = <JLine?>[
      for (int k = 0; k < jl.length; k++) k == i ? fn(jl[k]) : jl[k],
    ].whereType<JLine>().toList();
  });

  // ------------------------------------------------------------ workspace
  Workspace get curWs => wsList.firstWhere(
    (Workspace w) => w.id == activeWs,
    orElse: () => wsList.first,
  );

  void saveWs() {
    final String name = (form['wsName'] ?? '').trim();
    final String id = wsEdit ?? 'w${DateTime.now().millisecondsSinceEpoch}';
    final Workspace w = Workspace(
      id,
      name,
      List<String>.of(wsSel),
      wsSums.isNotEmpty ? List<String>.of(wsSums) : <String>['toGet', 'toGive'],
    );
    _set(() {
      wsList = wsEdit != null
          ? wsList.map((Workspace x) => x.id == id ? w : x).toList()
          : <Workspace>[...wsList, w];
      final List<String> h = List<String>.of(history);
      if (h.isNotEmpty && h.last == 'manageWs') h.removeLast();
      screen = 'manageWs';
      history = h;
      dir = 'bk';
      wsEdit = null;
    });
    say('Workspace saved');
  }

  void useWs(Workspace w) {
    _set(() {
      activeWs = w.id;
      page = 0;
    });
    say('Now using ${w.name}');
    selectTab(0);
  }

  void editWs(Workspace w) {
    _set(() {
      wsEdit = w.id;
      wsSel = List<String>.of(w.feats);
      wsSums = List<String>.of(w.sums);
      wsTab = 'f';
      form['wsName'] = w.name;
    });
    go('createWs');
  }

  void delWs(Workspace w) {
    _set(() {
      wsList = wsList.where((Workspace x) => x.id != w.id).toList();
      if (activeWs == w.id) activeWs = 'def';
    });
    say('${w.name} deleted');
  }

  void toggleWsKey(String k) => _set(() {
    final List<String> l = wsTab == 'f' ? wsSel : wsSums;
    final List<String> n = l.contains(k)
        ? l.where((String x) => x != k).toList()
        : <String>[...l, k];
    if (wsTab == 'f') {
      wsSel = n;
    } else {
      wsSums = n;
    }
  });

  // ------------------------------------------------------------ home pages
  List<List<String>> defaultPages(Workspace ws) => <List<String>>[
    <String>['newEntry', ...ws.feats, 'money'],
  ];

  List<List<String>> curPages() => (pagesByWs[curWs.id] ?? defaultPages(curWs))
      .map((List<String> p) => List<String>.of(p))
      .toList();

  void setPages(List<List<String>> pages, [VoidCallback? extra]) => _set(() {
    pagesByWs = Map<String, List<List<String>>>.of(pagesByWs)
      ..[curWs.id] = pages;
    extra?.call();
  });

  List<HiddenCard> hidList() => (hiddenW[curWs.id] ?? <HiddenCard>[])
      .map((HiddenCard h) => h.copy())
      .toList();

  /// `cleanPages`: drop empty pages (except page 0 and pages holding hidden
  /// cards) and remap hidden-card page indexes.
  (List<List<String>>, List<HiddenCard>) cleanPages(
    List<List<String>> pages, [
    List<HiddenCard>? hid,
  ]) {
    final List<HiddenCard> h = hid ?? hidList();
    final Map<int, int> map = <int, int>{};
    List<List<String>> out = <List<String>>[];
    for (int i = 0; i < pages.length; i++) {
      final bool keep =
          i == 0 || pages[i].isNotEmpty || h.any((HiddenCard x) => x.page == i);
      if (keep) {
        map[i] = out.length;
        out.add(pages[i]);
      }
    }
    if (out.isEmpty) out = <List<String>>[<String>[]];
    for (final HiddenCard x in h) {
      x.page = map[x.page] ?? 0;
    }
    return (out, h);
  }

  void _savePages() => store.save(LocalStorage.kPages, pagesByWs);

  void saveHid(List<HiddenCard> hid) {
    hiddenW = Map<String, List<HiddenCard>>.of(hiddenW)..[curWs.id] = hid;
    store.save(
      LocalStorage.kHidden,
      hiddenW.map(
        (String k, List<HiddenCard> v) => MapEntry<String, Object?>(
          k,
          v.map((HiddenCard h) => h.toJson()).toList(),
        ),
      ),
    );
    _set();
  }

  void persistPages(List<List<String>> pages, [VoidCallback? extra]) {
    pagesByWs = Map<String, List<List<String>>>.of(pagesByWs)
      ..[curWs.id] = pages;
    _savePages();
    _set(extra);
  }

  void scrollToPage(int i) {
    final PageController? pc = pager;
    if (pc != null && pc.hasClients) {
      pc.animateToPage(
        i,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
      );
    }
    _set(() => page = i);
    store.save(LocalStorage.kPage, i);
  }

  void onPageChanged(int i) {
    if (i != page) {
      _set(() => page = i);
      store.save(LocalStorage.kPage, i);
    }
  }

  void togglePin(String id) {
    final List<String> pn = List<String>.of(pinned);
    List<List<String>> pages = curPages();
    if (pn.contains(id)) {
      pn.remove(id);
      store.save(LocalStorage.kPinned, pn);
      _set(() {
        pinned = pn;
        cmenu = null;
      });
      say('Unpinned');
      return;
    }
    pn.add(id);
    _pluck(pages, id);
    final int n = pages[0].where(pn.contains).length;
    pages[0].insert(n, id);
    final (List<List<String>>, List<HiddenCard>) r = cleanPages(pages);
    pages = r.$1;
    store.save(LocalStorage.kPinned, pn);
    saveHid(r.$2);
    persistPages(pages, () {
      pinned = pn;
      cmenu = null;
      page = 0;
    });
    Timer(const Duration(milliseconds: 30), () {
      scrollToPage(0);
    });
    say('Pinned to the first page');
  }

  void hideWidget(String id) {
    List<List<String>> pages = curPages();
    final int total = pages.fold(0, (int n, List<String> x) => n + x.length);
    if (total <= 1) {
      _set(() => cmenu = null);
    } else {
      int pi = -1, idx = -1;
      for (int i = 0; i < pages.length; i++) {
        final int k = pages[i].indexOf(id);
        if (k >= 0) {
          pi = i;
          idx = k;
        }
      }
      if (pi < 0) {
        _set(() => cmenu = null);
      } else {
        final List<String> snap = List<String>.of(pages[pi]);
        pages[pi].removeAt(idx);
        final List<HiddenCard> hid =
            hidList().where((HiddenCard h) => h.id != id).toList()
              ..add(HiddenCard(id, pi, idx, snap));
        final (List<List<String>>, List<HiddenCard>) r = cleanPages(pages, hid);
        pages = r.$1;
        final List<String> pn = pinned.where((String x) => x != id).toList();
        pagesByWs = Map<String, List<List<String>>>.of(pagesByWs)
          ..[curWs.id] = pages;
        _savePages();
        store.save(LocalStorage.kPinned, pn);
        saveHid(r.$2);
        _set(() {
          pinned = pn;
          cmenu = null;
        });
      }
    }
    say('Card hidden');
  }

  void restoreHidden(List<String> ids) {
    List<List<String>> pages = curPages();
    List<HiddenCard> hid = hidList();
    final List<String> present = pages.expand((List<String> x) => x).toList();
    final List<HiddenCard> sel =
        hid.where((HiddenCard h) => ids.contains(h.id)).toList()..sort(
          (HiddenCard a, HiddenCard b) =>
              a.page != b.page ? a.page - b.page : a.index - b.index,
        );
    for (final HiddenCard h in sel) {
      if (present.contains(h.id)) continue;
      while (pages.length <= h.page) {
        pages.add(<String>[]);
      }
      final List<String> pg = pages[h.page];
      int at = -1;
      final List<String> snap = h.snap;
      final int me = snap.indexOf(h.id);
      if (me >= 0) {
        for (int k = me + 1; k < snap.length && at < 0; k++) {
          final int n = pg.indexOf(snap[k]);
          if (n >= 0) at = n;
        }
        if (at < 0) {
          for (int q = me - 1; q >= 0 && at < 0; q--) {
            final int b = pg.indexOf(snap[q]);
            if (b >= 0) at = b + 1;
          }
        }
      }
      if (at < 0) at = h.index.clamp(0, pg.length);
      pg.insert(at, h.id);
      present.add(h.id);
    }
    hid = hid.where((HiddenCard h) => !ids.contains(h.id)).toList();
    final (List<List<String>>, List<HiddenCard>) r = cleanPages(pages, hid);
    pages = r.$1;
    pagesByWs = Map<String, List<List<String>>>.of(pagesByWs)
      ..[curWs.id] = pages;
    _savePages();
    saveHid(r.$2);
    final int left = r.$2.where((HiddenCard h) => h.page == hidPage).length;
    _set(() {
      flash = List<String>.of(ids);
      if (left == 0) overlay = null;
    });
    _fl?.cancel();
    _fl = Timer(
      const Duration(milliseconds: 1400),
      () => _set(() => flash = <String>[]),
    );
    say(ids.length > 1 ? 'Cards unhidden' : 'Card unhidden');
  }

  void showHiddenPanel(int i) => _set(() {
    overlay = 'hiddenPanel';
    hidPage = i;
  });

  void _pluck(List<List<String>> pages, String id) {
    for (final List<String> p in pages) {
      p.remove(id);
    }
  }

  // --------------------------------------------------- card / list menus
  CardInfo? infoFor(String list, String key) {
    switch (list) {
      case 'home':
        final ({String label, String ic, String c})? w = widgetMeta(key);
        if (w == null) return null;
        return CardInfo(w.label, w.ic, w.c, () => openHomeWidget(key));
      case 'notifs':
        final Notif? n = notifs.where((Notif x) => x.id == key).firstOrNull;
        return n == null ? null : CardInfo(n.t, n.ic, n.c, () => openNotif(n));
      case 'vouchers':
        final Voucher? v = repo
            .vouchers()
            .where((Voucher x) => x.no == key)
            .firstOrNull;
        if (v == null) return null;
        final Kind k = kKinds[v.kind]!;
        return CardInfo(
          '${v.party} · ${v.no}',
          k.ic,
          k.c,
          () => go('entryDetail', <String, Object?>{'entry': v}),
        );
      case 'bills':
        final bool r = outKind == 'recv';
        final Bill? b = (r ? repo.receivables() : repo.payables())
            .where((Bill x) => x.no == key)
            .firstOrNull;
        if (b == null) return null;
        return CardInfo(
          '${b.party} · ${b.no}',
          r ? 'in' : 'out',
          r ? 'receipt' : 'payment',
          () =>
              go('billDetail', <String, Object?>{'bill': b.withKind(outKind)}),
        );
      case 'items':
        return CardInfo(
          key,
          'box',
          'items',
          () => go('report', <String, Object?>{'report': 'stock'}),
        );
      case 'party':
        return CardInfo(
          key,
          'person',
          'party',
          () => go('partyDetail', <String, Object?>{
            'party': key,
            'partyTab': 'summary',
          }),
        );
      case 'reports':
        final Report? rp = repo
            .reports()
            .where((Report x) => x.id == key)
            .firstOrNull;
        return rp == null
            ? null
            : CardInfo(
                rp.t,
                rp.ic,
                rp.c,
                () => go('report', <String, Object?>{'report': rp.id}),
              );
      case 'acts':
        final Act? a = acts.where((Act x) => x.id == key).firstOrNull;
        if (a == null) return null;
        final Kind k = kKinds[a.kind]!;
        return CardInfo(
          '${k.t} · ${a.no}',
          k.ic,
          k.c,
          () => go('actDetail', <String, Object?>{'act': a.id}),
        );
      case 'team':
        final Member? m = team.where((Member x) => x.email == key).firstOrNull;
        return m == null
            ? null
            : CardInfo(m.name, 'person', 'team', () => openMember(m));
    }
    return null;
  }

  /// `W(id)` label/icon/colour for a Home card.
  ({String label, String ic, String c})? widgetMeta(String id) {
    if (id == 'newEntry') return (label: 'New Entry', ic: 'plus', c: 'acc');
    if (id == 'money') {
      return (label: 'Money summary', ic: 'rupeeC', c: 'outstanding');
    }
    final Shortcut? t = kShortcuts[id];
    if (t == null) return null;
    return (label: t.t, ic: t.ic, c: t.c);
  }

  void openHomeWidget(String id) {
    if (id == 'newEntry') {
      go('newEntry');
    } else if (id == 'money') {
      go('outHub');
    } else {
      openShortcut(kShortcuts[id]!);
    }
  }

  void openShortcut(Shortcut t) {
    if (t.flow != null) {
      startFlow(t.flow!);
    } else {
      go(t.to!);
    }
  }

  void openNotif(Notif n) {
    _set(
      () => notifs = notifs
          .map((Notif x) => x.id == n.id ? x.read() : x)
          .toList(),
    );
    run(n.go);
  }

  void openMember(Member m) => _set(() {
    overlay = 'member';
    member = m.id;
  });

  /// `guard` / `lg`: swallow the click that follows a long-press, and clicks
  /// on an armed card.
  bool guardTap(String list, String key) {
    if (lpFired) {
      lpFired = false;
      return false;
    }
    final ListRef? a = armed;
    if (a != null && a.matches(list, key)) return false;
    return true;
  }

  bool isPinned(String list, String key) => list == 'home'
      ? pinned.contains(key)
      : (listPrefs[list]?.pinned.contains(key) ?? false);

  void closeCMenu() {
    lpFired = false;
    _set(() => cmenu = null);
  }

  void cmPin() {
    final CMenu? c = cmenu;
    if (c == null) return;
    lpFired = false;
    if (c.list == 'home') {
      togglePin(c.id);
      return;
    }
    bool on = false;
    updPref(c.list, (ListPref pr) {
      if (pr.pinned.contains(c.id)) {
        pr.pinned.remove(c.id);
      } else {
        pr.pinned.add(c.id);
        on = true;
      }
    });
    _set(() => cmenu = null);
    say(on ? 'Pinned to the top' : 'Unpinned');
  }

  void cmOpen() {
    final CMenu? c = cmenu;
    if (c == null) return;
    lpFired = false;
    final CardInfo? info = infoFor(c.list, c.id);
    _set(() => cmenu = null);
    info?.open();
  }

  void cmDrag() {
    final CMenu? c = cmenu;
    if (c == null) return;
    lpFired = false;
    _set(() {
      armed = ListRef(c.list, c.id);
      cmenu = null;
    });
  }

  /// NEW: Share from the long-press menu.
  void cmShare() {
    final CMenu? c = cmenu;
    if (c == null) return;
    lpFired = false;
    final ShareDoc? d = docForCard(c.list, c.id);
    _set(() => cmenu = null);
    if (d != null) shareDoc(d);
  }

  void cmHide() {
    final CMenu? c = cmenu;
    if (c == null) return;
    lpFired = false;
    if (c.list == 'home') {
      hideWidget(c.id);
      return;
    }
    updPref(c.list, (ListPref pr) {
      if (!pr.hidden.contains(c.id)) pr.hidden.add(c.id);
      pr.pinned.remove(c.id);
    });
    _set(() => cmenu = null);
    say('Card hidden');
  }

  void updPref(String list, void Function(ListPref) fn) {
    final ListPref pr = (listPrefs[list] ?? ListPref()).copy();
    fn(pr);
    listPrefs = Map<String, ListPref>.of(listPrefs)..[list] = pr;
    store.save(
      LocalStorage.kLists,
      listPrefs.map(
        (String k, ListPref v) => MapEntry<String, Object?>(k, v.toJson()),
      ),
    );
    _set();
  }

  /// The prototype's `L(list, rows, keyOf, …)`: hides hidden rows, puts
  /// pinned rows first, then the saved order, then the original order.
  ({List<T> rows, int hidden, VoidCallback unhide}) listView<T>(
    String list,
    List<T> rows,
    String Function(T) keyOf,
  ) {
    final ListPref pr = listPrefs[list] ?? ListPref();
    final List<String> keys = rows.map(keyOf).toList();
    final List<int> vis = <int>[
      for (int i = 0; i < rows.length; i++)
        if (!pr.hidden.contains(keys[i])) i,
    ];
    vis.sort((int a, int b) {
      final int pa = pr.pinned.contains(keys[a]) ? 0 : 1,
          pb = pr.pinned.contains(keys[b]) ? 0 : 1;
      if (pa != pb) return pa - pb;
      int ra = pr.order.indexOf(keys[a]), rb = pr.order.indexOf(keys[b]);
      ra = ra < 0 ? 1000000 + a : ra;
      rb = rb < 0 ? 1000000 + b : rb;
      return ra - rb;
    });
    _seq[list] = vis.map((int i) => keys[i]).toList();
    return (
      rows: vis.map((int i) => rows[i]).toList(),
      hidden: rows.length - vis.length,
      unhide: () => updPref(
        list,
        (ListPref q) =>
            q.hidden = q.hidden.where((String k) => !keys.contains(k)).toList(),
      ),
    );
  }

  // ------------------------------------------------- pointer: long-press
  int? _ptr;
  Offset _p0 = Offset.zero;
  bool _fired = false;
  String _pList = '';
  String _pId = '';
  GlobalKey? _pKey;
  Size _screen = const Size(390, 844);

  void setScreenSize(Size s) => _screen = s;
  Size get screenSize => _screen;

  /// `pDown(e, list, id)` — long-press 480 ms opens the card menu; moving
  /// more than 12 px afterwards starts a drag. An armed card drags at once.
  void pDown(PointerDownEvent e, String list, String id, GlobalKey key) {
    if (e.buttons > 1 && e.kind == PointerDeviceKind.mouse) return;
    lpFired = false;
    final ListRef? a = armed;
    if (a != null && a.matches(list, id)) {
      _startAnyDrag(list, id, e.position, e.pointer);
      return;
    }
    if (a != null) _set(() => armed = null);
    _lp?.cancel();
    _stopRoute();
    _ptr = e.pointer;
    _p0 = e.position;
    _fired = false;
    _pList = list;
    _pId = id;
    _pKey = key;
    _route = _lpRoute;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route!);
    _lp = Timer(const Duration(milliseconds: 480), () {
      _fired = true;
      lpFired = true;
      _lpActive = true;
      final Rect? r = HitRegistry.rectOf(_pKey!);
      if (r != null) openCardMenu(_pList, _pId, r);
      HapticFeedback.mediumImpact();
    });
  }

  PointerRoute? _route;

  void _stopRoute() {
    if (_route != null) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_route!);
      _route = null;
    }
  }

  void _lpRoute(PointerEvent ev) {
    if (ev.pointer != _ptr) return;
    if (ev is PointerMoveEvent) {
      final double d =
          (ev.position.dx - _p0.dx).abs() + (ev.position.dy - _p0.dy).abs();
      if (!_fired) {
        if (d > 10) {
          _lp?.cancel();
          _stopRoute();
        }
        return;
      }
      if (d > 12) {
        _stopRoute();
        _set(() => cmenu = null);
        _startAnyDrag(_pList, _pId, ev.position, ev.pointer);
      }
    } else if (ev is PointerUpEvent || ev is PointerCancelEvent) {
      _lp?.cancel();
      _stopRoute();
      if (_lpActive) _set(() => _lpActive = false);
    }
  }

  void openCardMenu(String list, String id, Rect b) {
    // 262 px in the prototype + one 48 px row for the new Share item.
    const double mh = 310, mw = 214;
    final double hgt = _screen.height, wid = _screen.width;
    double y = (b.bottom + 10 + mh < hgt - 104)
        ? b.bottom + 10
        : (b.top - 10 - mh).clamp(96, double.infinity);
    if (y + mh > hgt - 104) y = (hgt - 104 - mh).clamp(40, double.infinity);
    final double x = (b.left + b.width / 2 - mw / 2).clamp(16, wid - 16 - mw);
    _set(() => cmenu = CMenu(list, id, x.roundToDouble(), y.roundToDouble()));
  }

  void _startAnyDrag(String list, String id, Offset pos, int pointer) {
    _ptr = pointer;
    if (list == 'home') {
      _beginDrag(id, pos);
    } else {
      _lBegin(list, id, pos);
    }
  }

  // -------------------------------------------------- list drag reorder
  void _lBegin(String list, String id, Offset pt) {
    _lastKey = null;
    _stopRoute();
    _set(() {
      ldrag = DragPt(list, id, pt.dx, pt.dy);
      _lpActive = false;
    });
    _route = (PointerEvent ev) {
      if (ev.pointer != _ptr) return;
      if (ev is PointerMoveEvent) {
        _lMove(ev.position);
      } else if (ev is PointerUpEvent || ev is PointerCancelEvent) {
        _lEnd();
      }
    };
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route!);
  }

  void _lMove(Offset pt) {
    final DragPt? d = ldrag;
    if (d == null) return;
    _set(() => ldrag = DragPt(d.list, d.id, pt.dx, pt.dy));
    final ScrollController? sc = reg.screenScroll;
    final Rect? vr = reg.screenViewport != null
        ? HitRegistry.rectOf(reg.screenViewport!)
        : null;
    if (sc != null && sc.hasClients && vr != null) {
      final ScrollPosition ps = sc.position;
      if (pt.dy < vr.top + 56) {
        sc.jumpTo(
          (ps.pixels - 12).clamp(ps.minScrollExtent, ps.maxScrollExtent),
        );
      } else if (pt.dy > vr.bottom - 56) {
        sc.jumpTo(
          (ps.pixels + 12).clamp(ps.minScrollExtent, ps.maxScrollExtent),
        );
      }
    }
    for (final MapEntry<String, GlobalKey> e in reg.rows.entries) {
      final int bar = e.key.indexOf('|');
      if (e.key.substring(0, bar) != d.list) continue;
      final String tk = e.key.substring(bar + 1);
      if (tk == d.id) continue;
      final Rect? b = HitRegistry.rectOf(e.value);
      if (b == null || !b.contains(pt)) continue;
      final bool after = d.list == 'reports'
          ? pt.dx > b.left + b.width / 2
          : pt.dy > b.top + b.height / 2;
      final String key = '$tk${after ? '>' : '<'}';
      if (key == _lastKey) return;
      _lastKey = key;
      final List<String> seq = List<String>.of(_seq[d.list] ?? <String>[]);
      seq.remove(d.id);
      final int j = seq.indexOf(tk);
      if (j < 0) return;
      seq.insert(j + (after ? 1 : 0), d.id);
      updPref(
        d.list,
        (ListPref pr) => pr.order = <String>[
          ...seq,
          ...pr.order.where((String k) => !seq.contains(k)),
        ],
      );
      return;
    }
  }

  void _lEnd() {
    _stopRoute();
    _lastKey = null;
    _set(() {
      ldrag = null;
      armed = null;
      _lpActive = false;
    });
  }

  // -------------------------------------------------- home drag & drop
  void _beginDrag(String id, Offset pt) {
    _lastKey = null;
    _edge = null;
    _flipped = null;
    _d0 = pt;
    _snap = curPages().map((List<String> p) => p.join('\u0001')).join('\u0002');
    _stopRoute();
    _set(() {
      drag = DragPt('home', id, pt.dx, pt.dy);
      edge = null;
      _lpActive = false;
    });
    _route = (PointerEvent ev) {
      if (ev.pointer != _ptr) return;
      if (ev is PointerMoveEvent) {
        _dragMove(ev.position);
      } else if (ev is PointerUpEvent) {
        _dragEnd();
      } else if (ev is PointerCancelEvent) {
        _dragCancel();
      }
    };
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route!);
  }

  void _dragMove(Offset pt) {
    final DragPt? d = drag;
    if (d == null) return;
    final String id = d.id;
    final bool travelled = (pt.dx - _d0!.dx).abs() > 44;
    final String? e = !travelled
        ? null
        : (pt.dx < 22 && pt.dx < _d0!.dx
              ? 'l'
              : (pt.dx > _screen.width - 22 && pt.dx > _d0!.dx ? 'r' : null));
    if (e != _edge) {
      _edge = e;
      _et?.cancel();
      if (e == null) _flipped = null;
      if (e != null && _flipped != e) _armEdge(e);
    }
    _set(() {
      drag = DragPt('home', id, pt.dx, pt.dy);
      edge = e;
    });
    if (e != null) return;
    for (final MapEntry<String, GlobalKey> en in reg.cards.entries) {
      if (en.key == id) continue;
      final Rect? b = HitRegistry.rectOf(en.value);
      if (b == null || !b.contains(pt)) continue;
      final bool wide = en.key == 'newEntry' || en.key == 'money';
      final bool after = wide
          ? pt.dy > b.top + b.height / 2
          : pt.dx > b.left + b.width / 2;
      final String key = '${en.key}${after ? '>' : '<'}';
      if (key == _lastKey) return;
      _lastKey = key;
      _moveTo(id, en.key, after);
      return;
    }
    for (final MapEntry<int, GlobalKey> en in reg.ends.entries) {
      final Rect? b = HitRegistry.rectOf(en.value);
      if (b == null || !b.contains(pt)) continue;
      final String k2 = 'end${en.key}';
      if (k2 == _lastKey) return;
      _lastKey = k2;
      _moveToPage(id, en.key);
      return;
    }
  }

  void _moveTo(String id, String tid, bool after) {
    final List<List<String>> pages = curPages();
    _pluck(pages, id);
    for (final List<String> pg in pages) {
      final int k = pg.indexOf(tid);
      if (k >= 0) {
        pg.insert(k + (after ? 1 : 0), id);
        break;
      }
    }
    setPages(pages);
  }

  void _moveToPage(String id, int pi) {
    final List<List<String>> pages = curPages();
    if (pi >= pages.length) return;
    if (pages[pi].isNotEmpty && pages[pi].last == id) return;
    _pluck(pages, id);
    pages[pi].add(id);
    setPages(pages);
  }

  void _armEdge(String e) {
    _et = Timer(const Duration(milliseconds: 700), () {
      if (_edge != e || drag == null) return;
      _flipped = e;
      _flip(e);
    });
  }

  void _flip(String e) {
    final String id = drag!.id;
    final int cur = page;
    final List<List<String>> pages = curPages();
    if (e == 'l' && cur == 0) return;
    final int target = e == 'l' ? cur - 1 : cur + 1;
    if (target >= pages.length) {
      final List<String> src = cur < pages.length ? pages[cur] : <String>[];
      if (src.length <= 1 && src.contains(id)) return;
      pages.add(<String>[]);
    }
    _pluck(pages, id);
    pages[target].add(id);
    _lastKey = null;
    setPages(pages, () => page = target);
    Timer(const Duration(milliseconds: 20), () => scrollToPage(target));
  }

  void _dragCancel() {
    _stopRoute();
    _et?.cancel();
    _edge = null;
    _lastKey = null;
    final List<List<String>> pages = _snap != null
        ? _snap!
              .split('\u0002')
              .map((String p) => p.isEmpty ? <String>[] : p.split('\u0001'))
              .toList()
        : curPages();
    setPages(pages, () {
      drag = null;
      edge = null;
      armed = null;
    });
  }

  void _dragEnd() {
    _stopRoute();
    _et?.cancel();
    _edge = null;
    _lastKey = null;
    final (List<List<String>>, List<HiddenCard>) r = cleanPages(curPages());
    saveHid(r.$2);
    final int pi = page.clamp(0, r.$1.length - 1);
    persistPages(r.$1, () {
      drag = null;
      edge = null;
      page = pi;
      armed = null;
    });
    store.save(LocalStorage.kPage, pi);
    Timer(const Duration(milliseconds: 20), () => scrollToPage(pi));
  }

  // ------------------------------------------------------------- tab bar
  double _slot = 70;
  double _barLeft = 14;

  void setBarGeometry(double slot, double barLeft) {
    _slot = slot;
    _barLeft = barLeft;
  }

  /// `tDown(e, i)` — long-press 450 ms lifts a tab; dragging reorders.
  void tDown(PointerDownEvent e, int i) {
    tabLp = false;
    _tlp?.cancel();
    final Offset p0 = e.position;
    final int ptr = e.pointer;
    double barX(double gx) => gx - _barLeft;
    late final PointerRoute r;
    r = (PointerEvent ev) {
      if (ev.pointer != ptr) return;
      if (ev is PointerMoveEvent) {
        if (tdrag == null) {
          if ((ev.position.dx - p0.dx).abs() + (ev.position.dy - p0.dy).abs() >
              10) {
            _tlp?.cancel();
          }
          return;
        }
        final double maxL = _slot * 5 + 12 - _slot;
        final double left = (barX(ev.position.dx) - _slot / 2).clamp(0, maxL);
        final int pos = ((left - 6) / _slot).round().clamp(0, 4);
        final List<int> order = List<int>.of(tabOrder);
        final int cur = order.indexOf(i);
        _set(() {
          tdrag = (i: i, x: left);
          if (pos != cur) {
            order.removeAt(cur);
            order.insert(pos, i);
            tabOrder = order;
            pillPos = order.indexOf(tab).toDouble();
            pillSpan = 1;
            pillS = 1;
            pillT = PillTr.reorder;
          }
        });
      } else if (ev is PointerUpEvent || ev is PointerCancelEvent) {
        _tlp?.cancel();
        GestureBinding.instance.pointerRouter.removeGlobalRoute(r);
        if (tdrag != null) {
          store.save(LocalStorage.kTabs, tabOrder);
          _set(() => tdrag = null);
        }
      }
    };
    GestureBinding.instance.pointerRouter.addGlobalRoute(r);
    _tlp = Timer(const Duration(milliseconds: 450), () {
      tabLp = true;
      final double left = (barX(p0.dx) - _slot / 2).clamp(0, _slot * 4 + 12);
      _set(() => tdrag = (i: i, x: left));
      HapticFeedback.lightImpact();
    });
  }

  void tapTab(int i) {
    if (tabLp) {
      tabLp = false;
      return;
    }
    selectTab(i);
  }

  // hover bubble (`hb`)
  int? _hbStart;
  bool _hbTouch = false;

  int barPos(double localX) => ((localX - 6) / _slot).floor().clamp(0, 4);

  void hbDown(PointerDownEvent e, double localX) {
    final int q = barPos(localX);
    _hb?.cancel();
    _dw?.cancel();
    _hbStart = q;
    _hbTouch = e.kind != PointerDeviceKind.mouse;
    _set(() {
      hovPos = q;
      hovOn = true;
      dwell = false;
    });
  }

  void hbMove(PointerEvent e, double localX) {
    if (e.kind == PointerDeviceKind.touch && !hovOn) return;
    final int q = barPos(localX);
    if (q != hovPos || !hovOn) {
      _set(() {
        hovPos = q;
        hovOn = true;
        dwell = false;
      });
      _armDwell(e, q);
    }
  }

  void hbLeave() {
    _dw?.cancel();
    if (hovOn) {
      _set(() {
        hovOn = false;
        dwell = false;
      });
    }
  }

  void hbUp(PointerEvent e, double localX) {
    _dw?.cancel();
    final int q = barPos(localX);
    if (_hbTouch && q != _hbStart && tdrag == null) {
      final int ti = tabOrder[q];
      if (ti != tab) {
        tabLp = true;
        selectTab(ti);
      }
    }
    _hbTouch = false;
    if (e.kind != PointerDeviceKind.mouse) {
      _hb?.cancel();
      _hb = Timer(const Duration(milliseconds: 320), () {
        // A tap that never landed on a button must not leave tabLp set.
        tabLp = false;
        _set(() {
          hovOn = false;
          dwell = false;
        });
      });
    }
  }

  void _armDwell(PointerEvent e, int q) {
    _dw?.cancel();
    _dw0?.cancel();
    if (e.kind == PointerDeviceKind.touch || e.buttons != 0 || tdrag != null) {
      return;
    }
    final int ti = tabOrder[q];
    if (ti == tab) return;
    _dw0 = Timer(const Duration(milliseconds: 60), () {
      if (hovPos == q && hovOn) _set(() => dwell = true);
    });
    _dw = Timer(const Duration(milliseconds: 650), () {
      if (hovOn && hovPos == q && tdrag == null) {
        _set(() => dwell = false);
        if (tab != ti) selectTab(ti);
      }
    });
  }

  // ----------------------------------------------------------- team
  void sendInvite() {
    final String em = (form['iEmail'] ?? '').trim();
    _set(() {
      overlay = null;
      team = <Member>[
        ...team,
        Member(
          't${DateTime.now().millisecondsSinceEpoch}',
          em.split('@').first,
          em,
          'Sales Rep',
          'pending',
        ),
      ];
    });
    say('Invite sent to $em');
  }

  void saveUser() {
    final String nm = (form['nuName'] ?? '').trim();
    final String ph = form['nuPhone'] ?? '';
    _set(() {
      overlay = null;
      team = <Member>[
        ...team,
        Member(
          't${DateTime.now().millisecondsSinceEpoch}',
          nm,
          ph.isNotEmpty ? ph : 'No email yet',
          'Sales Rep',
          'active',
        ),
      ];
    });
    say('$nm added to your team');
  }

  void setMemberSt(Member m, String st, String msg) {
    _set(() {
      overlay = null;
      team = team.map((Member x) => x.id == m.id ? x.withSt(st) : x).toList();
    });
    say(msg);
  }

  void cancelInvite(Member m) {
    _set(() {
      overlay = null;
      team = team.where((Member x) => x.id != m.id).toList();
    });
    say('Invite cancelled');
  }

  void markAll() {
    _set(() => notifs = notifs.map((Notif n) => n.read()).toList());
    say('All marked as read');
  }

  // ------------------------------------------------------------- look
  void pickLook(String k) {
    final String a = okAccent(k, accent) ? accent : 'look';
    _set(() {
      preset = k;
      accent = a;
      mode = 'look';
    });
    store.save(LocalStorage.kPreset, k);
    store.save(LocalStorage.kAccent, a);
    store.save(LocalStorage.kMode, 'look');
  }

  void pickAccent(String k) {
    _set(() {
      accent = k;
      mode = 'look';
    });
    store.save(LocalStorage.kAccent, k);
    store.save(LocalStorage.kMode, 'look');
  }

  void setGlass(double v) => _set(() => glass = v);

  void resetLook() {
    _set(() {
      glass = 60;
      preset = 'aurora';
      accent = 'look';
      mode = 'look';
      wallK = 'theme';
      pendWall = null;
    });
    store.save(LocalStorage.kPreset, 'aurora');
    store.save(LocalStorage.kAccent, 'look');
    store.save(LocalStorage.kMode, 'look');
    store.save(LocalStorage.kWall, 'theme');
    say('Look set back to default');
  }

  String get cpHex =>
      cpExact ?? hsv2hex(cpH.toDouble(), cpS.toDouble(), cpV.toDouble());

  void cpPad(double sx, double vy) => _set(() {
    cpS = (sx.clamp(0, 1) * 100).round();
    cpV = ((1 - vy.clamp(0, 1)) * 100).round();
    cpHexTyping = null;
    cpExact = null;
  });

  void cpHue(double h) => _set(() {
    cpH = h.round();
    cpHexTyping = null;
    cpExact = null;
  });

  void cpHexInput(String raw) {
    final String v = raw.replaceAll(RegExp('[^0-9a-fA-F]'), '');
    final String t = v.length > 6 ? v.substring(0, 6) : v;
    if (t.length == 6) {
      final List<int> q = hex2hsv('#$t');
      _set(() {
        cpH = q[0];
        cpS = q[1];
        cpV = q[2];
        cpHexTyping = null;
        cpExact = '#$t'.toUpperCase();
      });
    } else {
      _set(() => cpHexTyping = t);
    }
  }

  void cpPickHex(String h) {
    final List<int> q = hex2hsv(h);
    _set(() {
      cpH = q[0];
      cpS = q[1];
      cpV = q[2];
      cpHexTyping = null;
      cpExact = h.toUpperCase();
    });
  }

  void pickCombo(int i) {
    final String base = cpHex;
    _set(() {
      mode = 'custom';
      customBase = base;
      customCombo = i;
    });
    store.save(LocalStorage.kCustom, <String, Object?>{
      'base': base,
      'combo': i,
    });
    store.save(LocalStorage.kMode, 'custom');
    say('${kCombos[i].t} look applied');
  }

  void pickWall(String k) {
    if (k == wallK) {
      _set(() => pendWall = null);
      return;
    }
    _set(() {
      pendWall = k;
      pendPhoto = k == 'photo' ? photo : null;
    });
  }

  void cancelWall() => _set(() {
    pendWall = null;
    pendPhoto = null;
  });

  void applyWall() {
    final String? k = pendWall;
    if (k == null) return;
    _set(() {
      wallK = k;
      if (k == 'photo' && pendPhoto != null) {
        photo = pendPhoto;
        store.save(LocalStorage.kPhoto, pendPhoto!.toJson());
      }
      pendWall = null;
      pendPhoto = null;
    });
    store.save(LocalStorage.kWall, k);
    say('Wallpaper applied');
  }

  /// `wp.onFile`: pick a photo, downscale to max side 1100 (JPEG q80), store
  /// it in the documents folder and measure average luminance on 16×16.
  Future<void> uploadPhoto() async {
    try {
      final XFile? x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1100,
        maxHeight: 1100,
        imageQuality: 80,
      );
      if (x == null) return;
      final String mime = x.mimeType ?? '';
      final String ext = p.extension(x.path).toLowerCase();
      final bool isImg =
          mime.startsWith('image/') ||
          <String>[
            '.jpg',
            '.jpeg',
            '.png',
            '.webp',
            '.heic',
            '.gif',
            '.bmp',
          ].contains(ext);
      if (!isImg) {
        say('Please pick a photo');
        return;
      }
      final Directory dir = await getApplicationDocumentsDirectory();
      final String dest = p.join(
        dir.path,
        'tc_wall_${DateTime.now().millisecondsSinceEpoch}${ext.isEmpty ? '.jpg' : ext}',
      );
      final List<int> bytes = await x.readAsBytes();
      await File(dest).writeAsBytes(bytes, flush: true);
      final ui.Codec codec = await ui.instantiateImageCodec(
        Uint8List.fromList(bytes),
        targetWidth: 16,
        targetHeight: 16,
      );
      final ui.FrameInfo fr = await codec.getNextFrame();
      final ByteData? data = await fr.image.toByteData();
      double sum = 0;
      int n = 0;
      if (data != null) {
        for (int i = 0; i + 3 < data.lengthInBytes; i += 4) {
          sum += lumOf(<int>[
            data.getUint8(i),
            data.getUint8(i + 1),
            data.getUint8(i + 2),
          ]);
          n++;
        }
      }
      _set(() {
        pendWall = 'photo';
        pendPhoto = Photo(dest, n == 0 ? 1 : sum / n);
      });
    } catch (_) {
      say('Could not read that photo');
    }
  }

  // ------------------------------------------------------------- pdf
  void openPdf(PdfInfo info) => _set(() {
    overlay = 'pdf';
    zoom = 100;
    pdf = info;
  });

  // ------------------------------------------- share / pdf (NEW feature)
  /// Document shown by the generic PDF preview (`overlay == 'doc'`).
  ShareDoc? docShown;
  Future<Uint8List>? _docBytes;
  bool docBusy = false;

  int get _accentArgb => palette.acc.toARGB32();

  Future<Uint8List> pdfOf(ShareDoc d) => exporter.pdf(d, _accentArgb);

  /// Native share sheet with the PDF + a text summary.
  Future<void> shareDoc(ShareDoc d) async {
    if (docBusy) return;
    docBusy = true;
    say('Share sheet opened');
    try {
      await exporter.share(d, await pdfOf(d));
    } catch (_) {
      say('Could not open the share sheet');
    } finally {
      docBusy = false;
    }
  }

  Future<void> downloadDoc(ShareDoc d) async {
    if (docBusy) return;
    docBusy = true;
    try {
      await exporter.download(d.fileName, await pdfOf(d));
      say('Saved to Downloads');
    } catch (_) {
      say('Could not save the PDF');
    } finally {
      docBusy = false;
    }
  }

  /// Opens the in-app PDF preview of a generated document.
  void previewDoc(ShareDoc d) => _set(() {
    docShown = d;
    _docBytes = pdfOf(d);
    zoom = 100;
    overlay = 'doc';
  });

  Future<Uint8List>? get docBytes => _docBytes;

  /// The bill PDF currently open in the prototype's viewer, as a document.
  ShareDoc get pdfDoc => docInvoice(
    pdf ??
        const PdfInfo(
          party: 'Shree Balaji Traders',
          no: 'Sales 9',
          date: '21 Sep 2026',
          due: '06 Oct 2026',
          total: 112100,
          kind: 'Sales bill',
          city: 'Mumbai',
          recv: true,
        ),
    companyName,
    repo.billLines('Sales 9'),
  );

  /// Document for a long-pressed card (`list|key`).
  ShareDoc? docForCard(String list, String key) {
    final String co = companyName;
    switch (list) {
      case 'home':
        switch (key) {
          case 'money':
            return docSums(<SumCard>[
              for (final String k in curWs.sums)
                if (repo.moneyCards()[k] != null) repo.moneyCards()[k]!,
            ], co);
          case 'items':
            return docItems(repo.items(), co);
          case 'party':
            return docParties(partyPool(), co);
          case 'vouchers':
            return docVouchers(
              'All Vouchers',
              repo.vouchers(),
              co,
              'This month',
            );
          case 'outstanding':
            return docBills(true, repo.receivables(), co);
          case 'reports':
            return docReportList(co);
          case 'sales' || 'purchase' || 'moneyIn' || 'moneyOut':
            final String kind = kShortcuts[key]!.flow!;
            final String t = kKinds[kind]!.t;
            return docVouchers(
              t,
              repo.vouchers().where((Voucher v) => v.kind == kind).toList(),
              co,
              'This month',
            );
          default:
            final ({String label, String ic, String c})? m = widgetMeta(key);
            if (m == null) return null;
            final Shortcut? sc = kShortcuts[key];
            return ShareDoc(
              title: m.label,
              subtitle: sc?.s ?? 'Record a sale, purchase, money in or out',
              company: co,
            );
        }
      case 'notifs':
        final Notif? n = notifs.where((Notif x) => x.id == key).firstOrNull;
        return n == null ? null : docNotif(n, co);
      case 'vouchers':
        final Voucher? v = repo
            .vouchers()
            .where((Voucher x) => x.no == key)
            .firstOrNull;
        return v == null ? null : docEntry(v, co);
      case 'bills':
        final Bill? b =
            (outKind == 'recv' ? repo.receivables() : repo.payables())
                .where((Bill x) => x.no == key)
                .firstOrNull;
        return b == null ? null : docBill(b.withKind(outKind), co);
      case 'items':
        final Item? it = repo
            .items()
            .where((Item x) => x.name == key)
            .firstOrNull;
        return it == null ? null : docItem(it, co);
      case 'party':
        final Party? pa = partyPool()
            .where((Party x) => x.name == key)
            .firstOrNull;
        return pa == null ? null : docPartyRow(pa, co);
      case 'reports':
        return docReport(reportData(repo, key), co);
      case 'acts':
        final Act? a = acts.where((Act x) => x.id == key).firstOrNull;
        return a == null ? null : docAct(a, co);
      case 'team':
        final Member? m = team.where((Member x) => x.email == key).firstOrNull;
        return m == null ? null : docMember(m, co);
    }
    return null;
  }

  ShareDoc docReportList(String co) => ShareDoc(
    title: 'Reports · September 2026',
    subtitle: 'Easy views of your Tally data',
    company: co,
    fileStem: 'Reports',
    table: DocTable(
      const <String>['Report', 'About', 'Value'],
      <List<String>>[
        for (final Report r in repo.reports())
          <String>[r.t, r.s, reportData(repo, r.id).total],
      ],
      right: const <int>{2},
    ),
  );

  void zoomBy(int d) => _set(() => zoom = (zoom + d).clamp(60, 160));

  // ------------------------------------------------------------ misc
  void refreshNow() => say('Up to date · synced just now');

  /// Android back: overlay → card menu/armed → screen back.
  bool handleSystemBack() {
    if (cmenu != null || armed != null) {
      _set(() {
        cmenu = null;
        armed = null;
      });
      return true;
    }
    if (overlay == 'addItem') {
      _set(() => overlay = 'picker');
      return true;
    }
    if (overlay != null) {
      closeOv();
      return true;
    }
    if (screen == 'login' || (screen == 'home' && history.isEmpty)) {
      return false;
    }
    back();
    return true;
  }

  /// Exposes `_set` for simple field toggles from views.
  void update(VoidCallback f) => _set(f);
}
