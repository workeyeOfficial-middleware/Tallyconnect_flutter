// Financial accuracy (exact paise sums, totals refreshed after a Tally
// sync, never a stale or doubtful figure) and phone notifications for new
// server alerts.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/core/notify/reminder_alarms.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/core/utils/format.dart';
import 'package:tallyconnect_ui/data/accounting.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart';
import 'package:tallyconnect_ui/data/repositories/voucher_pager.dart';

import 'api_integration_test.dart' show FakeBackend;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('exact sums', () {
    test('paise sums never drift', () {
      // 0.1 + 0.2 style errors over 100,000 values.
      final List<num> vs = List<num>.filled(100000, 0.1);
      expect(sumRupees(vs), 10000);
      expect(inr(sumRupees(<num>[285694078.63, 87])), '₹28,56,94,165.63');
      final VoucherCounts c = VoucherCounts.of(<Voucher>[
        for (int i = 0; i < 50000; i++)
          const Voucher('receipt', 'P', 'R', 1, 5714.88),
        const Voucher('receipt', 'P', 'R', 1, 87),
      ]);
      expect(c.amountFor('receipt'), 285744087);
      final OutstandingSummary s = summarise(<Bill>[
        for (int i = 0; i < 30000; i++)
          const Bill('A', 'B', '', '', '', 0.1, 'ok', '', ''),
      ], DateTime(2026, 10, 9));
      expect(s.total, 3000);
    });
  });

  group('totals follow Tally syncs', () {
    test('new ₹87 receipt synced → All-time Receipt total updates', () async {
      final FakeBackend f = FakeBackend()
        ..typeTotals = <String, num>{
          'Receipt': 285694078.63,
          'Payment': 1000,
          'Sales': 500.5,
          'Sales Order': 0,
        };
      final ApiTallyRepository r = f.repo();
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      final AppController c = AppController(
        store: LocalStorage.memory(),
        repo: r,
        startScreen: 'home',
      );
      await r.loadVoucherCounts('all');
      expect(c.periodAmount('all', 'receipt'), 285694078.63);

      // Agent syncs a new ₹87 receipt.
      f.typeTotals!['Receipt'] = 285694165.63;
      f.lastSync = '2026-10-03T05:00:00.000Z';
      await c.liveCheck();
      // Old figure is never shown while recounting.
      expect(r.voucherCounts('all')!.amountFor('receipt'), isNull);
      await r.loadVoucherCounts('all');
      expect(c.periodAmount('all', 'receipt'), 285694165.63);
      expect(inr(c.periodAmount('all', 'receipt')), '₹28,56,94,165.63');
      c.dispose();
    });

    test('mixed-sign server sums → amounts unavailable, not wrong', () async {
      final FakeBackend f = FakeBackend()
        ..typeTotals = <String, num>{'Receipt': 1000, 'Payment': -400};
      final ApiTallyRepository r = f.repo();
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      await r.loadVoucherCounts('all');
      final VoucherCounts vc = r.voucherCounts('all')!;
      expect(vc.amountsUnsure, isTrue);
      expect(vc.amountFor('receipt'), isNull);
      expect(vc.forFilter('all'), isNotNull); // counts stay exact
    });

    test('no new sync → no reload', () async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      expect(await r.checkNewSync(), isFalse);
      f.lastSync = '2026-10-03T06:00:00.000Z';
      expect(await r.checkNewSync(), isTrue);
      expect(await r.checkNewSync(), isFalse);
    });
  });

  group('server alerts as phone notifications', () {
    test('existing alerts not flooded; a new one pops up once', () async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      final NoReminderAlarms dev = NoReminderAlarms();
      final AppController c = AppController(
        store: LocalStorage.memory(),
        repo: r,
        startScreen: 'home',
        alarms: dev,
      );
      await r.refreshNotifications();
      // Tests run with no lifecycle state (not "resumed"): background.
      expect(dev.shown, isEmpty); // first look: only remembered
      f.moreNotifs.add(<String, Object?>{
        'id': 9,
        'title': 'Entry Created',
        'message': 'Receipt | ₹87 | Mehta | queued for Tally sync',
        'is_read': false,
        'created_at': '2026-10-03T06:00:00.000Z',
        'type': 'create_entry',
      });
      await r.refreshNotifications();
      expect(dev.shown, hasLength(1));
      expect(dev.shown.single.$1, 'Entry Created');
      expect(dev.shown.single.$3, 'alert:9');
      await r.refreshNotifications(); // not again
      expect(dev.shown, hasLength(1));
      c.dispose();
    });
  });
}
