// Several vouchers / parties → one WhatsApp message (floating action bar
// with Select all / Clear), and Home's Sales analytics card right after
// New Entry (real company data; not with sample data).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'share_chart_test.dart' show FakeExporter, boot, settle;
import 'screens_test.dart' show loadFigtree;

Future<AppController> _remote(
  FakeBackend f, {
  LocalStorage? store,
  List<Uri>? opened,
}) async {
  final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
  await r.login('ravi@x.in', 'secret', 'ADMIN');
  await r.refreshAll();
  final AppController c = AppController(
    store: store ?? LocalStorage.memory(),
    repo: r,
    startScreen: 'home',
    linkOpener: (Uri u) async {
      opened?.add(u);
      return true;
    },
  );
  c.afterRefresh(quietOk: true);
  return c;
}

void main() {
  group('vouchers: one WhatsApp message', () {
    test('Select all / Clear; several parties → pick a chat; long lists cut', () async {
      final List<Uri> opened = <Uri>[];
      final AppController c = AppController(
        store: LocalStorage.memory(),
        startScreen: 'vList',
        exporter: FakeExporter(),
        linkOpener: (Uri u) async {
          opened.add(u);
          return true;
        },
      );
      final List<Voucher> all = c.repo.vouchers();
      c.startVoucherSelect();
      c.selectAllPicked(all.take(3).toList());
      expect(c.vPicked, hasLength(3));
      c.selectAllPicked(all.take(3).toList()); // again: still 3, not cleared
      expect(c.vPicked, hasLength(3));
      c.clearPicked();
      expect(c.vPicked, isEmpty);
      expect(c.vSelecting, isTrue);

      // Two parties: wa.me without a number (WhatsApp asks whom to send to).
      final List<Voucher> two = <Voucher>[
        Voucher('sales', 'Gupta Traders', 'S/11', 2, 1180, guid: 'a', date: DateTime(2026, 10, 2)),
        Voucher('receipt', 'Mehta & Sons', 'R/4', 3, 500, guid: 'b', date: DateTime(2026, 10, 3)),
      ];
      two.forEach(c.togglePicked);
      await c.whatsAppPicked();
      final Uri u = opened.single;
      expect(u.host, 'wa.me');
      expect(u.path, '/');
      final String text = u.queryParameters['text']!;
      expect(text, startsWith('Hello,'));
      expect(text, contains('2 entries totalling ₹1,680'));
      expect(text, contains('S/11 · 02 Oct 2026 · Gupta Traders · ₹1,180'));
      expect(text, contains('R/4 · 03 Oct 2026 · Mehta & Sons · ₹500'));
      expect(text, contains('*Total: ₹1,680*'));

      // A long selection: 40 lines, the rest summed up in one line.
      c.clearPicked();
      final List<Voucher> many = <Voucher>[
        for (int i = 0; i < 55; i++)
          Voucher('sales', 'P$i', 'S/$i', 1, 100, guid: 'm$i', date: DateTime(2026, 9, 1)),
      ];
      c.selectAllPicked(many);
      await c.whatsAppPicked();
      final String long = opened.last.queryParameters['text']!;
      expect(long, contains('55 entries totalling ₹5,500'));
      expect('•'.allMatches(long), hasLength(AppController.kWaMaxLines));
      expect(long, contains('…and 15 more (₹1,500)'));
      c.dispose();
    });
  });

  group('parties: one WhatsApp message / one PDF', () {
    test('tick, totals, message, PDF; leaving the list ends selecting', () async {
      final List<Uri> opened = <Uri>[];
      final FakeExporter fx = FakeExporter();
      final AppController c = AppController(
        store: LocalStorage.memory(),
        startScreen: 'party',
        exporter: fx,
        linkOpener: (Uri u) async {
          opened.add(u);
          return true;
        },
      );
      final List<Party> pool = c.partyPool();
      final Party cust = pool.firstWhere((Party x) => x.type == 'c' && x.bal != 0);
      final Party supp = pool.firstWhere((Party x) => x.type == 's' && x.bal != 0);
      c.startPartySelect();
      c.togglePartyPicked(cust);
      c.togglePartyPicked(supp);
      expect(c.pPicked.keys, <String>[cust.name, supp.name]);
      final (num get, num give) = c.pickedPartyTotals;
      expect(get, cust.bal.abs());
      expect(give, supp.bal.abs());

      await c.whatsAppPickedParties();
      final String text = opened.single.queryParameters['text']!;
      expect(opened.single.path, '/');
      expect(text, startsWith('*2 parties · ${c.companyName}*'));
      expect(text, contains(c.partyLine(cust)));
      expect(text, contains('(Customer)'));
      expect(text, contains('to receive'));
      expect(text, contains('(Supplier)'));
      expect(text, contains('to pay'));

      await c.sharePickedParties();
      expect(fx.shared.last, startsWith('Party'));

      c.selectAllParties(pool);
      expect(c.pPicked, hasLength(pool.length));
      c.clearPartyPicked();
      expect(c.pPicked, isEmpty);

      c.togglePartyPicked(cust);
      c.go('reports');
      expect(c.pSelecting, isFalse);
      expect(c.pPicked, isEmpty);
      c.dispose();
    });
  });

  group('screens (320 px)', () {
    setUpAll(loadFigtree);

    testWidgets('Vouchers: floating bar, Select all, Clear, WhatsApp', (WidgetTester t) async {
      final FakeExporter fx = FakeExporter();
      final AppController c = await boot(t, fx, start: 'vList');
      t.view.physicalSize = const Size(320 * 3, 640 * 3);
      await settle(t);
      await t.tap(find.byKey(const ValueKey<String>('vSelect')));
      await settle(t);
      expect(find.byKey(const ValueKey<String>('vSelectBar')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('vSelectWa')), findsNothing);
      await t.tap(find.byKey(const ValueKey<String>('vSelectAll')));
      await settle(t);
      expect(c.vPicked, isNotEmpty);
      expect(find.byKey(const ValueKey<String>('vSelectWa')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('vSelectAll')), findsNothing); // all ticked
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey<String>('vSelectClear')));
      await settle(t);
      expect(c.vPicked, isEmpty);
      expect(c.vSelecting, isTrue);
      await t.tap(find.byKey(const ValueKey<String>('vSelect'))); // Done
      await settle(t);
      expect(find.byKey(const ValueKey<String>('vSelectBar')), findsNothing);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('Party: tick rows, floating bar, no overflow', (WidgetTester t) async {
      final FakeExporter fx = FakeExporter();
      final AppController c = await boot(t, fx, start: 'party');
      t.view.physicalSize = const Size(320 * 3, 640 * 3);
      await settle(t);
      await t.tap(find.byKey(const ValueKey<String>('pSelect')));
      await settle(t);
      expect(find.text('Tap parties to select them'), findsOneWidget);
      final Party first = c.partyPool().firstWhere(
        (Party x) => find.byKey(ValueKey<String>('pPick-${x.name}')).evaluate().isNotEmpty,
      );
      final Finder row = find.byKey(ValueKey<String>('pPick-${first.name}'));
      await t.ensureVisible(row);
      await settle(t);
      await t.tap(row);
      await settle(t);
      expect(c.pPicked.keys, <String>[first.name]);
      expect(c.screen, 'party'); // a tap ticks, it does not open the party
      expect(find.byKey(const ValueKey<String>('pSelectWa')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('pSharePdf')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey<String>('pSharePdf')));
      await settle(t);
      expect(fx.shared, isNotEmpty);
      await t.pump(const Duration(seconds: 6));
    });
  });

  group('Home: Sales analytics card', () {
    setUpAll(loadFigtree);

    test('right after New Entry; added once to saved layouts', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _remote(f);
      final List<String> p0 = c.curPages().first;
      expect(p0.indexOf(AppController.kSalesCard), p0.indexOf('newEntry') + 1);
      expect(c.widgetMeta(AppController.kSalesCard)?.label, 'Sales analytics');
      c.dispose();

      // A layout saved before the card existed.
      final LocalStorage s = LocalStorage.memory();
      s.save(LocalStorage.kPages, <String, Object?>{
        'def': <List<String>>[
          <String>['newEntry', 'vouchers', 'money'],
          <String>['reports'],
        ],
      });
      final AppController d = await _remote(FakeBackend(), store: s);
      expect(d.pagesByWs['def']!.first, <String>['newEntry', AppController.kSalesCard, 'vouchers', 'money']);
      // Hidden or moved later: not added again.
      d.persistPages(<List<String>>[
        <String>['newEntry', 'vouchers', 'money'],
        <String>['reports'],
      ]);
      d.dispose();
      final AppController e = await _remote(FakeBackend(), store: s);
      expect(e.pagesByWs['def']!.first, isNot(contains(AppController.kSalesCard)));
      e.dispose();
    });

    test('sample data: no card', () {
      final AppController c = AppController(store: LocalStorage.memory(), startScreen: 'home');
      expect(c.widgetMeta(AppController.kSalesCard), isNull);
      c.dispose();
    });

    testWidgets('real numbers on Home (320 px); tap → dashboard', (WidgetTester t) async {
      t.view.physicalSize = const Size(320 * 3, 720 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final FakeBackend f = FakeBackend();
      final AppController c = await _remote(f);
      await t.pumpWidget(
        ProviderScope(
          overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
          child: const TallyConnectApp(),
        ),
      );
      await settle(t);
      await settle(t);
      expect(f.salesQueries, hasLength(1)); // loaded once
      expect(find.byKey(const ValueKey<String>('homeSalesCard')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('homeSalesTotal')), findsOneWidget);
      expect(find.text('₹20,060'), findsOneWidget);
      expect(find.text('+100.6%'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('homeSalesSpark')), findsOneWidget);
      // Below New Entry.
      final double entryY = t.getTopLeft(find.text('New Entry').first).dy;
      final double salesY = t.getTopLeft(find.byKey(const ValueKey<String>('homeSalesCard'))).dy;
      expect(salesY, greaterThan(entryY));
      expect(t.takeException(), isNull);
      await settle(t);
      expect(f.salesQueries, hasLength(1)); // rebuilds do not reload
      await t.tap(find.byKey(const ValueKey<String>('homeSalesCard')));
      await settle(t);
      expect(c.screen, 'salesDash');
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
