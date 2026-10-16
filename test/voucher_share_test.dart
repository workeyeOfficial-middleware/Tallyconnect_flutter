// Several vouchers → one list PDF, one PDF each (one share sheet), or the
// party's WhatsApp chat with the list ready. Selection lives on the
// Vouchers list only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart'
    show DataSet;
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'share_chart_test.dart' show FakeExporter, boot, settle;
import 'screens_test.dart' show loadFigtree;

void main() {
  group('WhatsApp number', () {
    test('Indian numbers get +91; junk is refused', () {
      expect(AppController.whatsAppNumber('98200 12345'), '919820012345');
      expect(AppController.whatsAppNumber('+91-98200-12345'), '919820012345');
      expect(AppController.whatsAppNumber('09820012345'), '919820012345');
      expect(AppController.whatsAppNumber('98200 12345, 022 2345678'), '919820012345');
      expect(AppController.whatsAppNumber('+44 20 7946 0958'), '442079460958');
      expect(AppController.whatsAppNumber('12345'), isNull);
      expect(AppController.whatsAppNumber(null), isNull);
    });
  });

  group('controller (sample data)', () {
    AppController start(FakeExporter fx) => AppController(
      store: LocalStorage.memory(),
      startScreen: 'vList',
      exporter: fx,
    );

    test('select, one list PDF, one PDF each, the limit', () async {
      final FakeExporter fx = FakeExporter();
      final AppController c = start(fx);
      final List<Voucher> vs = c.repo.vouchers().take(3).toList();
      c.startVoucherSelect();
      for (final Voucher v in vs) {
        c.togglePicked(v);
      }
      expect(c.vPicked.length, 3);
      c.togglePicked(vs.first); // untick
      expect(c.vPicked.length, 2);
      c.togglePicked(vs.first);
      expect(c.pickedTotal, vs.fold<num>(0, (num a, Voucher v) => a + v.amt));

      await c.sharePickedList();
      expect(fx.shared.last, 'Selected vouchers');

      await c.sharePickedEach();
      expect(fx.sharedMany.single, hasLength(3));
      expect(fx.sharedMany.single.every((String n) => n.endsWith('.pdf')), isTrue);

      // More than 20: one PDF each is refused, the list PDF still works.
      c.pickAll(c.repo.vouchers());
      if (c.vPicked.length > AppController.kMaxShareEach) {
        await c.sharePickedEach();
        expect(c.toast, contains('at most 20'));
        expect(fx.sharedMany, hasLength(1));
      }
      c.pickAll(c.repo.vouchers()); // all ticked → Clear
      expect(c.vPicked, isEmpty);
      c.dispose();
    });

    test('leaving the list ends selecting', () {
      final AppController c = start(FakeExporter());
      c.startVoucherSelect();
      c.togglePicked(c.repo.vouchers().first);
      c.go('reports');
      expect(c.vSelecting, isFalse);
      expect(c.vPicked, isEmpty);
      c.dispose();
    });
  });

  test('WhatsApp the party: chat with the list ready (real company)', () async {
    final List<Uri> opened = <Uri>[];
    final FakeBackend f = FakeBackend()
      ..extraLedgers = <Map<String, Object?>>[
        <String, Object?>{
          'ledger_guid': 'L9',
          'name': 'Gupta Traders',
          'parent_group': 'Sundry Debtors',
          'opening_balance': '0',
          'closing_balance': '0',
          'phone': '98200 12345',
        },
      ];
    final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
    await r.login('ravi@x.in', 'secret', 'ADMIN');
    await r.refreshAll();
    await r.ensure(DataSet.ledgers);
    final AppController c = AppController(
      store: LocalStorage.memory(),
      repo: r,
      startScreen: 'vList',
      linkOpener: (Uri u) async {
        opened.add(u);
        return true;
      },
    );
    c.afterRefresh(quietOk: true);
    c.startVoucherSelect();
    c.togglePicked(Voucher('sales', 'Gupta Traders', 'S/11', 2, 1180, guid: 'g11', date: DateTime(2026, 10, 2)));
    c.togglePicked(Voucher('sales', 'Gupta Traders', 'S/12', 3, 2360, guid: 'g12', date: DateTime(2026, 10, 3)));
    expect(c.pickedParty?.name, 'Gupta Traders');
    await c.whatsAppPickedParty();
    final Uri u = opened.single;
    expect(u.host, 'wa.me');
    expect(u.path, '/919820012345');
    final String text = u.queryParameters['text']!;
    expect(text, startsWith('Dear Gupta Traders,'));
    expect(text, contains('2 entries totalling ₹3,540'));
    expect(text, contains('S/11 · 02 Oct 2026 · ₹1,180'));
    // Two parties: no single chat to open.
    c.togglePicked(Voucher('sales', 'Someone Else', 'S/13', 3, 10, guid: 'g13'));
    expect(c.pickedParty, isNull);
    c.dispose();
  });

  group('screen', () {
    setUpAll(loadFigtree);

    testWidgets('Select → tick → share bar (320 px), no overflow', (WidgetTester t) async {
      final FakeExporter fx = FakeExporter();
      final AppController c = await boot(t, fx, start: 'vList');
      t.view.physicalSize = const Size(320 * 3, 720 * 3);
      await settle(t);
      await t.tap(find.byKey(const ValueKey<String>('vSelect')));
      await settle(t);
      expect(find.text('Tap entries to select them'), findsOneWidget);
      final Voucher first = c.repo.vouchers().first;
      await t.tap(find.byKey(ValueKey<String>('vPick-${first.key}')));
      await settle(t);
      expect(c.vPicked.keys, <String>[first.key]);
      expect(find.byKey(const ValueKey<String>('vShareList')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('vShareEach')), findsOneWidget);
      expect(c.screen, 'vList'); // a tap ticks, it does not open the entry
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey<String>('vShareEach')));
      await settle(t);
      expect(fx.sharedMany.single, hasLength(1));
      await t.tap(find.byKey(const ValueKey<String>('vSelect'))); // Done
      await settle(t);
      expect(c.vSelecting, isFalse);
      expect(find.byKey(const ValueKey<String>('vSelectBar')), findsNothing);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
