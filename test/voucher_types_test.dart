// Every voucher type chip loads its vouchers (incl. rows the server flags
// is_active:false after a sync reset) and the Entries / Total value card
// stays clean for very large numbers.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/design/tc_palette.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/api/adapters.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/voucher_pager.dart';
import 'package:tallyconnect_ui/presentation/screens/voucher_screens.dart';

Future<void> loadFigtree() async {
  final FontLoader l = FontLoader('Figtree');
  for (final String w in <String>[
    'Regular',
    'Medium',
    'SemiBold',
    'Bold',
    'ExtraBold',
  ]) {
    final List<int> b = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    l.addFont(
      Future<ByteData>.value(ByteData.sublistView(Uint8List.fromList(b))),
    );
  }
  await l.load();
}

int _n = 0;
Map<String, Object?> row(String type, {bool active = true, num amt = 100}) =>
    <String, Object?>{
      'voucher_guid': 'G${_n++}',
      'voucher_date': '2025-08-22T00:00:00.000Z',
      'voucher_type': type,
      'reference_no': 'R$_n',
      'amount': '$amt',
      'is_active': active,
      'party_name': null,
      'items': <Object?>[],
    };

void main() {
  setUpAll(loadFigtree);

  test('every type chip loads its vouchers (Adjustment, Bank ↔ Cash, '
      'Physical Stock included)', () async {
    // Newest first, as the server sends them. Journal / Contra / Physical
    // Stock rows carry the start-of-sync reset flag (is_active:false); one
    // type name has stray spaces / other case.
    final List<Map<String, Object?>> book = <Map<String, Object?>>[
      row('Sales'),
      row('Sales', amt: 250),
      row('Purchase'),
      row('Receipt'),
      row('Payment'),
      row('Journal', active: false),
      row('Journal', active: false),
      row('Journal'),
      row('Contra', active: false),
      row('Contra', active: false),
      row('Physical Stock', active: false, amt: 0),
      row(' physical stock ', active: false, amt: 0),
      row('Stock Journal'),
    ];
    // The server's `type` filter: ILIKE '%type%', 2 rows per page here.
    Future<FetchedPage> fetch(int page, VoucherQuery q, DateTime t) async {
      final String? st = q.serverType?.toLowerCase();
      final List<Map<String, Object?>> hit = book
          .where(
            (Map<String, Object?> m) =>
                st == null || '${m['voucher_type']}'.toLowerCase().contains(st),
          )
          .toList();
      final List<Map<String, Object?>> pg = hit
          .skip((page - 1) * 2)
          .take(2)
          .toList();
      return FetchedPage(
        pg.map(voucherFrom).whereType<Voucher>().toList(),
        <String>[
          for (final Map<String, Object?> m in pg) '${m['voucher_guid']}',
        ],
        page * 2 < hit.length,
      );
    }

    Future<List<Voucher>> load(String filter) async {
      final VoucherPager p = VoucherPager(
        VoucherQuery(filter: filter),
        fetch,
        DateTime(2026, 10, 7),
      );
      while (p.hasMore && p.error == null) {
        await p.loadMore();
      }
      expect(p.complete, isTrue, reason: filter);
      return p.rows;
    }

    expect(await load('all'), hasLength(book.length));
    expect(await load('sales'), hasLength(2));
    expect(await load('purchase'), hasLength(1));
    expect(await load('receipt'), hasLength(1));
    expect(await load('payment'), hasLength(1));
    // Adjustment = Journal (Stock Journal is not an adjustment).
    final List<Voucher> j = await load('journal');
    expect(j, hasLength(3));
    expect(j.every((Voucher v) => v.type == 'Journal'), isTrue);
    expect(await load('contra'), hasLength(2)); // Bank ↔ Cash
    expect(await load('type:Physical Stock'), hasLength(2));
    expect(await load('type:Stock Journal'), hasLength(1));
  });

  group('Entries / Total value card with large numbers', () {
    for (final double width in <double>[320, 360, 390]) {
      for (final (String, String) v in <(String, String)>[
        ('0', '₹0'),
        ('…', '—'),
        ('46,438', '₹79,44,11,105.62'),
        ('1,00,000', '₹7,94,41,11,105.62'),
        ('12,34,56,789', '₹98,76,54,32,10,123.45'),
      ]) {
        testWidgets('${v.$1} / ${v.$2} at ${width.toInt()} wide', (
          WidgetTester t,
        ) async {
          t.view.physicalSize = Size(width * 3, 400 * 3);
          t.view.devicePixelRatio = 3;
          addTearDown(t.view.reset);
          final AppController c = AppController(store: LocalStorage.memory());
          await t.pumpWidget(
            ProviderScope(
              overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
              child: MaterialApp(
                home: Tc(
                  p: resolvePalette(preset: 'aurora'),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: VoucherSummaryRow(
                          icon: 'receipt',
                          color: const Color(0xFF8C1D3F),
                          count: v.$1,
                          total: v.$2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pump();
          // No overflow / layout error.
          expect(t.takeException(), isNull);
          final Rect card = t.getRect(find.byType(VoucherSummaryRow));
          final Rect cnt = t.getRect(find.text(v.$1));
          final Rect tot = t.getRect(find.text(v.$2));
          // Both fully inside the card, never overlapping, with a gap.
          expect(cnt.left, greaterThanOrEqualTo(card.left));
          expect(tot.right, lessThanOrEqualTo(card.right));
          expect(cnt.right + 12, lessThanOrEqualTo(tot.left));
          // Value at the card's right edge (as in the design), any size.
          expect(card.right - tot.right, lessThan(40));
          // Still readable: neither shrinks to a sliver.
          expect(t.getSize(find.text(v.$1)).height, greaterThan(8));
          expect(t.getSize(find.text(v.$2)).height, greaterThan(8));
          await t.pump(const Duration(seconds: 6));
        });
      }
    }
  });
}
