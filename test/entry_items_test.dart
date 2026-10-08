// Create Entry items: Tally item data fills the line, quantity / rate / GST
// are edited for this voucher only, and exactly those values are queued.
// Also the stock-value sign read from Tally's export.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/api/adapters.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart';
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

void main() {
  group('stock values from Tally\'s export', () {
    test('Dr-negative values read as stock values (1 Ltr Water Bottle)', () {
      // As /inventory/mobile returns the item (Tally Prime: opening 301
      // bottle × 11.88 = 3,576.38; closing 309 bottle = 3,976.78).
      final Item it = itemFrom(<String, Object?>{
        'item_guid': 'W1',
        'name': '1 Ltr Water Bottle',
        'unit': 'bottle',
        'group': 'WATER',
        'opening_qty': '301.000',
        'opening_value': '-3576.38',
        'closing_qty': '309.000',
        'closing_value': '-3976.78',
        'rate': '-12.87',
        'gst_rate': '0',
      });
      expect(it.openingQty, 301);
      expect(it.openingValue, 3576.38);
      expect(it.openingRate!.toStringAsFixed(2), '11.88');
      expect(it.stock, 309);
      expect(it.value, 3976.78);
      expect(it.worth, 3976.78);
      expect(it.rate, 12.87);
      expect(it.st, 'ok');
    });

    test('a genuine credit (negative) stock value keeps its sign', () {
      final Item it = itemFrom(<String, Object?>{
        'name': 'Overdrawn',
        'unit': 'pcs',
        'closing_qty': '-5',
        'closing_value': '500',
        'rate': '-100',
      });
      expect(it.value, -500);
      expect(it.rate, 100);
    });

    test('zero stays zero', () {
      final Item it = itemFrom(<String, Object?>{
        'name': 'Empty',
        'closing_qty': 0,
        'closing_value': 0,
        'rate': 0,
      });
      expect(it.value, 0);
      expect(it.rate, 0);
      expect(it.st, 'out');
    });
  });

  group('Create Entry item lines (sales)', () {
    Future<(FakeBackend, ApiTallyRepository, AppController)> start() async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      await r.ensure(DataSet.items);
      final AppController c = AppController(
        store: LocalStorage.memory(),
        repo: r,
      );
      c.startFlow('sales', <String, String>{
        'sParty': 'Mehta Electricals',
        'sDate': '2026-10-03',
        'sAmt': '0',
      });
      return (f, r, c);
    }

    Item item(ApiTallyRepository r, String name) =>
        r.items().firstWhere((Item x) => x.name == name);

    test(
      'picked item fills rate, unit, qty 1 and GST; no rate error',
      () async {
        final (FakeBackend _, ApiTallyRepository r, AppController c) =
            await start();
        c.togglePickItem(item(r, 'Wire'));
        final Line l = c.lines['sales']!.single;
        expect(l.rate, 5000);
        expect(l.unit, 'Coil');
        expect(l.qty, 1);
        expect(l.gst, 18);
        expect(c.flowBlocker, isNull);
        expect(c.totals(c.lines['sales']!).total, 5900);
        c.dispose();
      },
    );

    test('+ / − update line and bill totals', () async {
      final (FakeBackend _, ApiTallyRepository r, AppController c) =
          await start();
      c.togglePickItem(item(r, 'Wire'));
      c.updLine(0, (int q) => q + 1);
      c.updLine(0, (int q) => q + 1);
      expect(c.lines['sales']!.single.qty, 3);
      expect(c.totals(c.lines['sales']!).sub, 15000);
      expect(c.totals(c.lines['sales']!).total, 17700);
      c.updLine(0, (int q) => q - 1 < 1 ? 1 : q - 1);
      expect(c.totals(c.lines['sales']!).total, 11800);
      c.dispose();
    });

    test('rate / GST edited for this voucher only; queued exactly', () async {
      final (FakeBackend f, ApiTallyRepository r, AppController c) =
          await start();
      c.togglePickItem(item(r, 'Wire'));
      c.updLine(0, (int q) => q + 1); // qty 2
      // Double-tap on the amount → rate only.
      c.openLineEdit(0);
      expect(c.overlay, 'lineEdit');
      expect(c.lineEditField, 'rate');
      expect(c.f('leRate'), '5000');
      // Invalid values are refused.
      c.setF('leRate', '0');
      expect(c.lineEditError, isNotNull);
      c.saveLineEdit();
      expect(c.lines['sales']!.single.rate, 5000);
      // Valid edit.
      c.setF('leRate', '4800.5');
      c.saveLineEdit();
      expect(c.lines['sales']!.single.rate, 4800.5);
      expect(c.lines['sales']!.single.gst, 18); // GST untouched
      // Tap on the GST → GST only.
      c.openLineEdit(0, field: 'gst');
      expect(c.lineEditField, 'gst');
      expect(c.f('leGst'), '18');
      c.setF('leGst', '101');
      expect(c.lineEditError, isNotNull);
      c.setF('leGst', '12');
      c.saveLineEdit();
      final Line l = c.lines['sales']!.single;
      expect(l.rate, 4800.5);
      expect(l.gst, 12);
      expect(l.qty, 2);
      expect(c.overlay, isNull);
      // Bill total follows: 2 × 4,800.50 = 9,601 + 12 % = 1,152.12.
      expect(c.totals(c.lines['sales']!).sub, 9601);
      expect(c.totals(c.lines['sales']!).gst, 1152.12);
      expect(c.totals(c.lines['sales']!).total, 10753.12);
      // The item master is unchanged.
      expect(item(r, 'Wire').rate, 5000);
      expect(item(r, 'Wire').gst, 18);
      // Items → Payment → Check keep the line (it lives in the entry).
      c.update(() => c.flowStep = 2);
      c.update(() => c.flowStep = 3);
      expect(c.draftOf().lines.single.rate, 4800.5);
      expect(c.flowBlocker, isNull);
      // Save queues exactly these values.
      c.saveFlow(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final List<http.Request> sent = f.to(
        '/api/mobile-voucher-command/create',
      );
      expect(sent, hasLength(1));
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body['voucher_type'], 'Sales');
      final Map<String, Object?> it0 =
          (body['items']! as List<Object?>).single! as Map<String, Object?>;
      expect(it0['item_name'], 'Wire');
      expect(it0['item_guid'], 'I1');
      expect(it0['quantity'], 2);
      expect(it0['rate'], 4800.5);
      expect(it0['gst_rate'], 12);
      expect(it0['unit'], 'Coil');
      expect(it0['amount'], 9601);
      expect(it0['gst_amount'], 1152.12);
      c.dispose();
    });

    test('an item without a Tally rate asks for one, then saves', () async {
      final (FakeBackend _, ApiTallyRepository r, AppController c) =
          await start();
      c.togglePickItem(item(r, 'Pipe')); // no stock value → rate 0
      expect(c.flowBlocker, 'Every item needs a rate and quantity');
      c.openLineEdit(0);
      c.setF('leRate', '120');
      c.saveLineEdit();
      expect(c.lines['sales']!.single.rate, 120);
      expect(c.flowBlocker, isNull);
      expect(item(r, 'Pipe').rate, 0); // master unchanged
      c.dispose();
    });
  });

  test('purchase is sent like sales, as voucher_type Purchase', () async {
    final FakeBackend f = FakeBackend();
    final ApiTallyRepository r = f.repo();
    await r.login('ravi@x.in', 'secret', 'ADMIN');
    await r.refreshAll();
    await r.ensure(DataSet.items);
    final AppController c = AppController(
      store: LocalStorage.memory(),
      repo: r,
    );
    c.startFlow('purchase', <String, String>{
      'pParty': 'Polycab Wires',
      'pDate': '2026-10-03',
      'pSupInv': 'PW/778',
      'pAmt': '0',
    });
    c.togglePickItem(r.items().firstWhere((Item x) => x.name == 'Wire'));
    c.updLine(0, (int q) => q + 1); // qty 2
    c.openLineEdit(0);
    c.setF('leRate', '4500');
    c.saveLineEdit();
    expect(c.flowBlocker, isNull);
    c.saveFlow(false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final List<http.Request> sent = f.to('/api/mobile-voucher-command/create');
    expect(sent, hasLength(1));
    final Map<String, Object?> body =
        jsonDecode(sent.single.body) as Map<String, Object?>;
    expect(body['voucher_type'], 'Purchase');
    expect(body['party_name'], 'Polycab Wires');
    expect(body['voucher_no'], 'PW/778');
    final Map<String, Object?> it0 =
        (body['items']! as List<Object?>).single! as Map<String, Object?>;
    expect(it0['item_name'], 'Wire');
    expect(it0['quantity'], 2);
    expect(it0['rate'], 4500);
    expect(it0['amount'], 9000);
    final Map<String, Object?> sum = body['summary']! as Map<String, Object?>;
    expect(sum['subtotal'], 9000);
    expect(sum['total_amount'], 10620);
    expect(r.items().firstWhere((Item x) => x.name == 'Wire').rate, 5000); // master unchanged
    c.dispose();
  });

  group('Items step gestures', () {
    setUpAll(loadFigtree);

    testWidgets('double-tap amount → rate, tap GST → GST; no edit link', (
      WidgetTester t,
    ) async {
      t.view.physicalSize = const Size(360 * 3, 800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      await t.runAsync(() async {
        await r.login('ravi@x.in', 'secret', 'ADMIN');
        await r.refreshAll();
        await r.ensure(DataSet.items);
      });
      final AppController c = AppController(
        store: LocalStorage.memory(),
        repo: r,
        startScreen: 'home',
      );
      c.startFlow('sales', <String, String>{
        'sParty': 'Mehta Electricals',
        'sDate': '2026-10-03',
      });
      c.togglePickItem(r.items().firstWhere((Item x) => x.name == 'Wire'));
      c.update(() {
        c.overlay = null;
        c.flowStep = 1;
      });
      await t.pumpWidget(
        ProviderScope(
          overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
          child: const TallyConnectApp(),
        ),
      );
      for (int i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Edit rate / GST'), findsNothing);
      expect(find.text('GST 18%'), findsOneWidget);
      final Finder amt = find.byKey(const ValueKey<String>('lineAmt0'));
      // A single tap does nothing.
      await t.tap(amt);
      await t.pump(const Duration(milliseconds: 400));
      expect(c.overlay, isNull);
      // Double-tap: the rate editor.
      await t.tap(amt);
      await t.pump(const Duration(milliseconds: 60));
      await t.tap(amt);
      await t.pump(const Duration(milliseconds: 400));
      expect(c.overlay, 'lineEdit');
      expect(c.lineEditField, 'rate');
      expect(
        find.textContaining('Rate (₹ per Coil)', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('GST %', findRichText: true), findsNothing);
      c.closeOv();
      await t.pump(const Duration(milliseconds: 400));
      // Tap on the GST: the GST editor.
      await t.tap(find.byKey(const ValueKey<String>('lineGst0')));
      await t.pump(const Duration(milliseconds: 400));
      expect(c.overlay, 'lineEdit');
      expect(c.lineEditField, 'gst');
      expect(
        find.textContaining('GST %', findRichText: true),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      c.closeOv();
      await t.pump(const Duration(seconds: 6));
    });
  });
}
