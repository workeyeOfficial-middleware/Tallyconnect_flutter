// Leave management in the app: the admin's Leave settings (on / off, leave
// year, weekly off, half days, types, holidays), a member applying (days
// counted as the server does, retries, refusals), cancelling, the admin
// approving / rejecting, "On leave" on the Team page, no check-in popup on
// a day off, older servers; the screens at phone widths. The fake server's
// "today" is Saturday 3 Oct 2026 (weekly off: Sunday; holiday: 6 Oct).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/network/api_client.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

Future<AppController> _start(FakeBackend f, {String as = 'USER'}) async {
  final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
  await r.login('ravi@x.in', 'secret', as);
  await r.refreshAll();
  final AppController c = AppController(
    store: LocalStorage.memory(),
    repo: r,
    startScreen: 'home',
  );
  c.afterRefresh(quietOk: true);
  return c;
}

List<Map<String, Object?>> _calls(FakeBackend f, String path, [String? m]) => f
    .leaveCalls
    .where(
      (Map<String, Object?> x) =>
          x['path'] == '/api/leave/$path' && (m == null || x['method'] == m),
    )
    .toList();

/// A request of team member [user] (9 "asha", or 7: the member login).
void _seedReq(
  FakeBackend f, {
  int user = 9,
  String from = '2026-10-03',
  String? to,
  String status = 'pending',
  num days = 1,
}) => f.leaveReqs.add(<String, Object?>{
  'id': f.leaveReqs.length + 1,
  'user_id': user,
  'type_id': 1,
  'from': from,
  'to': to ?? from,
  'half_day': null,
  'days': days,
  'reason': 'Family function',
  'status': status,
  'decision_note': null,
  'created_at': '2026-10-01T05:00:00.000Z',
  'key': null,
});

LeaveBalance _bal(AppController c, String name) =>
    c.leaveMe!.balances.firstWhere((LeaveBalance b) => b.name == name);

void main() {
  group('member', () {
    test('leave off: not shown; the server refuses a request', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f);
      await c.loadLeave();
      expect(c.leaveMe!.enabled, isFalse);
      expect(c.leaveOn, isFalse);
      expect(c.leaveMe!.balances, isEmpty);
      await expectLater(
        c.repo.applyLeave(
          typeId: 1,
          from: DateTime(2026, 10, 5),
          to: DateTime(2026, 10, 5),
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.userMessage,
            'message',
            contains('Leave management is off'),
          ),
        ),
      );
      expect(f.leaveReqs, isEmpty);
      c.dispose();
    });

    test(
      'apply: days skip Sunday and holidays; one retry key; balance',
      () async {
        final FakeBackend f = FakeBackend()..leaveSetUp();
        final AppController c = await _start(f);
        await c.loadLeave();
        expect(c.leaveOn, isTrue);
        expect(c.leaveMe!.year.label, '2026-27');
        expect(c.leaveMe!.settings.weeklyOffLabel, 'Sunday');
        expect(c.leaveMe!.today!.kind, 'working'); // Saturday 3 Oct
        expect(_bal(c, 'Casual Leave').available, 12);
        expect(_bal(c, 'Unpaid Leave').unlimited, isTrue);

        c.openApplyLeave();
        expect(c.overlay, 'leaveApply');
        expect(c.f('lvType'), '1'); // the first type with days left
        expect(c.f('lvFrom'), '2026-10-03');
        // Mon 5 → Fri 9 Oct: the holiday on Tue 6 is not leave → 4 days.
        c.setLeaveFrom('2026-10-05');
        expect(c.f('lvTo'), '2026-10-05'); // To follows From
        c.setLeaveTo('2026-10-09');
        expect(c.leaveApplyDays, 4);
        expect(c.leaveApplyError, isNull);
        c.setF('lvReason', '  Family function ');
        await c.applyLeave();
        expect(c.overlay, isNull);
        expect(c.toast, 'Leave request sent · 4 days');
        final Map<String, Object?> sent = _calls(f, 'requests', 'POST').single;
        expect(sent['type_id'], 1);
        expect(sent['from'], '2026-10-05');
        expect(sent['to'], '2026-10-09');
        expect(sent['reason'], 'Family function');
        expect('${sent['idempotency_key']}'.length, greaterThanOrEqualTo(8));
        expect(f.leaveReqs.single['days'], 4);
        expect(_bal(c, 'Casual Leave').pending, 4);
        expect(_bal(c, 'Casual Leave').available, 8);
        expect(c.leaveMe!.requests.single.status, LeaveStatus.pending);

        // The same dates again: the server refuses (overlap); nothing saved.
        c.openApplyLeave();
        c.setLeaveFrom('2026-10-08');
        await c.applyLeave();
        expect(c.toast, contains('You already have pending leave'));
        expect(f.leaveReqs, hasLength(1));
        expect(c.overlay, 'leaveApply'); // still open to change the dates

        // Half day: one date, 0.5.
        c.setLeaveFrom('2026-10-12');
        c.setLeaveTo('2026-10-14');
        c.setLeaveHalf('first');
        expect(c.f('lvTo'), '2026-10-12');
        expect(c.leaveApplyDays, .5);
        c.setF('lvType', '2');
        await c.applyLeave();
        expect(f.leaveReqs.last['half_day'], 'first');
        expect(f.leaveReqs.last['days'], .5);
        // A new request: a new retry key.
        expect(
          _calls(f, 'requests', 'POST').last['idempotency_key'],
          isNot(_calls(f, 'requests', 'POST').first['idempotency_key']),
        );
        c.dispose();
      },
    );

    test('checks before sending: balance, dates, days off', () async {
      final FakeBackend f = FakeBackend()..leaveSetUp();
      final AppController c = await _start(f);
      await c.loadLeave();
      c.openApplyLeave();
      // 12 → 24 Oct: 12 working days (Sunday 18 off) — all of Casual.
      c.setLeaveFrom('2026-10-12');
      c.setLeaveTo('2026-10-24');
      expect(c.leaveApplyDays, 12);
      expect(c.leaveApplyError, isNull);
      c.setLeaveTo('2026-10-26');
      expect(c.leaveApplyError, 'Only 12 days of Casual Leave left');
      // Unpaid: no limit.
      c.setF('lvType', '3');
      expect(c.leaveApplyError, isNull);
      // Longer than the admin allows in one request (30 days).
      c.setLeaveTo('2026-11-20');
      expect(c.leaveApplyError, contains('at most 30 days'));
      // Only a Sunday.
      c.setLeaveFrom('2026-10-11');
      c.setLeaveTo('2026-10-11');
      expect(c.leaveApplyError, contains('weekly off or holidays'));
      // More than 7 days back.
      c.setLeaveFrom('2026-09-20');
      expect(c.leaveApplyError, contains('at most 7 days back'));
      await c.applyLeave(); // not sent
      expect(_calls(f, 'requests', 'POST'), isEmpty);
      c.dispose();
    });

    test('cancel while pending; approved leave cannot be cancelled', () async {
      final FakeBackend f = FakeBackend()..leaveSetUp();
      _seedReq(f, user: 7, from: '2026-10-12', days: 1);
      _seedReq(f, user: 7, from: '2026-10-14', days: 1, status: 'approved');
      final AppController c = await _start(f);
      await c.loadLeave();
      expect(_bal(c, 'Casual Leave').available, 10);
      final LeaveRequest p = c.leaveMe!.requests.firstWhere(
        (LeaveRequest r) => r.pending,
      );
      c.openLeaveReq(p);
      expect(c.overlay, 'leaveReq');
      await c.decideLeave('cancel');
      expect(c.toast, 'Leave cancelled');
      expect(f.leaveReqs.first['status'], 'cancelled');
      await pumpEventQueue();
      expect(_bal(c, 'Casual Leave').available, 11);
      // The server keeps approved leave for the admin to cancel.
      c.openLeaveReq(
        c.leaveMe!.requests.firstWhere(
          (LeaveRequest r) => r.status == LeaveStatus.approved,
        ),
      );
      await c.decideLeave('cancel');
      expect(c.toast, 'This request is already approved');
      expect(f.leaveReqs.last['status'], 'approved');
      c.dispose();
    });

    test('on leave today: no check-in popup; the today note', () async {
      final FakeBackend f = FakeBackend()..leaveSetUp();
      _seedReq(
        f,
        user: 7,
        from: '2026-10-02',
        to: '2026-10-05',
        status: 'approved',
        days: 2,
      );
      final AppController c = await _start(f);
      await c.loadLeave();
      await c.loadAttendance();
      expect(c.leaveMe!.today!.leave, isNotNull);
      expect(c.overlay, isNot('attPrompt'));
      // Without the leave the popup comes up.
      final FakeBackend g = FakeBackend()..leaveSetUp();
      final AppController d = await _start(g);
      await d.loadLeave();
      await d.loadAttendance();
      expect(d.overlay, 'attPrompt');
      c.dispose();
      d.dispose();
    });

    test('server without leave: says so; never signs out', () async {
      final FakeBackend f = FakeBackend()..leaveMissing = true;
      final AppController c = await _start(f);
      await c.loadLeave();
      expect(
        c.leaveError,
        contains('Leave is not available on the server yet'),
      );
      expect(c.loggedIn, isTrue);
      c.dispose();
      final AppController a = await _start(
        FakeBackend()..leaveMissing = true,
        as: 'ADMIN',
      );
      await a.loadTeamLeave();
      expect(a.leavePending, 0);
      expect(a.loggedIn, isTrue);
      a.dispose();
    });
  });

  group('admin', () {
    test('Leave settings: on, weekly off, leave year, steps', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f, as: 'ADMIN');
      expect(c.canOpen('leaveSettings'), isTrue);
      c.openLeaveSettings();
      await pumpEventQueue();
      expect(c.screen, 'leaveSettings');
      expect(c.leaveAdmin!.settings.enabled, isFalse);
      expect(c.leaveAdmin!.types, isEmpty);

      await c.saveLeaveSettings(<String, Object?>{'enabled': true});
      expect(f.leaveSettings['enabled'], isTrue);
      expect(c.leaveAdmin!.settings.enabled, isTrue);
      expect(c.toast, 'Leave management is on');

      c.toggleWeeklyOff(6);
      await pumpEventQueue();
      expect(f.leaveSettings['weekly_off'], <int>[0, 6]);
      expect(c.leaveAdmin!.settings.weeklyOffLabel, 'Saturday, Sunday');

      // Leave year: April → March; January ← December goes round.
      c.stepLeaveSetting('year_start_month', -1);
      await pumpEventQueue();
      expect(f.leaveSettings['year_start_month'], 3);
      await c.saveLeaveSettings(<String, Object?>{'year_start_month': 1});
      c.stepLeaveSetting('year_start_month', -1);
      await pumpEventQueue();
      expect(f.leaveSettings['year_start_month'], 12);

      // Back-dated days never below 0.
      await c.saveLeaveSettings(<String, Object?>{'backdate_days': 0});
      c.stepLeaveSetting('backdate_days', -1);
      await pumpEventQueue();
      expect(f.leaveSettings['backdate_days'], 0);
      expect(
        _calls(
          f,
          'settings',
          'PUT',
        ).where((Map<String, Object?> x) => x['backdate_days'] == -1),
        isEmpty,
      );
      c.dispose();
    });

    test('leave types and holidays', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f, as: 'ADMIN');
      c.openLeaveSettings();
      await pumpEventQueue();
      await c.addDefaultLeaveTypes();
      expect(c.leaveAdmin!.types.map((LeaveType t) => t.name), <String>[
        'Casual Leave',
        'Sick Leave',
        'Unpaid Leave',
      ]);
      expect(c.leaveAdmin!.types.last.summary, 'No limit · Unpaid');

      c.openLeaveType();
      expect(c.overlay, 'leaveType');
      expect(c.leaveTypeError, 'Give the leave type a name');
      c.setF('ltName', 'Earned Leave');
      c.setF('ltQuota', '1.3');
      expect(c.leaveTypeError, contains('half days'));
      c.setF('ltQuota', '15');
      c.toggleLeaveTypeFlag('ltCarry');
      c.setF('ltMaxCarry', '10');
      await c.saveLeaveType();
      expect(c.overlay, isNull);
      final Map<String, Object?> sent = _calls(f, 'types', 'POST').single;
      expect(sent['name'], 'Earned Leave');
      expect(sent['yearly_quota'], 15);
      expect(sent['carry_forward'], isTrue);
      expect(sent['max_carry'], 10);
      expect(sent.containsKey('active'), isFalse);
      expect(
        c.leaveAdmin!.types.last.summary,
        '15 days a year · Paid · Carries forward (max 10)',
      );

      // A name taken: the server says so.
      c.openLeaveType(c.leaveAdmin!.types[1]);
      expect(c.f('ltQuota'), '6');
      c.setF('ltName', 'casual leave');
      await c.saveLeaveType();
      expect(c.toast, 'A leave type with this name exists');
      // Hide it.
      c.setF('ltName', 'Sick Leave');
      c.toggleLeaveTypeFlag('ltActive');
      await c.saveLeaveType();
      expect(_calls(f, 'types/2', 'PUT').last['active'], isFalse);
      expect(c.leaveAdmin!.types[1].summary, endsWith('Hidden'));

      c.openAddHoliday();
      expect(c.holidayError, 'Give the holiday a name');
      c.setF('hdDate', '2026-11-08');
      c.setF('hdName', 'Diwali');
      await c.saveHoliday();
      expect(c.leaveAdmin!.holidays.single.name, 'Diwali');
      await c.deleteHoliday(c.leaveAdmin!.holidays.single);
      expect(c.leaveAdmin!.holidays, isEmpty);
      c.dispose();
    });

    test(
      'requests: pending count, approve with a note, reject, on leave today',
      () async {
        final FakeBackend f = FakeBackend()..leaveSetUp();
        _seedReq(f, from: '2026-10-03', to: '2026-10-05', days: 2); // asha
        _seedReq(f, user: 10, from: '2026-10-20');
        final AppController c = await _start(f, as: 'ADMIN');
        await c.loadTeamLeave();
        expect(c.leavePending, 2);
        expect(c.leaveTodayOf('9'), isNull); // pending is not leave yet

        c.openLeaveRequests();
        await pumpEventQueue();
        expect(c.screen, 'leaveReqs');
        expect(c.leaveReqs!.map((LeaveRequest r) => r.username), <String>[
          'asha',
          'vik',
        ]);
        c.openLeaveReq(c.leaveReqs!.first);
        c.setF('lvNote', 'Enjoy');
        await c.decideLeave('approve');
        expect(c.toast, 'Leave approved');
        expect(f.leaveReqs.first['status'], 'approved');
        expect(_calls(f, 'requests/1/approve').single['note'], 'Enjoy');
        await pumpEventQueue();
        expect(c.leavePending, 1);
        expect(c.leaveTodayOf('9')!.typeName, 'Casual Leave');

        c.openLeaveReq(c.leaveReqs!.single);
        await c.decideLeave('reject');
        expect(f.leaveReqs.last['status'], 'rejected');
        await pumpEventQueue();
        expect(c.leavePending, 0);
        c.setLeaveReqStatus('all');
        await pumpEventQueue();
        expect(c.leaveReqs, hasLength(2));

        // A member's leave year.
        c.openLeaveMember('9', 'asha');
        await pumpEventQueue();
        expect(c.screen, 'leaveMember');
        expect(
          c.leaveMemberData!.balances
              .firstWhere((LeaveBalance b) => b.name == 'Casual Leave')
              .used,
          2,
        );
        c.dispose();
      },
    );

    test('a member cannot open the admin screens', () async {
      final AppController c = await _start(FakeBackend());
      for (final String s in <String>[
        'leaveReqs',
        'leaveSettings',
        'leaveMember',
      ]) {
        expect(c.canOpen(s), isFalse, reason: s);
      }
      expect(c.canOpen('leave'), isTrue);
      c.dispose();
    });
  });

  group('screens', () {
    setUpAll(loadFigtree);

    Future<AppController> open(
      WidgetTester t,
      FakeBackend f,
      double w,
      String as,
    ) async {
      t.view.physicalSize = Size(w * 3, 760 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final AppController c = await _start(f, as: as);
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

    Future<void> tap(WidgetTester t, String k) async {
      final Finder x = find.byKey(ValueKey<String>(k));
      await t.ensureVisible(x);
      await t.pump();
      await t.tap(x);
      await settle(t);
    }

    for (final double w in <double>[320, 412]) {
      testWidgets('member: Leave → apply → request listed at ${w.toInt()} px', (
        WidgetTester t,
      ) async {
        final FakeBackend f = FakeBackend()..leaveSetUp();
        final AppController c = await open(t, f, w, 'USER');
        c.go('home');
        await settle(t);
        if (c.overlay == 'attPrompt') c.laterCheckIn();
        c.openOverlay('menu');
        await settle(t);
        await t.tap(find.text('Leave'));
        await settle(t);
        expect(c.screen, 'leave');
        expect(
          find.byKey(const ValueKey<String>('leaveBal-1')),
          findsOneWidget,
        );
        expect(find.text('Leave year 2026-27'), findsOneWidget);
        expect(t.takeException(), isNull);
        await tap(t, 'leaveApplyBtn');
        expect(c.overlay, 'leaveApply');
        expect(
          find.byKey(const ValueKey<String>('voiceBtn-lvReason')),
          findsOneWidget,
        );
        c.setLeaveFrom('2026-10-05');
        c.setLeaveTo('2026-10-07');
        await settle(t);
        expect(find.textContaining('2 days of leave'), findsOneWidget);
        expect(t.takeException(), isNull);
        await tap(t, 'lvSend');
        expect(c.overlay, isNull);
        expect(f.leaveReqs, hasLength(1));
        await settle(t);
        await t.scrollUntilVisible(
          find.byKey(const ValueKey<String>('leaveReq-1')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Waiting for approval'), findsOneWidget);
        await tap(t, 'leaveReq-1');
        expect(
          find.byKey(const ValueKey<String>('leaveCancel')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await t.pump(const Duration(seconds: 6));
      });

      testWidgets('admin: Team page → requests → approve at ${w.toInt()} px', (
        WidgetTester t,
      ) async {
        final FakeBackend f = FakeBackend()..leaveSetUp();
        _seedReq(f, from: '2026-10-03', to: '2026-10-05', days: 2);
        final AppController c = await open(t, f, w, 'ADMIN');
        c.go('team');
        await settle(t);
        await settle(t);
        expect(
          find.byKey(const ValueKey<String>('teamLeaveCard')),
          findsOneWidget,
        );
        expect(find.text('1 waiting for approval'), findsOneWidget);
        expect(t.takeException(), isNull);
        await tap(t, 'teamLeaveCard');
        expect(c.screen, 'leaveReqs');
        await tap(t, 'leaveReq-1');
        expect(c.overlay, 'leaveReq');
        expect(
          find.byKey(const ValueKey<String>('leaveApprove')),
          findsOneWidget,
        );
        await tap(t, 'leaveApprove');
        expect(f.leaveReqs.single['status'], 'approved');
        expect(t.takeException(), isNull);
        // Team page: asha is on leave today.
        c.go('team');
        await settle(t);
        await settle(t);
        await t.scrollUntilVisible(
          find.byKey(const ValueKey<String>('teamLeave-9')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('On leave · Casual Leave'), findsOneWidget);
        await t.pump(const Duration(seconds: 6));
      });

      testWidgets('admin: Leave settings at ${w.toInt()} px', (
        WidgetTester t,
      ) async {
        final FakeBackend f = FakeBackend()..leaveSetUp();
        final AppController c = await open(t, f, w, 'ADMIN');
        c.openLeaveSettings();
        await settle(t);
        expect(find.text('Leave settings'), findsWidgets);
        await tap(t, 'weeklyOff-6');
        expect(f.leaveSettings['weekly_off'], <int>[0, 6]);
        await t.scrollUntilVisible(
          find.byKey(const ValueKey<String>('leaveAddHoliday')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Dussehra'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('leaveType-1')),
          findsOneWidget,
        );
        await tap(t, 'leaveAddHoliday');
        expect(c.overlay, 'leaveHoliday');
        expect(t.takeException(), isNull);
        c.closeOv();
        await settle(t);
        await tap(t, 'leaveType-1');
        expect(c.overlay, 'leaveType');
        expect(t.takeException(), isNull);
        await t.pump(const Duration(seconds: 6));
      });
    }
  });
}
