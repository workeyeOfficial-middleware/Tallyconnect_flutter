// A voucher cancelled in Tally (sent as is_cancelled once the server stores
// Tally's voucher status): marked in the list and on its screen; an older
// server (no field) changes nothing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/data/api/adapters.dart';
import 'package:tallyconnect_ui/data/models/models.dart';

Map<String, Object?> _row({Object? cancelled}) => <String, Object?>{
  'voucher_guid': 'g1',
  'voucher_date': '2025-04-10',
  'voucher_type': 'Sales',
  'reference_no': 'LUM/101',
  'amount': 0,
  'party_name': null,
  'is_active': true,
  'is_cancelled': ?cancelled,
};

void main() {
  test('cancelled in Tally → Voucher.cancelled', () {
    expect(voucherFrom(_row(cancelled: true))!.cancelled, isTrue);
    expect(voucherFrom(_row(cancelled: false))!.cancelled, isFalse);
  });

  test('older server (no field) or anything but true: not cancelled', () {
    expect(voucherFrom(_row())!.cancelled, isFalse);
    expect(voucherFrom(_row(cancelled: 'Yes'))!.cancelled, isFalse);
    final Voucher v = voucherFrom(_row())!;
    expect(v.party, '—');
    expect(v.no, 'LUM/101');
  });
}
