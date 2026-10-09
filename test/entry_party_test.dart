// New Entry cards (pin / hide / restore / order) and inline Add New Party
// in a voucher (sent as new_party; type validated).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/mock/mock_data.dart' show kEntryTiles;
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart';
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

void main() {
  group('New Entry cards', () {
    setUpAll(loadFigtree);

    testWidgets('pin first, hide, restore; saved', (WidgetTester t) async {
      t.view.physicalSize = const Size(360 * 3, 900 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final LocalStorage s = LocalStorage.memory();
      final AppController c = AppController(store: s, startScreen: 'home');
      await t.pumpWidget(
        ProviderScope(
          overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
          child: const TallyConnectApp(),
        ),
      );
      c.go('newEntry');
      for (int i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      List<String> order() => c
          .listView<(String, String, String, String, String)>(
            'entries',
            kEntryTiles,
            ((String, String, String, String, String) e) => e.$1,
          )
          .rows
          .map(((String, String, String, String, String) e) => e.$1)
          .toList();
      expect(order().first, 'sales');
      // Pin Receipt → first.
      c.updPref('entries', (ListPref pr) => pr.pinned.add('receipt'));
      expect(order().first, 'receipt');
      // Hide Contra.
      c.updPref('entries', (ListPref pr) => pr.hidden.add('contra'));
      await t.pump(const Duration(milliseconds: 200));
      expect(order(), isNot(contains('contra')));
      expect(find.text('1 hidden · Unhide'), findsOneWidget);
      expect(t.takeException(), isNull);
      // Saved on the phone.
      final AppController c2 = AppController(store: s, startScreen: 'home');
      expect(c2.listPrefs['entries']!.hidden, <String>['contra']);
      expect(c2.listPrefs['entries']!.pinned, <String>['receipt']);
      c2.restoreEntryTile('contra');
      expect(c2.listPrefs['entries']!.hidden, isEmpty);
      c2.dispose();
      await t.pump(const Duration(seconds: 6));
    });
  });

  group('Add New Party in a voucher (real repository)', () {
    Future<(FakeBackend, AppController)> start(String flow) async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      await r.ensure(DataSet.ledgers);
      await r.ensure(DataSet.items);
      final AppController c = AppController(
        store: LocalStorage.memory(),
        repo: r,
      );
      c.startFlow(flow, <String, String>{
        '${flow == 'sales' ? 's' : 'r'}Date': '2026-10-03',
        if (flow == 'sales') 'sAmt': '0',
      });
      return (f, c);
    }

    test('sale: new customer is selected and sent as new_party', () async {
      final (FakeBackend f, AppController c) = await start('sales');
      c.openNewParty(key: 'sParty', type: 'c');
      c.setF('npName', 'Neha Pal');
      c.setF('npPhone', '98673 80182');
      c.setF('npCity', 'Mumbai');
      // Wrong type for a sale.
      c.update(() => c.npType = 's');
      expect(c.newPartyError, contains('needs a customer'));
      c.update(() => c.npType = 'c');
      expect(c.newPartyError, isNull);
      c.saveParty();
      expect(c.overlay, isNull);
      expect(c.f('sParty'), 'Neha Pal');
      expect(c.partyPool().any((Party x) => x.name == 'Neha Pal'), isTrue);
      c.togglePickItem(c.repo.items().firstWhere((Item x) => x.name == 'Wire'));
      expect(c.flowBlocker, isNull);
      c.saveFlow(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final List<http.Request> sent = f.to(
        '/api/mobile-voucher-command/create',
      );
      expect(sent, hasLength(1));
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body['party_name'], 'Neha Pal');
      expect(body['new_party'], <String, Object?>{
        'name': 'Neha Pal',
        'group': 'Sundry Debtors',
        'type': 'customer',
        'phone': '9867380182',
        'city': 'Mumbai',
      });
      c.dispose();
    });

    test(
      'existing party is selected, not created; bad input refused',
      () async {
        final (FakeBackend _, AppController c) = await start('sales');
        c.openNewParty(key: 'sParty', type: 'c');
        c.setF('npName', 'mehta electricals'); // exists (customer)
        c.saveParty();
        expect(c.f('sParty'), 'Mehta Electricals');
        expect(c.newParties, isEmpty);
        c.openNewParty(key: 'sParty', type: 'c');
        c.setF('npName', 'HDFC Bank'); // a non-party ledger
        c.saveParty();
        expect(c.toast, contains('already'));
        c.setF('npName', 'A <B>');
        expect(c.newPartyError, isNotNull);
        c.setF('npName', 'Good Name');
        c.setF('npPhone', '12ab');
        expect(c.newPartyError, 'Enter a valid mobile number');
        c.dispose();
      },
    );

    test('receipt: new customer goes with the draft', () async {
      final (FakeBackend _, AppController c) = await start('receipt');
      c.openNewParty(key: 'rParty', type: 'c');
      c.setF('npName', 'Walk-in Ravi');
      c.saveParty();
      expect(c.draftOf().newParty?.name, 'Walk-in Ravi');
      expect(c.draftOf().newParty?.group, 'Sundry Debtors');
      c.dispose();
    });
  });
}
