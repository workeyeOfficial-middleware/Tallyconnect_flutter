// Attendance and leave for the admin (each employee's days, hours, leave
// and absences for any dates; one person's month calendar), check-in rules
// (positions; managers exempt; per person always / exempt) and ledgers by
// location (state, city / area, PIN from Tally) shared one or many. Today
// is Sat 3 Oct 2026; the team login is user 7, members 9 "asha" and 10
// "vik".
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/share/pdf_builder.dart';
import 'package:tallyconnect_ui/core/share/share_doc.dart';
import 'package:tallyconnect_ui/core/utils/format.dart' show dmy;
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/ledger_location.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart'
    show DataSet;
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';
import 'package:tallyconnect_ui/presentation/screens/att_admin_screens.dart'
    show ruleText;
import 'package:tallyconnect_ui/presentation/screens/attendance_screens.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;
import 'share_chart_test.dart' show FakeExporter, fonts;

Future<AppController> _start(
  FakeBackend f, {
  String as = 'ADMIN',
  List<Uri>? opened,
  bool widget = false,
  FakeExporter? exporter,
}) async {
  final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
  await r.login('ravi@x.in', 'secret', as);
  await r.refreshAll();
  await r.ensure(DataSet.ledgers);
  final AppController c = AppController(
    store: LocalStorage.memory(),
    repo: r,
    startScreen: 'home',
    exporter: exporter,
    linkOpener: (Uri u) async {
      opened?.add(u);
      return true;
    },
  );
  c.afterRefresh(quietOk: true);
  if (!widget) await pumpEventQueue();
  return c;
}

/// Lumilo-like ledgers with their Tally location.
List<Map<String, Object?>> _located() => <Map<String, Object?>>[
  <String, Object?>{
    'ledger_guid': 'M1',
    'name': 'Andheri Lights',
    'parent_group': 'Sundry Debtors',
    'state': 'Maharashtra',
    'pincode': '400069',
    'address': 'Lokhandwala, Andheri, Mumbai',
    'phone': '9820012345',
  },
  <String, Object?>{
    'ledger_guid': 'M2',
    'name': 'Grant Road Traders',
    'parent_group': 'Sundry Debtors',
    'state': 'Maharashtra',
    'pincode': '400007',
    'address': 'Grant Rd West MUMBAI 400007',
  },
  <String, Object?>{
    'ledger_guid': 'M3',
    'name': 'Vasai Works',
    'parent_group': 'Sundry Creditors',
    'state': 'Maharashtra',
    'pincode': '401208',
    'address': 'Waliv, Vasai East -401208',
  },
  <String, Object?>{
    'ledger_guid': 'K1',
    'name': 'Bengaluru Electricals',
    'parent_group': 'Sundry Debtors',
    'state': 'Karnataka',
    'pincode': '560001',
    'address': 'MG Road, Bengaluru',
  },
];

void main() {
  group('check-in rules (admin)', () {
    test(
      'managers exempt by position; one member exempted; team day',
      () async {
        final FakeBackend f = FakeBackend();
        final AppController c = await _start(f);
        c.openAttRules();
        await pumpEventQueue();
        expect(c.screen, 'attRules');
        expect(
          c.attRules!.members.every((AttRuleMember m) => m.required),
          isTrue,
        );

        await c.toggleExemptPosition('Manager');
        expect(f.attRulePuts.last, <String, Object?>{
          'exempt_positions': <String>['Manager'],
        });
        expect(c.attRules!.exemptPosition('manager'), isTrue);

        // Vik is a Manager (by position: exempt); Asha is exempted herself.
        c.editAttRuleMember(
          c.attRules!.members.firstWhere((AttRuleMember m) => m.userId == '10'),
        );
        expect(c.overlay, 'attRuleMember');
        c.setF('arPosition', 'Manager');
        await c.saveAttRuleMember('auto');
        expect(f.attRulePuts.last, <String, Object?>{
          'user_id': '10',
          'position': 'Manager',
          'rule': 'auto',
        });
        expect(c.overlay, isNull);
        final AttRuleMember vik = c.attRules!.members.firstWhere(
          (AttRuleMember m) => m.userId == '10',
        );
        expect((vik.required, vik.reason), (false, 'position'));
        expect(ruleText(vik), 'exempt by position');

        // Always for a manager: the admin's choice wins.
        c.editAttRuleMember(vik);
        await c.saveAttRuleMember('required');
        expect(
          c.attRules!.members
              .firstWhere((AttRuleMember m) => m.userId == '10')
              .required,
          isTrue,
        );
        await c.saveAttRuleMember('exempt');

        // The day: exempt members are "Not tracked", never "Not checked in".
        await c.loadAttTeam();
        final AttMember v = c.attTeam!.members.firstWhere(
          (AttMember m) => m.userId == '10',
        );
        expect(v.status, AttStatus.exempt);
        expect(v.position, 'Manager');
        expect(v.status.label, 'Not tracked');
        c.dispose();
      },
    );

    test(
      'an exempt team login: no check-in, no popup, the reason shown',
      () async {
        final FakeBackend f = FakeBackend()
          ..attExempt = <String>['Manager']
          ..attRules['7'] = ('Manager', 'auto');
        final AppController c = await _start(f, as: 'USER');
        await c.loadAttendance();
        expect(c.attMe!.exempt, isTrue);
        expect(c.attEnabled, isFalse);
        expect(c.overlay, isNot('attPrompt'));
        expect(attOffText(c.attMe!), contains('as Manager'));
        c.dispose();
      },
    );

    test(
      'server without the rules: everyone checks in, saving explains',
      () async {
        final FakeBackend f = FakeBackend()..attRulesMissing = true;
        final AppController c = await _start(f);
        c.openAttRules();
        await pumpEventQueue();
        expect(c.attRules!.ready, isFalse);
        await c.toggleExemptPosition('Manager');
        expect(c.attRulesError, contains('not available on the server yet'));
        c.dispose();
      },
    );
  });

  group('employee attendance (admin)', () {
    test('cards for a From–To; presets and custom dates; open one', () async {
      final FakeBackend f = FakeBackend();
      f.attSessions.add(<String, Object?>{
        'id': 1,
        'user_id': '9',
        'work_date': '2026-10-01',
        'check_in_at': DateTime(2026, 10, 1, 9, 30),
        'last_seen_at': DateTime(2026, 10, 1, 18),
        'check_out_at': DateTime(2026, 10, 1, 18),
        'closed_by': 'user',
      });
      final AppController c = await _start(f);
      c.openAttEmployees();
      await pumpEventQueue();
      expect(c.screen, 'attEmployees');
      Map<String, Object?> last() => f.attRequests.lastWhere(
        (Map<String, Object?> x) => x['path'] == '/api/attendance/summary',
      );
      expect(last()['from'], '2026-10-01'); // This month
      expect(last()['to'], '2026-10-03');
      final AttSumRow asha = c.attSum!.members.firstWhere(
        (AttSumRow r) => r.userId == '9',
      );
      expect(asha.presentDays, 1);
      expect(asha.totalMinutes, 510);
      expect(asha.leaveDays, 0.5);
      expect(asha.avgIn, '09:30');

      c.setAttSumPreset('lastMonth');
      await pumpEventQueue();
      expect((last()['from'], last()['to']), ('2026-09-01', '2026-09-30'));
      c.setAttSumPreset('range');
      expect(c.overlay, 'dateRange');
      c.setF('drFrom', '2026-08-01');
      c.setF('drTo', '2026-08-31');
      c.applyRange();
      await pumpEventQueue();
      expect((last()['from'], last()['to']), ('2026-08-01', '2026-08-31'));
      // More than 92 days: refused before asking the server.
      c.openRange('attsum');
      c.setF('drFrom', '2026-01-01');
      c.setF('drTo', '2026-08-31');
      expect(c.rangeError, contains('at most'));
      c.closeOv();

      c.openAttSumMember(c.attSum!.members.first);
      await pumpEventQueue();
      expect(c.screen, 'attMember');
      expect(c.attRange, (DateTime(2026, 8), DateTime(2026, 8, 31)));
      c.dispose();
    });

    test('a member month calendar: worked, leave, absent, ahead', () async {
      final FakeBackend f = FakeBackend()..leaveSetUp();
      f.leaveReqs.add(<String, Object?>{
        'id': 1,
        'user_id': 7,
        'type_id': 1,
        'from': '2026-10-01',
        'to': '2026-10-01',
        'half_day': null,
        'days': 1,
        'status': 'approved',
      });
      final AppController c = await _start(f, as: 'USER');
      await c.loadAttendance();
      await c.checkIn();
      c.openAttendance();
      c.setAttView('calendar');
      await pumpEventQueue();
      expect(c.attMonth, DateTime(2026, 10));
      expect(c.attRange, (DateTime(2026, 10), DateTime(2026, 10, 3)));
      expect(attDayOf(c, DateTime(2026, 10, 3)).$1, AttDayKind.worked);
      expect(attDayOf(c, DateTime(2026, 10, 1)).$1, AttDayKind.leave);
      expect(attDayOf(c, DateTime(2026, 10, 2)).$1, AttDayKind.absent);
      expect(attDayOf(c, DateTime(2026, 10, 10)).$1, AttDayKind.ahead);
      c.shiftAttMonth(1); // never a month ahead
      expect(c.attMonth, DateTime(2026, 10));
      c.shiftAttMonth(-1);
      await pumpEventQueue();
      expect(c.attRange, (DateTime(2026, 9), DateTime(2026, 9, 30)));
      expect(attDayOf(c, DateTime(2026, 9, 27)).$1, AttDayKind.weeklyOff);
      c.pickAttCalDay(DateTime(2026, 9, 28));
      expect(c.attCalDay, DateTime(2026, 9, 28));
      c.pickAttCalDay(DateTime(2026, 9, 28));
      expect(c.attCalDay, isNull);
      c.dispose();
    });
  });

  group('ledgers by location', () {
    test('state and city / area / PIN from Tally', () {
      Party p(String name, String? state, String? pin, String? addr) =>
          Party(name, 'c', '', 0, state: state, pincode: pin, address: addr);
      final Party a = p('A', 'Maharashtra', '400069', 'Andheri, Mumbai');
      final Party b = p('B', 'Maharashtra', '401208', 'Vasai East');
      final Party k = p('K', 'Karnataka', '560001', 'MG Road, Bengaluru');
      final Party none = p('N', null, null, null);
      bool m(Party x, LocFilter f) => matchesLocation(x, f);
      expect(m(a, const LocFilter(area: 'mumbai')), isTrue);
      expect(m(b, const LocFilter(area: 'Mumbai')), isFalse);
      expect(m(a, const LocFilter(area: '4000')), isTrue); // PIN start
      expect(m(b, const LocFilter(area: '4000')), isFalse);
      expect(m(k, const LocFilter(state: 'karnataka')), isTrue);
      expect(
        m(a, const LocFilter(state: 'Maharashtra', area: 'Andheri')),
        isTrue,
      );
      expect(
        m(k, const LocFilter(state: 'Maharashtra', area: 'MG Road')),
        isFalse,
      );
      expect(m(none, const LocFilter(area: 'Mumbai')), isFalse);
      expect(m(none, LocFilter.none), isTrue);
      expect(statesOf(<Party>[a, b, k, none]), <(String, int)>[
        ('Maharashtra', 2),
        ('Karnataka', 1),
      ]);
      expect(placeOf(a), '400069 · Maharashtra');
      expect(withLocation(<Party>[a, none]), 1);
    });

    test(
      'filter the list, share the matching ledgers (WhatsApp / PDF)',
      () async {
        final FakeBackend f = FakeBackend()..extraLedgers = _located();
        final List<Uri> opened = <Uri>[];
        final FakeExporter ex = FakeExporter();
        final AppController c = await _start(f, opened: opened, exporter: ex);
        final List<Party> pool = c.partyPool();
        expect(
          pool.firstWhere((Party x) => x.name == 'Vasai Works').state,
          'Maharashtra',
        );
        c.go('party');
        c.openPartyLocation();
        expect(c.overlay, 'partyLoc');
        c.setF('plArea', 'Mumbai');
        expect(
          pool.where((Party x) => matchesLocation(x, c.partyLocDraft)).length,
          2,
        );
        c.applyPartyLocation();
        expect(c.partyLoc.label, 'Mumbai');
        final List<Party> mumbai = pool
            .where((Party x) => matchesLocation(x, c.partyLoc))
            .toList();
        c.sharePartiesHere(mumbai);
        expect(c.pSelecting, isTrue);
        expect(c.pPicked.keys.toSet(), <String>{
          'Andheri Lights',
          'Grant Road Traders',
        });
        // A location is on: WhatsApp gets the formatted PDF (share sheet),
        // not a plain-text message.
        await c.whatsAppPickedParties();
        expect(opened, isEmpty);
        expect(ex.shared, <String>['Ledgers · Mumbai']);
        final ShareDoc d = c.pickedLocationDoc();
        expect(d.fileName, 'TallyConnect_Ledgers_Mumbai.pdf');
        expect(d.subtitle, '2 ledgers · as on ${dmy(c.today)}');
        expect(d.facts, contains(('City / area / PIN', 'Mumbai')));
        final List<List<String>> rows = d.table!.rows;
        expect(rows.map((List<String> r) => r[1].split('\n').first), <String>[
          'Andheri Lights',
          'Grant Road Traders',
        ]);
        // Address, then PIN and state on their own line; phone; balance.
        expect(
          rows.first[2],
          'Lokhandwala, Andheri, Mumbai\nPIN 400069 · Maharashtra',
        );
        expect(rows.first[3], '9820012345');
        expect(rows[1][3], '—');
        expect(d.text, isNot(contains('Lokhandwala')));
        expect(d.text, contains('2 ledgers'));
        // The real PDF: logo, Figtree only (no Courier), multi-line cells.
        final Uint8List logo = File(
          'assets/images/tc_logo.png',
        ).readAsBytesSync();
        // pdf prints a warning when a built-in (non-Unicode) font is used.
        final List<String> printed = <String>[];
        final Uint8List pdf = await runZoned(
          () => buildPdf(
            d,
            fonts: fonts(),
            accentArgb: 0xFF1F4FD8,
            logo: logo,
          ),
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, String line) => printed.add(line),
          ),
        );
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
        expect(printed, isEmpty);
        // The logo image is embedded (the file grows by about its size).
        final Uint8List plain = await buildPdf(
          d,
          fonts: fonts(),
          accentArgb: 0xFF1F4FD8,
        );
        expect(pdf.length - plain.length, greaterThan(logo.length ~/ 2));
        // The PDF button gives the same document.
        await c.sharePickedParties();
        expect(ex.shared, <String>['Ledgers · Mumbai', 'Ledgers · Mumbai']);
        // Without a location: the plain WhatsApp message as before.
        c.clearPartyLocation();
        await c.whatsAppPickedParties();
        final String text = Uri.decodeComponent(opened.single.query);
        expect(text, contains('Andheri Lights'));
        expect(text, contains('400069 · Maharashtra'));
        expect(text, isNot(contains('Vasai')));
        // Search finds the location too.
        expect(
          pool.firstWhere((Party x) => x.name == 'Grant Road Traders').search,
          contains('mumbai'),
        );
        c.clearPartyLocation();
        expect(c.partyLoc.on, isFalse);
        c.dispose();
      },
    );
  });

  group('screens', () {
    setUpAll(loadFigtree);

    for (final double w in <double>[320, 412]) {
      testWidgets('rules, employees, calendar, location at ${w.toInt()} px', (
        WidgetTester t,
      ) async {
        t.view.physicalSize = Size(w * 3, 760 * 3);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        final FakeBackend f = FakeBackend()
          ..extraLedgers = _located()
          ..attExempt = <String>['Manager']
          ..attRules['10'] = ('Manager', 'auto');
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

        c.go('team');
        await settle();
        final Finder rulesRow = find.byKey(
          const ValueKey<String>('teamAttRules'),
        );
        await t.scrollUntilVisible(
          rulesRow,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await t.tap(rulesRow);
        await settle();
        expect(c.screen, 'attRules');
        expect(
          find.byKey(const ValueKey<String>('attExempt-Manager')),
          findsOneWidget,
        );
        await t.tap(find.byKey(const ValueKey<String>('attRule-10')));
        await settle();
        expect(find.byKey(const ValueKey<String>('arRule')), findsOneWidget);
        expect(
          find.text('Does not check in; never counted as absent.'),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        c.closeOv();
        await settle();

        c.openAttEmployees();
        await settle();
        expect(
          find.byKey(const ValueKey<String>('attSumCard-9')),
          findsOneWidget,
        );
        expect(find.text('Not tracked'), findsWidgets); // Vik, a manager
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const ValueKey<String>('attSumCard-9')));
        await settle();
        expect(c.screen, 'attMember');
        await t.tap(find.text('Calendar'));
        await settle();
        expect(
          find.byKey(const ValueKey<String>('attCalendar')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('attCal-2026-10-01')),
          findsOneWidget,
        );
        // Cells show only the date; the status is the colour (legend).
        for (final String day in <String>['2026-10-01', '2026-10-02']) {
          final Finder cell = find.byKey(ValueKey<String>('attCal-$day'));
          final List<String?> words = find
              .descendant(of: cell, matching: find.byType(Text))
              .evaluate()
              .map((Element e) => (e.widget as Text).data)
              .toList();
          expect(words, <String>['${int.parse(day.substring(8))}']);
        }
        final Finder grid = find.byKey(const ValueKey<String>('attCalendar'));
        for (final String w in <String>['Absent', 'Present', 'Off', 'Leave']) {
          expect(
            find.descendant(of: grid, matching: find.text(w)),
            findsNothing,
          );
        }
        expect(
          find.byKey(const ValueKey<String>('attCalN-worked')),
          findsOneWidget,
        );
        await t.tap(find.byKey(const ValueKey<String>('attCal-2026-10-01')));
        await settle();
        expect(t.takeException(), isNull);

        c.go('party');
        await settle();
        await t.tap(find.byKey(const ValueKey<String>('partyLocBtn')));
        await settle();
        expect(
          find.byKey(const ValueKey<String>('plState-Maharashtra')),
          findsOneWidget,
        );
        await t.enterText(
          find.byKey(const ValueKey<String>('plArea')),
          'Mumbai',
        );
        await settle();
        expect(find.text('2 ledgers in Mumbai'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey<String>('plApply')));
        await settle();
        expect(
          find.byKey(const ValueKey<String>('partyLocShare')),
          findsOneWidget,
        );
        expect(find.textContaining('400069 · Maharashtra'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pump(const Duration(seconds: 6));
      });
    }
  });
}
