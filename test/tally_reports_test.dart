// Official Tally reports: a statement tile opens Tally's own figures when
// the Agent has fetched them (else the calculated report, as before), the
// periods, the sides check, group → ledger drill-down, Cash Flow, errors,
// the screens at 320 px and the PDF.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/share/share_doc.dart' show ShareDoc;
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';
import 'package:tallyconnect_ui/presentation/screens/tally_report_screens.dart'
    show drCr, tagLabel, tallyReportDoc;

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

const List<Object?> _bs = <Object?>[
  <String, Object?>{
    'name': 'Capital Account',
    'tag': 'DSPDISPNAME',
    'amounts': <String, Object?>{'BSMAINAMT': 150000},
    'ledgers': <Object?>[
      <String, Object?>{
        'name': 'Capital',
        'group': 'Capital Account',
        'amount': 150000,
      },
    ],
  },
  <String, Object?>{
    'name': 'Current Liabilities',
    'tag': 'DSPDISPNAME',
    'amounts': <String, Object?>{'BSMAINAMT': 25000.5},
  },
  <String, Object?>{
    'name': 'Current Assets',
    'tag': 'DSPDISPNAME',
    'amounts': <String, Object?>{'BSMAINAMT': -175000.5},
    'ledgers': <Object?>[
      <String, Object?>{
        'name': 'HDFC Bank',
        'group': 'Bank Accounts',
        'amount': -172500.5,
      },
      <String, Object?>{
        'name': 'Cash',
        'group': 'Cash-in-Hand',
        'amount': -2500,
      },
    ],
  },
];

const List<Object?> _tb = <Object?>[
  <String, Object?>{
    'name': 'Cash',
    'parent': 'Cash-in-Hand',
    'opening': -1000,
    'closing': -2500,
  },
  <String, Object?>{
    'name': 'HDFC Bank',
    'parent': 'Bank Accounts',
    'opening': 0,
    'closing': -172500.5,
  },
  <String, Object?>{
    'name': 'Capital',
    'parent': 'Capital Account',
    'opening': 150000,
    'closing': 150000,
  },
  <String, Object?>{
    'name': 'Polycab',
    'parent': 'Sundry Creditors',
    'opening': 0,
    'closing': 25000.5,
  },
];

const List<Object?> _cf = <Object?>[
  <String, Object?>{
    'name': 'April',
    'tag': 'DSPPERIOD',
    'amounts': <String, Object?>{'DSPINFLOW': 50000, 'DSPOUTFLOW': -20000},
  },
  <String, Object?>{
    'name': 'Grand Total',
    'tag': 'DSPPERIOD',
    'amounts': <String, Object?>{},
  },
];

FakeBackend _fake({bool withTally = true}) {
  final FakeBackend f = FakeBackend();
  if (withTally) {
    f.tallyReports['balance_sheet'] = <Map<String, Object?>>[
      <String, Object?>{'from': '2026-04-01', 'to': '2026-10-03', 'rows': _bs},
      <String, Object?>{
        'from': '2025-04-01',
        'to': '2026-03-31',
        'rows': _bs.sublist(1),
      },
    ];
    f.tallyReports['trial_balance'] = <Map<String, Object?>>[
      <String, Object?>{'from': '2026-04-01', 'to': '2026-10-03', 'rows': _tb},
    ];
    f.tallyReports['cash_flow'] = <Map<String, Object?>>[
      <String, Object?>{'from': '2026-04-01', 'to': '2026-10-03', 'rows': _cf},
    ];
  }
  return f;
}

Future<AppController> _start(FakeBackend f) async {
  final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
  await r.login('ravi@x.in', 'secret', 'ADMIN');
  await r.refreshAll();
  final AppController c = AppController(
    store: LocalStorage.memory(),
    repo: r,
    startScreen: 'home',
  );
  c.afterRefresh(quietOk: true);
  return c;
}

void main() {
  group('controller', () {
    test(
      'tile opens Tally figures when fetched, else the calculated report',
      () async {
        final FakeBackend f = _fake();
        final AppController c = await _start(f);
        await c.checkFinancialAccess(force: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(c.hasTallyReport('bs'), isTrue);
        expect(c.hasTallyReport('pl'), isFalse); // not fetched yet
        await c.openStatement('bs');
        expect(c.screen, 'tallyReport');
        final TallyReport r = c.trData!;
        expect(r.title, 'Balance Sheet');
        expect(r.to, DateTime(2026, 10, 3));
        expect(r.rows.map((TallyRow x) => x.main), <num>[
          150000,
          25000.5,
          -175000.5,
        ]);
        expect(r.rows[2].ledgers.map((TallyLedger l) => l.name), <String>[
          'HDFC Bank',
          'Cash',
        ]);
        expect(r.balanced, isTrue);
        expect(r.fetchSeconds, 12.4);

        // Another period: last year's close (sides differ there).
        await c.setTallyPeriod(c.trPeriods!.of('balance_sheet')[1]);
        expect(c.trData!.to, DateTime(2026, 3, 31));
        expect(c.trData!.balanced, isFalse);
        expect(c.trData!.difference, 150000);

        // P&L not fetched from Tally: the calculated report, as before.
        await c.openStatement('pl');
        expect(c.screen, 'finReport');
        // Expenses: always calculated.
        await c.openStatement('exp');
        expect(c.screen, 'finReport');
        c.dispose();
      },
    );

    test('Trial Balance and Cash Flow from Tally', () async {
      final AppController c = await _start(_fake());
      await c.checkFinancialAccess(force: true);
      await c.openStatement('tb');
      final TallyReport tb = c.trData!;
      expect(tb.ledgers, hasLength(4));
      expect((tb.debit, tb.credit, tb.balanced), (175000.5, 175000.5, true));
      await c.openStatement('cf');
      expect(c.trData!.rows.first.amounts, <String, num>{
        'DSPINFLOW': 50000,
        'DSPOUTFLOW': -20000,
      });
      c.dispose();
    });

    test(
      'nothing fetched yet / older server / no access: clear messages',
      () async {
        final AppController c = await _start(_fake(withTally: false));
        await c.checkFinancialAccess(force: true);
        await c.openStatement('cf'); // Cash Flow is only from Tally
        expect(c.screen, 'tallyReport');
        expect(c.trError, contains('No figures from Tally'));
        c.dispose();

        final AppController d = await _start(
          _fake()..tallyReportsMissing = true,
        );
        await d.openTallyReport('balance_sheet');
        expect(
          d.trError,
          'Reports from Tally are not available on the server yet.',
        );
        expect(d.trPeriods, isNull);
        d.dispose();

        final AppController e = await _start(_fake()..finAllowed = false);
        await e.openTallyReport('balance_sheet');
        expect(e.trError, contains('Ask your admin'));
        e.dispose();
      },
    );

    test('PDF, Dr / Cr, column labels', () async {
      final AppController c = await _start(_fake());
      await c.checkFinancialAccess(force: true);
      await c.openStatement('tb');
      final ShareDoc tb = tallyReportDoc(c, c.trData!);
      expect(tb.title, 'Trial Balance');
      expect(tb.table!.rows.first, <String>[
        'HDFC Bank',
        'Bank Accounts',
        '₹1,72,500.50',
        '',
      ]);
      expect(tb.totals.first, ('Total debit', '₹1,75,000.50'));
      await c.openStatement('bs');
      final ShareDoc bs = tallyReportDoc(c, c.trData!);
      expect(bs.table!.rows.last, <String>[
        'Current Assets',
        '₹1,75,000.50 Dr',
      ]);
      expect(drCr(-10), '₹10 Dr');
      expect(drCr(10), '₹10 Cr');
      expect(tagLabel('DSPINFLOW'), 'Inflow');
      expect(tagLabel('BSMAINAMT'), 'Main');
      c.dispose();
    });
  });

  group('screens (320 px)', () {
    setUpAll(loadFigtree);

    Future<AppController> open(WidgetTester t, FakeBackend f) async {
      t.view.physicalSize = const Size(320 * 3, 720 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final AppController c = await _start(f);
      await t.pumpWidget(
        ProviderScope(
          overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
          child: const TallyConnectApp(),
        ),
      );
      return c;
    }

    Future<void> settle(WidgetTester t) async {
      for (int i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets(
      'Reports: "Tally" mark on fetched tiles; Balance Sheet lines open ledgers',
      (WidgetTester t) async {
        final AppController c = await open(t, _fake());
        await c.checkFinancialAccess(force: true);
        c.go('reports');
        await settle(t);
        await t.scrollUntilVisible(
          find.byKey(const ValueKey<String>('fin-cf')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.byKey(const ValueKey<String>('fin-tally-bs')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('fin-tally-pl')),
          findsNothing,
        );
        expect(t.takeException(), isNull);

        await c.openStatement('bs');
        await settle(t);
        expect(find.text('Both sides are equal'), findsOneWidget);
        expect(
          find.textContaining(
            RegExp(r'^Liabilities$', caseSensitive: false),
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            RegExp(r'^Assets$', caseSensitive: false),
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(find.text('HDFC Bank'), findsNothing);
        await t.ensureVisible(
          find.byKey(const ValueKey<String>('trRow-Current Assets')),
        );
        await settle(t);
        await t.tap(find.byKey(const ValueKey<String>('trRow-Current Assets')));
        await settle(t);
        expect(find.text('HDFC Bank'), findsOneWidget);
        expect(find.text('₹1,72,500.50 Dr'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pump(const Duration(seconds: 6));
      },
    );

    testWidgets('Trial Balance by group, Cash Flow lines; no overflow', (
      WidgetTester t,
    ) async {
      final AppController c = await open(t, _fake());
      await c.checkFinancialAccess(force: true);
      await c.openStatement('tb');
      await settle(t);
      expect(
        find.textContaining('Debit ₹1,75,000.50 = Credit ₹1,75,000.50'),
        findsOneWidget,
      );
      await t.ensureVisible(
        find.byKey(const ValueKey<String>('trRow-Cash-in-Hand')),
      );
      await settle(t);
      await t.tap(find.byKey(const ValueKey<String>('trRow-Cash-in-Hand')));
      await settle(t);
      expect(find.text('Cash'), findsOneWidget);
      expect(t.takeException(), isNull);
      await c.openStatement('cf');
      await settle(t);
      expect(find.text('April'), findsOneWidget);
      expect(find.textContaining('Inflow ₹50,000'), findsOneWidget);
      expect(
        find.text('Grand Total'),
        findsNothing,
      ); // heading line without figures
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
