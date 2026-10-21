// Sales team check-in / check-out in the app: a member checks in and out,
// retries never double check-in, history; members not on the team and demo
// cannot; the admin's team view (status, filters, a person's history) and
// the Configure User switch; the screens at phone widths.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
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

List<Map<String, Object?>> _calls(FakeBackend f, String path) => f.attRequests
    .where((Map<String, Object?> x) => x['path'] == '/api/attendance/$path')
    .toList();

/// Team member 9 checked in [minutes] ago, last seen [seen] minutes ago.
void _seedAsha(FakeBackend f, {int minutes = 90, int seen = 2}) {
  final DateTime now = f.attNow();
  final DateTime d = DateTime(now.year, now.month, now.day);
  f.attSessions.add(<String, Object?>{
    'id': 100,
    'user_id': '9',
    'work_date':
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
    'check_in_at': now.subtract(Duration(minutes: minutes)),
    'last_seen_at': now.subtract(Duration(minutes: seen)),
    'check_out_at': null,
    'in_note': null,
    'out_note': null,
    'closed_by': null,
    'key': null,
  });
}

void main() {
  group('controller', () {
    test('right after sign-in: check-in is known (no screen opened)', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f); // signs in, afterRefresh
      await pumpEventQueue();
      expect(c.screen, 'home');
      expect(c.attEnabled, isTrue);
      expect(_calls(f, 'me'), isNotEmpty);
      c.dispose();
    });

    test('check in → check out; a second tap is refused; history', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f);
      await c.loadAttendance();
      expect(c.attEnabled, isTrue);
      expect(c.attCheckedIn, isFalse);
      expect(c.attMe!.status, AttStatus.absent);

      await c.checkIn();
      expect(c.attCheckedIn, isTrue);
      expect(c.toast, contains('Checked in at'));
      expect(f.attSessions, hasLength(1));
      final Object? key = _calls(f, 'check-in').single['idempotency_key'];
      expect(key, isA<String>());
      expect((key! as String).length, greaterThanOrEqualTo(8));
      expect(c.attMe!.status, AttStatus.active);

      // The server refuses a second check-in; the state stays correct.
      await c.checkIn();
      expect(c.toast, 'You are already checked in.');
      expect(f.attSessions, hasLength(1));
      expect(c.attCheckedIn, isTrue);
      expect(await c.repo.attendancePing(), isTrue);

      c.openCheckOut();
      expect(c.overlay, 'attCheckOut');
      c.setF('attNote', '  Visited 4 customers ');
      await c.checkOut();
      expect(c.overlay, isNull);
      expect(c.attCheckedIn, isFalse);
      expect(c.attMe!.status, AttStatus.checkedOut);
      expect(_calls(f, 'check-out').single['note'], 'Visited 4 customers');
      expect(c.toast, contains('Checked out at'));

      c.go('attendance');
      await pumpEventQueue();
      expect(c.attHist!.days, hasLength(1));
      expect(
        c.attHist!.days.single.sessions.single.outNote,
        'Visited 4 customers',
      );
      final Map<String, Object?> h = _calls(f, 'me/history').last;
      final (DateTime from, DateTime to) = c.attRange;
      expect(to.difference(from).inDays, 6); // the last 7 days
      expect(h['to'], isNotNull);

      // History dates: at most 92 days, To not after today.
      c.openAttRange();
      expect(c.overlay, 'dateRange');
      c.setF('drFrom', '2025-01-01');
      expect(c.rangeError, contains('at most 92 days'));
      c.dispose();
    });

    test(
      'my history keeps its From / To after the app is opened again',
      () async {
        final FakeBackend f = FakeBackend();
        final LocalStorage store = LocalStorage.memory();
        Future<AppController> start() async {
          final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
          await r.login('ravi@x.in', 'secret', 'USER');
          await r.refreshAll();
          return AppController(store: store, repo: r, startScreen: 'home');
        }

        final AppController c = await start();
        c.openAttendance();
        await pumpEventQueue();
        c.openAttRange();
        c.setF('drFrom', '2026-09-01');
        c.setF('drTo', '2026-09-30');
        c.applyRange();
        await pumpEventQueue();
        c.dispose();
        final AppController d = await start();
        expect(d.attRange, (DateTime(2026, 9), DateTime(2026, 9, 30)));
        d.openAttendance();
        await pumpEventQueue();
        expect(_calls(f, 'me/history').last['from'], '2026-09-01');
        d.dispose();
      },
    );

    test('server refuses / admin / demo / older server', () async {
      final FakeBackend f = FakeBackend()..attOnTeam = false;
      final AppController c = await _start(f);
      await c.loadAttendance();
      expect(c.attEnabled, isFalse);
      await c.checkIn();
      expect(c.toast, contains('Check-in is for team members'));
      expect(f.attSessions, isEmpty);
      c.dispose();

      final AppController a = await _start(FakeBackend(), as: 'ADMIN');
      await a.loadAttendance();
      expect(a.attEnabled, isFalse);
      expect(a.attMe!.isAdmin, isTrue);
      a.dispose();

      final FakeBackend h = FakeBackend()..newAccount = true;
      final AppController d = await _start(h);
      expect(d.demo, isTrue);
      await d.loadAttendance();
      expect(d.attMe, isNull);
      expect(h.attRequests, isEmpty); // demo never asks the server
      d.dispose();

      final AppController o = await _start(FakeBackend()..attMissing = true);
      await o.loadAttendance();
      expect(
        o.attError,
        contains('Check-in is not available on the server yet'),
      );
      o.dispose();
    });

    test(
      'admin: every member\'s status, filters, a person\'s history',
      () async {
        final FakeBackend f = FakeBackend();
        _seedAsha(f);
        final AppController c = await _start(f, as: 'ADMIN');
        c.openAttTeam();
        await pumpEventQueue();
        expect(c.screen, 'attTeam');
        expect(c.attTeam!.company, 'Gupta Industries');
        // Every team member, no switch needed.
        expect(
          c.attTeam!.members.map((AttMember m) => (m.userId, m.status)),
          <(String, AttStatus)>[
            ('9', AttStatus.active),
            ('10', AttStatus.absent),
          ],
        );
        expect(c.attTeam!.members.first.totalMinutes, 90);
        expect(c.attTeam!.checkedIn, 1);
        c.setAttTeamFilter('absent');
        expect(c.attTeamRows.map((AttMember m) => m.userId), <String>['10']);
        c.setAttTeamFilter('all');

        // The day before: nobody in; never after today.
        c.shiftAttDay(1);
        expect(c.attDay, DateTime(c.today.year, c.today.month, c.today.day));
        c.shiftAttDay(-1);
        await pumpEventQueue();
        expect(
          _calls(f, 'team').last['date'],
          isNot(_calls(f, 'team').first['date']),
        );
        expect(c.attTeam!.checkedIn, 0);
        expect(c.attOf('9'), isNull); // the Team page shows today only
        c.shiftAttDay(1);
        await pumpEventQueue();
        expect(c.attOf('9')!.status, AttStatus.active);

        c.openAttMember(
          c.attTeam!.members.firstWhere((AttMember m) => m.userId == '9'),
        );
        expect(c.screen, 'attMember');
        await pumpEventQueue();
        expect(f.attRequests.last['path'], '/api/attendance/team/9/history');
        expect(c.attHist!.days.single.totalMinutes, 90);

        // Idle: checked in, the app not seen for over 15 minutes.
        f.attSessions.first['last_seen_at'] = f.attNow().subtract(
          const Duration(minutes: 20),
        );
        await c.loadAttTeam();
        expect(c.attTeam!.members.first.status, AttStatus.idle);
        c.dispose();
      },
    );
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
      testWidgets(
        'member: Home profile → check in → check out at ${w.toInt()} px',
        (WidgetTester t) async {
          final FakeBackend f = FakeBackend();
          final AppController c = await open(t, f, w, 'USER');
          c.go('home');
          await settle(t);
          // Not checked in today: the check-in popup comes up first.
          expect(c.overlay, 'attPrompt');
          expect(find.text('Check in for today'), findsOneWidget);
          await tap(t, 'attPromptLater');
          expect(c.overlay, isNull);
          // The profile button sits right before Feedback.
          final Finder prof = find.byKey(const ValueKey<String>('profileBtn'));
          final Finder fb = find.byKey(const ValueKey<String>('feedbackBtn'));
          expect(prof, findsOneWidget);
          expect(t.getTopLeft(prof).dx, lessThan(t.getTopLeft(fb).dx));
          expect(t.takeException(), isNull);
          await tap(t, 'profileBtn');
          expect(c.overlay, 'profile');
          expect(find.text('Team member'), findsOneWidget);
          expect(find.text('Not checked in today'), findsOneWidget);
          await tap(t, 'profileCheckIn');
          expect(c.attCheckedIn, isTrue);
          expect(find.textContaining('Checked in since'), findsOneWidget);
          expect(t.takeException(), isNull);
          await tap(t, 'profileCheckOut');
          expect(c.overlay, 'attCheckOut');
          await t.enterText(
            find.byKey(const ValueKey<String>('attNote')),
            'Done',
          );
          await tap(t, 'attCheckOutConfirm');
          expect(c.attCheckedIn, isFalse);
          expect(_calls(f, 'check-out').single['note'], 'Done');
          // My attendance: today's day card.
          await tap(t, 'profileBtn');
          expect(find.text('Checked out'), findsOneWidget);
          await tap(t, 'profileMyAtt');
          expect(c.screen, 'attendance');
          await t.scrollUntilVisible(
            find.byKey(const ValueKey<String>('attHistTotal')),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            find.byKey(const ValueKey<String>('attHistTotal')),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          await t.pump(const Duration(seconds: 6));
        },
      );

      testWidgets(
        'admin: Team page shows check-ins → a person at ${w.toInt()} px',
        (WidgetTester t) async {
          final FakeBackend f = FakeBackend();
          _seedAsha(f);
          final AppController c = await open(t, f, w, 'ADMIN');
          // Home: no profile button on the admin's header.
          c.go('home');
          await settle(t);
          expect(
            find.byKey(const ValueKey<String>('profileBtn')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey<String>('feedbackBtn')),
            findsOneWidget,
          );
          // Team page: today's check-ins card and each member's status.
          c.go('team');
          await settle(t);
          await settle(t);
          expect(
            find.byKey(const ValueKey<String>('teamAttCard')),
            findsOneWidget,
          );
          expect(find.text("Today's check-ins"), findsOneWidget);
          await t.scrollUntilVisible(
            find.byKey(const ValueKey<String>('teamAtt-9')),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.textContaining('Active · in'), findsOneWidget);
          // Only the server's status: no made-up account badges / counts.
          expect(find.text('Invite sent'), findsNothing);
          expect(find.text('Pending'), findsNothing);
          expect(find.text('Checked in'), findsOneWidget); // filter
          expect(find.text('ravi'), findsOneWidget);
          // Filter by today's check-in.
          c.update(() => c.teamFilter = 'in');
          await settle(t);
          expect(find.text('asha'), findsOneWidget);
          expect(find.text('ravi'), findsNothing); // the admin: no check-in
          c.update(() => c.teamFilter = 'absent');
          await settle(t);
          expect(find.text('asha'), findsNothing);
          c.update(() => c.teamFilter = 'all');
          await settle(t);
          expect(t.takeException(), isNull);
          c.openAttTeam();
          await settle(t);
          expect(
            find.byKey(const ValueKey<String>('attMember-9')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey<String>('attMember-10')),
            findsOneWidget,
          );
          await tap(t, 'attStat-active');
          expect(
            find.byKey(const ValueKey<String>('attMember-10')),
            findsNothing,
          );
          await tap(t, 'attStat-active');
          await tap(t, 'attPrev');
          expect(find.byKey(const ValueKey<String>('attDate')), findsOneWidget);
          await tap(t, 'attNext');
          await tap(t, 'attMember-9');
          expect(c.screen, 'attMember');
          expect(find.textContaining('1 day'), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pump(const Duration(seconds: 6));
        },
      );
    }

    for (final double w in <double>[320, 412]) {
      testWidgets(
        'check-in popup after login: Check in from it at ${w.toInt()} px',
        (WidgetTester t) async {
          final FakeBackend f = FakeBackend();
          final AppController c = await open(t, f, w, 'USER');
          c.go('home');
          await settle(t);
          expect(c.overlay, 'attPrompt');
          expect(
            find.byKey(const ValueKey<String>('attPromptCheckIn')),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          await tap(t, 'attPromptCheckIn');
          // Checked in from the popup; it closes by itself.
          expect(c.attCheckedIn, isTrue);
          expect(f.attSessions, hasLength(1));
          expect(c.overlay, isNull);
          // Opening Home again: no popup (already checked in today).
          c.go('home');
          await settle(t);
          expect(c.overlay, isNull);
          expect(t.takeException(), isNull);
          await t.pump(const Duration(seconds: 6));
        },
      );
    }

    testWidgets('popup: "Later" (or closing it) is not shown again today', (
      WidgetTester t,
    ) async {
      final FakeBackend f = FakeBackend();
      final AppController c = await open(t, f, 360, 'USER');
      c.go('home');
      await settle(t);
      expect(c.overlay, 'attPrompt');
      c.closeOv(); // outside tap / Back = Later
      await settle(t);
      expect(c.overlay, isNull);
      c.go('home');
      await settle(t);
      await c.loadAttendance(quiet: true);
      await settle(t);
      expect(c.overlay, isNull);
      expect(f.attSessions, isEmpty); // nothing checked in by itself
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('popup: never for the admin, or once checked in', (
      WidgetTester t,
    ) async {
      final AppController a = await open(t, FakeBackend(), 360, 'ADMIN');
      a.go('home');
      await settle(t);
      await a.loadAttendance(quiet: true);
      await settle(t);
      expect(a.overlay, isNull);
      await t.pump(const Duration(seconds: 6));

      final FakeBackend f = FakeBackend();
      final DateTime now = f.attNow();
      f.attSessions.add(<String, Object?>{
        'id': 1,
        'user_id': '7',
        'work_date':
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        'check_in_at': now.subtract(const Duration(hours: 1)),
        'last_seen_at': now,
        'check_out_at': null,
      });
      final AppController c = await open(t, f, 360, 'USER');
      c.go('home');
      await settle(t);
      await c.loadAttendance(quiet: true);
      await settle(t);
      expect(c.attCheckedIn, isTrue);
      expect(c.overlay, isNull);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('server without check-in: the profile and screen say so', (
      WidgetTester t,
    ) async {
      final FakeBackend f = FakeBackend()..attMissing = true;
      final AppController c = await open(t, f, 360, 'USER');
      c.go('home');
      await settle(t);
      await tap(t, 'profileBtn');
      expect(
        find.textContaining('not available on the server yet'),
        findsOneWidget,
      );
      c.closeOv();
      c.openOverlay('menu');
      await settle(t);
      await t.tap(find.text('Check-in'));
      await settle(t);
      expect(c.screen, 'attendance');
      expect(
        find.textContaining('not available on the server yet'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
