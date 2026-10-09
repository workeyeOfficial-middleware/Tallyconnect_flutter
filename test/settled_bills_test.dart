// Settled bills (pending 0) are kept apart from pending ones: they never
// count in Outstanding totals and are listed in their own "Settled" tab.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/data/api/set_parsers.dart';

void main() {
  test('pending and settled bills are split; settled keep last amount', () {
    Map<String, Object?> row(
      String name,
      String type,
      num pending, [
      num? amount,
    ]) => <String, Object?>{
      'company_guid': 'co-1',
      'ledger_guid': 'L1',
      'ledger_name': 'Real Glory',
      'bill_name': name,
      'bill_type': type,
      'pending_amount': '$pending',
      if (amount != null) 'bill_amount': '$amount',
      'due_date': '2026-09-20T00:00:00.000Z',
      'status': pending == 0 ? 'Settled' : 'Pending',
    };
    final String raw = jsonEncode(<String, Object?>{
      'bills': <String, Object?>{
        'success': true,
        'data': <Object?>[
          row('SHADE WORK', 'PAYABLE', 71390, 71390),
          row('PARTY EVENT', 'PAYABLE', 0, 162500),
          row('S/1', 'RECEIVABLE', 500),
          row('S/OLD', 'RECEIVABLE', 0),
          // Another company: ignored.
          <String, Object?>{
            ...row('X', 'PAYABLE', 0, 1),
            'company_guid': 'co-2',
          },
        ],
      },
      'summary': null,
    });
    final BillsParsed b =
        parseSetText(
              ParseIn(
                'bills',
                raw,
                'co-1',
                DateTime(2026, 10, 9),
                DateTime(2026, 10, 9),
              ),
            )!
            as BillsParsed;
    expect(b.pay.map((x) => x.no), <String>['SHADE WORK']);
    expect(b.recv.map((x) => x.no), <String>['S/1']);
    expect(b.settledPay.map((x) => x.no), <String>['PARTY EVENT']);
    expect(b.settledPay.single.st, 'settled');
    expect(b.settledPay.single.txt, 'Settled');
    expect(b.settledPay.single.amt, 0);
    expect(b.settledPay.single.billAmt, 162500);
    expect(b.settledRecv.map((x) => x.no), <String>['S/OLD']);
    expect(b.settledRecv.single.billAmt, isNull); // no amount stored
  });
}
