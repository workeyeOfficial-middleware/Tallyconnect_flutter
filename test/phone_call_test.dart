// One-tap calling from party detail: Tally's free-text phone field parsed
// into dialable numbers; the dialer opens (never calls); several numbers →
// a choice; none / unreadable → a message; Demo Company → off.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/core/utils/phone.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart'
    show DataSet;
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

void main() {
  group('dialableNumbers', () {
    test('one number, any format', () {
      expect(dialableNumbers('9820012345'), <String>['9820012345']);
      expect(dialableNumbers('+91 98200 12345'), <String>['+919820012345']);
      expect(dialableNumbers('+91-98200-12345'), <String>['+919820012345']);
      expect(dialableNumbers('(022) 2345-6789'), <String>['02223456789']);
      expect(dialableNumbers('0091 98200 12345'), <String>['+919820012345']);
    });

    test('several numbers; duplicates once; extensions dropped', () {
      expect(dialableNumbers('022-2345 6789 / 98200 12345'), <String>[
        '02223456789',
        '9820012345',
      ]);
      expect(dialableNumbers('Office 2345678 or Mobile 9820012345'), <String>[
        '2345678',
        '9820012345',
      ]);
      expect(dialableNumbers('98200 12345 98201 54321'), <String>[
        '9820012345',
        '9820154321',
      ]);
      expect(dialableNumbers('9820012345, 98200 12345'), <String>[
        '9820012345',
      ]);
      expect(dialableNumbers('Tel: 022 2345 6789 ext 23'), <String>[
        '02223456789',
      ]);
    });

    test('nothing dialable', () {
      expect(dialableNumbers(null), isEmpty);
      expect(dialableNumbers('   '), isEmpty);
      expect(dialableNumbers('N/A'), isEmpty);
      expect(dialableNumbers('123'), isEmpty);
    });

    test('tel link and label', () {
      expect(telUri('+919820012345').toString(), 'tel:+919820012345');
      expect(phoneLabel('+919820012345'), '+91 98200 12345');
      expect(phoneLabel('9820012345'), '98200 12345');
      expect(phoneLabel('02223456789'), '02223456789');
    });
  });

  group('callParty', () {
    late List<Uri> opened;
    bool works = true;
    AppController make({TallyRepositoryOverride? repo}) {
      opened = <Uri>[];
      return AppController(
        store: LocalStorage.memory(),
        startScreen: 'home',
        repo: repo?.repo,
        linkOpener: (Uri u) async {
          opened.add(u);
          return works;
        },
      );
    }

    Party party(String? phone) =>
        Party('Gupta Traders', 'c', 'Mumbai', 0, phone: phone);

    test('one number → dialer opens with it (no call placed)', () async {
      works = true;
      final AppController c = make();
      c.callParty(party('+91 98200 12345'));
      await Future<void>.delayed(Duration.zero);
      expect(opened, <Uri>[Uri.parse('tel:+919820012345')]);
      expect(c.overlay, isNull);
      c.dispose();
    });

    test('several numbers → choose, then the dialer', () async {
      works = true;
      final AppController c = make();
      c.callParty(party('022-2345 6789 / 98200 12345'));
      expect(c.overlay, 'callPick');
      expect(c.callNumbers, <String>['02223456789', '9820012345']);
      expect(opened, isEmpty);
      await c.dial('9820012345');
      expect(opened, <Uri>[Uri.parse('tel:9820012345')]);
      expect(c.overlay, isNull);
      c.dispose();
    });

    test('no number / unreadable number / dialer missing → messages', () async {
      works = true;
      final AppController c = make();
      c.callParty(party(null));
      expect(c.toast, contains('No phone number saved'));
      c.callParty(party('N/A'));
      expect(c.toast, contains('cannot be dialled'));
      expect(opened, isEmpty);
      works = false;
      await c.dial('9820012345');
      expect(c.toast, contains('Could not open the phone dialer'));
      c.dispose();
    });

    test('Demo Company: calling is off', () async {
      final FakeBackend f = FakeBackend()..newAccount = true;
      final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      final AppController c = make(repo: TallyRepositoryOverride(r));
      c.afterRefresh(quietOk: true);
      expect(c.demo, isTrue);
      c.callParty(party('9820012345'));
      await Future<void>.delayed(Duration.zero);
      expect(opened, isEmpty);
      expect(c.toast, contains('Calling is off'));
      c.dispose();
    });
  });

  group('party detail screen', () {
    setUpAll(loadFigtree);

    testWidgets('call icons on header and Phone row; choice for two numbers', (
      WidgetTester t,
    ) async {
      t.view.physicalSize = const Size(320 * 3, 720 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final FakeBackend f = FakeBackend()
        ..extraLedgers = <Map<String, Object?>>[
          <String, Object?>{
            'ledger_guid': 'L9',
            'name': 'Gupta Traders',
            'parent_group': 'Sundry Debtors',
            'opening_balance': '0',
            'closing_balance': '0',
            'phone': '022-2345 6789 / 98200 12345',
          },
        ];
      final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      await r.ensure(DataSet.ledgers);
      final List<Uri> opened = <Uri>[];
      final AppController c = AppController(
        store: LocalStorage.memory(),
        repo: r,
        startScreen: 'home',
        linkOpener: (Uri u) async {
          opened.add(u);
          return true;
        },
      );
      c.afterRefresh(quietOk: true);
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

      c.go('partyDetail', <String, Object?>{
        'party': 'Gupta Traders',
        'partyTab': 'summary',
      });
      await settle();
      expect(
        find.byKey(const ValueKey<String>('callPartyBtn')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('callPhoneRow')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey<String>('callPhoneRow')));
      await settle();
      expect(c.overlay, 'callPick');
      await t.tap(find.byKey(const ValueKey<String>('callNumber-9820012345')));
      await settle();
      expect(opened, <Uri>[Uri.parse('tel:9820012345')]);
      // A party without a phone shows no call icon.
      c.go('partyDetail', <String, Object?>{
        'party': 'Mehta Electricals',
        'partyTab': 'summary',
      });
      await settle();
      expect(find.byKey(const ValueKey<String>('callPartyBtn')), findsNothing);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });
  });
}

/// Lets a test pass a prepared repository through the shared factory.
class TallyRepositoryOverride {
  TallyRepositoryOverride(this.repo);
  final DemoAwareRepository repo;
}
