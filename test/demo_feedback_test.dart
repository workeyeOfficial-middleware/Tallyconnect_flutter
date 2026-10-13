// Demo data for new / unsynced accounts (isolated from real data, never
// sent to Tally, labelled everywhere, safe switch to live data) and
// feedback sent to POST /api/feedback.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/notify/reminder_alarms.dart';
import 'package:tallyconnect_ui/core/share/share_doc.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend, kGuid;
import 'screens_test.dart' show loadFigtree;

/// Signed-in app on [f] (a new account when [f.newAccount]).
Future<(DemoAwareRepository, AppController)> _start(
  FakeBackend f, {
  LocalStorage? store,
  NoReminderAlarms? alarms,
}) async {
  final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
  await r.login('ravi@x.in', 'secret', 'ADMIN');
  await r.refreshAll();
  final AppController c = AppController(
    store: store ?? LocalStorage.memory(),
    repo: r,
    startScreen: 'home',
    alarms: alarms,
  );
  c.afterRefresh(quietOk: true);
  return (r, c);
}

List<http.Request> _entries(FakeBackend f) => f.calls
    .where((http.Request q) => q.url.path.contains('mobile-voucher-command'))
    .toList();

void main() {
  group('demo data', () {
    test('new account: demo company, isolated from the real data', () async {
      final FakeBackend f = FakeBackend()..newAccount = true;
      final (DemoAwareRepository r, AppController c) = await _start(f);
      expect(c.demo, isTrue);
      expect(r.isRemote, isFalse);
      expect(r.companies().single.name, kDemoCompanyName);
      // Shown data is the sample set; the real account has none.
      expect(identical(r.receivables(), r.demo.receivables()), isTrue);
      expect(r.receivables(), isNotEmpty);
      expect(r.live.receivables(), isEmpty);
      expect(r.live.companies(), isEmpty);
      // The session stays the real account's.
      expect(r.user?.email, 'ravi@x.in');
      c.dispose();
    });

    test('demo entries are never saved, queued or sent', () async {
      final FakeBackend f = FakeBackend()..newAccount = true;
      final (DemoAwareRepository r, AppController c) = await _start(f);
      expect(c.flowBlocker, kDemoWriteBlocked);
      final int acts = c.acts.length;
      c.startFlow('receipt', <String, String>{'rAmt': '500'});
      c.saveFlow(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.toast, kDemoWriteBlocked);
      expect(c.acts.length, acts);
      final SubmitResult s = await r.submitEntry(c.draftOf());
      expect(s.ok, isFalse);
      expect(await r.pushEntry(c.acts.first), isFalse);
      expect(_entries(f), isEmpty);
      c.dispose();
    });

    test('documents made from demo data are labelled', () async {
      final FakeBackend f = FakeBackend()..newAccount = true;
      final (DemoAwareRepository _, AppController c) = await _start(f);
      c.previewDoc(const ShareDoc(title: 'Receivable', company: 'X'));
      final ShareDoc d = c.docShown!;
      expect(d.demo, isTrue);
      expect(d.fileName, startsWith('DEMO_'));
      expect(d.text, startsWith(ShareDoc.kDemoLabel));
      c.dispose();
    });

    test('no phone alarms for demo bills', () async {
      final FakeBackend f = FakeBackend()..newAccount = true;
      final NoReminderAlarms dev = NoReminderAlarms();
      final (DemoAwareRepository _, AppController c) = await _start(
        f,
        alarms: dev,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(dev.pending, isEmpty);
      c.dispose();
    });

    test(
      'first Tally sync → real data; never back to demo by itself',
      () async {
        final FakeBackend f = FakeBackend()..newAccount = true;
        final LocalStorage s = LocalStorage.memory();
        final (DemoAwareRepository r, AppController c) = await _start(
          f,
          store: s,
        );
        expect(c.demo, isTrue);
        // The agent registers the company and finishes its first sync.
        f.newAccount = false;
        await c.liveCheck();
        expect(c.demo, isFalse);
        expect(r.isRemote, isTrue);
        expect(c.toast, contains('Your Tally company is here'));
        // Real companies first, Demo Company still listed last.
        expect(r.companies().first.name, isNot(kDemoCompanyName));
        expect(r.companies().last.id, kDemoCompanyId);
        expect(r.activeCompanyId, isNot(kDemoCompanyId));
        // Real data seen: even if it is not there later, no demo data.
        f.newAccount = true;
        await r.refreshAll(force: true);
        c.afterRefresh(quietOk: true);
        expect(c.demo, isFalse);
        c.dispose();
        final (DemoAwareRepository _, AppController c2) = await _start(
          f,
          store: s,
        );
        expect(c2.demo, isFalse);
        c2.dispose();
      },
    );

    test('"Use my data" leaves demo data and is remembered', () async {
      final FakeBackend f = FakeBackend()..newAccount = true;
      final LocalStorage s = LocalStorage.memory();
      final (DemoAwareRepository r, AppController c) = await _start(
        f,
        store: s,
      );
      c.useMyData();
      expect(c.demo, isFalse);
      expect(r.isRemote, isTrue);
      expect(c.demoMode, 'off');
      c.dispose();
      final (DemoAwareRepository _, AppController c2) = await _start(
        f,
        store: s,
      );
      expect(c2.demo, isFalse);
      c2.dispose();
    });

    test('account with data: no demo unless chosen in Settings', () async {
      final FakeBackend f = FakeBackend();
      final LocalStorage s = LocalStorage.memory();
      final (DemoAwareRepository r, AppController c) = await _start(
        f,
        store: s,
      );
      expect(c.demo, isFalse);
      final List<Bill> real = r.receivables();
      c.setDemoMode('on');
      expect(c.demo, isTrue);
      expect(identical(r.receivables(), real), isFalse);
      c.dispose();
      final (DemoAwareRepository r2, AppController c2) = await _start(
        f,
        store: s,
      );
      expect(c2.demo, isTrue); // kept on the phone
      c2.setDemoMode('off');
      expect(c2.demo, isFalse);
      expect(r2.isRemote, isTrue);
      c2.dispose();
    });
  });

  group('Demo Company beside the real companies', () {
    test('synced account: real company shown, Demo Company listed last', () async {
      // Sync time not known yet: the company alone decides, not its data.
      final FakeBackend f = FakeBackend()..lastSync = '';
      final (DemoAwareRepository r, AppController c) = await _start(f);
      expect(c.demo, isFalse);
      expect(r.activeCompanyId, kGuid);
      expect(r.companies().map((Company x) => x.id), contains(kGuid));
      expect(r.companies().last, kDemoCompany);
      expect(c.company, kGuid);
      c.dispose();
    });

    test('picking Demo Company changes nothing on the server or real data', () async {
      final FakeBackend f = FakeBackend();
      final (DemoAwareRepository r, AppController c) = await _start(f);
      final List<Bill> real = r.live.receivables();
      final int companies = r.live.companies().length;
      c.pickCompany(kDemoCompany);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.demo, isTrue);
      expect(c.company, kDemoCompanyId);
      expect(r.activeCompanyId, kDemoCompanyId);
      // Real companies stay listed and untouched; the server's active
      // company is not changed by a demo pick.
      expect(r.companies().where((Company x) => x.id != kDemoCompanyId).length, companies);
      expect(r.live.activeCompanyId, kGuid);
      expect(identical(r.live.receivables(), real), isTrue);
      expect(f.to('/company/set-active'), isEmpty);
      // Back to the real company: no server switch needed.
      c.pickCompany(r.companies().firstWhere((Company x) => x.id == kGuid));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.demo, isFalse);
      expect(c.company, kGuid);
      expect(f.to('/company/set-active'), isEmpty);
      c.dispose();
    });

    test('refresh on Demo Company still reloads the real companies', () async {
      final FakeBackend f = FakeBackend();
      final (DemoAwareRepository _, AppController c) = await _start(f);
      c.pickCompany(kDemoCompany);
      final int before = f.to('/company').length;
      await c.pullRefresh();
      expect(f.to('/company').length, greaterThan(before));
      expect(c.demo, isTrue); // the user's pick is kept
      c.dispose();
    });

    test('sign out on Demo Company, sign in again → real server login, real company', () async {
      final FakeBackend f = FakeBackend();
      final (DemoAwareRepository r, AppController c) = await _start(f);
      c.pickCompany(kDemoCompany);
      expect(c.demo, isTrue);
      c.logout();
      expect(c.loggedIn, isFalse);
      expect(r.isRemote, isTrue); // the demo view went with the session
      final int logins = f.to('/auth/login').length;
      c.setF('user', 'ravi@x.in');
      c.setF('pass', 'secret');
      c.doLogin();
      for (int i = 0; i < 20 && c.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(f.to('/auth/login').length, logins + 1); // a real sign-in
      expect(c.loggedIn, isTrue);
      expect(c.demo, isFalse);
      expect(r.activeCompanyId, kGuid);
      expect(c.demoMode, 'auto');
      c.dispose();
    });
  });

  group('feedback', () {
    test('server without the feedback route: clear message, text kept', () async {
      final FakeBackend f = FakeBackend()..feedbackMissing = true;
      final (DemoAwareRepository _, AppController c) = await _start(f);
      c.openFeedback();
      c.setF('fbMsg', 'Please add GST reports');
      await c.submitFeedback();
      expect(c.toast, contains('not available on the server yet'));
      expect(c.toast, isNot(contains('Cannot POST')));
      expect(c.overlay, 'feedback');
      expect(c.f('fbMsg'), 'Please add GST reports');
      c.dispose();
    });

    test('sends type, rating, message; closes and clears', () async {
      final FakeBackend f = FakeBackend();
      final (DemoAwareRepository _, AppController c) = await _start(f);
      c.openFeedback();
      c.setFeedbackRating(4);
      expect(c.feedbackError, isNotNull); // no message yet
      await c.submitFeedback();
      expect(f.feedback, isEmpty);
      c.setF('fbMsg', '  Love the outstanding view  ');
      await c.submitFeedback();
      expect(f.feedback.single['type'], 'feedback');
      expect(f.feedback.single['rating'], 4);
      expect(f.feedback.single['message'], 'Love the outstanding view');
      expect(c.overlay, isNull);
      expect(c.f('fbMsg'), isEmpty);
      expect(c.toast, contains('Thank you'));
      // Bug reports carry no rating.
      c.openFeedback();
      c.setFeedbackType('bug');
      c.setFeedbackRating(2);
      c.setF('fbMsg', 'Crash on save');
      await c.submitFeedback();
      expect(f.feedback.last['type'], 'bug');
      expect(f.feedback.last.containsKey('rating'), isFalse);
      c.dispose();
    });

    for (final (String mode, String says) x in <(String, String)>[
      ('failed', 'could not be sent'),
      ('skipped', 'not set up on the server'),
      ('legacy', 'did not confirm'),
    ]) {
      test('email ${x.$1}: saved, never shown as sent', () async {
        final FakeBackend f = FakeBackend()..feedbackEmail = x.$1;
        final (DemoAwareRepository _, AppController c) = await _start(f);
        c.openFeedback();
        c.setF('fbMsg', 'Totals look wrong');
        await c.submitFeedback();
        expect(f.feedback, hasLength(1)); // stored once
        expect(c.toast, contains('saved (#1)'));
        expect(c.toast, contains(x.$2));
        expect(c.toast, isNot(contains('Thank you')));
        expect(c.toast, isNot(contains('your feedback was sent')));
        // Saved: the form closes (resending would store it twice).
        expect(c.overlay, isNull);
        expect(c.fbSending, isFalse);
        c.dispose();
      });
    }

    test('rate limited: message kept, form stays open', () async {
      final FakeBackend f = FakeBackend()..feedbackLimited = true;
      final (DemoAwareRepository _, AppController c) = await _start(f);
      c.openFeedback();
      c.setF('fbMsg', 'Please add GST reports');
      await c.submitFeedback();
      expect(c.overlay, 'feedback');
      expect(c.f('fbMsg'), 'Please add GST reports');
      expect(c.toast, contains('try again later'));
      expect(c.fbSending, isFalse);
      c.dispose();
    });

    test('sent to the real account even while demo data is shown', () async {
      final FakeBackend f = FakeBackend()..newAccount = true;
      final (DemoAwareRepository _, AppController c) = await _start(f);
      expect(c.demo, isTrue);
      c.openFeedback();
      c.setF('fbMsg', 'Exploring the demo');
      await c.submitFeedback();
      expect(f.feedback.single['message'], 'Exploring the demo');
      c.dispose();
    });
  });

  group('screens', () {
    setUpAll(loadFigtree);

    testWidgets('demo banner on every screen at 320 px; Connect Tally', (
      WidgetTester t,
    ) async {
      t.view.physicalSize = const Size(320 * 3, 720 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final FakeBackend f = FakeBackend()..newAccount = true;
      final (DemoAwareRepository _, AppController c) = await _start(f);
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

      await settle();
      for (final String s in <String>[
        'home',
        'vHub',
        'outHub',
        'reports',
        'items',
        'settings',
      ]) {
        c.jump(s);
        await settle();
        expect(find.byKey(const ValueKey<String>('demoBanner')), findsOneWidget);
        expect(t.takeException(), isNull, reason: s);
      }
      c.jump('home');
      await settle();
      await t.tap(find.byKey(const ValueKey<String>('demoConnect')));
      await settle();
      expect(c.overlay, 'connectTally');
      await t.tap(find.byKey(const ValueKey<String>('useMyData')));
      await settle();
      expect(c.demo, isFalse);
      expect(find.byKey(const ValueKey<String>('demoBanner')), findsNothing);
      // Feedback from the header.
      await t.tap(find.byKey(const ValueKey<String>('feedbackBtn')));
      await settle();
      expect(c.overlay, 'feedback');
      c.setF('fbMsg', 'Nice app');
      await settle();
      await t.tap(find.byKey(const ValueKey<String>('fbSend')));
      await settle();
      expect(f.feedback.single['message'], 'Nice app');
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
