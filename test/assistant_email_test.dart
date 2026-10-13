// AI assistant (user's own Gemini key, server-side answers) and one-tap
// email from party detail.
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
    test(
      'connect: key checked by the server, then kept in the keystore',
      () async {
        final FakeBackend f = FakeBackend();
        final MemoryAssistantKeyStore keys = MemoryAssistantKeyStore();
        final (_, AppController c) = await _start(f, keys: keys);
        await c.openAssistant();
        expect(c.overlay, 'assistant');
        expect(c.aiConnected, isFalse);
        await c.connectAssistant();
        expect(c.aiError, 'Paste your Gemini API key');
        c.setF('aiKey', 'AIzaWRONG_1234567890abcdefgh');
        await c.connectAssistant();
        expect(c.aiConnected, isFalse);
        expect(c.aiError, contains('rejected this API key'));
        expect(keys.keys, isEmpty); // a bad key is never saved
        expect(c.repo.user, isNotNull); // a bad key never signs the user out
        c.setF('aiKey', '  $kGood ');
        await c.connectAssistant();
        expect(c.aiConnected, isTrue);
        expect(keys.keys['ravi@x.in'], kGood);
        expect(c.f('aiKey'), isEmpty); // not left in the form
        c.dispose();
      },
    );

    test('asks with the key in a header; history sent; answer shown', () async {
      final FakeBackend f = FakeBackend();
      final MemoryAssistantKeyStore keys = MemoryAssistantKeyStore()
        ..keys['ravi@x.in'] = kGood;
      final (_, AppController c) = await _start(f, keys: keys);
      await c.openAssistant();
      expect(c.aiConnected, isTrue); // loaded from the keystore
      await c.askAssistant('Who owes me the most?');
      expect(c.aiTurns.last.text, contains('Mehta Electricals'));
      c.setF('aiQ', 'And how much is overdue?');
      await c.askAssistant();
      final Map<String, Object?> second = f.aiAsks.last;
      expect(second['question'], 'And how much is overdue?');
      expect((second['history']! as List<Object?>).length, 2);
      // The key travels only in the header, never in the body.
      expect(f.aiKeysSeen.every((String? k) => k == kGood), isTrue);
      for (final Map<String, Object?> a in f.aiAsks) {
        expect(a.toString(), isNot(contains(kGood)));
      }
      c.dispose();
    });

    test(
      'quota / outage / key revoked: shown in the chat, session kept',
      () async {
        final FakeBackend f = FakeBackend()..aiFail = 'quota';
        final MemoryAssistantKeyStore keys = MemoryAssistantKeyStore()
          ..keys['ravi@x.in'] = kGood;
        final (_, AppController c) = await _start(f, keys: keys);
        await c.openAssistant();
        await c.askAssistant('Sales this month');
        expect(c.aiTurns.last.error, isTrue);
        expect(c.aiTurns.last.text, contains('quota'));
        f.aiFail = 'down';
        await c.askAssistant('Sales this month');
        expect(c.aiTurns.last.text, contains('not answering'));
        f
          ..aiFail = null
          ..aiValidKeys = <String>{};
        await c.askAssistant('Sales this month');
        expect(c.aiTurns.last.text, contains('rejected this API key'));
        expect(c.loggedIn, isTrue);
        // Failed turns are not sent back as history.
        f.aiValidKeys = <String>{kGood};
        await c.askAssistant('Payables?');
        expect(f.aiAsks.last['history'], hasLength(3)); // the three questions
        c.dispose();
      },
    );

    test('mic: speech fills the question; nothing sent until Send', () async {
      final FakeBackend f = FakeBackend();
      final FakeVoice v = FakeVoice();
      final MemoryAssistantKeyStore keys = MemoryAssistantKeyStore()
        ..keys['ravi@x.in'] = kGood;
      final (_, AppController c) = await _start(f, keys: keys, voice: v);
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

    test(
      'remove key; server without the routes; Demo Company blocked',
      () async {
        final FakeBackend f = FakeBackend()..aiMissing = true;
        final MemoryAssistantKeyStore keys = MemoryAssistantKeyStore();
        final (_, AppController c) = await _start(f, keys: keys);
        await c.openAssistant();
        c.setF('aiKey', kGood);
        await c.connectAssistant();
        expect(
          c.aiError,
          'The AI assistant is not available on the server yet.',
        );
        f.aiMissing = false;
        await c.connectAssistant();
        expect(c.aiConnected, isTrue);
        await c.disconnectAssistant();
        expect(c.aiConnected, isFalse);
        expect(keys.keys, isEmpty);
        c.dispose();

        final FakeBackend g = FakeBackend()..newAccount = true;
        final (_, AppController d) = await _start(g);
        expect(d.demo, isTrue);
        await d.openAssistant();
        expect(d.overlay, isNot('assistant'));
        expect(d.toast, contains('not Demo Company'));
        expect(g.aiKeysSeen, isEmpty);
        d.dispose();
      },
    );
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

    testWidgets('Home chat button → connect → ask; party email icon (320 px)', (
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
      expect(find.byKey(const ValueKey<String>('aiConnect')), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey<String>('aiKeyField')).first,
        kGood,
      );
      await t.pump();
      c.setF('aiKey', kGood);
      await t.tap(find.byKey(const ValueKey<String>('aiConnect')));
      await settle();
      expect(c.aiConnected, isTrue);
      await t.tap(find.text('Who owes me the most?'));
      await settle();
      expect(
        find.textContaining('Mehta Electricals owes the most'),
        findsOneWidget,
      );
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
