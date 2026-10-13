// AI assistant answers: KPI cards / tables from the server's figures, the
// summary rendered (never raw Markdown), ₹ formatting, long / empty /
// off-topic answers and narrow screens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/design/tc_palette.dart';
import 'package:tallyconnect_ui/core/storage/assistant_key_store.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';
import 'package:tallyconnect_ui/presentation/overlays/assistant_answer.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

const String kGood = 'AIzaGOODKEY_1234567890abcdef';
const String kOffTopic =
    'I’m the TallyConnect AI Assistant, designed to help you with '
    'TallyConnect and your accounting data. Please ask me something related '
    'to TallyConnect.';

/// Every piece of text on screen (Text and Text.rich).
String screenText(WidgetTester t) => <String>[
  for (final Element e in find.byType(RichText).evaluate())
    (e.widget as RichText).text.toPlainText(),
].join('\n');

Future<void> pumpAnswer(WidgetTester t, AiTurn turn, double w) async {
  t.view.physicalSize = Size(w * 3, 900 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final AppController c = AppController(
    store: LocalStorage.memory(),
    startScreen: 'home',
  );
  addTearDown(c.dispose);
  await t.pumpWidget(
    MaterialApp(
      home: Tc(
        p: c.palette,
        child: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[AiAnswer(turn)],
          ),
        ),
      ),
    ),
  );
  await t.pump();
}

void main() {
  group('blocks and values', () {
    test('cards, tables and notes from the server; bad rows dropped', () {
      final AssistantReply r = AssistantReply.fromJson(<String, Object?>{
        'answer': 'x',
        'blocks': <Object?>[
          <String, Object?>{
            'type': 'kpis',
            'title': 'Receivables · as on 2026-10-12',
            'items': <Object?>[
              <String, Object?>{
                'label': 'Total pending',
                'value': 1234567.5,
                'format': 'money',
                'tone': 'primary',
              },
            ],
          },
          <String, Object?>{
            'type': 'table',
            'title': 'Entries',
            'columns': <Object?>[
              <String, Object?>{'label': 'Date', 'format': 'date'},
              <String, Object?>{'label': 'Amount', 'format': 'money'},
            ],
            'rows': <Object?>[
              <Object?>['2026-10-03', 2000],
              <Object?>['bad row'], // wrong length → dropped
            ],
            'total_rows': 14,
          },
          <String, Object?>{'type': 'note', 'text': 'Several parties match.'},
          <String, Object?>{'type': 'chart'}, // unknown → ignored
          'junk',
        ],
      });
      expect(r.blocks.map((AiBlock b) => b.type), <String>[
        'kpis',
        'table',
        'note',
      ]);
      expect(r.blocks[1].rows, hasLength(1));
      expect(r.blocks[1].totalRows, 14);
      expect(
        AssistantReply.fromJson(<String, Object?>{
          'answer': 'old server',
        }).blocks,
        isEmpty,
      );
    });

    test('Indian money, counts and dates', () {
      expect(aiValue(1234567.5, 'money'), '₹12,34,567.50');
      expect(aiValue(15000, 'money'), '₹15,000');
      expect(aiValue('2000.25', 'money'), '₹2,000.25');
      expect(aiValue(46438, 'count'), '46,438');
      expect(aiValue('2026-10-12', 'date'), '12 Oct 2026');
      expect(aiValue('2026-10', 'date'), 'Oct 2026');
      expect(aiValue(null, 'money'), '—');
      expect(aiValue('  ', 'text'), '—');
      expect(
        aiTitle('Sales · 2026-04-01 to 2026-10-12'),
        'Sales · 01 Apr 2026 to 12 Oct 2026',
      );
    });
  });

  group('rendering', () {
    setUpAll(loadFigtree);

    const String markdown =
        '### Outstanding summary\n'
        'You are owed **₹19,000.50** in total; ₹14,000.50 is overdue.\n'
        '\n'
        '- **Mehta Electricals** owes the most\n'
        '* Gupta Stores: ₹4,000\n'
        '1. Call Mehta first\n'
        '2) Then Gupta\n'
        '| Party | Pending |\n'
        '|---|---|\n'
        '| Mehta | ₹15,000.50 |\n'
        '```\n'
        'raw code\n'
        '```\n'
        'See [the app](https://x.y) and `code`, _note_.';

    final AiTurn rich = AiTurn(
      'model',
      markdown,
      blocks: <AiBlock>[
        const AiBlock.note(
          'Several parties match "a": Mehta Electricals, Gupta Stores.',
        ),
        const AiBlock.kpis('Receivables · as on 2026-10-12', <AiKpi>[
          AiKpi(
            'Total pending',
            1900000050.5,
            format: 'money',
            tone: 'primary',
          ),
          AiKpi('Overdue', 14000.5, format: 'money', tone: 'neg'),
          AiKpi('Bills', 3, format: 'count'),
          AiKpi('Parties', 2, format: 'count'),
        ]),
        AiBlock.table(
          'Entries · 2026-10-01 to 2026-10-31',
          const <AiColumn>[
            AiColumn('Date', format: 'date'),
            AiColumn('Type'),
            AiColumn('Party'),
            AiColumn('Amount', format: 'money'),
            AiColumn('Bills', format: 'count'),
            AiColumn('Overdue', format: 'money'),
          ],
          <List<Object?>>[
            <Object?>[
              '2026-10-03',
              'Receipt',
              'Mehta Electricals Private Limited, Mumbai',
              2000,
              1,
              0,
            ],
            <Object?>['2026-10-02', 'Sales', 'Gupta Stores', 4000, 1, 0],
          ],
          totalRows: 27,
        ),
        const AiBlock.table(
          'Top parties',
          <AiColumn>[AiColumn('Party'), AiColumn('Amount', format: 'money')],
          <List<Object?>>[],
          empty: 'No entries in this period.',
        ),
      ],
    );

    for (final double w in <double>[320, 412]) {
      testWidgets(
        'cards, tables and summary at ${w.toInt()} px — no raw Markdown',
        (WidgetTester t) async {
          await pumpAnswer(t, rich, w);
          expect(t.takeException(), isNull);
          final String s = screenText(t);
          // Formatted, not raw.
          for (final String raw in <String>[
            '**',
            '###',
            '|',
            '```',
            '](',
            '`',
            '_note_',
          ]) {
            expect(s, isNot(contains(raw)), reason: raw);
          }
          expect(s, contains('Outstanding summary'));
          expect(s, contains('Call Mehta first'));
          expect(s, contains('note')); // emphasis kept as plain text
          // Code-fence text stays readable as plain text (fences removed).
        expect(s, contains('raw code'));
          // KPI cards and table values formatted from the server figures.
          expect(s, contains('₹1,90,00,00,050.50'));
          expect(s, contains('₹14,000.50'));
          expect(s, contains('Receivables · as on 12 Oct 2026'));
          expect(s, contains('03 Oct 2026'));
          expect(s, contains('₹2,000'));
          expect(s, contains('+ 25 more'));
          expect(s, contains('No entries in this period.'));
          expect(s, contains('Several parties match'));
          expect(find.byKey(const ValueKey<String>('aiKpis')), findsOneWidget);
          expect(
            find.byKey(const ValueKey<String>('aiTable')),
            findsNWidgets(2),
          );
        },
      );
    }

    testWidgets('long answer: no overflow', (WidgetTester t) async {
      final String long = <String>[
        for (int i = 1; i <= 60; i++)
          '- Party number $i with a rather long name that needs wrapping owes **₹${i * 1000}**',
      ].join('\n');
      await pumpAnswer(t, AiTurn('model', long), 320);
      expect(t.takeException(), isNull);
      expect(screenText(t), contains('Party number 60'));
    });
  });

  group('in the chat', () {
    setUpAll(loadFigtree);

    Future<AppController> openChat(WidgetTester t, FakeBackend f) async {
      t.view.physicalSize = const Size(320 * 3, 720 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      final AppController c = AppController(
        store: LocalStorage.memory(),
        repo: r,
        startScreen: 'home',
        assistantKeys: MemoryAssistantKeyStore()..keys['ravi@x.in'] = kGood,
      );
      c.afterRefresh(quietOk: true);
      await t.pumpWidget(
        ProviderScope(
          overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
          child: const TallyConnectApp(),
        ),
      );
      await c.openAssistant();
      for (int i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      return c;
    }

    Future<void> settle(WidgetTester t) async {
      for (int i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('answer card with KPIs, summary and table', (
      WidgetTester t,
    ) async {
      final FakeBackend f = FakeBackend();
      final AppController c = await openChat(t, f);
      await c.askAssistant('Who owes me the most?');
      await settle(t);
      expect(c.aiTurns.last.blocks, hasLength(2));
      expect(find.byKey(const ValueKey<String>('aiAnswer')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('aiKpis')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('aiTable')), findsOneWidget);
      final String s = screenText(t);
      expect(s, contains('₹15,000.50'));
      expect(s, isNot(contains('**')));
      expect(t.takeException(), isNull);
      c.closeOv();
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('off-topic: the fixed TallyConnect reply, shown plainly', (
      WidgetTester t,
    ) async {
      final FakeBackend f = FakeBackend()
        ..aiReply = <String, Object?>{
          'success': true,
          'answer': kOffTopic,
          'tools_used': <String>[],
        };
      final AppController c = await openChat(t, f);
      await c.askAssistant('Who won the cricket world cup?');
      await settle(t);
      expect(c.aiTurns.last.text, kOffTopic);
      expect(c.aiTurns.last.blocks, isEmpty);
      expect(
        find.textContaining('designed to help you with TallyConnect'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      c.closeOv();
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('empty answer and older server answers handled', (
      WidgetTester t,
    ) async {
      final FakeBackend f = FakeBackend()
        ..aiReply = <String, Object?>{'success': true, 'answer': ''};
      final AppController c = await openChat(t, f);
      await c.askAssistant('Sales?');
      await settle(t);
      expect(c.aiTurns.last.text, 'No answer was returned. Try asking again.');
      f.aiReply = <String, Object?>{
        'success': true,
        'answer': 'Sales this month: **₹4,000**.',
      };
      await c.askAssistant('Sales?');
      await settle(t);
      expect(screenText(t), contains('Sales this month: ₹4,000.'));
      expect(t.takeException(), isNull);
      c.closeOv();
      await t.pump(const Duration(seconds: 6));
    });
  });
}
