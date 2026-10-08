// The app controller: a 1:1 port of `class Component` in Main.dc.html
// (state 1916–1955, methods 1956–2258 and the handlers built in renderVals).
// One ChangeNotifier holds every piece of UI state, exactly like the
// prototype's single component state; widgets read it and call methods.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/design/tc_color_math.dart';
import '../core/network/api_client.dart';
import '../core/notify/reminder_alarms.dart';
import '../core/design/tc_palette.dart';
import '../core/storage/local_storage.dart';
import '../core/utils/format.dart';
import '../data/accounting.dart' show voucherKind;
import '../data/api/adapters.dart' show kNotifTarget;
import '../data/mock/mock_data.dart';
import '../data/models/models.dart';
import '../data/repositories/api_tally_repository.dart' show DataSet;
import '../data/repositories/tally_repository.dart';
import '../data/repositories/team_admin.dart';
import '../core/share/doc_exporter.dart';
import '../core/share/links.dart';
import '../core/share/report_data.dart';
import '../core/share/share_doc.dart';

class ListRef {
  const ListRef(this.list, this.id);
  final String list, id;
  bool matches(String l, String i) => list == l && id == i;
}

/// One global-search result (screen, item, party, voucher, bill, …).
class SearchHit {
  const SearchHit(this.t, this.s, this.ic, this.c, this.open);
  final String t, s, ic, c;
  final VoidCallback open;
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

/// One switch in Settings → Notifications.
///
/// [key]: a mobile alert type (`create_entry`, `voucher_sync`, … — saved
/// with /api/mobile/notifications/config), `web.<key>` (web-dashboard
/// preference — /users/me/notifications) or `phone.<key>` (generated on
/// this phone from real data: due dates, stock).
class NotifPref {
  const NotifPref(
    this.key,
    this.t,
    this.s,
    this.group,
    this.ic,
    this.c, {
    this.adminOnly = false,
  });
  final String key, t, s, group, ic, c;
  final bool adminOnly;
}

const List<NotifPref> kNotifPrefs = <NotifPref>[
  NotifPref(
    'voucher_sync',
    'New vouchers synced from Tally',
    'When the sync brings new vouchers from Tally',
    'Tally sync',
    'receipt',
    'vouchers',
  ),
  NotifPref(
    'sync_completed',
    'Sync completed',
    'When a sync with Tally finishes',
    'Tally sync',
    'sync',
    'activity',
  ),
  NotifPref(
    'sync_failed',
    'Sync failed',
    'When a sync with Tally fails',
    'Tally sync',
    'xCircle',
    'payment',
  ),
  NotifPref(
    'tally_connection',
    'Tally connection',
    'When Tally connects or disconnects',
    'Tally sync',
    'laptop',
    'activity',
  ),
  NotifPref(
    'party_sync',
    'New party synced',
    'A new customer or supplier arrives from Tally',
    'Tally sync',
    'person',
    'party',
  ),
  NotifPref(
    'ledger_sync',
    'New ledger synced',
    'A new ledger arrives from Tally',
    'Tally sync',
    'person',
    'party',
  ),
  NotifPref(
    'item_sync',
    'New item synced',
    'A new stock item arrives from Tally',
    'Tally sync',
    'box',
    'items',
  ),
  NotifPref(
    'create_entry',
    'New entry created',
    'An entry made in the app is queued for Tally',
    'Entries',
    'plus',
    'activity',
  ),
  NotifPref(
    'entry_failed',
    'Entry failed to reach Tally',
    'Tally could not take an entry made in the app',
    'Entries',
    'xCircle',
    'payment',
  ),
  NotifPref(
    'web.new_voucher',
    'Voucher / entry updates',
    'Vouchers created or deleted from TallyConnect',
    'Entries',
    'receipt',
    'vouchers',
  ),
  NotifPref(
    'web.bill_created',
    'Bill created',
    'When a new bill is created',
    'Bills and payments',
    'file',
    'sales',
  ),
  NotifPref(
    'phone.due',
    'Payment due reminders',
    '3 days before a bill is due (on this phone)',
    'Bills and payments',
    'calendar',
    'payment',
  ),
  NotifPref(
    'phone.lowStock',
    'Low stock alerts',
    'When an item runs out of stock in Tally (on this phone)',
    'Stock',
    'box',
    'items',
  ),
  NotifPref(
    'web.monthly_reports',
    'Monthly reports',
    'When your scheduled monthly report is ready',
    'Reports',
    'chart',
    'acc',
  ),
  NotifPref(
    'web.user_created',
    'Team member added',
    'Someone is added to your team',
    'Team',
    'userPlus',
    'team',
    adminOnly: true,
  ),
  NotifPref(
    'web.user_deleted',
    'Team member removed',
    'Someone is removed from your team',
    'Team',
    'person',
    'team',
    adminOnly: true,
  ),
  NotifPref(
    'system_alerts',
    'System alerts',
    'Important messages about your account',
    'System',
    'bell',
    'acc',
  ),
];

class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    TallyRepository? repo,
    String startScreen = 'login',
    double glassLevel = 60,
    DocExporter? exporter,
    ReminderAlarms? alarms,
  }) : repo = repo ?? MockTallyRepository(),
       exporter = exporter ?? PlatformDocExporter(),
       alarms = alarms ?? NoReminderAlarms() {
    final int ti = kTabs.indexWhere(
      (({String k, String t, String ic}) t) => t.k == startScreen,
    );
    screen = startScreen;
    loggedIn = startScreen != 'login' && startScreen != 'forgot';
    tab = ti < 0 ? 0 : ti;
    glass = glassLevel;
    _load();
    pillPos = posOf(tab).toDouble();
    if (this.repo.isRemote) {
      // Real data: no sample values in the entry forms.
      form = _blankForm(this.repo.today);
      lines = <String, List<Line>>{'sales': <Line>[], 'purchase': <Line>[]};
      jl = <JLine>[];
      company = this.repo.activeCompanyId ?? '';
      acts = this.repo.activity();
      notifs = this.repo.notifications();
      team = _labelTeam(this.repo.team());
      this.repo.addListener(_onRepo);
    }
    _startAlarms();
  }

  /// Form defaults for real use: empty fields, today's dates.
  static Map<String, String> _blankForm(DateTime today) {
    final String d = ymd(today);
    return <String, String>{
      for (final String k in kForm.keys) k: '',
      'niQty': '1',
      'niDisc': '0',
      for (final String p in <String>['s', 'p', 'r', 'y', 'j']) '${p}Date': d,
    };
  }

  /// Keeps the controller's lists in step with the repository and ends the
  /// session when the server rejects the token.
  void _onRepo() {
    if (_disposed) return;
    if (repo.activeCompanyId != null &&
        company.isNotEmpty &&
        repo.activeCompanyId != company) {
      // Company changed: on-demand sets were cleared — reload this screen's.
      company = repo.activeCompanyId!;
      Future<void>.microtask(reEnter);
    }
    acts = repo.activity();
    notifs = repo.notifications();
    team = _labelTeam(repo.team());
    company = repo.activeCompanyId ?? '';
    _armDueAlerts();
    _checkStock();
    if (repo.sessionExpired && loggedIn) {
      _endSession('Your session has ended. Please log in again.');
      return;
    }
    _set();
  }

  final LocalStorage store;
  final TallyRepository repo;

  /// Share / PDF / Download platform side (NEW feature).
  final DocExporter exporter;

  /// Device notifications for reminders and due-bill alerts.
  final ReminderAlarms alarms;
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

  /// New item: Tally stock group (chosen from the company's real groups;
  /// empty until picked) and unit.
  String niCat = '', niUnit = 'PCS';
  int niGst = 18;

  String vFilter = 'all', vPeriod = 'all';

  /// Extra Tally voucher types listed in the "More types" sheet.
  List<String> vTypeOptions = const <String>[];

  /// Opens every voucher type (main + this company's other Tally types).
  void openVoucherTypes(List<String> others) => _set(() {
    vTypeOptions = others;
    overlay = 'vTypes';
  });

  /// Picks a voucher type from the sheet (`all`, `sales`, … or
  /// `type:<Tally type>`).
  void pickVoucherType(String f) => _set(() {
    vFilter = f;
    overlay = null;
  });
  Voucher? entry;
  String outKind = 'recv', outFilter = 'all';

  /// Outstanding list: `list` or `graph`; graph series `age` | `party`.
  String outView = 'list', outChart = 'age';
  Bill? bill;

  /// Due-bill alerts (Outstanding → Payable "Payment alerts" and Settings →
  /// Alerts "Bills due soon" are the same switch): a device notification
  /// 3 days before each pending bill's due date.
  bool get autoRemind => prefs['due'] ?? true;
  String itemsFilter = 'all',
      partyFilter = 'all',
      partySort = 'amt',
      party = 'Shree Balaji Traders',
      partyTab = 'summary';
  String repCat = 'all', report = 'top';

  /// Item detail: selected item name and tab (summary | customers | suppliers).
  String itemSel = '', itemTab = 'summary';

  /// Settings → Look sub-tab: theme | colour | background | glass.
  String lookTab = 'theme';

  /// Wallpaper opacity (20–100 %) and shade (−100 lighter … +100 darker),
  /// independent of the glass / card level. Saved on this phone.
  double bgOpacity = 100, bgShade = 0;

  /// Outstanding reminders (this phone only — no backend endpoint).
  List<Reminder> reminders = <Reminder>[];

  /// Bill the reminder sheet is editing.
  Bill? remBill;

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
  };
  bool yearly = true;
  int faq = 0;
  late List<Notif> notifs = List<Notif>.of(repo.notifications());
  String nFilter = 'all';
  bool showPass = false, forgotSent = false;

  /// Forgot password step 2 is done (password changed).
  bool forgotDone = false;

  /// Login role sent as `loginType` (`ADMIN` | `USER`).
  String loginType = 'ADMIN';

  /// A login / save request is in flight (blocks double taps).
  bool busy = false;
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
    teamCfg?.dispose();
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
    _alarmSub?.cancel();
    for (final Timer t in _qTimers.values) {
      t.cancel();
    }
    if (repo.isRemote) repo.removeListener(_onRepo);
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
    bgOpacity =
        ((store.load<Object?>(LocalStorage.kBgOpacity, 100) as num?) ?? 100)
            .toDouble()
            .clamp(0, 100);
    bgShade = ((store.load<Object?>(LocalStorage.kBgShade, 0) as num?) ?? 0)
        .toDouble()
        .clamp(-100, 100);
    final Object? rm = store.load<Object?>(LocalStorage.kReminders, null);
    reminders = rm is List
        ? rm.map(Reminder.fromJson).whereType<Reminder>().toList()
        : <Reminder>[];
    prefs['due'] = store.load<Object?>(LocalStorage.kAutoRemind, true) != false;
    prefs['lowStock'] =
        store.load<Object?>(LocalStorage.kLowStockOn, true) != false;
    final Object? mi = store.load<Object?>(LocalStorage.kMemberInfo, null);
    if (mi is Map) {
      mi.forEach((Object? k, Object? v) {
        if (k is String && v is Map) {
          memberInfo[k] = <String, String>{
            for (final MapEntry<Object?, Object?> e in v.entries)
              if (e.key is String) e.key! as String: '${e.value ?? ''}',
          };
        }
      });
    }
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
  Company get companyObj {
    final List<Company> all = repo.companies();
    if (all.isEmpty) return const Company('', 'No company', '');
    return all.firstWhere(
      (Company c) => c.id == company,
      orElse: () => all.length > 1 && !repo.isRemote ? all[1] : all.first,
    );
  }

  String get companyName => companyObj.short;

  /// "Today" for dates shown on screens (fixed for sample data).
  DateTime get today => repo.today;

  /// Logged-in user is an admin (sample data always is).
  bool get isAdmin => !repo.isRemote || (repo.user?.isAdmin ?? false);
  int get unread => notifs.where((Notif n) => n.unread).length;
  bool get scrollLock =>
      drag != null || ldrag != null || _lpActive || tdrag != null;
  /// Screens only an admin may open (the team and its settings). A USER
  /// never sees them: no tab, no menu row, no search hit, no navigation.
  static const Set<String> kAdminScreens = <String>{
    'team',
    'teamUser',
    'teamLayout',
    'teamSelect',
  };

  /// Screen [s] is allowed for the logged-in user (from its server role).
  bool canOpen(String s) => isAdmin || !kAdminScreens.contains(s);

  /// Tab [i] is not shown in the bottom bar for this user.
  bool tabHidden(int i) => !canOpen(kTabs[i].k);

  /// The bottom bar's tabs in the user's order (hidden tabs left out).
  List<int> get barOrder => <int>[
    for (final int i in tabOrder)
      if (!tabHidden(i)) i,
  ];

  /// Number of tabs in the bottom bar.
  int get barCount => barOrder.length;

  /// Slot of tab [i] in the bottom bar.
  int posOf(int i) => barOrder.indexOf(i);

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

  /// Search text actually applied to lists (set 350 ms after typing stops).
  final Map<String, String> _applied = <String, String>{};
  final Map<String, Timer> _qTimers = <String, Timer>{};

  /// Applied (debounced) search text of a search field.
  String q(String k) => _applied[k] ?? form[k] ?? '';

  /// Search field typing: the text is kept at once (no rebuild per
  /// keystroke); lists filter 350 ms after the user stops typing.
  void setQuery(String k, String v) {
    form[k] = v;
    _qTimers[k]?.cancel();
    _qTimers[k] = Timer(const Duration(milliseconds: 350), () {
      _set(() => _applied[k] = v);
      if (k == 'q') _searchVouchers(v);
    });
  }

  /// Clears a search field immediately.
  void clearQuery(String k) {
    _qTimers[k]?.cancel();
    _set(() {
      form[k] = '';
      _applied[k] = '';
    });
  }

  // ------------------------------------------------------ cached derived
  final Map<String, (String, Object?)> _memo = <String, (String, Object?)>{};

  /// List-preference changes (pin / hide / order) — part of memo keys.
  int prefsVersion = 0;

  /// Returns the value cached under [slot] while [key] is unchanged, so a
  /// heavy filter / sort over thousands of rows runs once per data change
  /// instead of on every rebuild.
  T memo<T>(String slot, String key, T Function() build) {
    final (String, Object?)? e = _memo[slot];
    if (e != null && e.$1 == key) return e.$2 as T;
    final T v = build();
    _memo[slot] = (key, v);
    return v;
  }

  // ------------------------------------------------- server voucher search
  int _vSearchSeq = 0;
  String vSearchQuery = '';
  List<Voucher> vSearchHits = <Voucher>[];
  bool vSearchBusy = false;

  /// Global search for vouchers uses the server's `search`; results of an
  /// older query that arrive late are ignored.
  Future<void> _searchVouchers(String query) async {
    final String qq = query.trim();
    final int seq = ++_vSearchSeq;
    if (qq.isEmpty) {
      _set(() {
        vSearchQuery = '';
        vSearchHits = <Voucher>[];
        vSearchBusy = false;
      });
      return;
    }
    _set(() => vSearchBusy = true);
    try {
      final List<Voucher> r = await repo.searchVouchers(qq);
      if (seq != _vSearchSeq) return; // a newer search started
      _set(() {
        vSearchQuery = qq;
        vSearchHits = r;
        vSearchBusy = false;
      });
    } catch (_) {
      if (seq != _vSearchSeq) return;
      _set(() {
        vSearchQuery = qq;
        vSearchHits = <Voucher>[];
        vSearchBusy = false;
      });
    }
  }

  void jump(String s) {
    if (!canOpen(s)) s = 'home';
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
    if (tabHidden(i)) i = 0;
    _onEnter(kTabs[i].k);
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
    if (!canOpen(s)) return;
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
    _onEnter(s);
  }

  /// Loads only the data the screen being opened needs (big sets such as
  /// ledgers, items, stock and team are not loaded at startup).
  void _onEnter(String s) {
    if (!repo.isRemote) return;
    switch (s) {
      case 'party' || 'partyDetail' || 'flow':
        repo.ensure(DataSet.ledgers);
      case 'items':
        repo.ensure(DataSet.items);
      case 'team':
        repo.ensure(DataSet.team);
      case 'reports':
        repo.ensure(DataSet.items);
        repo.ensure(DataSet.stock);
        repo.ensure(DataSet.ledgers);
      case 'report':
        if (report == 'stock') repo.ensure(DataSet.items);
        if (report == 'inI') repo.ensure(DataSet.stock);
        if (report == 'inC') repo.ensure(DataSet.ledgers);
    }
    if (s == 'flow') repo.ensure(DataSet.items);
    if (s == 'teamSelect') {
      if (teamKind == 'ledger') repo.ensure(DataSet.ledgers);
      if (teamKind == 'inventory') repo.ensure(DataSet.items);
    }
    if (s == 'partyDetail') {
      final Party? p = partyPool()
          .where((Party x) => x.name == party)
          .firstOrNull;
      if (p != null) repo.loadPartyDetail(p);
    } else if (s == 'entryDetail') {
      final String? g = entry?.guid;
      if (g != null && g.isNotEmpty) repo.loadVoucherLines(g);
    } else if (s == 'itemDetail') {
      repo.ensure(DataSet.items);
      final Item? it = repo
          .items()
          .where((Item x) => x.name == itemSel)
          .firstOrNull;
      if (it != null) repo.loadItemDetail(it);
      // Sales / purchase summary needs the whole history: read it now, on
      // this explicit request, with progress on screen (never at startup).
      repo.scanHistory();
    }
  }

  /// Re-runs the current screen's data needs (after a company switch the
  /// on-demand sets were cleared).
  void reEnter() => _onEnter(screen);

  void run(NavTo a) => go(a.screen, a.extra.isEmpty ? null : a.extra);

  // ------------------------------------------------- period money totals
  static const List<(String, String)> kPeriods = <(String, String)>[
    ('all', 'All time'),
    ('month', 'This month'),
    ('week', 'Last 7 days'),
    ('today', 'Today'),
  ];

  String periodLabel(String period) => switch (period) {
    'month' => monthYear(today),
    'week' => 'Last 7 days',
    'today' => 'Today',
    _ => 'All time',
  };

  /// Total value of the vouchers of [filter] (`all`, a kind or `type:X`)
  /// in [period] — one source for every summary: This month from the
  /// complete month set (as before); other periods from that period's exact
  /// totals (All time: the server's sums). Null while loading.
  // ------------------------------------------------ refer / outside links
  /// The referral message (WhatsApp / share sheet).
  static const String kReferMessage =
      'Hi! I use TallyConnect to see my Tally data on my phone — sales, '
      'outstanding bills, stock and reports, synced from Tally automatically. '
      'Entries made in the app go straight into Tally too. If your business '
      'runs on Tally, have a look and get started:\n${TcSite.website}';

  /// Opens WhatsApp with the referral message (contact picked there).
  Future<void> referOnWhatsApp() async {
    if (!await shareOnWhatsApp(kReferMessage)) {
      say('Could not open WhatsApp or the share sheet');
    }
  }

  /// The system share sheet with the referral message.
  Future<void> referOtherApps() async {
    if (!await shareText(kReferMessage, subject: 'Try TallyConnect')) {
      say('Could not open the share sheet');
    }
  }

  /// Opens [uri] outside the app; [fail] is shown when nothing opens it.
  Future<void> openExternal(Uri uri, String fail) async {
    if (!await openLink(uri)) say(fail);
  }

  /// Home "Money summary": outstanding as today, and Receipts / Payments /
  /// Sales / Purchase over ALL TIME (the server's exact totals). A tap opens
  /// those vouchers for All time; a month or other period is picked there.
  Map<String, SumCard> homeMoneyCards() {
    final Map<String, SumCard> base = repo.moneyCards();
    const Map<String, String> kind = <String, String>{
      'mIn': 'receipt',
      'mOut': 'payment',
      'sales': 'sales',
      'purch': 'purchase',
    };
    return <String, SumCard>{
      for (final MapEntry<String, SumCard> e in base.entries)
        e.key: kind.containsKey(e.key)
            ? SumCard(
                e.value.k,
                e.value.t,
                'All time',
                periodAmount('all', kind[e.key]!),
                e.value.ic,
                e.value.c,
                e.value.cls,
                NavTo('vList', <String, Object?>{
                  'vFilter': kind[e.key],
                  'vPeriod': 'all',
                }),
              )
            : e.value,
    };
  }

  num? periodAmount(String period, String filter) {
    if (period == 'month') {
      final MonthTotals mt = repo.monthTotals();
      final bool ready =
          !repo.isRemote ||
          // Last good data stays visible while a refresh runs; an
          // incomplete month reports no amounts → `—`.
          (repo.hasData(DataSet.vouchers) &&
              (mt.amount.isNotEmpty || mt.count.isEmpty));
      if (!ready) return null;
      if (filter == 'all') {
        return paise(mt.amount.values.fold<num>(0, (num s, num v) => s + v));
      }
      return mt.amount[filter] ?? 0;
    }
    if (repo.isRemote) {
      Future<void>.microtask(() => repo.loadVoucherCounts(period));
    }
    return repo.voucherCounts(period)?.amountFor(filter);
  }

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
        case 'item':
          itemSel = v! as String;
        case 'itemTab':
          itemTab = v! as String;
        case 'teamKind':
          teamKind = v! as String;
          // Each selection screen starts with an empty search.
          form['tsQ'] = '';
          _applied['tsQ'] = '';
      }
    });
  }

  void openOverlay(String o) {
    if (repo.isRemote && (o == 'search' || o == 'picker')) {
      repo.ensure(DataSet.items);
      if (o == 'search') repo.ensure(DataSet.ledgers);
    }
    _set(() => overlay = o);
  }

  void closeOv() => _set(() => overlay = null);

  // ---------------------------------------------------------- nav actions
  void doLogin() {
    if (repo.isRemote) {
      _loginRemote();
      return;
    }
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

  Future<void> _loginRemote() async {
    final String email = (form['user'] ?? '').trim();
    final String pass = form['pass'] ?? '';
    if (busy) return;
    if (email.isEmpty || pass.isEmpty) {
      say('Enter your email and password');
      return;
    }
    _set(() => busy = true);
    try {
      final AuthUser u = await repo.login(email, pass, loginType);
      _set(() {
        busy = false;
        form['pass'] = '';
        loggedIn = true;
        tab = 0;
        pillPos = posOf(0).toDouble();
        pillSpan = 1;
        pillT = PillTr.none;
        screen = 'home';
        history = <String>[];
        dir = 'fwd';
      });
      say('Welcome back, ${u.username}');
      await repo.refreshAll();
      afterRefresh(quietOk: true);
      _openPendingTap();
    } on ApiException catch (e) {
      _set(() => busy = false);
      say(e.userMessage);
    } catch (_) {
      _set(() => busy = false);
      say('Could not log in. Try again.');
    }
  }

  void _endSession(String msg) {
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
    repo.logout();
    say(msg);
  }

  void logout() {
    if (repo.isRemote) {
      _endSession('You are logged out');
      return;
    }
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
    forgotDone = false;
    form['fEmail'] = (form['user'] ?? '').trim();
    for (final String k in <String>['fCode', 'fPass', 'fPass2']) {
      form[k] = '';
    }
    go('forgot');
  }

  static final RegExp _emailRx = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Forgot password step 1: the server emails a 6-digit code
  /// (`POST /api/auth/send-otp`). Also "Resend code".
  Future<void> sendReset() async {
    final String email = (form['fEmail'] ?? '').trim();
    if (busy) return;
    if (!_emailRx.hasMatch(email)) {
      say('Enter a valid email address');
      return;
    }
    _set(() => busy = true);
    try {
      await repo.sendResetCode(email);
      _set(() {
        busy = false;
        forgotSent = true;
        form['fCode'] = '';
      });
      say('Code sent to $email');
    } on ApiException catch (e) {
      _set(() => busy = false);
      say(
        e.status == 404
            ? 'No TallyConnect account uses this email'
            : e.userMessage,
      );
    } catch (_) {
      _set(() => busy = false);
      say('Could not send the code. Try again.');
    }
  }

  /// Why step 2 cannot be sent yet, or null.
  String? get resetError {
    if (!RegExp(r'^\d{6}$').hasMatch((form['fCode'] ?? '').trim())) {
      return 'Enter the 6-digit code from the email';
    }
    final String pw = form['fPass'] ?? '';
    if (pw.length < 8) return 'New password needs at least 8 characters';
    if (pw != (form['fPass2'] ?? '')) return 'The two passwords do not match';
    return null;
  }

  /// Forgot password step 2: code + new password
  /// (`POST /api/auth/verify-otp`), then back to Log in with the email.
  Future<void> confirmReset() async {
    final String? err = resetError;
    if (err != null) {
      say(err);
      return;
    }
    if (busy) return;
    final String email = (form['fEmail'] ?? '').trim();
    _set(() => busy = true);
    try {
      await repo.resetPassword(
        email,
        (form['fCode'] ?? '').trim(),
        form['fPass'] ?? '',
      );
      _set(() {
        busy = false;
        forgotDone = true;
        form['user'] = email;
        form['pass'] = '';
        form['fPass'] = '';
        form['fPass2'] = '';
        form['fCode'] = '';
      });
    } on ApiException catch (e) {
      _set(() => busy = false);
      final String m = e.message.toLowerCase();
      say(
        m.contains('invalid otp')
            ? 'That code is not right. Check the email and try again.'
            : (m.contains('expired')
                  ? 'The code has expired. Tap Resend code.'
                  : e.userMessage),
      );
    } catch (_) {
      _set(() => busy = false);
      say('Could not change the password. Try again.');
    }
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
    if (repo.isRemote) {
      _pickCompanyRemote(c);
      return;
    }
    _set(() {
      company = c.id;
      overlay = null;
    });
    say('Now showing ${c.short}');
  }

  /// The server keeps one active company per admin (shared with the team);
  /// only an admin may change it.
  Future<void> _pickCompanyRemote(Company c) async {
    if (c.id == company) {
      _set(() => overlay = null);
      return;
    }
    if (!isAdmin) {
      say('Only your admin can switch the company');
      return;
    }
    _set(() => overlay = null);
    say('Switching to ${c.short}…');
    try {
      await repo.setActiveCompany(c.id);
      say('Now showing ${c.short}');
    } on ApiException catch (e) {
      say(e.userMessage);
    }
  }

  // ------------------------------------------------------------------ flow
  void startFlow(String type, [Map<String, String>? patch]) {
    if (patch != null) _set(() => form.addAll(patch));
    go('flow', <String, Object?>{'flowType': type, 'flowStep': 0});
  }

  /// Bill totals. Sample data keeps the prototype's whole-rupee rounding;
  /// real entries keep paise (line amount and GST rounded to 2 decimals —
  /// the same arithmetic as the request body sent to the server).
  ({num sub, num gst, num total}) totals(List<Line> ls) {
    if (!repo.isRemote) {
      double sub = 0, gst = 0;
      for (final Line l in ls) {
        final double a = (l.rate * l.qty).toDouble();
        sub += a;
        gst += a * l.gst / 100;
      }
      final int s = sub.round(), g = gst.round();
      return (sub: s, gst: g, total: s + g);
    }
    num sub = 0, gst = 0;
    for (final Line l in ls) {
      final num a = paise(l.rate * l.qty);
      sub += a;
      gst += paise(a * l.gst / 100);
    }
    return (sub: paise(sub), gst: paise(gst), total: paise(sub + gst));
  }

  List<Party>? _pool;
  List<Party>? _poolSrc, _poolExtra;

  /// Tally parties plus parties added here. Built once per change of either
  /// list (16K+ ledgers are not copied on every call).
  List<Party> partyPool() {
    final List<Party> src = repo.parties();
    if (_pool == null ||
        !identical(src, _poolSrc) ||
        !identical(extraParties, _poolExtra)) {
      _poolSrc = src;
      _poolExtra = extraParties;
      _pool = List<Party>.unmodifiable(<Party>[...src, ...extraParties]);
    }
    return _pool!;
  }

  num get drSum => paise(
    jl
        .where((JLine j) => j.side == 'Dr')
        .fold<num>(0, (num s, JLine j) => s + j.amt),
  );
  num get crSum => paise(
    jl
        .where((JLine j) => j.side == 'Cr')
        .fold<num>(0, (num s, JLine j) => s + j.amt),
  );

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

  /// The entry being built, in repository terms.
  EntryDraft draftOf() {
    final String pf = kFlowTypes[flowType]!.p;
    String v(String k) => (form['$pf$k'] ?? '').trim();
    return EntryDraft(
      type: flowType,
      no: v('No'),
      date: v('Date'),
      party: v('Party'),
      due: v('Due'),
      note: v('Note'),
      amount: numOf(form['${pf}Amt']),
      ref: v('Ref'),
      mode: modes[flowType] ?? 'cash',
      bank: v('Bank'),
      utr: v('Utr'),
      account: v('Acc'),
      supplierInvoice: (form['pSupInv'] ?? '').trim(),
      lines: List<Line>.of(lines[flowType] ?? <Line>[]),
      journal: List<JLine>.of(jl),
    );
  }

  /// Why the current entry cannot be saved to the server, or null.
  String? get flowBlocker {
    if (!repo.isRemote) return null;
    final EntryDraft d = draftOf();
    final String? b = repo.entryBlocker(d);
    if (b != null) return b;
    if (d.date.isEmpty) return 'Pick the date';
    if (d.type != 'journal' && d.party.isEmpty) return 'Choose the party';
    switch (d.type) {
      case 'sales' || 'purchase':
        if (d.lines.isEmpty) return 'Add at least one item';
        if (d.lines.any((Line l) => l.rate <= 0 || l.qty <= 0)) {
          return 'Every item needs a rate and quantity';
        }
        if (d.amount < 0) return 'Amount cannot be negative';
        if (d.amount > totals(d.lines).total) {
          return d.type == 'purchase'
              ? 'Money paid is more than the bill total'
              : 'Money received is more than the bill total';
        }
      case 'receipt' || 'payment':
        if (d.amount <= 0) return 'Enter an amount above zero';
        if (d.account.isEmpty) return 'Choose the cash / bank account';
      case 'journal':
        if (d.journal.length < 2) return 'Add at least two accounts';
        if (d.journal.any((JLine j) => j.amt <= 0)) {
          return 'Every account needs an amount above zero';
        }
        if (drSum != crSum) return 'Both sides must be equal';
    }
    return null;
  }

  void saveFlow(bool draft) {
    if (repo.isRemote && !draft) {
      _saveRemote();
      return;
    }
    final FlowType cfg = kFlowTypes[flowType]!;
    final String pf = cfg.p;
    num amt;
    if (cfg.items) {
      amt = totals(lines[flowType] ?? <Line>[]).total;
    } else if (flowType == 'journal') {
      amt = drSum;
    } else {
      amt = numOf(form['${pf}Amt']);
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

  /// Sends the entry to the server queue; returns Home only on success.
  Future<void> _saveRemote() async {
    if (busy) return;
    final String? why = flowBlocker;
    if (why != null) {
      say(why);
      return;
    }
    final EntryDraft d = draftOf();
    _set(() => busy = true);
    final SubmitResult r = await repo.submitEntry(d);
    _set(() => busy = false);
    if (!r.ok) {
      say(r.message.isEmpty ? 'Could not save. Try again.' : r.message);
      return;
    }
    final String pf = kFlowTypes[d.type]!.p;
    _set(() {
      form = <String, String>{
        ...form,
        for (final String k in <String>[
          'No',
          'Party',
          'Due',
          'Note',
          'Amt',
          'Ref',
          'Bank',
          'Utr',
          'PayNote',
        ])
          '$pf$k': '',
      };
      if (d.type == 'sales' || d.type == 'purchase') lines[d.type] = <Line>[];
      if (d.type == 'journal') jl = <JLine>[];
    });
    selectTab(0);
    say(r.message.isEmpty ? 'Saved! It will reach Tally by itself' : r.message);
  }

  void retry(String id) {
    if (repo.isRemote) {
      say(
        'Sending again is not available yet — the server has no retry option',
      );
      return;
    }
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
    if (repo.isRemote) {
      say('Checking for updates…');
      repo.refreshActivity().then((_) => say(_statusToast(DataSet.activity)));
      return;
    }
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
    if (repo.isRemote) {
      say(
        'Adding a party is not available yet — the server cannot create parties',
      );
      return;
    }
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
      final String key = '${kFlowTypes[flowType]!.p}Acc';
      if (repo.isRemote) {
        // Default to the first matching cash / bank ledger from Tally.
        final bool cash = m == 'cash';
        form[key] =
            repo
                .accounts()
                .where(
                  (Opt o) => o.s.toLowerCase().contains(cash ? 'cash' : 'bank'),
                )
                .firstOrNull
                ?.t ??
            '';
        return;
      }
      form[key] = m == 'cash'
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
        : <Line>[
            ...l,
            // The item's Tally data: its rate (closing rate, else the
            // opening rate when nothing is in stock), unit, GST; qty 1.
            Line(
              it.name,
              it.rate > 0
                  ? it.rate
                  : ((it.openingRate ?? 0) > 0 ? it.openingRate! : 0),
              1,
              it.unit,
              it.gst ?? (repo.isRemote ? 0 : 18),
              guid: it.guid,
              hsn: it.hsn,
              group: it.group,
            ),
          ];
  });

  // ------------------------------------------- one voucher line's rate / GST
  /// Line being edited in the line sheet.
  int? lineEdit;

  /// What the line sheet edits: `rate` (double-tap on the line amount) or
  /// `gst` (tap on the line's GST).
  String lineEditField = 'rate';

  /// Opens the rate ([field] `rate`) or GST ([field] `gst`) editor of line
  /// [i] of the current entry.
  void openLineEdit(int i, {String field = 'rate'}) {
    final List<Line> l = lines[flowType] ?? <Line>[];
    if (i < 0 || i >= l.length) return;
    _set(() {
      lineEdit = i;
      lineEditField = field == 'gst' ? 'gst' : 'rate';
      form['leRate'] = l[i].rate == 0 ? '' : qty(paise(l[i].rate));
      form['leGst'] = qty(l[i].gst);
      overlay = 'lineEdit';
    });
  }

  /// Why the line sheet's value cannot be used, or null.
  String? get lineEditError {
    if (lineEditField == 'gst') {
      final num? g = num.tryParse((form['leGst'] ?? '').trim());
      if (g == null || g < 0 || g > 100) return 'GST must be 0 to 100%';
      return null;
    }
    final num? r = num.tryParse((form['leRate'] ?? '').trim());
    if (r == null || r <= 0) return 'Enter a rate above zero';
    return null;
  }

  /// Applies the sheet's rate or GST to that line of THIS voucher only —
  /// the item master (and Tally's item) is not changed.
  void saveLineEdit() {
    final int? i = lineEdit;
    final List<Line> l = lines[flowType] ?? <Line>[];
    if (i == null || i >= l.length || lineEditError != null) return;
    final bool gst = lineEditField == 'gst';
    final Line edited = gst
        ? l[i].withGst(num.parse(form['leGst']!.trim()))
        : l[i].withRate(paise(num.parse(form['leRate']!.trim())));
    _set(() {
      lines[flowType] = <Line>[
        for (int j = 0; j < l.length; j++) j == i ? edited : l[j],
      ];
      lineEdit = null;
      overlay = null;
    });
    say(gst ? 'GST updated for this bill' : 'Rate updated for this bill');
  }

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
    // Tally needs the stock group to create the item (the sync agent
    // otherwise silently picks one), so it must be one of the real groups.
    final String group = niCat.trim();
    if (repo.isRemote && !repo.stockGroups().contains(group)) {
      say('Choose the stock group from Tally');
      return;
    }
    _set(() {
      lines[flowType] = <Line>[
        ...(lines[flowType] ?? <Line>[]),
        Line(
          nm,
          (nr * (1 - nd / 100) * 100).round() / 100,
          nq.toInt(),
          niUnit.toLowerCase(),
          niGst,
          hsn: (form['niHsn'] ?? '').trim().isEmpty
              ? null
              : form['niHsn']!.trim(),
          group: group.isEmpty ? null : group,
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
        final Voucher? v = repo.voucherByKey(key);
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
            .where((Bill x) => x.key == key)
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
        return CardInfo(key, 'box', 'items', () => openItem(key));
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
    if (repo.isRemote) {
      if (n.unread) repo.markNotifRead(n.id);
      if (n.go.screen == kNotifTarget) {
        unawaited(openNotifTarget(n.go.extra));
      } else {
        run(n.go);
      }
      return;
    }
    _set(
      () => notifs = notifs
          .map((Notif x) => x.id == n.id ? x.read() : x)
          .toList(),
    );
    run(n.go);
  }

  /// Opens exactly what a server alert is about, from its type, `meta` and
  /// message:
  /// - Entry created → that queued entry (matched by its server reference
  ///   number) in Activity;
  /// - Entry failed → the failed entry with that error;
  /// - Vouchers synced → that voucher's detail (GUID from `meta`);
  /// - New party / ledger / item → that party / item;
  /// - Bill created → that bill;
  /// - others → their screen. When the target is not found, the alert's
  ///   own screen opens with a short note (never a wrong record).
  Future<void> openNotifTarget(Map<String, Object?> x) async {
    final String type = '${x['type'] ?? ''}';
    final String msg = '${x['message'] ?? ''}';
    final Map<String, Object?> meta =
        (x['meta'] as Map<String, Object?>?) ?? const <String, Object?>{};
    final NavTo fallback = x['fallback'] is NavTo
        ? x['fallback']! as NavTo
        : const NavTo('notifs');
    String s(String k) => '${meta[k] ?? ''}'.trim();
    // Text after the first ": " (party / item / error in the message).
    String tail() {
      final int i = msg.indexOf(': ');
      return i < 0 ? '' : msg.substring(i + 2).trim();
    }

    // Queued entries (Activity): loaded on demand.
    Future<Act?> findAct(bool Function(Act a) hit) async {
      Act? a = acts.where(hit).firstOrNull;
      if (a == null && repo.isRemote) {
        await repo.refreshActivity();
        if (_disposed) return null;
        acts = repo.activity();
        a = acts.where(hit).firstOrNull;
      }
      return a;
    }

    String ref(Act a) =>
        a.rows
            .where(((String, String) r) => r.$1 == 'Reference no.')
            .firstOrNull
            ?.$2 ??
        '';

    switch (type) {
      case 'create_entry':
        final String rn = s('reference_no');
        final Act? a = await findAct(
          (Act a) =>
              (rn.isNotEmpty && ref(a) == rn) ||
              (rn.isEmpty &&
                  a.party == s('party_name') &&
                  paise(a.amt) == paise(numOf(s('amount')))),
        );
        if (a != null) {
          go('actDetail', <String, Object?>{'act': a.id});
          return;
        }
        go('activity');
        say('This entry is no longer in the queue');
        return;
      case 'entry_failed':
        final int i = msg.indexOf('sync failed: ');
        final String err = i < 0 ? '' : msg.substring(i + 13).trim();
        final Act? a = await findAct(
          (Act a) => a.status == 'fail' && err.isNotEmpty && a.note.trim() == err,
        );
        if (a != null) {
          go('actDetail', <String, Object?>{'act': a.id});
          return;
        }
        go('activity');
        if (err.isNotEmpty) say(err);
        return;
      case 'voucher_sync':
        final String g = s('voucher_guid');
        if (g.isNotEmpty) {
          final DateTime? d = DateTime.tryParse(s('voucher_date'));
          final String vt = s('voucher_type');
          go('entryDetail', <String, Object?>{
            'entry': Voucher(
              voucherKind(vt),
              s('party_name').isEmpty ? '—' : s('party_name'),
              s('reference_no'),
              d?.day ?? 0,
              numOf(s('amount')).abs(),
              guid: g,
              date: d == null ? null : DateTime(d.year, d.month, d.day),
              type: vt.isEmpty ? null : vt,
            ),
          });
          return;
        }
      case 'party_sync' || 'ledger_sync':
        final String name = tail();
        if (name.isNotEmpty) {
          await openParty(name);
          return;
        }
      case 'item_sync':
        final String name = tail();
        if (name.isNotEmpty) {
          openItem(name);
          return;
        }
      case 'web:BILL':
        // "🧾 Bill <no> created for <ledger> (₹<amount>)"
        final RegExpMatch? m = RegExp(
          r'Bill (.+) created for (.+) \(₹',
        ).firstMatch(msg);
        if (m != null) {
          final String no = m.group(1)!.trim(), led = m.group(2)!.trim();
          for (final (List<Bill>, String) side in <(List<Bill>, String)>[
            (repo.receivables(), 'recv'),
            (repo.payables(), 'pay'),
          ]) {
            final Bill? b = side.$1
                .where((Bill b) => b.no == no && b.party == led)
                .firstOrNull;
            if (b != null) {
              go('billDetail', <String, Object?>{'bill': b.withKind(side.$2)});
              return;
            }
          }
          go('outHub');
          say('Bill $no is settled or not synced yet');
          return;
        }
    }
    run(fallback);
  }

  /// Opens a party by name: its detail when it is a ledger of this
  /// company, else its pending bills (Outstanding filtered to the name) —
  /// never another party's page.
  Future<void> openParty(String name) async {
    bool known() => partyPool().any((Party x) => x.name == name);
    if (!known() && repo.isRemote) {
      await repo.ensure(DataSet.ledgers);
      if (_disposed) return;
    }
    if (known()) {
      go('partyDetail', <String, Object?>{
        'party': name,
        'partyTab': 'summary',
      });
      return;
    }
    final bool recv = repo.receivables().any((Bill b) => b.party == name);
    final bool pay = repo.payables().any((Bill b) => b.party == name);
    if (recv || pay) {
      go('outList', <String, Object?>{
        'outKind': recv ? 'recv' : 'pay',
        'outFilter': 'all',
      });
      _set(() {
        outSearch = true;
        outQuery = name;
      });
      return;
    }
    say('$name is not in this company\'s ledgers');
  }

  /// A report row's party / item / voucher.
  void openRowTarget(RowTarget t) {
    switch (t.kind) {
      case 'party':
        unawaited(openParty(t.name));
      case 'item':
        openItem(t.name);
      case 'voucher':
        go('entryDetail', <String, Object?>{'entry': t.voucher});
    }
  }

  // ------------------------------------------------- outstanding search
  /// Search box on Outstanding / Receivable / Payable is open.
  bool outSearch = false;

  /// Words to find in party, bill number, place, dates, status and amount.
  String outQuery = '';

  void toggleOutSearch() => _set(() {
    outSearch = !outSearch;
    if (!outSearch) outQuery = '';
  });

  void setOutQuery(String q) => _set(() => outQuery = q);

  /// [bills] matching every word of [outQuery] (any order, any case) —
  /// over the bills already on the phone, no extra download.
  List<Bill> searchBills(List<Bill> bills) {
    final List<String> words = outQuery
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return bills;
    return bills.where((Bill b) {
      final String hay =
          '${b.party} ${b.no} ${b.city} ${b.bill} ${b.due} ${b.txt} '
                  '${inr(b.amt)} ${qty(b.amt)}'
              .toLowerCase();
      return words.every(hay.contains);
    }).toList();
  }

  void openMember(Member m) => _set(() {
    overlay = 'member';
    member = m.id;
    form['memDel'] = '';
  });

  // ------------------------------------------- Sales Team: configure user
  /// The member being configured (permissions loaded when it opens).
  TeamConfig? teamCfg;

  /// Permission area of the Layout / Selection screen.
  String teamKind = 'ledger';

  /// The admin account itself is not configured / deleted from this list.
  bool _isAdminRow(Member m) => m.role == 'Admin';

  void configureMember(Member m) {
    final TeamAdmin? admin = repo.teamAdmin;
    if (admin == null) {
      say('Configure User saves to your server; sample data has none');
      return;
    }
    if (_isAdminRow(m)) {
      say('The admin account always sees everything');
      return;
    }
    teamCfg?.dispose();
    teamCfg = TeamConfig(admin, m)..load();
    overlay = null;
    go('teamUser');
  }

  Future<void> inviteMember(Member m) async {
    final TeamAdmin? admin = repo.teamAdmin;
    if (admin == null) {
      closeOv();
      say('Invite sent again');
      return;
    }
    if (m.email.isEmpty || !m.email.contains('@')) {
      say('${m.name} has no email address');
      return;
    }
    closeOv();
    say('Sending invite…');
    try {
      await admin.sendInvite(m);
      say('Invite sent to ${m.email}');
    } catch (e) {
      say(e is ApiException ? e.userMessage : 'Could not send the invite');
    }
  }

  /// First tap asks to confirm (in the member sheet); the second deletes.
  Future<void> deleteMember(Member m) async {
    if (_isAdminRow(m)) {
      say('The admin account cannot be deleted here');
      return;
    }
    if (form['memDel'] != m.id) {
      _set(() => form['memDel'] = m.id);
      return;
    }
    final TeamAdmin? admin = repo.teamAdmin;
    if (admin == null) {
      _set(() {
        overlay = null;
        team = team.where((Member x) => x.id != m.id).toList();
      });
      say('${m.name} deleted');
      return;
    }
    closeOv();
    say('Deleting ${m.name}…');
    try {
      await admin.deleteUser(m);
      say('${m.name} deleted');
    } catch (e) {
      say(e is ApiException ? e.userMessage : 'Could not delete the user');
    }
  }

  void cancelDelete() => _set(() => form['memDel'] = '');

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
    // A voucher shares its one complete document (same as its PDF).
    final Voucher? v = c.list == 'vouchers' ? repo.voucherByKey(c.id) : null;
    final ShareDoc? d = v == null ? docForCard(c.list, c.id) : null;
    _set(() => cmenu = null);
    if (v != null) {
      shareVoucher(v);
    } else if (d != null) {
      shareDoc(d);
    }
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
    prefsVersion++;
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
        final int n = barCount;
        final double maxL = _slot * n + 12 - _slot;
        final double left = (barX(ev.position.dx) - _slot / 2).clamp(0, maxL);
        final int pos = ((left - 6) / _slot).round().clamp(0, n - 1);
        final List<int> order = barOrder;
        final int cur = order.indexOf(i);
        _set(() {
          tdrag = (i: i, x: left);
          if (pos != cur) {
            order.removeAt(cur);
            order.insert(pos, i);
            // Hidden tabs keep their place after the visible ones.
            tabOrder = <int>[
              ...order,
              for (final int t in tabOrder)
                if (!order.contains(t)) t,
            ];
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
      final double left = (barX(p0.dx) - _slot / 2).clamp(
        0,
        _slot * (barCount - 1) + 12,
      );
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

  int barPos(double localX) =>
      ((localX - 6) / _slot).floor().clamp(0, barCount - 1);

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
      final int ti = barOrder[q];
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
    final int ti = barOrder[q];
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
    if (repo.isRemote) {
      // SECURITY_BLOCKER: /send-invite emails the user's password in plain
      // text and has no invitation state.
      say('Invites are turned off until the server sends a safe join link');
      return;
    }
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

  /// Add person: name / company-role / mobile entered for a login, by
  /// lower-case email. Kept on this phone (POST /users stores only email
  /// and password) and shown in the team list.
  final Map<String, Map<String, String>> memberInfo =
      <String, Map<String, String>>{};

  /// Add person: temporary password shown in clear text.
  bool showNuPass = false;

  /// Shortest temporary password accepted.
  static const int kMinTempPass = 6;

  List<Member> _labelTeam(List<Member> ms) => <Member>[
    for (final Member m in ms)
      m.labeled(
        memberInfo[m.email.toLowerCase()]?['name'],
        memberInfo[m.email.toLowerCase()]?['role'],
      ),
  ];

  /// Why the Add person form cannot be sent yet, or null.
  String? get newUserError {
    if ((form['nuName'] ?? '').trim().isEmpty) return 'Enter the full name';
    final String em = (form['nuEmail'] ?? '').trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(em)) {
      return 'Enter a valid email address';
    }
    final String pw = form['nuPass'] ?? '';
    if (pw.length < kMinTempPass) {
      return 'Temporary password needs at least $kMinTempPass characters';
    }
    if (pw.trim() != pw) return 'Password cannot start or end with a space';
    return null;
  }

  /// Opens Add person with a clean form.
  void openNewUser() {
    _set(() {
      for (final String k in <String>[
        'nuName',
        'nuEmail',
        'nuRole',
        'nuPhone',
        'nuPass',
      ]) {
        form[k] = '';
      }
      showNuPass = false;
      overlay = 'newUser';
    });
  }

  /// Fills a random 10-character temporary password (shown, to share).
  void suggestTempPass() {
    const String abc = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final math.Random r = math.Random.secure();
    _set(() {
      form['nuPass'] = <String>[
        for (int i = 0; i < 10; i++) abc[r.nextInt(abc.length)],
      ].join();
      showNuPass = true;
    });
  }

  /// Creates the login (POST /users with email + temporary password).
  Future<void> saveUser() async {
    final String? err = newUserError;
    if (err != null) {
      say(err);
      return;
    }
    if (busy) return;
    final String nm = (form['nuName'] ?? '').trim();
    final String em = (form['nuEmail'] ?? '').trim().toLowerCase();
    final String role = (form['nuRole'] ?? '').trim();
    final String ph = (form['nuPhone'] ?? '').trim();
    final String pw = form['nuPass'] ?? '';
    void remember() {
      memberInfo[em] = <String, String>{
        'name': nm,
        if (role.isNotEmpty) 'role': role,
        if (ph.isNotEmpty) 'phone': ph,
      };
      store.save(LocalStorage.kMemberInfo, memberInfo);
    }

    final TeamAdmin? admin = repo.teamAdmin;
    if (!repo.isRemote || admin == null) {
      remember();
      _set(() {
        overlay = null;
        team = <Member>[
          ...team,
          Member(
            't${DateTime.now().millisecondsSinceEpoch}',
            nm,
            em,
            role.isEmpty ? 'Sales Rep' : role,
            'active',
          ),
        ];
      });
      say('$nm added to your team');
      return;
    }
    _set(() => busy = true);
    try {
      remember(); // before the reload, so the new row shows the name
      await admin.createUser(em, pw);
      if (_disposed) return;
      _set(() {
        busy = false;
        overlay = null;
        form['nuPass'] = '';
        team = _labelTeam(repo.team());
      });
      say('$nm added · logs in with $em');
    } catch (e) {
      // Not created: forget the details (unless that login already exists).
      final String msg = e is ApiException ? e.userMessage : 'Could not add';
      if (!msg.toLowerCase().contains('already exists')) {
        memberInfo.remove(em);
        store.save(LocalStorage.kMemberInfo, memberInfo);
      }
      if (_disposed) return;
      _set(() => busy = false);
      say(msg);
    }
  }

  void setMemberSt(Member m, String st, String msg) {
    if (repo.isRemote) {
      say('Turning access on or off is not available yet on the server');
      return;
    }
    _set(() {
      overlay = null;
      team = team.map((Member x) => x.id == m.id ? x.withSt(st) : x).toList();
    });
    say(msg);
  }

  void cancelInvite(Member m) {
    if (repo.isRemote) {
      say('Invites are not available yet on the server');
      return;
    }
    _set(() {
      overlay = null;
      team = team.where((Member x) => x.id != m.id).toList();
    });
    say('Invite cancelled');
  }

  void markAll() {
    if (repo.isRemote) {
      repo.markAllNotifsRead();
      say('All marked as read');
      return;
    }
    _set(() => notifs = notifs.map((Notif n) => n.read()).toList());
    say('All marked as read');
  }

  // ------------------------------------------- notification preferences
  /// Unsaved switch changes in Settings → Notifications (null: none).
  Map<String, bool>? alertDraft;
  bool alertSaving = false;

  /// Switches this user can set (team switches: admins only).
  List<NotifPref> get notifPrefs => <NotifPref>[
    for (final NotifPref x in kNotifPrefs)
      if (!x.adminOnly || isAdmin) x,
  ];

  /// Low-stock (out of stock) alerts on this phone.
  bool get lowStockAlerts => prefs['lowStock'] ?? true;

  /// The saved value of switch [k].
  bool savedAlert(String k) {
    if (k == 'phone.due') return autoRemind;
    if (k == 'phone.lowStock') return lowStockAlerts;
    if (repo.isRemote) {
      // The server fills every mobile type with its default; a web key the
      // user never saved is off (the web list shows it only when true).
      return repo.alertConfig()?[k] ?? false;
    }
    return prefs[k] ?? true; // sample data: kept on this phone
  }

  /// The switch as shown: unsaved change, else the saved value.
  bool alertOn(String k) => alertDraft?[k] ?? savedAlert(k);

  void toggleAlert(String k) => _set(() {
    final bool on = !alertOn(k);
    final Map<String, bool> d = alertDraft ?? <String, bool>{};
    if (on == savedAlert(k)) {
      d.remove(k);
    } else {
      d[k] = on;
    }
    alertDraft = d.isEmpty ? null : d;
  });

  /// Unsaved changes exist.
  bool get alertDirty => alertDraft != null && alertDraft!.isNotEmpty;

  /// Settings loaded (server switches known) — always for sample data.
  bool get alertsReady => !repo.isRemote || repo.alertConfig() != null;

  /// Saves the changed switches: server ones to this user's account (the
  /// server then shows / creates only the enabled alert types), phone ones
  /// on this phone.
  Future<void> saveAlertPrefs() async {
    final Map<String, bool>? d = alertDraft;
    if (d == null || d.isEmpty || alertSaving) return;
    _set(() => alertSaving = true);
    try {
      final Map<String, bool> server = <String, bool>{
        for (final MapEntry<String, bool> e in d.entries)
          if (!e.key.startsWith('phone.')) e.key: e.value,
      };
      if (server.isNotEmpty) {
        if (repo.isRemote) {
          await repo.saveAlerts(server);
        } else {
          prefs.addAll(server);
        }
      }
      final bool? due = d['phone.due'];
      if (due != null) setAutoRemind(due, quiet: true);
      final bool? low = d['phone.lowStock'];
      if (low != null) {
        prefs['lowStock'] = low;
        store.save(LocalStorage.kLowStockOn, low);
        if (low) unawaited(alarms.requestAccess());
      }
      if (_disposed) return;
      _set(() {
        alertSaving = false;
        alertDraft = null;
      });
      say('Notification preferences saved');
    } catch (e) {
      if (_disposed) return;
      _set(() => alertSaving = false);
      say(e is ApiException ? e.userMessage : 'Could not save preferences');
    }
  }

  // ------------------------------------------------- out-of-stock alerts
  String _stockSig = '';

  /// When the items list changes, raises a device notification for items
  /// that newly reached zero stock in Tally (compared with the items seen
  /// out of stock last time for this company). The first look only
  /// records the current state.
  void _checkStock() {
    final List<Item> its = repo.items();
    final String co = repo.activeCompanyId ?? '';
    if (its.isEmpty || co.isEmpty) return;
    final String sig = '${identityHashCode(its)}|${its.length}|$co';
    if (sig == _stockSig) return;
    _stockSig = sig;
    final Set<String> out = <String>{
      for (final Item x in its)
        if (x.st == 'out') x.name,
    };
    final Object? saved = store.load<Object?>(LocalStorage.kOutStock, null);
    final Map<String, Object?> all = saved is Map
        ? saved.cast<String, Object?>()
        : <String, Object?>{};
    final Object? before = all[co];
    all[co] = out.toList();
    store.save(LocalStorage.kOutStock, all);
    if (before is! List || !lowStockAlerts || !loggedIn) return;
    final Set<String> was = before.whereType<String>().toSet();
    final List<String> fresh = out.difference(was).toList()..sort();
    if (fresh.isEmpty) return;
    unawaited(
      alarms.schedule(
        AlarmSpec(
          id: alarmId('stock:$co'),
          at: DateTime.now().add(const Duration(seconds: 2)),
          title: fresh.length == 1
              ? 'Out of stock: ${fresh.first}'
              : '${fresh.length} items ran out of stock',
          body: fresh.length == 1
              ? 'Its stock in Tally has reached zero.'
              : '${fresh.take(3).join(', ')}${fresh.length > 3 ? ' and ${fresh.length - 3} more' : ''}',
          payload: 'stock:${fresh.length == 1 ? fresh.first : ''}',
          actions: false,
        ),
      ),
    );
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
    setBgOpacity(100);
    setBgShade(0);
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
  /// A bill's PDF: the real generated document (the same bytes Share and
  /// Download use), shown in the PDF viewer.
  void openPdf(PdfInfo info) => previewDoc(docInvoice(info, companyName));

  /// One voucher's complete document — its item lines (when it has items)
  /// and its Dr / Cr ledger lines (loaded first when not on the phone yet).
  /// Voucher Detail's See bill PDF, Share and Download all use this.
  Future<ShareDoc> voucherDoc(Voucher e) async {
    final String? g = e.guid;
    if (repo.isRemote && g != null && g.isNotEmpty) {
      try {
        await repo.loadVoucherLines(g);
      } catch (_) {
        // Shown without accounts; the detail screen shows the load error.
      }
    }
    return docVoucher(
      e,
      companyName,
      lines: g == null ? null : repo.voucherLines(g),
      city:
          partyPool().where((Party x) => x.name == e.party).firstOrNull?.city ??
          '',
    );
  }

  Future<void> openVoucherPdf(Voucher e) async {
    final ShareDoc d = await voucherDoc(e);
    if (!_disposed) previewDoc(d);
  }

  Future<void> shareVoucher(Voucher e) async => shareDoc(await voucherDoc(e));

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
    overlay = 'doc';
  });

  Future<Uint8List>? get docBytes => _docBytes;

  /// Document for a long-pressed card (`list|key`).
  ShareDoc? docForCard(String list, String key) {
    final String co = companyName;
    switch (list) {
      case 'home':
        switch (key) {
          case 'money':
            return docSums(
              <SumCard>[
                for (final String k in curWs.sums)
                  if (repo.moneyCards()[k] != null) repo.moneyCards()[k]!,
              ],
              co,
              repo.isRemote
                  ? 'As on ${dmy(today)}'
                  : 'September 2026 · Sample data',
            );
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
            return docBills(true, repo.receivables(), co, today);
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
        final Voucher? v = repo.voucherByKey(key);
        return v == null
            ? null
            : docVoucher(
                v,
                co,
                lines: v.guid == null ? null : repo.voucherLines(v.guid!),
              );
      case 'bills':
        final Bill? b =
            (outKind == 'recv' ? repo.receivables() : repo.payables())
                .where((Bill x) => x.key == key)
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
        return pa == null ? null : docPartyRow(pa, co, repo.isRemote);
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
    title: 'Reports · ${monthYear(today)}',
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

  // ------------------------------------------------------------ misc
  /// Refresh button: forced reload; the data on screen stays until the
  /// fresh data replaces it.
  void refreshNow() {
    if (!repo.isRemote) {
      say('Up to date · synced just now');
      return;
    }
    say('Refreshing…');
    pullRefresh();
  }

  /// Pull-to-refresh / Refresh: one shared forced reload (a reload already
  /// running is joined, not repeated).
  Future<void> pullRefresh() async {
    if (!repo.isRemote) return;
    await repo.refreshAll(force: true);
    afterRefresh();
  }

  /// Toast after a reload: the error (old data is kept on screen), or
  /// "Up to date"; then any reminder due today.
  void afterRefresh({bool quietOk = false}) {
    if (_disposed || !loggedIn) return;
    final String? err = repo.lastError();
    if (err != null) {
      say('$err · showing the last saved data');
    } else if (!quietOk) {
      say('Up to date');
    } else {
      final int due = dueReminders.length;
      if (due > 0) {
        say('$due ${due == 1 ? 'reminder is' : 'reminders are'} due');
      }
    }
  }

  /// Empty-list text: loading / error message from the server, else [normal].
  String emptyText(String set, String normal) {
    if (!repo.isRemote) return normal;
    final DataStatus st = repo.status(set);
    if (st.loading && !repo.hasData(set)) return 'Loading from the server…';
    if (st.failed) return st.message ?? 'Could not load. Tap refresh.';
    return normal;
  }

  /// Sync line for a company: `Synced 5 min ago` / `Syncing now`.
  String syncText(String companyId) {
    final SyncInfo? s = repo.syncInfo(companyId);
    if (s == null) return 'Sync status not known';
    if (s.inProgress) return 'Syncing now';
    if (s.lastSyncAt == null) return 'Not synced yet';
    return 'Synced ${ago(s.lastSyncAt!, DateTime.now())}';
  }

  String _statusToast(String set) {
    final DataStatus st = repo.status(set);
    return st.failed ? (st.message ?? 'Could not refresh') : 'Up to date';
  }

  // ---------------------------------------------------------- item detail
  void openItem(String name) =>
      go('itemDetail', <String, Object?>{'item': name, 'itemTab': 'summary'});

  // ---------------------------------------------------------- global search
  /// Searches every loaded entity: items, parties, vouchers, outstanding
  /// bills, activity, team, reports and app screens. Every word typed must
  /// appear (any order, any case).
  List<SearchHit> searchHits(String query) {
    final List<String> words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const <SearchHit>[];
    bool hit(String hay) {
      final String h = hay.toLowerCase();
      return words.every(h.contains);
    }

    const int cap = 25;
    final List<SearchHit> out = <SearchHit>[];
    void add(List<SearchHit> group) => out.addAll(group.take(cap));

    add(<SearchHit>[
      for (final Item x
          in repo
              .items()
              .where(
                (Item x) => hit(
                  x.search.isNotEmpty
                      ? x.search
                      : '${x.name} ${x.group ?? ''} ${x.hsn ?? ''}',
                ),
              )
              .take(cap))
        SearchHit(
          x.name,
          'Item · ${x.stock > 0 ? '${qty(x.stock)} ${x.unit} in stock' : 'Finished'}',
          'box',
          'items',
          () => openItem(x.name),
        ),
    ]);
    add(<SearchHit>[
      for (final Party x
          in partyPool()
              .where(
                (Party x) => hit(
                  '${x.search.isNotEmpty ? x.search : '${x.name} ${x.group ?? ''} ${x.city}'} ${x.kindLabel}',
                ),
              )
              .take(cap))
        SearchHit(
          x.name,
          '${x.kindLabel}${(x.group ?? x.city).isEmpty ? '' : ' · ${x.group ?? x.city}'}',
          'person',
          'party',
          () => go('partyDetail', <String, Object?>{
            'party': x.name,
            'partyTab': 'summary',
          }),
        ),
    ]);
    // Vouchers: the server's search over the whole history (sample data
    // searches locally) — never a scan of every voucher on the phone.
    add(<SearchHit>[
      for (final Voucher v
          in (repo.isRemote
              ? (vSearchQuery == query.trim() ? vSearchHits : const <Voucher>[])
              : repo.vouchers().where(
                  (Voucher v) => hit(
                    '${v.party} ${v.no} ${v.type ?? kKinds[v.kind]!.t} ${v.date == null ? '' : dmy(v.date)}',
                  ),
                )))
        SearchHit(
          v.party,
          '${v.type ?? kKinds[v.kind]!.t} · ${v.no} · ${inr(v.amt)}',
          kKinds[v.kind]!.ic,
          kKinds[v.kind]!.c,
          () => go('entryDetail', <String, Object?>{'entry': v}),
        ),
    ]);
    add(<SearchHit>[
      for (final (Bill, String) b in <(Bill, String)>[
        for (final Bill x in repo.receivables()) (x, 'recv'),
        for (final Bill x in repo.payables()) (x, 'pay'),
      ])
        if (hit('${b.$1.party} ${b.$1.no} outstanding'))
          SearchHit(
            '${b.$1.party} · ${b.$1.no}',
            '${b.$2 == 'recv' ? 'Receivable' : 'Payable'} · ${inr(b.$1.amt)} · ${b.$1.txt}',
            b.$2 == 'recv' ? 'in' : 'out',
            b.$2 == 'recv' ? 'receipt' : 'payment',
            () => go('billDetail', <String, Object?>{
              'bill': b.$1.withKind(b.$2),
            }),
          ),
    ]);
    add(<SearchHit>[
      for (final Act a in acts)
        if (hit('${a.party} ${a.no} ${kKinds[a.kind]!.t}'))
          SearchHit(
            '${kKinds[a.kind]!.t} · ${a.no}',
            'Activity · ${a.party} · ${inr(a.amt)}',
            'activity',
            'activity',
            () => go('actDetail', <String, Object?>{'act': a.id}),
          ),
    ]);
    if (isAdmin) {
      add(<SearchHit>[
        for (final Member m in team)
          if (hit('${m.name} ${m.email}'))
            SearchHit(m.name, 'Team · ${m.email}', 'person', 'team', () {
              go('team');
              openMember(m);
            }),
      ]);
    }
    add(<SearchHit>[
      for (final Report r in repo.reports())
        if (hit('${r.t} ${r.s} report'))
          SearchHit(
            r.t,
            'Report · ${r.s}',
            r.ic,
            r.c,
            () => go('report', <String, Object?>{'report': r.id}),
          ),
    ]);
    add(<SearchHit>[
      for (final SearchEntry e in kSearch)
        if (hit('${e.t} ${e.s}') &&
            (e.a == null || canOpen(e.a!.screen)))
          SearchHit(e.t, e.s, e.ic, e.c, () {
            if (e.f != null) {
              startFlow(e.f!);
            } else {
              run(e.a!);
            }
          }),
    ]);
    return out;
  }

  // ------------------------------------------------------ background look
  void setBgOpacity(double v) {
    _set(() => bgOpacity = v.clamp(0, 100).roundToDouble());
    store.save(LocalStorage.kBgOpacity, bgOpacity);
  }

  void setBgShade(double v) {
    _set(() => bgShade = v.clamp(-100, 100).roundToDouble());
    store.save(LocalStorage.kBgShade, bgShade);
  }

  // ------------------------------------------------------------ reminders
  String get _reminderCompany => repo.activeCompanyId ?? company;

  /// Reminders of the active company, soonest first (date, then time).
  List<Reminder> get companyReminders =>
      reminders.where((Reminder r) => r.company == _reminderCompany).toList()
        ..sort(
          (Reminder a, Reminder b) =>
              '${a.date} ${a.time}'.compareTo('${b.date} ${b.time}'),
        );

  /// Reminders whose date and time have arrived and are not done yet.
  List<Reminder> get dueReminders {
    final DateTime now = DateTime.now();
    return companyReminders.where((Reminder r) {
      final DateTime? at = r.at;
      return !r.done && at != null && !at.isAfter(now);
    }).toList();
  }

  /// Active (not done) reminders of the active company, soonest first.
  List<Reminder> get activeReminders =>
      companyReminders.where((Reminder r) => !r.done).toList();

  /// `Scheduled` (rings later), `Due` (time has come, not done) or `Done`.
  String reminderStatus(Reminder r) {
    if (r.done) return 'Done';
    final DateTime? at = r.at;
    return at == null || at.isAfter(DateTime.now()) ? 'Scheduled' : 'Due';
  }

  Reminder? reminderFor(Bill b) =>
      companyReminders.where((Reminder r) => r.billKey == b.key).firstOrNull;

  /// Opens the reminder sheet for [b] (new or existing reminder).
  void openReminder(Bill b) {
    final Reminder? r = reminderFor(b);
    _set(() {
      remBill = b;
      form['remDate'] = r?.date ?? ymd(today.add(const Duration(days: 1)));
      form['remTime'] = (r?.time ?? '').isNotEmpty ? r!.time : '10:00';
      form['remNote'] = r?.note ?? '';
      overlay = 'reminder';
    });
  }

  void saveReminder() {
    final Bill? b = remBill;
    final String date = (form['remDate'] ?? '').trim();
    if (b == null) return;
    if (DateTime.tryParse(date) == null) {
      say('Pick a date for the reminder');
      return;
    }
    final String time = (form['remTime'] ?? '').trim();
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(time)) {
      say('Pick a time for the reminder');
      return;
    }
    final DateTime? at = DateTime.tryParse('${date}T$time:00');
    if (at == null || !at.isAfter(DateTime.now())) {
      // e.g. 1:58 AM picked at 1:56 PM today: it could never ring.
      say('That time has already passed. Pick a later time (check AM / PM)');
      return;
    }
    final Reminder? old = reminderFor(b);
    final Reminder r = Reminder(
      id: old?.id ?? 'r${DateTime.now().microsecondsSinceEpoch}',
      company: _reminderCompany,
      billKey: b.key,
      party: b.party,
      billNo: b.no,
      kind: b.kind,
      amount: b.amt,
      date: date,
      time: time,
      note: (form['remNote'] ?? '').trim(),
    );
    _set(() {
      reminders = <Reminder>[
        for (final Reminder x in reminders)
          if (x.id != r.id) x,
        r,
      ];
      overlay = null;
    });
    _saveReminders();
    say('Reminder set for ${reminderWhen(r)}');
    unawaited(_armWithAccess(r));
  }

  /// Asks for notification permission (first time), then schedules [r].
  Future<void> _armWithAccess(Reminder r) async {
    final AlarmAccess a = await alarms.requestAccess();
    if (_disposed) return;
    if (a == AlarmAccess.blocked) {
      say(
        'Notifications are off for TallyConnect. Turn them on in phone '
        'Settings to hear this reminder',
      );
    } else if (a == AlarmAccess.inexact) {
      say(
        'Allow "Alarms & reminders" for TallyConnect so it rings exactly on '
        'time',
      );
    }
    await _arm(r);
  }

  int _remAlarmId(Reminder r) => alarmId('rem:${r.id}');

  /// Schedules (or cancels) the device notification of [r].
  Future<void> _arm(Reminder r) async {
    final DateTime? at = r.at;
    if (r.done || at == null || !at.isAfter(DateTime.now())) {
      await alarms.cancel(_remAlarmId(r));
      return;
    }
    final bool recv = r.kind == 'recv';
    await alarms.schedule(
      AlarmSpec(
        id: _remAlarmId(r),
        at: at,
        title: recv
            ? 'Collect ${inr(r.amount)} from ${r.party}'
            : 'Pay ${inr(r.amount)} to ${r.party}',
        body: <String>[
          'Bill ${r.billNo}',
          recv ? 'Receivable' : 'Payable',
          if (r.note.isNotEmpty) r.note,
        ].join(' · '),
        payload: 'rem:${r.id}',
      ),
    );
  }

  /// Marks a reminder done: it stops ringing and leaves the active list.
  void markReminderDone(String id) {
    final Reminder? r = reminders.where((Reminder x) => x.id == id).firstOrNull;
    if (r == null) return;
    final Reminder d = r.copyWith(done: true);
    _set(() => reminders = <Reminder>[
      for (final Reminder x in reminders) x.id == id ? d : x,
    ]);
    _saveReminders();
    unawaited(_arm(d));
    say('Reminder done · ${r.party}');
  }

  /// Rings again in [minutes] minutes.
  void snoozeReminder(String id, {int minutes = 10}) {
    final Reminder? r = reminders.where((Reminder x) => x.id == id).firstOrNull;
    if (r == null) return;
    final DateTime at = DateTime.now().add(Duration(minutes: minutes));
    final Reminder s = r.copyWith(
      date: ymd(at),
      time:
          '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
      done: false,
    );
    _set(() => reminders = <Reminder>[
      for (final Reminder x in reminders) x.id == id ? s : x,
    ]);
    _saveReminders();
    unawaited(_arm(s));
    say('Snoozed · rings again at ${clock(at)}');
  }

  // ------------------------------------------------- notifications (device)
  StreamSubscription<AlarmTap>? _alarmSub;

  /// A notification tap waiting for the login / data to open.
  AlarmTap? _pendingTap;

  /// Bills behind the armed due alerts (re-armed only when they change).
  String _dueSig = '';

  void _startAlarms() {
    _alarmSub = alarms.taps.listen(onAlarmTap);
    alarms.init().then((AlarmTap? launch) {
      if (_disposed) return;
      // Re-arm every saved reminder (after an update / time-zone change the
      // OS may have dropped them; scheduling the same id replaces it).
      for (final Reminder r in reminders) {
        unawaited(_arm(r));
      }
      _armDueAlerts();
      if (launch != null) onAlarmTap(launch);
    }, onError: (Object _) {});
  }

  /// A tapped notification (or its Mark done / Snooze button).
  void onAlarmTap(AlarmTap t) {
    if (_disposed) return;
    final String p = t.payload;
    if (p.startsWith('rem:')) {
      final String id = p.substring(4);
      if (t.action == 'done') return markReminderDone(id);
      if (t.action == 'snooze') return snoozeReminder(id);
    }
    if (!loggedIn) {
      _pendingTap = t; // opened after the login
      return;
    }
    _pendingTap = t;
    _openPendingTap();
  }

  void _openPendingTap() {
    final AlarmTap? t = _pendingTap;
    if (t == null || !loggedIn || _disposed) return;
    _pendingTap = null;
    final String p = t.payload;
    if (p.startsWith('rem:')) {
      final String id = p.substring(4);
      final Reminder? r = reminders
          .where((Reminder x) => x.id == id)
          .firstOrNull;
      if (r == null) {
        say('This reminder was removed');
        return;
      }
      if (r.company != _reminderCompany) {
        say('Reminder for ${r.party} belongs to another company');
        return;
      }
      go('outHub');
      _set(() => overlay = 'reminders');
      return;
    }
    if (p.startsWith('stock:')) {
      final String name = p.substring(6);
      if (name.isEmpty) {
        go('items');
      } else {
        openItem(name);
      }
      return;
    }
    if (p.startsWith('auto:')) {
      final List<String> k = p.substring(5).split('\n');
      final String kind = k.first == 'pay' ? 'pay' : 'recv';
      final String key = k.length > 1 ? k[1] : '';
      final Bill? b = (kind == 'pay' ? repo.payables() : repo.receivables())
          .where((Bill x) => x.key == key)
          .firstOrNull;
      if (b == null) {
        say('This bill is no longer pending');
        return;
      }
      go('billDetail', <String, Object?>{'bill': b.withKind(kind)});
    }
  }

  /// Turns the 3-days-before-due alerts on / off (saved on this phone).
  void toggleAutoRemind() => setAutoRemind(!autoRemind);

  /// Sets the due-date alerts switch ([quiet]: no toast).
  void setAutoRemind(bool on, {bool quiet = false}) {
    _set(() => prefs['due'] = on);
    store.save(LocalStorage.kAutoRemind, on);
    _dueSig = '';
    _armDueAlerts();
    if (on) unawaited(alarms.requestAccess());
    if (quiet) return;
    say(on ? 'Alert 3 days before each bill is due' : 'Due-date alerts are off');
  }

  /// Most due alerts kept armed at once (the soonest ones).
  static const int kMaxDueAlerts = 40;

  /// Schedules a notification at 10:00 AM, 3 days before the due date, for
  /// each pending bill of the active company (receivable and payable), and
  /// cancels the ones no longer needed. Runs when the bills change.
  void _armDueAlerts() {
    final List<Bill> recv = repo.receivables(), pay = repo.payables();
    final String sig =
        '$autoRemind|${identityHashCode(recv)}|${identityHashCode(pay)}|'
        '${recv.length}|${pay.length}|${ymd(today)}';
    if (sig == _dueSig) return;
    _dueSig = sig;
    final DateTime now = DateTime.now();
    final List<(DateTime, Bill, String)> want = <(DateTime, Bill, String)>[];
    if (autoRemind && loggedIn) {
      for (final (List<Bill>, String) side in <(List<Bill>, String)>[
        (recv, 'recv'),
        (pay, 'pay'),
      ]) {
        for (final Bill b in side.$1) {
          final DateTime? due = b.dueDate;
          if (due == null) continue;
          final DateTime at = DateTime(due.year, due.month, due.day - 3, 10);
          if (at.isAfter(now)) want.add((at, b, side.$2));
        }
      }
      want.sort(
        ((DateTime, Bill, String) a, (DateTime, Bill, String) b) =>
            a.$1.compareTo(b.$1),
      );
    }
    final List<int> ids = <int>[];
    for (final (DateTime, Bill, String) w in want.take(kMaxDueAlerts)) {
      final Bill b = w.$2;
      final bool r = w.$3 == 'recv';
      final int id = alarmId('auto:${w.$3}\n${b.key}');
      ids.add(id);
      unawaited(
        alarms.schedule(
          AlarmSpec(
            id: id,
            at: w.$1,
            title: r
                ? 'Due in 3 days: collect ${inr(b.amt)}'
                : 'Due in 3 days: pay ${inr(b.amt)}',
            body: '${b.party} · Bill ${b.no} · due ${b.due}',
            payload: 'auto:${w.$3}\n${b.key}',
            actions: false,
          ),
        ),
      );
    }
    final Object? old = store.load<Object?>(LocalStorage.kDueAlertIds, null);
    if (old is List) {
      for (final int id in old.whereType<num>().map((num n) => n.toInt())) {
        if (!ids.contains(id)) unawaited(alarms.cancel(id));
      }
    }
    store.save(LocalStorage.kDueAlertIds, ids);
  }

  /// `06 Oct 2026 · 10:30 AM`.
  String reminderWhen(Reminder r) {
    final DateTime? at = r.at;
    if (at == null) return r.date;
    return r.time.isEmpty ? dmy(at) : '${dmy(at)} · ${clock(at)}';
  }

  /// Opens the edit sheet of [r] (its bill must still be pending).
  void editReminder(Reminder r) {
    final Bill? b = (r.kind == 'pay' ? repo.payables() : repo.receivables())
        .where((Bill x) => x.key == r.billKey)
        .firstOrNull;
    if (b == null) {
      say('This bill is no longer pending');
      return;
    }
    openReminder(b.withKind(r.kind));
  }

  /// Removes a reminder and its pending notification. [keepOpen] keeps the
  /// reminders list open (removing from the list).
  void deleteReminder(String id, {bool keepOpen = false}) {
    final Reminder? gone = reminders
        .where((Reminder x) => x.id == id)
        .firstOrNull;
    if (gone != null) unawaited(alarms.cancel(_remAlarmId(gone)));
    _set(() {
      reminders = reminders.where((Reminder x) => x.id != id).toList();
      if (overlay == 'reminder' || (overlay == 'reminders' && !keepOpen)) {
        overlay = null;
      }
    });
    _saveReminders();
    say('Reminder removed');
  }

  void _saveReminders() => store.save(
    LocalStorage.kReminders,
    reminders.map((Reminder r) => r.toJson()).toList(),
  );

  /// Opens the bill of a reminder (if it is still pending).
  void openReminderBill(Reminder r) {
    final Bill? b = (r.kind == 'pay' ? repo.payables() : repo.receivables())
        .where((Bill x) => x.key == r.billKey)
        .firstOrNull;
    if (b == null) {
      say('This bill is no longer pending');
      return;
    }
    go('billDetail', <String, Object?>{'bill': b.withKind(r.kind)});
  }

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
