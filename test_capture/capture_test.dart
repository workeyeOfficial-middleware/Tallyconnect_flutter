// Dev-only: renders every screen at the prototype's 390×844 frame into PNGs
// (run: flutter test test_capture --update-goldens). Not part of `flutter test`.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/main.dart';

Future<void> loadFigtree() async {
  final FontLoader l = FontLoader('Figtree');
  for (final String w in <String>['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    l.addFont(Future<ByteData>.value(ByteData.sublistView(File('assets/fonts/Figtree-$w.ttf').readAsBytesSync())));
  }
  await l.load();
}

void main() {
  setUpAll(loadFigtree);
  testWidgets('capture', (WidgetTester t) async {
    debugDisableShadows = false;
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    final AppController c = AppController(store: LocalStorage.memory(), startScreen: 'home');
    await t.pumpWidget(ProviderScope(overrides: <Override>[appProvider.overrideWith((Ref ref) => c)], child: const TallyConnectApp()));
    Future<void> pumpN() async { for (int i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); } }
    Future<void> shot(String name) async {
      await pumpN();
      await expectLater(find.byType(TallyConnectApp), matchesGoldenFile('out/$name.png'));
      bool moved = false;
      for (final ScrollableState s in t.stateList<ScrollableState>(find.byType(Scrollable))) {
        final ScrollPosition ps = s.position;
        if (s.axisDirection == AxisDirection.down && ps.maxScrollExtent > 20 && ps.viewportDimension > 300) { ps.jumpTo(ps.maxScrollExtent); moved = true; }
      }
      if (moved) { await pumpN(); await expectLater(find.byType(TallyConnectApp), matchesGoldenFile('out/${name}_b.png')); }
    }
    final Map<String, void Function()> plan = <String, void Function()>{
      'home': () => c.jump('home'),
      'notifs': () => c.go('notifs'),
      'items': () => c.go('items'),
      'party': () => c.go('party'),
      'partyDetail': () => c.go('partyDetail', <String, Object?>{'party': 'Shree Balaji Traders', 'partyTab': 'summary'}),
      'vHub': () => c.go('vHub'),
      'vList': () => c.go('vList', <String, Object?>{'vFilter': 'all', 'vPeriod': 'month'}),
      'entryDetail': () => c.go('entryDetail', <String, Object?>{'entry': c.repo.vouchers().first}),
      'settings': () => c.go('settings', <String, Object?>{'setTab': 'profile'}),
      'settings_alerts': () => c.update(() => c.setTab = 'alerts'),
      'settings_plan': () => c.update(() => c.setTab = 'plan'),
      'settings_look': () => c.update(() => c.setTab = 'look'),
      'newEntry': () => c.go('newEntry'),
      'flow1': () => c.startFlow('sales'),
      'flow2': () => c.flowNext(),
      'flow3': () => c.flowNext(),
      'flow4': () => c.flowNext(),
      'outHub': () => c.jump('outHub'),
      'outList': () => c.go('outList', <String, Object?>{'outKind': 'recv', 'outFilter': 'all'}),
      'billDetail': () => c.go('billDetail', <String, Object?>{'bill': c.repo.receivables().first}),
      'team': () => c.jump('team'),
      'activity': () => c.jump('activity'),
      'actDetail': () => c.go('actDetail', <String, Object?>{'act': 'a2'}),
      'reports': () => c.jump('reports'),
      'report': () => c.go('report', <String, Object?>{'report': 'top'}),
      'companies': () => c.go('companies'),
      'billing': () => c.go('billing'),
      'refer': () => c.go('refer'),
      'help': () => c.go('help'),
      'manageWs': () => c.go('manageWs'),
      'createWs': () => c.goCreateWs(),
      'report_bar': () => c.go('report', <String, Object?>{'report': 'top'}),
      'report_pie': () => c.update(() => c.chartType['top'] = 'pie'),
      'report_line': () => c.update(() => c.chartType['top'] = 'line'),
      'report_day': () => c.go('report', <String, Object?>{'report': 'day'}),
      'report_inC': () => c.go('report', <String, Object?>{'report': 'inC'}),
      'ov_cmenu': () { c.jump('home'); c.openCardMenu('home', 'items', const Rect.fromLTWH(16, 428, 110, 136)); },
      'ov_menu': () {
        c.closeCMenu(); c.jump('home'); c.openOverlay('menu'); },
      'ov_search': () => c.openOverlay('search'),
      'ov_company': () => c.openOverlay('company'),
    };
    for (final MapEntry<String, void Function()> e in plan.entries) {
      e.value();
      await shot(e.key);
      if (e.key.startsWith('ov_')) c.closeOv();
    }
    await t.pump(const Duration(seconds: 7));
    debugDisableShadows = true;
  });
}
