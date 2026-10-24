// Outstanding email reminders: the app sends only the party and bill
// numbers; the server's amounts, recipient and send result are shown as
// reported ("accepted for delivery", never "delivered"); explicit
// confirmation; failures, retry, no answer, demo and admin-only templates.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/network/api_client.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/core/storage/session_store.dart';
import 'package:tallyconnect_ui/core/storage/snapshot_cache.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart';
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

/// Signed-in app on [f] with the real company's data loaded.
Future<(DemoAwareRepository, AppController)> _start(
  FakeBackend f, {
  String role = 'ADMIN',
  ApiTallyRepository? live,
}) async {
  final DemoAwareRepository r = DemoAwareRepository(live: live ?? f.repo());
  await r.login('ravi@x.in', 'secret', role);
  await r.refreshAll();
  await r.ensure(DataSet.ledgers);
  final AppController c = AppController(
    store: LocalStorage.memory(),
    repo: r,
    startScreen: 'home',
  );
  c.afterRefresh(quietOk: true);
  return (r, c);
}

/// Opens the sheet for Mehta Electricals and loads the preview.
Future<void> _toPreview(AppController c) async {
  c.openEmailReminder(party: 'Mehta Electricals');
  await c.previewEmailReminder();
}

void main() {
  group('email reminders', () {
    test('customers with pending bills; all their bills ticked', () async {
      final FakeBackend f = FakeBackend();
      final (_, AppController c) = await _start(f);
      c.openEmailReminder();
      expect(c.overlay, 'emailRem');
      expect(c.emStep, 'party');
      final ({String party, int bills, num total}) m = c.emParties.single;
      expect(m.party, 'Mehta Electricals');
      expect(m.bills, 2);
      expect(m.total, 15000.5);
      c.pickEmailParty('Mehta Electricals');
      expect(c.emStep, 'bills');
      expect(c.emLedger, 'L1');
      expect(c.emPicked, <String>{'S/101', 'S/102'});
      c.toggleEmailBill('S/102');
      expect(c.emPicked, <String>{'S/101'});
      expect(c.emPickedTotal, 10000.5);
      c.emailAllBills(true);
      expect(c.emPicked.length, 2);
      c.dispose();
    });

    test('preview shows the server amounts, not the phone ones', () async {
      final FakeBackend f = FakeBackend()
        ..remBills = <String, (num, String)>{
          'S/101': (9000, '2026-09-20'), // part-paid since the phone loaded
        };
      final (_, AppController c) = await _start(f);
      await _toPreview(c);
      expect(c.emStep, 'preview');
      final ReminderPreview pv = c.emPreview!;
      expect(pv.total, 9000);
      expect(pv.bills.single.no, 'S/101');
      expect(pv.missingBills, <String>['S/102']);
      expect(pv.recipients, <String>['accounts@mehta.in']);
      expect(pv.canSend, isTrue);
      // The request carried only the party and the bill numbers.
      expect(f.violations, isEmpty);
      expect(f.remSends, isEmpty); // a preview never sends
      c.dispose();
    });

    test('nothing is sent without the confirmation step', () async {
      final FakeBackend f = FakeBackend();
      final (_, AppController c) = await _start(f);
      await _toPreview(c);
      await c.sendEmailReminder(); // still on the preview step
      expect(f.remSends, isEmpty);
      c.confirmEmailReminder();
      expect(c.emStep, 'confirm');
      await c.sendEmailReminder();
      expect(f.remSends, hasLength(1));
      final Map<String, Object?> sent = f.remSends.single;
      expect(sent['ledger_guid'], 'L1');
      expect(sent['bill_names'], <String>['S/101', 'S/102']);
      expect(sent['expected_total'], 15000.5);
      expect(f.violations, isEmpty);
      final ReminderOutcome r = c.emResult!;
      expect(r.ok, isTrue);
      expect(c.emStep, 'result');
      expect(r.message, contains('Accepted by Microsoft 365'));
      expect(r.message, contains('not confirmed'));
      expect(r.message, isNot(contains('delivered')));
      // The party's history shows it with the server's status.
      await pumpEventQueue();
      final List<ReminderLog> h = c.reminderLogs('L1')!;
      expect(h.single.status, 'accepted');
      expect(h.single.total, 15000.5);
      c.dispose();
    });

    test('provider failure is shown as not sent; retry from history', () async {
      final FakeBackend f = FakeBackend()..remSendFail = true;
      final (_, AppController c) = await _start(f);
      await _toPreview(c);
      c.confirmEmailReminder();
      await c.sendEmailReminder();
      final ReminderOutcome r = c.emResult!;
      expect(r.ok, isFalse);
      expect(r.code, 'send_failed');
      expect(r.message, contains('HTTP 403'));
      await pumpEventQueue();
      final ReminderLog failed = c.reminderLogs('L1')!.single;
      expect(failed.failed, isTrue);
      f.remSendFail = false;
      await c.retryEmailReminder(failed);
      expect(c.toast, contains('Accepted by Microsoft 365'));
      expect(c.reminderLogs('L1')!.single.status, 'accepted');
      expect(c.reminderLogs('L1')!.single.attempts, 2);
      c.dispose();
    });

    test('email not configured on the server: never a fake success', () async {
      final FakeBackend f = FakeBackend()..remNotConfigured = true;
      final (_, AppController c) = await _start(f);
      await _toPreview(c);
      expect(c.emPreview!.canSend, isFalse);
      expect(
        c.emPreview!.problems,
        contains('Email sending is not configured on the server.'),
      );
      c.confirmEmailReminder(); // the button is disabled; nothing happens
      expect(c.emStep, 'preview');
      await c.sendEmailReminder();
      expect(f.remSends, isEmpty);
      // Configuration removed between preview and send: the server says so.
      f.remNotConfigured = false;
      await c.previewEmailReminder();
      c.confirmEmailReminder();
      f.remNotConfigured = true;
      await c.sendEmailReminder();
      expect(c.emResult!.ok, isFalse);
      expect(c.emResult!.code, 'email_not_configured');
      expect(c.emResult!.message, contains('Nothing was sent'));
      c.dispose();
    });

    test('no email address in Tally: cannot send', () async {
      final FakeBackend f = FakeBackend()..remEmail = null;
      final (_, AppController c) = await _start(f);
      await _toPreview(c);
      expect(c.emPreview!.canSend, isFalse);
      expect(c.emPreview!.problems.single, contains('No valid email address'));
      c.dispose();
    });

    test('bills changed since the preview → review again', () async {
      final FakeBackend f = FakeBackend();
      final (_, AppController c) = await _start(f);
      await _toPreview(c);
      c.confirmEmailReminder();
      f.remBills['S/102'] = (2000, '2026-10-05'); // a receipt synced
      await c.sendEmailReminder();
      expect(c.emResult!.code, 'changed');
      expect(f.remSends, isEmpty);
      await c.emailTryAgain(); // → a fresh preview with the new total
      expect(c.emStep, 'preview');
      expect(c.emPreview!.total, 12000.5);
      c.dispose();
    });

    test(
      'no answer: "may or may not"; trying again never sends twice',
      () async {
        final FakeBackend f = FakeBackend();
        final ApiTallyRepository live = ApiTallyRepository(
          client: ApiClient(
            client: f.client,
            baseUrl: 'https://api.test',
            timeout: const Duration(milliseconds: 200),
          ),
          sessions: MemorySessionStore(),
          cache: MemorySnapshotCache(),
          clock: () => DateTime(2026, 10, 3, 11),
        );
        final (_, AppController c) = await _start(f, live: live);
        await _toPreview(c);
        c.confirmEmailReminder();
        f.delay = const Duration(
          milliseconds: 400,
        ); // the answer comes too late
        await c.sendEmailReminder();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(c.emResult!.unknown, isTrue);
        expect(c.emResult!.message, contains('may or may not have been sent'));
        expect(f.remSends, hasLength(1)); // it did reach the server
        f.delay = Duration.zero;
        await c.emailTryAgain(); // same confirmation, same key
        expect(c.emResult!.ok, isTrue);
        expect(c.emResult!.message, startsWith('Already sent'));
        expect(f.remSends, hasLength(1)); // one email only
        c.dispose();
      },
    );

    test('server without the reminder routes: clear message', () async {
      final FakeBackend f = FakeBackend()..remMissing = true;
      final (_, AppController c) = await _start(f);
      await _toPreview(c);
      expect(c.emStep, 'bills');
      expect(c.emError, 'Email reminders are not available on the server yet.');
      expect(c.repo.user, isNotNull); // the session is kept
      c.dispose();
    });

    test(
      'Demo Company: reminders are off, nothing reaches the server',
      () async {
        final FakeBackend f = FakeBackend()..newAccount = true;
        final (DemoAwareRepository r, AppController c) = await _start(f);
        expect(c.demo, isTrue);
        c.openEmailReminder(party: 'Shree Balaji Traders');
        expect(c.overlay, isNot('emailRem'));
        expect(c.toast, contains('Demo Company'));
        expect(c.canManageReminderTemplates, isFalse);
        await expectLater(
          r.sendReminder(
            ledgerGuid: 'L1',
            bills: <String>['S/101'],
            expectedTotal: 1,
            key: 'abcdefgh12345678',
          ),
          throwsA(same(kDemoReminderBlocked)),
        );
        expect(
          f.calls.where(
            (dynamic x) => '${x.url.path}'.startsWith('/api/reminders'),
          ),
          isEmpty,
        );
        c.dispose();
      },
    );

    test('templates: admin only', () async {
      final FakeBackend f = FakeBackend();
      final (_, AppController a) = await _start(f);
      expect(a.canManageReminderTemplates, isTrue);
      a.openReminderTemplates();
      await pumpEventQueue();
      expect(a.overlay, 'remTemplates');
      expect(a.emTemplates!.templates.single.builtIn, isTrue);
      a.editReminderTemplate(null);
      expect(a.overlay, 'remTemplateEdit');
      expect(a.templateFormError, 'Give the template a name');
      a.setF('rtName', 'Firm');
      await a.saveReminderTemplate();
      expect(f.remTemplates.single['name'], 'Firm');
      expect(a.overlay, 'remTemplates');
      a.dispose();

      final FakeBackend g = FakeBackend();
      final (_, AppController u) = await _start(g, role: 'USER');
      expect(u.canManageReminderTemplates, isFalse);
      u.openReminderTemplates();
      expect(u.overlay, isNull);
      expect(u.toast, contains('Only the admin'));
      u.dispose();
    });
  });

  group('screens', () {
    setUpAll(loadFigtree);

    testWidgets('Outstanding → email reminder → party history at 320 px', (
      WidgetTester t,
    ) async {
      t.view.physicalSize = const Size(320 * 3, 720 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final FakeBackend f = FakeBackend();
      final (_, AppController c) = await _start(f);
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

      Future<void> tapKey(String k) async {
        final Finder w = find.byKey(ValueKey<String>(k));
        await t.ensureVisible(w);
        await t.pump();
        await t.tap(w);
        await settle();
      }

      c.update(() => c.outKind = 'recv');
      c.go('outList');
      await settle();
      expect(t.takeException(), isNull);
      await tapKey('outEmailRem');
      expect(c.emStep, 'party');
      await tapKey('emParty-Mehta Electricals');
      expect(
        find.byKey(const ValueKey<String>('emBill-S/101')),
        findsOneWidget,
      );
      await tapKey('emPreviewBtn');
      expect(c.emStep, 'preview');
      expect(find.text('accounts@mehta.in'), findsOneWidget);
      expect(t.takeException(), isNull);
      await tapKey('emSendBtn');
      expect(
        find.byKey(const ValueKey<String>('emConfirmText')),
        findsOneWidget,
      );
      expect(f.remSends, isEmpty);
      await tapKey('emConfirmSend');
      expect(f.remSends, hasLength(1));
      expect(find.textContaining('Accepted by Microsoft 365'), findsOneWidget);
      expect(t.takeException(), isNull);
      await tapKey('emDone');
      expect(c.overlay, isNull);

      // Party detail lists the reminder with its server status.
      c.go('partyDetail', <String, Object?>{
        'party': 'Mehta Electricals',
        'partyTab': 'summary',
      });
      await settle();
      // The page builds its sections lazily: below the Address card the
      // reminders are not built until scrolled near, so scroll to them
      // (ensureVisible needs a built widget).
      final Finder log = find.byKey(const ValueKey<String>('remLog-1'));
      await t.scrollUntilVisible(
        log,
        200,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.pump();
      expect(log, findsOneWidget);
      expect(find.text('Accepted'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
