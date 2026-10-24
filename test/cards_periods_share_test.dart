// Standard report periods (All time … Previous financial year, custom
// range) on every report; graphs on Cash Flow, Expenses and Tally's own
// reports; cards (pin / hide / share / drag) on the financial statement
// tiles, voucher type tiles and Receivable / Payable cards; several bills
// shared together; AI answers and the whole chat shared on WhatsApp.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/share/report_data.dart' show ChartPoint;
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/core/utils/periods.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';
import 'package:tallyconnect_ui/presentation/overlays/assistant_answer.dart';
import 'package:tallyconnect_ui/presentation/screens/fin_charts.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;
import 'share_chart_test.dart' show FakeExporter;

Future<AppController> _start(
  FakeBackend f, {
  List<Uri>? opened,
  FakeExporter? exporter,
}) async {
  final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
  await r.login('ravi@x.in', 'secret', 'ADMIN');
  await r.refreshAll();
  final AppController c = AppController(
    store: LocalStorage.memory(),
    repo: r,
    startScreen: 'home',
    exporter: exporter,
    linkOpener: (Uri u) async {
      opened?.add(u);
      return true;
    },
  );
  c.afterRefresh(quietOk: true);
  return c;
}

num _sum(FinChartSet s) =>
    s.points.fold<num>(0, (num a, ChartPoint p) => a + p.value);

void main() {
  group('standard periods', () {
    test('the list and each range (Indian financial year)', () {
      expect(kStdPeriods.map(((String, String) p) => p.$2), <String>[
        'All time',
        'Today',
        'Yesterday',
        'Last 7 days',
        'This month',
        'Next month',
        'Current financial year',
        'Previous financial year',
      ]);
      final DateTime t = DateTime(2026, 10, 12);
      expect(stdPeriodRange('all', t), isNull);
      expect(stdPeriodRange('today', t), (t, t));
      expect(stdPeriodRange('yesterday', t), (
        DateTime(2026, 10, 11),
        DateTime(2026, 10, 11),
      ));
      expect(stdPeriodRange('week', t), (DateTime(2026, 10, 6), t));
      expect(stdPeriodRange('month', t), (DateTime(2026, 10), t));
      expect(stdPeriodRange('next', t), (
        DateTime(2026, 11),
        DateTime(2026, 11, 30),
      ));
      expect(stdPeriodRange('fy', t), (DateTime(2026, 4), t));
      expect(stdPeriodRange('pfy', t), (
        DateTime(2025, 4),
        DateTime(2026, 3, 31),
      ));
      // January: the year started last April; December runs into January.
      final DateTime j = DateTime(2026, 1, 5);
      expect(stdPeriodRange('fy', j)!.$1, DateTime(2025, 4));
      expect(stdPeriodRange('pfy', j), (
        DateTime(2024, 4),
        DateTime(2025, 3, 31),
      ));
      expect(stdPeriodRange('next', DateTime(2026, 12, 20)), (
        DateTime(2027),
        DateTime(2027, 1, 31),
      ));
    });

    test('vouchers, reports, outstanding and sales all offer them', () async {
      final AppController c = await _start(FakeBackend());
      expect(AppController.kPeriodBar, kStdPeriods);
      c.pickPeriod('v', 'yesterday');
      expect(c.vPeriod, 'range');
      expect(c.periodSel('v'), 'yesterday');
      c.pickPeriod('v', 'week'); // natively, as before
      expect(c.vPeriod, 'week');
      c.pickPeriod('rep', 'pfy');
      expect(c.repPeriod, 'range');
      expect(c.periodSel('rep'), 'pfy');
      c.pickPeriod('out', 'fy');
      expect(c.outRange, isTrue);
      expect(c.periodSel('out'), 'fy');
      expect(
        AppController.kSalesPresets.map(((String, String) p) => p.$1),
        <String>['today', 'yesterday', 'week', 'month', 'next', 'fy', 'pfy'],
      );
      await c.setSalesPreset('pfy');
      final (DateTime, DateTime) pfy = stdPeriodRange('pfy', c.today)!;
      expect(c.salesRange.from, pfy.$1);
      expect(c.salesRange.to, pfy.$2);
      c.dispose();
    });
  });

  group('graphs', () {
    test('Cash Flow: by group, by month, in vs out — the listed figures', () {
      final FinReport r = FinReport('cf', <String, Object?>{
        'inflow': 1500,
        'outflow': 700,
        'inflow_groups': <Object?>[
          <String, Object?>{'name': 'Sundry Debtors', 'amount': 1200},
          <String, Object?>{'name': 'Capital Account', 'amount': 300},
        ],
        'outflow_groups': <Object?>[
          <String, Object?>{'name': 'Sundry Creditors', 'amount': 700},
        ],
        'months': <Object?>[
          <String, Object?>{'month': '2026-09', 'inflow': 500, 'outflow': 200},
          <String, Object?>{'month': '2026-10', 'inflow': 1000, 'outflow': 500},
        ],
      });
      final List<FinChartSet> s = finChartSets(r, 'cf');
      expect(s.map((FinChartSet x) => x.key), <String>[
        'inflow',
        'outflow',
        'monthIn',
        'monthOut',
        'compare',
      ]);
      expect(_sum(s[0]), 1500);
      expect(_sum(s[1]), 700);
      expect(_sum(s[2]), 1500);
      expect(s[2].points.first.label, 'Sep 26');
      expect(s.last.adds, isFalse);
    });

    test('Expenses: by group (= total), top ledgers, by month', () {
      final FinReport r = FinReport('exp', <String, Object?>{
        'total': 900,
        'sections': <Object?>[
          <String, Object?>{'name': 'Indirect Expenses', 'amount': 600},
          <String, Object?>{'name': 'Direct Expenses', 'amount': 300},
        ],
        'top_ledgers': <Object?>[
          <String, Object?>{'name': 'Rent', 'amount': 400},
        ],
        'by_month': <Object?>[
          <String, Object?>{'as_on': '2026-09-30', 'amount': 400},
          <String, Object?>{'as_on': '2026-10-12', 'amount': 500},
        ],
      });
      final List<FinChartSet> s = finChartSets(r, 'exp');
      expect(_sum(s.first), r.n('total'));
      expect(s[1].adds, isFalse); // top ledgers are not all of it
      expect(_sum(s[2]), 900);
      expect(finChartSets(r, 'unknown'), isEmpty);
    });

    test("Tally's own reports: each side exactly as listed", () {
      final TallyReport bs = TallyReport.fromJson(<String, Object?>{
        'report': 'balance_sheet',
        'rows': <Object?>[
          <String, Object?>{
            'name': 'Capital Account',
            'amounts': <String, Object?>{'BSMAINAMT': 1000},
          },
          <String, Object?>{
            'name': 'Current Assets',
            'amounts': <String, Object?>{'BSMAINAMT': -1000},
          },
        ],
      });
      final List<FinChartSet> s = tallyChartSets(bs);
      expect(s.map((FinChartSet x) => x.key), <String>[
        'liabilities',
        'assets',
      ]);
      expect(_sum(s[0]), 1000);
      expect(_sum(s[1]), 1000);
    });
  });

  group('cards', () {
    test(
      'financial tiles / voucher types / receivable cards: pin, hide, share',
      () async {
        final FakeExporter ex = FakeExporter();
        final AppController c = await _start(FakeBackend(), exporter: ex);
        // Pinned first, hidden left out (the same list preferences as rows).
        final ({List<String> rows, int hidden, VoidCallback unhide}) v0 = c
            .listView<String>('fin', <String>[
              'bs',
              'pl',
              'tb',
            ], (String k) => k);
        expect(v0.rows, <String>['bs', 'pl', 'tb']);
        c.updPref('fin', (ListPref p) => p.pinned.add('tb'));
        c.updPref('fin', (ListPref p) => p.hidden.add('pl'));
        final ({List<String> rows, int hidden, VoidCallback unhide}) v = c
            .listView<String>('fin', <String>[
              'bs',
              'pl',
              'tb',
            ], (String k) => k);
        expect(v.rows, <String>['tb', 'bs']);
        expect(v.hidden, 1);
        v.unhide();
        expect(c.listPrefs['fin']!.hidden, isEmpty);

        expect(c.infoFor('fin', 'bs')!.label, 'Balance Sheet');
        expect(c.infoFor('fin', 'cfcast')!.label, 'Cash Flow Forecast');
        expect(c.infoFor('vtypes', 'sales')!.label, isNotEmpty);
        expect(
          c.infoFor('vtypes', 'type:Stock Journal')!.label,
          'Stock Journal',
        );
        expect(c.infoFor('outCards', 'pay')!.label, 'Payable');
        expect(c.docForCard('outCards', 'recv'), isNotNull);
        expect(c.docForCard('vtypes', 'all'), isNotNull);
        c.dispose();
      },
    );
  });

  group('several bills shared together', () {
    test('select → one WhatsApp message; list PDF; one PDF each', () async {
      final List<Uri> opened = <Uri>[];
      final FakeExporter ex = FakeExporter();
      final AppController c = await _start(
        FakeBackend(),
        opened: opened,
        exporter: ex,
      );
      final List<Bill> rows = c.repo
          .receivables()
          .map((Bill b) => b.withKind('recv'))
          .toList();
      expect(rows, hasLength(2));
      c.go('outList', <String, Object?>{'outKind': 'recv', 'outFilter': 'all'});
      c.startBillSelect();
      c.toggleBillPicked(rows.first);
      c.selectAllBills(rows);
      expect(c.bPicked, hasLength(2));
      expect(c.pickedBillsTotal, 15000.5);
      await c.whatsAppPickedBills();
      final String text = Uri.decodeComponent(opened.single.query);
      expect(text, contains('Dear Mehta Electricals,'));
      expect(text, contains('S/101'));
      expect(text, contains('S/102'));
      expect(text, contains('*Total: ₹15,000.50*'));
      await c.sharePickedBillsList();
      expect(ex.shared.single, contains('Receivable'));
      await c.sharePickedBillsEach();
      expect(ex.sharedMany.single, hasLength(2));
      // Leaving the list ends selecting.
      c.go('home');
      expect(c.bSelecting, isFalse);
      expect(c.bPicked, isEmpty);
      c.dispose();
    });
  });

  group('AI assistant on WhatsApp', () {
    const List<AiTurn> turns = <AiTurn>[
      AiTurn('user', 'Who owes me the most?'),
      AiTurn(
        'model',
        '## Top debtors\n- **Mehta** owes the most',
        blocks: <AiBlock>[
          AiBlock.kpis('Outstanding as on 2026-10-12', <AiKpi>[
            AiKpi('Total', 15000.5, format: 'money'),
          ]),
          AiBlock.table(
            'Parties',
            <AiColumn>[AiColumn('Party'), AiColumn('Due', format: 'money')],
            <List<Object?>>[
              <Object?>['Mehta', 15000.5],
            ],
            totalRows: 3,
          ),
        ],
      ),
      AiTurn('model', 'Network error', error: true),
    ];

    test('one answer (with its question) and the whole chat', () {
      final String one = aiMessageShare(turns, 1, 'Rajlaxmi Traders');
      expect(one, startsWith('*Q:* Who owes me the most?'));
      expect(one, contains('*Outstanding as on 12 Oct 2026*'));
      expect(one, contains('• Total: ₹15,000.50'));
      expect(one, contains('*Top debtors*'));
      expect(one, contains('• *Mehta* owes the most'));
      expect(one, contains('• Mehta · ₹15,000.50'));
      expect(one, contains('…2 more'));
      expect(one, endsWith('— TallyConnect AI · Rajlaxmi Traders'));
      final String all = aiChatShare(turns, 'Rajlaxmi Traders');
      expect(all, startsWith('*TallyConnect AI · Rajlaxmi Traders*'));
      expect(all, contains('*Q:* Who owes me the most?'));
      expect(all, isNot(contains('Network error'))); // failures left out
    });

    test('opens WhatsApp with the text', () async {
      final List<Uri> opened = <Uri>[];
      final AppController c = await _start(FakeBackend(), opened: opened);
      await c.shareAiOnWhatsApp(aiChatShare(turns, 'Rajlaxmi Traders'));
      expect(opened.single.host, 'wa.me');
      expect(
        Uri.decodeComponent(opened.single.query),
        contains('Who owes me the most?'),
      );
      c.dispose();
    });
  });

  group('screens', () {
    setUpAll(loadFigtree);

    for (final double w in <double>[320, 412]) {
      testWidgets('cards, bill selection, periods at ${w.toInt()} px', (
        WidgetTester t,
      ) async {
        t.view.physicalSize = Size(w * 3, 760 * 3);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        final FakeBackend f = FakeBackend()..finAnyPeriod = true;
        final AppController c = await _start(f);
        await t.pumpWidget(
          ProviderScope(
            overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
            child: const TallyConnectApp(),
          ),
        );
        Future<void> settle() async {
          for (int i = 0; i < 8; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }

        await c.checkFinancialAccess();
        c.go('reports');
        c.setRepTab('fin');
        await settle();
        expect(find.byKey(const ValueKey<String>('fin-bs')), findsOneWidget);
        expect(t.takeException(), isNull);

        c.go('vHub');
        await settle();
        expect(t.takeException(), isNull);
        c.go('outHub');
        await settle();
        expect(t.takeException(), isNull);

        c.go('outList', <String, Object?>{
          'outKind': 'recv',
          'outFilter': 'all',
        });
        await settle();
        // The period row: every standard period and the custom range.
        expect(
          find.byKey(const ValueKey<String>('period-out-pfy')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey<String>('range-out')), findsOneWidget);
        final Finder sel = find.byKey(const ValueKey<String>('bSelect'));
        await t.scrollUntilVisible(
          sel,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await settle();
        await t.tap(sel);
        await settle();
        expect(c.bSelecting, isTrue);
        final Bill b = c.repo.receivables().first;
        await t.tap(find.byKey(ValueKey<String>('bPick-${b.key}')));
        await settle();
        expect(c.bPicked, hasLength(1));
        expect(
          find.byKey(const ValueKey<String>('bSelectBarFloat')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);

        await t.pump(const Duration(seconds: 6));
      });
    }
  });
}
