// Renders every screen and overlay of the prototype and drives the main
// interactions to make sure nothing throws.
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/main.dart';
import 'package:tallyconnect_ui/presentation/shell.dart';
import 'package:tallyconnect_ui/presentation/widgets/tab_bar.dart';

Future<AppController> boot(WidgetTester t, {String start = 'login'}) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final AppController c = AppController(
    store: LocalStorage.memory(),
    startScreen: start,
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
      child: const TallyConnectApp(),
    ),
  );
  await t.pump(const Duration(milliseconds: 600));
  return c;
}

Future<void> settle(WidgetTester t) async {
  for (int i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Lets every pending timer (toasts, pill, mock sync) finish.
Future<void> drain(WidgetTester t) async => t.pump(const Duration(seconds: 6));

/// Loads the bundled Figtree TTFs so text is measured like on a device
/// (the default test font draws every glyph as a full-width square).
Future<void> loadFigtree() async {
  final FontLoader l = FontLoader('Figtree');
  for (final String w in <String>[
    'Regular',
    'Medium',
    'SemiBold',
    'Bold',
    'ExtraBold',
  ]) {
    final List<int> b = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    l.addFont(
      Future<ByteData>.value(ByteData.sublistView(Uint8List.fromList(b))),
    );
  }
  await l.load();
}

void main() {
  setUpAll(loadFigtree);

  testWidgets('login → Home, toast and tab bar', (WidgetTester t) async {
    final AppController c = await boot(t);
    expect(find.text('Welcome back'), findsOneWidget);
    await t.tap(find.text('Log In'));
    await settle(t);
    expect(c.screen, 'home');
    expect(find.text('Welcome back, workk72002'), findsOneWidget);
    expect(find.text('What would you like to do?'), findsOneWidget);
    // "Outstanding" is both a tab label and a Home shortcut tile; check the
    // tab bar's label.
    expect(
      find.descendant(
        of: find.byType(TcTabBar),
        matching: find.text('Outstanding'),
      ),
      findsOneWidget,
    );
    await drain(t);
  });

  testWidgets('every screen renders', (WidgetTester t) async {
    final AppController c = await boot(t, start: 'home');
    for (final String s in kScreens) {
      c.jump(s);
      await settle(t);
      expect(t.takeException(), isNull, reason: s);
    }
    await drain(t);
  });

  testWidgets('every overlay renders', (WidgetTester t) async {
    final AppController c = await boot(t, start: 'home');
    for (final String o in <String>[
      'menu',
      'search',
      'company',
      'newParty',
      'picker',
      'addItem',
      'invite',
      'newUser',
      'member',
      'hiddenPanel',
    ]) {
      c.openOverlay(o);
      await settle(t);
      expect(t.takeException(), isNull, reason: o);
      c.closeOv();
      await settle(t);
    }
    c.openPick('Choose customer', 'sPartyX', c.repo.ledgers());
    await settle(t);
    expect(find.text('Choose customer'), findsOneWidget);
    await drain(t);
  });

  testWidgets('every flow type and step renders; Save returns Home', (
    WidgetTester t,
  ) async {
    final AppController c = await boot(t, start: 'home');
    for (final String type in <String>[
      'sales',
      'purchase',
      'receipt',
      'payment',
      'journal',
    ]) {
      c.startFlow(type);
      await settle(t);
      final int steps = type == 'sales' || type == 'purchase' ? 4 : 3;
      for (int i = 1; i < steps; i++) {
        c.flowNext();
        await settle(t);
        expect(t.takeException(), isNull, reason: '$type step $i');
      }
      expect(find.text('Save'), findsOneWidget);
    }
    await t.tap(find.text('Save'));
    await settle(t);
    expect(c.screen, 'home');
    await drain(t);
  });

  testWidgets('settings look tab: looks, combos, wallpapers, glass', (
    WidgetTester t,
  ) async {
    final AppController c = await boot(t, start: 'home');
    c.go('settings', <String, Object?>{'setTab': 'look'});
    await settle(t);
    expect(find.text('Mint Ledger'), findsOneWidget);
    c.pickLook('royal');
    c.pickCombo(2);
    // Wallpapers live in the Look → Background sub-tab.
    c.update(() => c.lookTab = 'background');
    c.pickWall('silk');
    await settle(t);
    expect(find.text('Preview · Silk waves'), findsOneWidget);
    c.applyWall();
    c.setGlass(20);
    await settle(t);
    expect(t.takeException(), isNull);
    await drain(t);
  });

  testWidgets('card menu, drag arming and hidden panel', (
    WidgetTester t,
  ) async {
    final AppController c = await boot(t, start: 'home');
    c.openCardMenu('home', 'items', const Rect.fromLTWH(20, 300, 110, 136));
    await settle(t);
    expect(find.text('Pin'), findsOneWidget);
    await t.tap(find.text('Hide'));
    await settle(t);
    expect(find.text('Hidden cards · Unhide'), findsOneWidget);
    c.showHiddenPanel(0);
    await settle(t);
    expect(find.text('Hidden on Page 1'), findsOneWidget);
    await t.tap(find.text('Unhide'));
    await settle(t);
    expect(c.hidList(), isEmpty);
    c.openCardMenu('reports', 'top', const Rect.fromLTWH(20, 300, 160, 150));
    c.cmDrag();
    expect(c.armed?.id, 'top');
    await drain(t);
  });
}
