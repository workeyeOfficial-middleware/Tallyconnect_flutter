// AI assistant (the server's AI key, a token allowance per login) and
// one-tap email from party detail.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/storage/assistant_key_store.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/core/utils/email.dart';
import 'package:tallyconnect_ui/core/voice/voice_input.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart'
    show DataSet;
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;
import 'voice_search_test.dart' show FakeVoice;

const String kGood = 'AIzaGOODKEY_1234567890abcdef';

Future<(DemoAwareRepository, AppController)> _start(
  FakeBackend f, {
  MemoryAssistantKeyStore? keys,
  List<Uri>? opened,
  VoiceInput? voice,
}) async {
  final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
  await r.login('ravi@x.in', 'secret', 'ADMIN');
  await r.refreshAll();
  await r.ensure(DataSet.ledgers);
  final AppController c = AppController(
    store: LocalStorage.memory(),
    repo: r,
    startScreen: 'home',
    assistantKeys: keys ?? MemoryAssistantKeyStore(),
    voice: voice,
    linkOpener: (Uri u) async {
      opened?.add(u);
      return true;
    },
  );
  c.afterRefresh(quietOk: true);
  return (r, c);
}

void main() {
  group('AI assistant', () {
    test('no key needed: opens the chat with the plan and tokens left; '
        'old saved keys are wiped', () async {
      final FakeBackend f = FakeBackend()..aiUsed = 2400;
      final MemoryAssistantKeyStore keys = MemoryAssistantKeyStore()
        ..keys['ravi@x.in'] = kGood;
      final (_, AppController c) = await _start(f, keys: keys);
      await c.openAssistant();
      expect(c.overlay, 'assistant');
      expect(c.aiEnabled, isTrue);
      expect(c.aiUsage!.limit, 10000);
      expect(c.aiUsage!.remaining, 7600);
      expect(keys.keys, isEmpty); // the user's own key is no longer kept
      c.dispose();
    });

    test('asks without any key; history sent; usage updated', () async {
      final FakeBackend f = FakeBackend();
      final (_, AppController c) = await _start(f);
      await c.openAssistant();
      await c.askAssistant('Who owes me the most?');
      expect(c.aiTurns.last.text, contains('Mehta Electricals'));
      expect(c.aiUsage!.used, 240);
      c.setF('aiQ', 'And how much is overdue?');
      await c.askAssistant();
      final Map<String, Object?> second = f.aiAsks.last;
      expect(second['question'], 'And how much is overdue?');
      expect((second['history']! as List<Object?>).length, 2);
      expect(c.aiUsage!.remaining, 10000 - 480);
      // No AI key, provider or model is ever sent by the app.
      for (final Map<String, String> h in f.aiHeadersSeen) {
        expect(h.keys.map((String k) => k.toLowerCase()), isNot(contains('x-ai-key')));
        expect(h.keys.map((String k) => k.toLowerCase()), isNot(contains('x-gemini-key')));
      }
      for (final Map<String, Object?> a in f.aiAsks) {
        expect(a.keys, isNot(contains('provider')));
        expect(a.keys, isNot(contains('model')));
      }
      c.dispose();
    });

    test('allowance used up: popup with the exact message, nothing sent, '
        'View plans → Plans', () async {
      final FakeBackend f = FakeBackend()
        ..aiLimit = 10000
        ..aiUsed = 9900;
      final (_, AppController c) = await _start(f);
      await c.openAssistant();
      expect(c.overlay, 'assistant'); // 100 left: still allowed
      await c.askAssistant('Sales this month');
      expect(c.aiExhausted, isTrue); // this answer used the rest
      expect(c.aiTurns.last.mine, isFalse);
      // The next question: the server refuses → popup, question kept.
      f.aiUsed = 9000; // even if the phone thinks there is room…
      c.aiUsage = const AiUsage(limit: 10000, used: 9000);
      f.aiUsed = 10000; // …the server decides.
      await c.askAssistant('Payables?');
      expect(c.overlay, 'aiLimit');
      expect(c.aiExhausted, isTrue);
      expect(c.f('aiQ'), 'Payables?'); // given back, not lost
      expect(c.aiTurns.last.text, isNot('Payables?'));
      expect(
        AppController.kAiLimitMessage,
        'Your free AI access has ended. Upgrade your plan to continue.',
      );
      final int asked = f.aiAsks.length;
      c.dismissAiLimit();
      expect(c.overlay, 'assistant');
      await c.askAssistant('Again?'); // blocked on the phone, nothing sent
      expect(f.aiAsks.length, asked);
      expect(c.overlay, 'aiLimit');
      c.viewAiPlans();
      expect(c.overlay, isNull);
      expect(c.screen, 'billing');
      // Opening the assistant again goes straight to the popup.
      await c.openAssistant();
      expect(c.overlay, 'aiLimit');
      expect(c.loggedIn, isTrue); // never signed out
      c.dispose();
    });

    test('busy / outage / not set up: shown in the chat, session kept', () async {
      final FakeBackend f = FakeBackend()..aiFail = 'busy';
      final (_, AppController c) = await _start(f);
      await c.openAssistant();
      await c.askAssistant('Sales this month');
      expect(c.aiTurns.last.error, isTrue);
      expect(c.aiTurns.last.text, contains('busy'));
      f.aiFail = 'down';
      await c.askAssistant('Sales this month');
      expect(c.aiTurns.last.text, contains('not answering'));
      expect(c.loggedIn, isTrue);
      // Failed turns are not sent back as history.
      f.aiFail = null;
      await c.askAssistant('Payables?');
      expect(f.aiAsks.last['history'], hasLength(2)); // the two questions
      expect(f.aiUsed, 240); // failures cost nothing
      c.dispose();

      final FakeBackend g = FakeBackend()..aiDisabled = true;
      final (_, AppController d) = await _start(g);
      await d.openAssistant();
      expect(d.aiEnabled, isFalse);
      expect(d.aiError, 'The AI Assistant is not available right now.');
      d.dispose();
    });

    test('mic: speech fills the question; nothing sent until Send', () async {
      final FakeBackend f = FakeBackend();
      final FakeVoice v = FakeVoice();
      final (_, AppController c) = await _start(f, voice: v);
      await c.openAssistant();
      await c.toggleAssistantVoice();
      expect(c.aiVoiceOn, isTrue);
      expect(c.voiceNote, AppController.kVoiceListening);
      v.session!.onWords('Last five', false);
      expect(c.f('aiQ'), 'Last five');
      v.session!.onWords('Last five receipts', true);
      expect(c.f('aiQ'), 'Last five receipts');
      expect(c.aiVoiceOn, isFalse);
      expect(c.f('q'), isEmpty); // the search field is untouched
      expect(f.aiAsks, isEmpty); // speech alone sends nothing
      await c.askAssistant();
      expect(f.aiAsks.single['question'], 'Last five receipts');
      // Permission off: a clear note, typing still works.
      v.start = VoiceStart.denied;
      await c.toggleAssistantVoice();
      expect(c.aiVoiceOn, isFalse);
      expect(c.voiceNote, AppController.kVoiceDenied);
      // Closing the sheet while listening stops it.
      v.start = VoiceStart.ok;
      await c.toggleAssistantVoice();
      c.closeOv();
      await pumpEventQueue();
      expect(c.voiceOn, isFalse);
      expect(v.stops, greaterThan(0));
      c.dispose();
    });

    test('server without the routes; Demo Company blocked', () async {
      final FakeBackend f = FakeBackend()..aiMissing = true;
      final (_, AppController c) = await _start(f);
      await c.openAssistant();
      expect(c.aiEnabled, isFalse);
      expect(c.aiError, 'The AI Assistant is not available on the server yet.');
      c.dispose();

      final FakeBackend g = FakeBackend()..newAccount = true;
      final (_, AppController d) = await _start(g);
      expect(d.demo, isTrue);
      await d.openAssistant();
      expect(d.overlay, isNot('assistant'));
      expect(d.toast, contains('not Demo Company'));
      expect(g.aiHeadersSeen, isEmpty);
      d.dispose();
    });
  });

  group('one-tap email', () {
    test('addresses from the Tally field', () {
      expect(emailAddresses(null), isEmpty);
      expect(emailAddresses('N/A'), isEmpty);
      expect(emailAddresses('accounts@mehta.in'), <String>[
        'accounts@mehta.in',
      ]);
      expect(
        emailAddresses('Accounts: a@x.in; B@Y.co.in, a@x.in / mailto:c@z.com.'),
        <String>['a@x.in', 'B@Y.co.in', 'c@z.com'],
      );
      expect(mailUri('a@x.in').toString(), 'mailto:a@x.in');
    });

    test(
      'one address → email app; several → choose; none / demo → message',
      () async {
        final List<Uri> opened = <Uri>[];
        final FakeBackend f = FakeBackend();
        final (_, AppController c) = await _start(f, opened: opened);
        Party party(String? e) =>
            Party('Gupta Traders', 'c', 'Mumbai', 0, email: e);
        c.emailParty(party('accounts@gupta.in'));
        await pumpEventQueue();
        expect(opened, <Uri>[Uri.parse('mailto:accounts@gupta.in')]);
        c.emailParty(party('a@gupta.in, b@gupta.in'));
        expect(c.overlay, 'mailPick');
        expect(c.mailAddresses, <String>['a@gupta.in', 'b@gupta.in']);
        await c.composeEmail('b@gupta.in');
        expect(opened.last, Uri.parse('mailto:b@gupta.in'));
        expect(c.overlay, isNull);
        c.emailParty(party(null));
        expect(c.toast, contains('No email address saved'));
        c.emailParty(party('not an email'));
        expect(c.toast, contains('not valid'));
        c.dispose();

        final FakeBackend g = FakeBackend()..newAccount = true;
        final (_, AppController d) = await _start(g, opened: opened);
        final int before = opened.length;
        d.emailParty(party('a@x.in'));
        expect(opened.length, before);
        expect(d.toast, contains('Email is off for Demo Company'));
        d.dispose();
      },
    );
  });

  group('screens', () {
    setUpAll(loadFigtree);

    testWidgets('Home chat button → ask → used up → plans; party email icon (320 px)', (
      WidgetTester t,
    ) async {
      t.view.physicalSize = const Size(320 * 3, 720 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final List<Uri> opened = <Uri>[];
      final FakeBackend f = FakeBackend()
        ..extraLedgers = <Map<String, Object?>>[
          <String, Object?>{
            'ledger_guid': 'L9',
            'name': 'Gupta Traders',
            'parent_group': 'Sundry Debtors',
            'opening_balance': '0',
            'closing_balance': '0',
            'email': 'accounts@gupta.in',
          },
        ];
      final (_, AppController c) = await _start(f, opened: opened);
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

      await settle();
      expect(
        find.byKey(const ValueKey<String>('assistantFab')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey<String>('assistantFab')));
      await settle();
      expect(c.overlay, 'assistant');
      // No key to enter: straight to the chat, with the tokens left.
      expect(find.byKey(const ValueKey<String>('aiQuestion')), findsOneWidget);
      expect(find.text('Free plan · 10,000 of 10,000 AI tokens left'), findsOneWidget);
      await t.tap(find.text('Who owes me the most?'));
      await settle();
      expect(
        find.textContaining('Mehta Electricals owes the most'),
        findsOneWidget,
      );
      expect(find.text('Free plan · 9,760 of 10,000 AI tokens left'), findsOneWidget);
      expect(t.takeException(), isNull);
      // Used up: the popup with the exact message → View plans → Plans.
      f.aiUsed = f.aiLimit;
      c.setF('aiQ', 'Payables?');
      await t.tap(find.byKey(const ValueKey<String>('aiSend')));
      await settle();
      expect(c.overlay, 'aiLimit');
      expect(
        find.text('Your free AI access has ended. Upgrade your plan to continue.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey<String>('aiLimitClose')));
      await settle();
      expect(c.overlay, 'assistant');
      expect(find.byKey(const ValueKey<String>('aiLimitBanner')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('aiQuestion')), findsNothing);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey<String>('aiBannerPlans')));
      await settle();
      expect(c.screen, 'billing');
      expect(t.takeException(), isNull);
      c.closeOv();
      await settle();

      // The FAB is only on Home.
      c.go('partyDetail', <String, Object?>{
        'party': 'Gupta Traders',
        'partyTab': 'summary',
      });
      await settle();
      expect(find.byKey(const ValueKey<String>('assistantFab')), findsNothing);
      await t.tap(find.byKey(const ValueKey<String>('emailRow')));
      await settle();
      expect(opened.last, Uri.parse('mailto:accounts@gupta.in'));
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
