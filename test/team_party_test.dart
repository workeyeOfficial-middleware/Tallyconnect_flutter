// Sales Team user configuration (permissions, invite, delete) and the Party
// card (opening balance, pin inside the card), against the fake backend.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/design/tc_kit.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart';
import 'package:tallyconnect_ui/data/repositories/team_admin.dart';
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend;

Map<String, Object?> bodyOf(http.Request r) =>
    jsonDecode(r.body) as Map<String, Object?>;

void main() {
  group('team admin on the existing routes', () {
    test('loads, saves and keeps other stored keys; only that user', () async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.ensure(DataSet.team);
      final Member m = r.team().firstWhere((Member x) => x.id == '9');
      final TeamConfig cfg = TeamConfig(r.teamAdmin, m);
      await cfg.load();
      expect(cfg.error, isNull);
      expect(cfg.selError, isEmpty);

      // Layouts as stored (missing key = shown, false = hidden).
      final PermArea led = permArea('ledger'), inv = permArea('inventory');
      expect(cfg.columns(led)['dueDays'], isFalse);
      expect(cfg.columns(led)['partyName'], isTrue);
      expect(
        cfg.columns(permArea('order')).values.every((bool v) => v),
        isTrue,
      );
      expect(cfg.columns(inv)['rate'], isFalse);

      // Selections as stored.
      expect(cfg.selected['ledger'], <String>{'L1', 'OTHER-CO'});
      expect(cfg.selected['voucher'], <String>{'V1'});
      expect(cfg.selected['order'], isEmpty);
      expect(cfg.selected['inventory'], <String>{'Wire'});

      // Save a layout: PUT for user 9 only, other stored keys kept.
      await cfg.saveLayout(
        led,
        cfg.columns(led)
          ..['type'] = false
          ..['dueDays'] = true,
      );
      final http.Request put = f.calls.lastWhere(
        (http.Request x) => x.method == 'PUT',
      );
      expect(put.url.path, '/users/9/ledger-permissions');
      final Map<String, Object?> b = bodyOf(put);
      expect(b['note'], 'web');
      final Map<String, Object?> cols = b['columns']! as Map<String, Object?>;
      expect(cols['type'], isFalse);
      expect(cols['dueDays'], isTrue);
      expect(cols['partyName'], isTrue);
      // Reopened: the saved value is what loads.
      expect(cfg.columns(led)['type'], isFalse);

      await cfg.saveLayout(inv, cfg.columns(inv)..['value'] = false);
      final Map<String, Object?> ib = bodyOf(
        f.calls.lastWhere((http.Request x) => x.method == 'PUT'),
      );
      expect((ib['columns']! as Map<String, Object?>)['legacyKey'], isTrue);
      expect((ib['columns']! as Map<String, Object?>)['rate'], isFalse);
      expect(
        f.calls.where(
          (http.Request x) => x.method == 'PUT' && !x.url.path.contains('/9/'),
        ),
        isEmpty,
      );

      // Save a selection: the whole set for user 9 (unlisted keys kept).
      await cfg.saveSelection('ledger', <String>{'L1', 'OTHER-CO', 'L2'});
      final Map<String, Object?> lb = bodyOf(
        f.to('/ledger/user-ledgers').single,
      );
      expect(lb['userId'], 9);
      expect(lb['ledgers'], <String>['L1', 'L2', 'OTHER-CO']);
      await cfg.saveSelection('inventory', <String>{'Wire', 'Pipe'});
      expect(
        bodyOf(f.to('/inventory/user-inventory').single)['items'],
        <String>['Pipe', 'Wire'],
      );

      // Voucher list for selection: server pages of 50, server search.
      final SelPage pg = await r.teamAdmin.vouchers(0 + 1, 'mehta');
      final Map<String, String> q = f
          .to('/voucher-entry/paged')
          .last
          .url
          .queryParameters;
      expect(q['limit'], '50');
      expect(q['search'], 'mehta');
      expect(pg.rows, isNotEmpty);

      // Invite and delete.
      await r.teamAdmin.sendInvite(m);
      expect(bodyOf(f.to('/send-invite').single), <String, Object?>{
        'email': 'asha@x.in',
        'username': 'asha',
      });
      await r.teamAdmin.deleteUser(m);
      expect(
        f.calls.where(
          (http.Request x) => x.method == 'DELETE' && x.url.path == '/users/9',
        ),
        hasLength(1),
      );
      expect(r.team().map((Member x) => x.id), <String>['7']);
      expect(f.violations, isEmpty);
    });
  });

  group('screens (real repository)', () {
    Future<(FakeBackend, AppController)> boot(WidgetTester t) async {
      t.view.physicalSize = const Size(390 * 3, 1600 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final FakeBackend f = FakeBackend()
        ..extraLedgers = <Map<String, Object?>>[
          <String, Object?>{
            'ledger_guid': 'L5',
            'name': 'Shree Traders',
            'parent_group': 'Sundry Debtors',
            'opening_balance': '25000.75',
            'closing_balance': '25000.75',
          },
        ];
      final AppController c = AppController(
        store: LocalStorage.memory(),
        repo: f.repo(),
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
          child: const TallyConnectApp(),
        ),
      );
      c.loginType = 'ADMIN';
      c.setF('user', 'ravi@x.in');
      c.setF('pass', 'secret');
      c.doLogin();
      for (int i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(c.screen, 'home');
      return (f, c);
    }

    Future<void> ticks(WidgetTester t, [int n = 8]) async {
      for (int i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('party card: opening balance, pin inside without overlap', (
      WidgetTester t,
    ) async {
      final (FakeBackend _, AppController c) = await boot(t);
      c.updPref('party', (ListPref pr) => pr.pinned.add('Shree Traders'));
      c.go('party');
      await ticks(t);
      // No pending bills → the ledger's real opening balance.
      expect(find.text('No pending bills'), findsNothing);
      expect(find.text('Opening Balance'), findsWidgets);
      expect(find.text('₹25,000.75'), findsOneWidget);
      // The pin sits inside the row and clear of name and amount.
      final Finder pin = find.byType(PinBadge);
      expect(pin, findsOneWidget);
      final Rect pr = t.getRect(pin);
      final Rect name = t.getRect(find.text('Shree Traders'));
      final Rect amt = t.getRect(find.text('₹25,000.75'));
      final Rect lbl = t.getRect(
        find
            .descendant(
              of: find.ancestor(of: pin, matching: find.byType(Row)).first,
              matching: find.text('Opening Balance'),
            )
            .first,
      );
      expect(pr.overlaps(name), isFalse);
      expect(pr.overlaps(amt), isFalse);
      expect(pr.overlaps(lbl), isFalse);
      expect(pr.right, lessThanOrEqualTo(amt.left));
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('member menu → configure, save layout and selection', (
      WidgetTester t,
    ) async {
      final (FakeBackend f, AppController c) = await boot(t);
      c.go('team');
      await ticks(t);
      final Member m = c.team.firstWhere((Member x) => x.id == '9');
      c.openMember(m);
      await ticks(t, 3);
      for (final String s in <String>[
        'Configure User',
        'Send Invite',
        'Turn Off Access',
        'Delete User',
      ]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      await t.tap(find.text('Configure User'));
      await ticks(t);
      expect(c.screen, 'teamUser');
      expect(find.text('Ledgers Layout'), findsOneWidget);
      expect(find.text('5 of 6 fields shown'), findsOneWidget);
      expect(find.text('Ledger Selection'), findsOneWidget);
      expect(find.text('2 selected'), findsOneWidget); // ledgers
      expect(find.text('Active'), findsWidgets); // status kept

      // Layout: switch "Type" off and save for this user.
      await t.tap(find.text('Ledgers Layout'));
      await ticks(t);
      expect(c.screen, 'teamLayout');
      await t.tap(find.text('Type'));
      await ticks(t, 2);
      await t.tap(find.text('Save'));
      await ticks(t);
      final http.Request put = f.calls.lastWhere(
        (http.Request x) => x.method == 'PUT',
      );
      expect(put.url.path, '/users/9/ledger-permissions');
      expect(
        (bodyOf(put)['columns']! as Map<String, Object?>)['type'],
        isFalse,
      );
      expect(c.toast, contains('saved for asha'));

      // Selection: Select All items and save.
      c.back();
      await ticks(t);
      await t.tap(find.text('Inventory Selection'));
      await ticks(t, 12);
      expect(c.screen, 'teamSelect');
      expect(find.text('Wire'), findsOneWidget);
      expect(find.text('Pipe'), findsOneWidget);
      await t.tap(find.text('Select All'));
      await ticks(t, 2);
      expect(find.text('Unselect All'), findsOneWidget);
      await t.tap(find.text('Save'));
      await ticks(t);
      expect(
        bodyOf(f.to('/inventory/user-inventory').single)['items'],
        <String>['Pipe', 'Wire'],
      );
      expect(f.violations, isEmpty);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('delete asks first, then removes only that user', (
      WidgetTester t,
    ) async {
      final (FakeBackend f, AppController c) = await boot(t);
      c.go('team');
      await ticks(t);
      c.openMember(c.team.firstWhere((Member x) => x.id == '9'));
      await ticks(t, 3);
      await t.tap(find.text('Delete User'));
      await ticks(t, 2);
      expect(find.text('Delete asha?'), findsOneWidget);
      expect(f.calls.where((http.Request x) => x.method == 'DELETE'), isEmpty);
      await t.tap(find.text('Delete'));
      await ticks(t);
      expect(
        f.calls
            .where((http.Request x) => x.method == 'DELETE')
            .map((http.Request x) => x.url.path),
        <String>['/users/9'],
      );
      expect(c.team.map((Member x) => x.id), <String>['7']);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
