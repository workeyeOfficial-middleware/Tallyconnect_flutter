// Contra (money moved between cash and bank accounts): the request body,
// the server's answers, the checks before saving, the flow screens at
// 320 px and the Activity row of a queued Contra.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/api/adapters.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart';
import 'package:tallyconnect_ui/data/repositories/tally_repository.dart';
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

const EntryDraft _draft = EntryDraft(
  type: 'contra',
  no: 'C-7',
  date: '2026-10-03',
  party: 'Cash',
  account: 'HDFC Bank',
  amount: 5000.555,
  utr: 'UTR123',
  note: 'Cash deposited',
);

FakeBackend _fake() => FakeBackend()
  ..extraLedgers = <Map<String, Object?>>[
    <String, Object?>{
      'ledger_guid': 'L-CASH',
      'name': 'Cash',
      'parent_group': 'Cash-in-Hand',
      'opening_balance': '0',
      'closing_balance': '0',
    },
  ];

Future<ApiTallyRepository> _repo(FakeBackend f) async {
  final ApiTallyRepository r = f.repo();
  await r.login('ravi@x.in', 'secret', 'ADMIN');
  await r.refreshAll();
  await r.ensure(DataSet.ledgers);
  return r;
}

Map<String, Object?> _sent(FakeBackend f) =>
    jsonDecode(f.to('/api/mobile-voucher-command/contra/create').single.body)
        as Map<String, Object?>;

void main() {
  test('request body: from / to account, amount in paise, optional fields', () {
    expect(contraBody(_draft), <String, Object?>{
      'voucher_date': '2026-10-03',
      'voucher_no': 'C-7',
      'from_account': 'Cash',
      'to_account': 'HDFC Bank',
      'amount': 5000.56,
      'instrument_no': 'UTR123',
      'narration': 'Cash deposited',
    });
    final Map<String, Object?> bare = contraBody(
      const EntryDraft(
        type: 'contra',
        no: ' ',
        date: '2026-10-03',
        party: 'Cash',
        account: 'HDFC Bank',
        amount: 10,
      ),
    );
    expect(bare.keys, isNot(contains('voucher_no')));
    expect(bare.keys, isNot(contains('instrument_no')));
    expect(bare.keys, isNot(contains('narration')));
    // Never a party: the Agent would treat the account as a customer.
    expect(bare.keys, isNot(contains('party_name')));
  });

  test('posts to the Contra route; older server → a clear message', () async {
    final FakeBackend f = _fake();
    final ApiTallyRepository r = await _repo(f);
    final SubmitResult ok = await r.submitEntry(_draft);
    expect(ok.ok, isTrue);
    expect(ok.commandId, '55');
    expect(_sent(f)['to_account'], 'HDFC Bank');

    final FakeBackend old = _fake()..contraMissing = true;
    final ApiTallyRepository r2 = await _repo(old);
    final SubmitResult no = await r2.submitEntry(_draft);
    expect(no.ok, isFalse);
    expect(no.message, 'Contra entries are not available on the server yet.');
  });

  test('checks before saving; save → queued, back to Home', () async {
    final FakeBackend f = _fake();
    final AppController c = AppController(
      store: LocalStorage.memory(),
      repo: await _repo(f),
    );
    c.afterRefresh(quietOk: true);
    // The New Entry card now opens the flow (it used to refuse).
    c.openEntryTile('contra');
    expect(c.screen, 'flow');
    expect(c.flowType, 'contra');
    expect(c.f('kDate'), isNotEmpty); // today
    expect(c.flowBlocker, 'Choose the account money goes out of');
    c.setF('kParty', 'Cash');
    expect(c.flowBlocker, 'Choose the account money goes into');
    c.setF('kAcc', 'cash');
    expect(c.flowBlocker, 'From and To must be different accounts');
    c.setF('kAcc', 'Mehta Electricals');
    expect(c.flowBlocker, 'Mehta Electricals is not a cash or bank account');
    c.setF('kAcc', 'HDFC Bank');
    expect(c.flowBlocker, 'Enter an amount above zero');
    c.setF('kAmt', '2500');
    c.setF('kUtr', 'CHQ 000123');
    expect(c.flowBlocker, isNull);
    c.saveFlow(false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.screen, 'home');
    final Map<String, Object?> b = _sent(f);
    expect(b['from_account'], 'Cash');
    expect(b['to_account'], 'HDFC Bank');
    expect(b['amount'], 2500);
    expect(b['instrument_no'], 'CHQ 000123');
    // The next Contra starts clean (the To account is kept, like Receipt).
    expect(c.f('kParty'), '');
    expect(c.f('kAmt'), '');
    c.dispose();
  });

  test('Journal is unchanged: no party, must balance', () async {
    final FakeBackend f = _fake();
    final AppController c = AppController(
      store: LocalStorage.memory(),
      repo: await _repo(f),
    );
    c.afterRefresh(quietOk: true);
    c.startFlow('journal');
    c.jl = <JLine>[
      const JLine('Dr', 'Rent A/c', '', 800),
      const JLine('Cr', 'HDFC Bank', '', 700),
    ];
    expect(c.flowBlocker, 'Both sides must be equal');
    c.dispose();
  });

  test('Activity: a queued Contra reads From → To with both accounts', () {
    final Act a = actFrom(<String, Object?>{
      'id': 12,
      'status': 'pending',
      'created_at': '2026-10-03T10:00:00Z',
      'payload': <String, Object?>{
        'voucher_type': 'Contra',
        'voucher_date': '2026-10-03',
        'voucher_no': 'C-7',
        'transfer': <String, Object?>{
          'from_account': 'Cash',
          'to_account': 'HDFC Bank',
          'amount': 5000,
        },
        'ledger_entries': <Object?>[
          <String, Object?>{
            'ledger_name': 'HDFC Bank',
            'amount': 5000,
            'is_debit': true,
          },
          <String, Object?>{
            'ledger_name': 'Cash',
            'amount': 5000,
            'is_debit': false,
          },
        ],
      },
    }, DateTime(2026, 10, 3, 12));
    expect(a.kind, 'contra');
    expect(a.party, 'Cash → HDFC Bank');
    expect(a.amt, 5000);
    expect(a.status, 'wait');
    expect(a.items.map(((String, String, num) i) => i.$1), <String>[
      'HDFC Bank',
      'Cash',
    ]);
  });

  group('screens (320 px)', () {
    setUpAll(loadFigtree);

    testWidgets('Details → To account → Check, no overflow', (
      WidgetTester t,
    ) async {
      t.view.physicalSize = const Size(320 * 3, 640 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      // Sample data: From = Cash in hand, To = HDFC Bank – Current.
      final AppController c = AppController(store: LocalStorage.memory());
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

      c.openEntryTile('contra');
      await settle();
      expect(find.text('Contra'), findsWidgets);
      expect(
        find.textContaining(
          'From account (money goes out)',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Against which bill', findRichText: true),
        findsNothing,
      );
      expect(t.takeException(), isNull);
      // The From picker lists cash / bank accounts only.
      await t.tap(find.byKey(const ValueKey<String>('kPartyPick')));
      await settle();
      expect(
        c.pick?.opts.map((Opt o) => o.t),
        c.repo.accounts().map((Opt o) => o.t),
      );
      c.closeOv();
      await settle();

      c.flowNext();
      await settle();
      expect(find.byKey(const ValueKey<String>('kAccPick')), findsOneWidget);
      expect(
        find.textContaining('Cheque / UTR no.', findRichText: true),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      // The To picker leaves out the From account.
      await t.tap(find.byKey(const ValueKey<String>('kAccPick')));
      await settle();
      expect(c.pick!.opts.map((Opt o) => o.t), isNot(contains('Cash in hand')));
      c.closeOv();
      await settle();
      // Same account on both sides: a warning and no Next.
      c.setF('kAcc', 'Cash in hand');
      await settle();
      expect(
        find.text('From and To must be different accounts'),
        findsOneWidget,
      );
      c.setF('kAcc', 'HDFC Bank – Current');
      await settle();

      c.flowNext();
      await settle();
      expect(find.text('To (money comes in)'), findsOneWidget);
      expect(find.text('HDFC Bank – Current'), findsWidgets);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
