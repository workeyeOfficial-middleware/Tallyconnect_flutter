// Date range filter: vouchers (list, hub, totals), outstanding receivables
// / payables, reports (Day Book, Sales / Purchase lists, Top customers) —
// From–To both included, exact totals, read month by month from the
// existing `/voucher-entry/paged` year / month filter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/share/report_data.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/core/utils/format.dart';
import 'package:tallyconnect_ui/data/accounting.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart';
import 'package:tallyconnect_ui/data/repositories/tally_repository.dart';
import 'package:tallyconnect_ui/data/repositories/voucher_pager.dart'
    show FetchedPage;
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

/// A server that honours year / month like `/voucher-entry/paged`
/// (newest first, [per] rows a page) and records the months asked for.
class _MonthServer {
  _MonthServer(this.all);
  final List<Voucher> all;

  /// Rows per page (small, so a month spans several pages).
  static const int per = 2;
  final List<String> asked = <String>[];

  Future<FetchedPage> fetch(int page, VoucherQuery q, DateTime t) async {
    final DateTime? m = q.ym;
    asked.add(m == null ? 'all' : '${m.year}-${m.month}');
    final List<Voucher> rows =
        all
            .where(
              (Voucher v) =>
                  m == null ||
                  (v.date!.year == m.year && v.date!.month == m.month),
            )
            .toList()
          ..sort((Voucher a, Voucher b) => b.date!.compareTo(a.date!));
    final List<Voucher> pg = rows.skip((page - 1) * per).take(per).toList();
    return FetchedPage(
      pg,
      <String>[for (final Voucher v in pg) v.guid!],
      page * per < rows.length,
    );
  }
}

Voucher _v(String g, DateTime d, num amt, [String kind = 'sales']) => Voucher(
  kind,
  'P$g',
  g,
  d.day,
  amt,
  date: d,
  guid: g,
  type: kind == 'sales' ? 'Sales' : 'Receipt',
);

void main() {
  group('DateRange', () {
    test('both ends included; months newest first across a year end', () {
      final DateRange r = DateRange(
        DateTime(2025, 12, 15, 18),
        DateTime(2026, 2, 10),
      );
      expect(r.contains(DateTime(2025, 12, 15)), isTrue);
      expect(r.contains(DateTime(2026, 2, 10, 23, 59)), isTrue);
      expect(r.contains(DateTime(2025, 12, 14)), isFalse);
      expect(r.contains(DateTime(2026, 2, 11)), isFalse);
      expect(r.contains(null), isFalse);
      expect(r.monthsNewestFirst, <DateTime>[
        DateTime(2026, 2),
        DateTime(2026),
        DateTime(2025, 12),
      ]);
      expect(DateRange.parse(r.period), r);
      expect(DateRange.parse('month'), isNull);
      expect(r.label, '15 Dec 2025 – 10 Feb 2026');
    });
  });

  group('pager reads only the range’s months', () {
    test('exact rows, newest first, no month outside the range', () async {
      final List<Voucher> data = <Voucher>[
        _v('a', DateTime(2025, 11, 30), 1),
        _v('b', DateTime(2025, 12, 14), 2),
        _v('c', DateTime(2025, 12, 15), 3.10),
        _v('d', DateTime(2025, 12, 31), 4.20),
        _v('e', DateTime(2026, 1, 5), 5.30, 'receipt'),
        _v('f', DateTime(2026, 1, 20), 6.40),
        _v('g', DateTime(2026, 1, 21), 7.50),
        _v('h', DateTime(2026, 2, 10), 8.60),
        _v('i', DateTime(2026, 2, 11), 9),
        _v('j', DateTime(2026, 3, 1), 10),
      ];
      final _MonthServer s = _MonthServer(data);
      final DateRange r = DateRange(DateTime(2025, 12, 15), DateTime(2026, 2, 10));
      final VoucherPager pg = VoucherPager(
        VoucherQuery(period: 'range', range: r),
        s.fetch,
        DateTime(2026, 3, 5),
      );
      while (pg.hasMore) {
        await pg.loadMore(minNew: 1 << 30);
      }
      expect(pg.complete, isTrue);
      expect(pg.rows.map((Voucher v) => v.guid), <String>[
        'h',
        'g',
        'f',
        'e',
        'd',
        'c',
      ]);
      expect(s.asked.toSet(), <String>{'2026-2', '2026-1', '2025-12'});
      expect(pg.loadedTotal, 35.10);
      // A kind filter inside the range.
      final _MonthServer s2 = _MonthServer(data);
      final VoucherPager rc = VoucherPager(
        VoucherQuery(filter: 'receipt', period: 'range', range: r),
        s2.fetch,
        DateTime(2026, 3, 5),
      );
      while (rc.hasMore) {
        await rc.loadMore(minNew: 1 << 30);
      }
      expect(rc.rows.map((Voucher v) => v.guid), <String>['e']);
    });
  });

  group('server (simulated backend)', () {
    test(
      'range list and totals: only October pages, same as the month set',
      () async {
        final FakeBackend f = FakeBackend();
        final ApiTallyRepository r = f.repo();
        await r.login('ravi@x.in', 'secret', 'ADMIN');
        await r.refreshAll();
        await r.ensure(DataSet.vouchers);
        final DateRange rg = DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 2));
        final int before = f.to('/voucher-entry/paged').length;
        await r.loadVoucherCounts(rg.period);
        final VoucherCounts? vc = r.voucherCounts(rg.period);
        expect(vc, isNotNull);
        expect(vc!.error, isNull);
        // Same vouchers counted from the complete month set on the phone.
        final VoucherCounts want = VoucherCounts.of(
          r.vouchers().where((Voucher v) => rg.contains(v.date)),
        );
        expect(vc.forFilter('all'), want.forFilter('all'));
        expect(vc.amountFor('all'), want.amountFor('all'));
        expect(vc.amountFor('sales'), want.amountFor('sales'));
        expect(vc.forFilter('all'), greaterThan(0));
        // Every range request used the server's year / month filter.
        final List<http.Request> sent = f
            .to('/voucher-entry/paged')
            .skip(before)
            .toList();
        expect(sent, isNotEmpty);
        for (final http.Request q in sent) {
          expect(q.url.queryParameters['year'], '2026');
          expect(q.url.queryParameters['month'], '10');
        }
        expect(f.violations, isEmpty);

        // Reports: Sales list for the range (rows read so far / all).
        final AppController c = AppController(
          store: LocalStorage.memory(),
          repo: r,
          startScreen: 'home',
        );
        c.openRange('rep');
        c.setF('drFrom', '2026-10-01');
        c.setF('drTo', '2026-10-02');
        c.applyRange();
        expect(c.repPeriod, 'range');
        expect(
          c.periodAmountText('range', 'sales'),
          inr(want.amountFor('sales')),
        );
        final ReportData d = reportData(
          r,
          'sreg',
          period: 'range',
          range: rg,
          loaded: const <Voucher>[],
        );
        expect(d.total, inr(want.amountFor('sales')));
        expect(d.partial, isTrue);
        expect(d.period, startsWith('01 Oct 2026 – 02 Oct 2026'));
        c.dispose();
      },
    );
  });

  group('sample data', () {
    final TallyRepository repo = MockTallyRepository();
    final DateRange rg = DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 10));

    test('vouchers: totals of exactly the vouchers in the range', () {
      final AppController c = AppController(store: LocalStorage.memory());
      c.openRange('v');
      c.setF('drFrom', '2026-09-01');
      c.setF('drTo', '2026-09-10');
      c.applyRange();
      expect(c.vPeriod, 'range');
      final List<Voucher> inR = c.repo
          .vouchers()
          .where((Voucher v) => rg.contains(v.date))
          .toList();
      expect(inR, isNotEmpty);
      expect(
        c.periodAmount('range', 'all'),
        sumRupees(inR.map((Voucher v) => v.amt)),
      );
      expect(
        c.periodAmount('range', 'receipt'),
        sumRupees(
          inR.where((Voucher v) => v.kind == 'receipt').map((Voucher v) => v.amt),
        ),
      );
      c.clearRange('v');
      expect(c.vPeriod, 'all');
      c.dispose();
    });

    test('outstanding: bills dated in the range, exact totals', () {
      final AppController c = AppController(store: LocalStorage.memory());
      expect(c.inOutRange(c.repo.receivables()), c.repo.receivables());
      c.openRange('out');
      c.setF('drFrom', '2026-09-01');
      c.setF('drTo', '2026-09-10');
      c.applyRange();
      expect(c.outRange, isTrue);
      final List<Bill> got = c.inOutRange(c.repo.receivables());
      final List<Bill> want = c.repo
          .receivables()
          .where((Bill b) => rg.contains(b.billDate))
          .toList();
      expect(got, want);
      expect(got.length, lessThan(c.repo.receivables().length));
      expect(
        summarise(got, c.today).total,
        sumRupees(want.map((Bill b) => b.amt)),
      );
      c.clearRange('out');
      expect(c.outRange, isFalse);
      c.dispose();
    });

    test('Top customers: only bills dated in the range', () {
      final ReportData all = reportData(repo, 'top');
      final ReportData d = reportData(repo, 'top', period: 'range', range: rg);
      final Map<String, num> by = sumByRupees(<(String, num)>[
        for (final Bill b in repo.receivables())
          if (rg.contains(b.billDate)) (b.party, b.amt),
      ]);
      final List<num> top = (by.values.toList()..sort((num a, num b) => b.compareTo(a)))
          .take(5)
          .toList();
      expect(d.total, inr(sumRupees(top)));
      expect(d.rows.length, top.length);
      expect(d.total, isNot(all.total));
      expect(d.period, rg.label);
    });

    test('Day Book: entries in the range; chart per day', () {
      final ReportData d = reportData(repo, 'day', period: 'range', range: rg);
      final List<Voucher> inR = repo
          .vouchers()
          .where((Voucher v) => rg.contains(v.date))
          .toList();
      expect(d.rows.length, inR.length);
      expect(d.total, inr(sumRupees(inR.map((Voucher v) => v.amt))));
      expect(d.points.every((ChartPoint x) => x.label.endsWith('Sep')), isTrue);
    });

    test('a range ending before it starts cannot be applied', () {
      final AppController c = AppController(store: LocalStorage.memory());
      c.openRange('v');
      c.setF('drFrom', '2026-09-10');
      c.setF('drTo', '2026-09-01');
      expect(c.rangeError, contains('on or before'));
      c.applyRange();
      expect(c.vPeriod, isNot('range'));
      expect(c.overlay, 'dateRange');
      c.dispose();
    });

    test('range and the Reports choice are kept on the phone', () {
      final LocalStorage s = LocalStorage.memory();
      final AppController c = AppController(store: s);
      c.openRange('rep');
      c.rangePreset('last');
      c.applyRange();
      final DateRange? r = c.range;
      c.dispose();
      final AppController c2 = AppController(store: s);
      expect(c2.range, r);
      expect(c2.repPeriod, 'range');
      c2.dispose();
    });
  });

  group('screens', () {
    setUpAll(loadFigtree);

    testWidgets('pick, apply and remove a range on every page', (
      WidgetTester t,
    ) async {
      t.view.physicalSize = const Size(360 * 3, 800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final AppController c = AppController(
        store: LocalStorage.memory(),
        startScreen: 'home',
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
          child: const TallyConnectApp(),
        ),
      );
      Future<void> settle() async {
        for (int i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> pickThisMonth() async {
        expect(find.text('Date range'), findsWidgets);
        await t.tap(find.text('This month').last);
        await settle();
        await t.tap(find.text('Apply'));
        await settle();
        expect(c.overlay, isNull);
        expect(t.takeException(), isNull);
      }

      // Vouchers hub: the option under the period choices.
      c.jump('vHub');
      await settle();
      await t.tap(find.byKey(const ValueKey<String>('range-v')));
      await settle();
      expect(c.overlay, 'dateRange');
      await pickThisMonth();
      expect(c.vPeriod, 'range');
      expect(find.text(c.range!.label), findsOneWidget);
      // Voucher list keeps it.
      c.go('vList', <String, Object?>{'vFilter': 'sales', 'vPeriod': 'range'});
      await settle();
      expect(find.text(c.range!.label), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('range-clear-v')));
      await settle();
      expect(c.vPeriod, 'all');

      // Outstanding: calendar button beside search / Share.
      c.jump('outHub');
      await settle();
      await t.tap(find.byKey(const ValueKey<String>('outRangeBtn')));
      await settle();
      await pickThisMonth();
      expect(c.outRange, isTrue);
      c.go('outList', <String, Object?>{'outKind': 'recv'});
      await settle();
      expect(find.text(c.range!.label), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey<String>('range-clear-out')));
      await settle();
      expect(c.outRange, isFalse);

      // Reports and Top customers.
      c.jump('reports');
      await settle();
      await t.tap(find.byKey(const ValueKey<String>('range-rep')));
      await settle();
      await pickThisMonth();
      expect(c.repPeriod, 'range');
      for (final String id in <String>['top', 'day', 'sreg', 'preg', 'stock']) {
        c.go('report', <String, Object?>{'report': id});
        await settle();
        expect(t.takeException(), isNull, reason: id);
        c.back();
        await settle();
      }
      await t.pump(const Duration(seconds: 6));
    });
  });
}
