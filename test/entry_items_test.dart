// Create Entry items: Tally item data fills the line, quantity / rate / GST
// are edited for this voucher only, and exactly those values are queued.
// Also the stock-value sign read from Tally's export.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/api/adapters.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart';

import 'api_integration_test.dart' show FakeBackend;

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
      c.openLineEdit(0);
      expect(c.overlay, 'lineEdit');
      expect(c.f('leRate'), '5000');
      expect(c.f('leGst'), '18');
      // Invalid values are refused.
      c.setF('leRate', '0');
      expect(c.lineEditError, isNotNull);
      c.saveLineEdit();
      expect(c.lines['sales']!.single.rate, 5000);
      // Valid edit.
      c.setF('leRate', '4800.5');
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
      c.setF('leGst', '18');
      c.saveLineEdit();
      expect(c.flowBlocker, isNull);
      expect(item(r, 'Pipe').rate, 0); // master unchanged
      c.dispose();
    });
  });
}
