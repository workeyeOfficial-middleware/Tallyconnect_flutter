// Outstanding-bill reminders end to end: create → schedule (device
// notification) → persist → re-arm on restart → notification tap / Mark
// done / Snooze → update → remove; due-date alerts; the Reminders sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/notify/reminder_alarms.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/core/utils/format.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/tally_repository.dart';
import 'package:tallyconnect_ui/main.dart';

import 'screens_test.dart' show loadFigtree;

/// Sample data with bills due in the future (for due-date alerts).
class _DueRepo extends MockTallyRepository {
  _DueRepo(this.recv, this.pay);
  final List<Bill> recv, pay;
  @override
  List<Bill> receivables() => recv;
  @override
  List<Bill> payables() => pay;
}

Bill _bill(String party, String no, DateTime due, num amt, String kind) =>
    Bill(
      party,
      no,
      '',
      dmy(due),
      '',
      amt,
      'ok',
      '',
      '',
      kind,
      '$party|$no',
      null,
      due,
    );

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

void main() {
  group('reminder flow', () {
    test('create → schedule → persist → re-arm → done / snooze → remove', () async {
      final LocalStorage s = LocalStorage.memory();
      final NoReminderAlarms dev = NoReminderAlarms();
      final AppController c = AppController(
        store: s,
        startScreen: 'home',
        alarms: dev,
      );
      await pumpEventQueue();
      final Bill b = c.repo.receivables().first;

      // A time already passed today is refused (the 1:58 AM case).
      final DateTime past = DateTime.now().subtract(const Duration(hours: 2));
      c.openReminder(b);
      c.setF('remDate', ymd(past));
      c.setF('remTime', _hm(past));
      c.saveReminder();
      expect(c.reminderFor(b), isNull);
      expect(c.toast, contains('already passed'));
      expect(
        dev.pending.values.where((AlarmSpec a) => a.payload.startsWith('rem:')),
        isEmpty,
      );

      // Create: saved and scheduled as a device notification at that time.
      final DateTime at = DateTime.now().add(const Duration(days: 1, hours: 1));
      c.setF('remDate', ymd(at));
      c.setF('remTime', _hm(at));
      c.setF('remNote', 'Call Ravi');
      c.saveReminder();
      await pumpEventQueue();
      final Reminder r = c.reminderFor(b)!;
      expect(c.reminderStatus(r), 'Scheduled');
      final int id = alarmId('rem:${r.id}');
      expect(dev.pending.keys, contains(id));
      final AlarmSpec a = dev.pending[id]!;
      expect(a.at, r.at);
      expect(a.title, contains(b.party));
      expect(a.body, contains('Call Ravi'));
      expect(a.payload, 'rem:${r.id}');
      c.dispose();

      // Persist + restart: re-armed on the device.
      final NoReminderAlarms dev2 = NoReminderAlarms();
      final AppController c2 = AppController(
        store: s,
        startScreen: 'home',
        alarms: dev2,
      );
      await pumpEventQueue();
      expect(c2.reminderFor(b)!.note, 'Call Ravi');
      expect(dev2.pending.keys, contains(id));

      // Tap on the notification: Outstanding + the reminders list.
      dev2.tap(AlarmTap('rem:${r.id}'));
      await pumpEventQueue();
      expect(c2.screen, 'outHub');
      expect(c2.overlay, 'reminders');

      // Snooze button: rings again in 10 minutes.
      dev2.tap(AlarmTap('rem:${r.id}', 'snooze'));
      await pumpEventQueue();
      final Reminder sn = c2.reminderFor(b)!;
      final Duration left = sn.at!.difference(DateTime.now());
      expect(left.inMinutes, inInclusiveRange(8, 10));
      expect(dev2.pending[id]!.at, sn.at);

      // Mark done button: no longer rings, leaves the active list.
      dev2.tap(AlarmTap('rem:${r.id}', 'done'));
      await pumpEventQueue();
      expect(c2.reminderFor(b)!.done, isTrue);
      expect(c2.reminderStatus(c2.reminderFor(b)!), 'Done');
      expect(c2.activeReminders, isEmpty);
      expect(dev2.pending.containsKey(id), isFalse);

      // Update it again (new time): active and scheduled again.
      final DateTime at2 = DateTime.now().add(const Duration(days: 3));
      c2.openReminder(b);
      c2.setF('remDate', ymd(at2));
      c2.setF('remTime', '09:30');
      c2.saveReminder();
      await pumpEventQueue();
      expect(c2.reminderFor(b)!.done, isFalse);
      expect(c2.activeReminders, hasLength(1));
      expect(dev2.pending[id]!.at, DateTime(at2.year, at2.month, at2.day, 9, 30));

      // Remove: gone and its notification cancelled.
      c2.deleteReminder(c2.reminderFor(b)!.id);
      await pumpEventQueue();
      expect(c2.companyReminders, isEmpty);
      expect(dev2.pending.containsKey(id), isFalse);
      c2.dispose();
    });

    test('due-date alerts: 10 AM, 3 days before due; switch off cancels', () async {
      final DateTime now = DateTime.now();
      final DateTime d10 = DateTime(now.year, now.month, now.day + 10);
      final DateTime d2 = DateTime(now.year, now.month, now.day + 2);
      final _DueRepo repo = _DueRepo(
        <Bill>[_bill('Mehta', 'S/1', d10, 5000, 'recv')],
        <Bill>[
          _bill('Polycab', 'P/1', d10, 9000, 'pay'),
          _bill('Late', 'P/2', d2, 100, 'pay'), // alert time already gone
        ],
      );
      final LocalStorage s = LocalStorage.memory();
      final NoReminderAlarms dev = NoReminderAlarms();
      final AppController c = AppController(
        store: s,
        repo: repo,
        startScreen: 'home',
        alarms: dev,
      );
      await pumpEventQueue();
      expect(c.autoRemind, isTrue);
      expect(dev.pending, hasLength(2));
      final DateTime want = DateTime(d10.year, d10.month, d10.day - 3, 10);
      expect(dev.pending.values.every((AlarmSpec a) => a.at == want), isTrue);
      final AlarmSpec pay = dev.pending.values.firstWhere(
        (AlarmSpec a) => a.payload.startsWith('auto:pay'),
      );
      expect(pay.title, contains('pay ₹9,000'));
      expect(pay.body, contains('Polycab'));

      // Tap: opens that bill.
      dev.tap(AlarmTap(pay.payload));
      await pumpEventQueue();
      expect(c.screen, 'billDetail');
      expect(c.bill!.party, 'Polycab');

      // Switch off (saved): every due alert cancelled.
      c.toggleAutoRemind();
      expect(dev.pending, isEmpty);
      expect(c.autoRemind, isFalse);
      c.dispose();
      final AppController c2 = AppController(
        store: s,
        repo: repo,
        startScreen: 'home',
        alarms: dev,
      );
      await pumpEventQueue();
      expect(c2.autoRemind, isFalse);
      expect(dev.pending, isEmpty);
      c2.dispose();
    });
  });

  group('Reminders sheet', () {
    setUpAll(loadFigtree);

    testWidgets('bell on Outstanding lists active reminders with status', (
      WidgetTester t,
    ) async {
      t.view.physicalSize = const Size(360 * 3, 800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final NoReminderAlarms dev = NoReminderAlarms();
      final AppController c = AppController(
        store: LocalStorage.memory(),
        startScreen: 'home',
        alarms: dev,
      );
      final Bill b = c.repo.payables().first;
      final DateTime at = DateTime.now().add(const Duration(days: 2));
      c.openReminder(b);
      c.setF('remDate', ymd(at));
      c.setF('remTime', '11:15');
      c.saveReminder();
      c.closeOv();
      await t.pumpWidget(
        ProviderScope(
          overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
          child: const TallyConnectApp(),
        ),
      );
      c.go('outHub');
      for (int i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.tap(find.byKey(const ValueKey<String>('remindersBtn')));
      for (int i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(c.overlay, 'reminders');
      expect(find.text('Reminders'), findsWidgets);
      expect(find.text('1 active · rings on this phone at the set time'),
          findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.text(c.reminderWhen(c.reminderFor(b)!)), findsOneWidget);
      expect(t.takeException(), isNull);
      // Mark done from the list.
      await t.tap(find.text('Mark done'));
      await t.pump(const Duration(milliseconds: 300));
      expect(c.reminderFor(b)!.done, isTrue);
      expect(find.text('Done (1)'), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
