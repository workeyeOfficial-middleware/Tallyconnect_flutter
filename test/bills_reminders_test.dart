// Bill details (bill type "Sales" / "Purchase", Bill date and Credit period
// from the synced bill date), the outstanding graph's Ageing terms, and the
// payment reminder settings: admin edits (Automatic / Manual, before /
// after / both, days, hour), others read them, a server without the table,
// the customers due today, and the phone's due alerts following them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/notify/reminder_alarms.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/core/utils/format.dart';
import 'package:tallyconnect_ui/data/api/adapters.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/data/repositories/tally_repository.dart';
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

Future<AppController> _start(
  FakeBackend f, {
  String as = 'ADMIN',
  LocalStorage? store,
  bool widget = false,
}) async {
  final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
  await r.login('ravi@x.in', 'secret', as);
  await r.refreshAll();
  final AppController c = AppController(
    store: store ?? LocalStorage.memory(),
    repo: r,
    startScreen: 'home',
  );
  c.afterRefresh(quietOk: true);
  // In a widget test the clock is fake: the screen's pumps finish it.
  if (!widget) await pumpEventQueue();
  return c;
}

class _DueRepo extends MockTallyRepository {
  _DueRepo(this.recv);
  final List<Bill> recv;
  @override
  List<Bill> receivables() => recv;
  @override
  List<Bill> payables() => const <Bill>[];
}

Bill _bill(String no, DateTime due) => Bill(
  'Mehta',
  no,
  '',
  dmy(due),
  '',
  1000,
  'ok',
  '',
  '',
  'recv',
  'Mehta|$no',
  null,
  due,
);

void main() {
  group('bill details', () {
    test('bill date from the server → Bill date and Credit period', () {
      final DateTime t = DateTime(2026, 10, 12);
      Bill b(String? billDate, String due) => billFrom(<String, Object?>{
        'ledger_name': 'Mehta',
        'bill_name': 'S/1',
        'pending_amount': '100',
        'due_date': due,
        'bill_type': 'RECEIVABLE',
        'bill_date': billDate,
      }, t)!;
      expect(b('2026-09-01', '2026-10-01').credit, '30 days');
      expect(b('2026-09-01', '2026-10-01').bill, '01 Sep 2026');
      expect(b('2026-10-01', '2026-10-01').credit, 'None');
      expect(b('2026-09-30', '2026-10-01').credit, '1 day');
      // Not synced yet (older server): shown as not known, as before.
      expect(b(null, '2026-10-01').credit, '—');
      expect(creditPeriod(null, DateTime(2026)), '—');
    });
  });

  group('payment reminder settings', () {
    test(
      'admin: Automatic, both, 5 days before / 2 after every 7, 9 AM',
      () async {
        final FakeBackend f = FakeBackend();
        final AppController c = await _start(f);
        expect(c.remSettings.canEdit, isTrue);
        expect(c.remSettings.automatic, isFalse); // default: Manual
        c.openReminderSettings();
        await pumpEventQueue();
        expect(c.overlay, 'remSettings');
        c.editRemDraft((ReminderSettings s) => s.copyWith(mode: 'automatic'));
        c.editRemDraft((ReminderSettings s) => s.copyWith(timing: 'both'));
        for (int i = 0; i < 2; i++) {
          c.editRemDraft(
            (ReminderSettings s) => s.copyWith(beforeDays: s.beforeDays + 1),
          );
        }
        c.editRemDraft(
          (ReminderSettings s) => s.copyWith(afterDays: 2, repeatDays: 7),
        );
        c.editRemDraft((ReminderSettings s) => s.copyWith(sendHour: 9));
        await c.saveReminderSettings();
        expect(f.remSettingsPuts.single, <String, Object?>{
          'mode': 'automatic',
          'timing': 'both',
          'before_days': 5,
          'after_days': 2,
          'repeat_days': 7,
          'send_hour': 9,
        });
        expect(c.overlay, isNull);
        expect(c.remSettings.automatic, isTrue);
        expect(
          c.remRuleText(c.remSettings),
          '5 days before and 2 days after (then every 7 days) the due date, at 9:00 AM',
        );
        c.dispose();
      },
    );

    test('team member: sees them, cannot change them', () async {
      final FakeBackend f = FakeBackend()
        ..remSettings = <String, Object?>{
          'mode': 'automatic',
          'timing': 'after',
          'before_days': 3,
          'after_days': 1,
          'repeat_days': 0,
          'send_hour': 10,
        };
      final AppController c = await _start(f, as: 'USER');
      expect(c.remSettings.automatic, isTrue);
      expect(c.remSettings.canEdit, isFalse);
      c.openReminderSettings();
      await pumpEventQueue();
      c.editRemDraft((ReminderSettings s) => s.copyWith(mode: 'manual'));
      await c.saveReminderSettings();
      expect(f.remSettingsPuts, isEmpty);
      expect(c.remSettings.automatic, isTrue);
      c.dispose();
    });

    test('server without the table: defaults shown, saving explains', () async {
      final FakeBackend f = FakeBackend()..remSettingsNoTable = true;
      final AppController c = await _start(f);
      expect(c.remSettings.ready, isFalse);
      expect(c.loggedIn, isTrue);
      c.openReminderSettings();
      await pumpEventQueue();
      await c.saveReminderSettings();
      expect(c.remSetError, contains('not available on the server yet'));
      c.dispose();
    });

    test(
      'Manual: customers due today listed first; their bills ticked',
      () async {
        final FakeBackend f = FakeBackend()
          ..remDue = <Map<String, Object?>>[
            <String, Object?>{
              'ledger_guid': 'L1',
              'party': 'Mehta Electricals',
              'emails': <String>['accounts@mehta.in'],
              'reason': 'after',
              'bills': <Object?>[
                <String, Object?>{
                  'bill_name': 'S/101',
                  'pending_amount': 10000.5,
                  'due_date': '2026-09-20',
                  'overdue_days': 22,
                },
              ],
              'total': 10000.5,
            },
          ];
        final AppController c = await _start(f);
        c.openEmailReminder();
        await pumpEventQueue();
        expect(c.dueToday!.single.party, 'Mehta Electricals');
        final DueReminder d = c.dueToday!.single;
        c.pickEmailParty(
          d.party,
          only: <String>{for (final ReminderBill b in d.bills) b.no},
        );
        expect(c.emPicked, <String>{'S/101'}); // S/102 is not due for one
        c.dispose();
      },
    );

    test('phone due alerts follow the settings (days, after, hour)', () async {
      final DateTime now = DateTime.now();
      final DateTime d10 = DateTime(now.year, now.month, now.day + 10);
      final LocalStorage s = LocalStorage.memory()
        ..save(LocalStorage.kRemSettings, <String, Object?>{
          'mode': 'manual',
          'timing': 'both',
          'before_days': 5,
          'after_days': 2,
          'repeat_days': 0,
          'send_hour': 9,
        });
      final NoReminderAlarms dev = NoReminderAlarms();
      final AppController c = AppController(
        store: s,
        repo: _DueRepo(<Bill>[_bill('S/1', d10)]),
        startScreen: 'home',
        alarms: dev,
      );
      await pumpEventQueue();
      c.setAutoRemind(true, quiet: true);
      await pumpEventQueue();
      final List<AlarmSpec> a =
          dev.pending.values
              .where((AlarmSpec x) => x.payload.startsWith('auto:'))
              .toList()
            ..sort((AlarmSpec x, AlarmSpec y) => x.at.compareTo(y.at));
      expect(a.map((AlarmSpec x) => x.at), <DateTime>[
        DateTime(d10.year, d10.month, d10.day - 5, 9),
        DateTime(d10.year, d10.month, d10.day + 2, 9),
      ]);
      expect(a.first.title, startsWith('Due in 5 days: collect'));
      expect(a.last.title, startsWith('Overdue: collect'));
      expect(a.first.body, contains('tap to send a reminder'));
      c.dispose();
    });
  });

  group('screens', () {
    setUpAll(loadFigtree);

    for (final double w in <double>[320, 412]) {
      testWidgets(
        'bill details, Ageing graph, reminder settings at ${w.toInt()} px',
        (WidgetTester t) async {
          t.view.physicalSize = Size(w * 3, 760 * 3);
          t.view.devicePixelRatio = 3;
          addTearDown(t.view.reset);
          final FakeBackend f = FakeBackend();
          final AppController c = await _start(f, widget: true);
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

          final Bill b = c.repo.receivables().first;
          c.go('billDetail', <String, Object?>{'bill': b});
          await settle();
          expect(find.textContaining('· Sales'), findsOneWidget);
          await t.ensureVisible(find.text('Credit period'));
          await settle();
          expect(find.text('Bill type'), findsOneWidget);
          expect(find.text('Due date'), findsOneWidget);
          expect(find.text('Purchase bill'), findsNothing);
          expect(find.text('Sales bill'), findsNothing);
          expect(t.takeException(), isNull);

          // Outstanding graph: Ageing (Tally's term).
          c.go('outList', <String, Object?>{
            'outKind': 'recv',
            'outFilter': 'all',
          });
          await settle();
          c.update(() => c.outView = 'graph');
          await settle();
          expect(find.text('By Ageing'), findsOneWidget);
          expect(find.text('By age'), findsNothing);
          expect(t.takeException(), isNull);

          // The Outstanding page: the settings icon sits beside search.
          c.go('outHub');
          await settle();
          final Finder search = find.byKey(
            const ValueKey<String>('outSearchBtn'),
          );
          final Finder gear = find.byKey(
            const ValueKey<String>('outRemSettingsBtn'),
          );
          expect(gear, findsOneWidget);
          expect(t.getCenter(gear).dy, t.getCenter(search).dy);
          expect(
            (t.getCenter(gear).dx - t.getCenter(search).dx).abs(),
            lessThan(80),
          );
          expect(t.takeException(), isNull);
          await t.tap(gear);
          await settle();
          expect(find.byKey(const ValueKey<String>('remMode')), findsOneWidget);
          await t.tap(find.text('Automatic'));
          await settle();
          await t.tap(find.text('Both'));
          await settle();
          expect(
            find.byKey(const ValueKey<String>('remAfter')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey<String>('remRepeat')),
            findsOneWidget,
          );
          expect(c.remDraft!.automatic, isTrue);
          expect(t.takeException(), isNull);
          await t.pump(const Duration(seconds: 6));
        },
      );
    }
  });
}
