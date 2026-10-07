// Parses the server's JSON text for one data set into compact app models.
// Top-level functions so large responses (/ledger with 16K+ ledgers, /bill,
// /inventory/mobile, voucher pages) can be parsed in a background isolate
// with `compute`; small ones are parsed inline. Only the parsed models are
// kept afterwards — the text is written to the snapshot cache and dropped.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'adapters.dart';

/// Text bigger than this is parsed in a background isolate.
const int kIsolateParseBytes = 64 * 1024;

/// Input of [parseSetText] (sendable to an isolate).
class ParseIn {
  const ParseIn(this.set, this.raw, this.active, this.today, this.now);
  final String set, raw;
  final String? active;
  final DateTime today, now;
}

/// Pending bills of the active company, split and sorted by due date.
class BillsParsed {
  const BillsParsed(this.recv, this.pay, this.serverRecv, this.serverPay);
  final List<Bill> recv, pay;
  final num? serverRecv, serverPay;
}

/// The current month's vouchers (active, de-duplicated, server order).
class MonthParsed {
  const MonthParsed(this.year, this.month, this.rows, this.complete);
  final int year, month;
  final List<Voucher> rows;
  final bool complete;
}

/// One parsed voucher page (`/voucher-entry/paged`).
class VoucherPageParsed {
  const VoucherPageParsed(this.rows, this.guids, this.hasMore, this.total);

  /// The page's vouchers.
  final List<Voucher> rows;

  /// GUIDs of every row on the page, for de-duplication
  /// and completeness checks.
  final List<String> guids;
  final bool hasMore;
  final int? total;
}

/// Parses [a] inline or, when large, in a background isolate.
Future<Object?> parseSet(ParseIn a) => a.raw.length > kIsolateParseBytes
    ? compute(parseSetText, a)
    : Future<Object?>.value(parseSetText(a));

Future<VoucherPageParsed> parseVoucherPage(String raw) =>
    raw.length > kIsolateParseBytes
    ? compute(parseVoucherPageText, raw)
    : Future<VoucherPageParsed>.value(parseVoucherPageText(raw));

VoucherPageParsed parseVoucherPageText(String raw) {
  final Object? body = jsonDecode(raw);
  final List<Map<String, Object?>> rs = rows(body);
  final Object? meta = body is Map ? body['meta'] : null;
  return VoucherPageParsed(
    rs.map(voucherFrom).whereType<Voucher>().toList(),
    <String>[for (final Map<String, Object?> m in rs) str(m['voucher_guid'])],
    meta is Map && meta['hasMore'] == true,
    meta is Map && meta['total'] is num
        ? (meta['total']! as num).toInt()
        : null,
  );
}

int _byDue(Bill a, Bill b) =>
    (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999));

Object? parseSetText(ParseIn a) {
  final Object? body = jsonDecode(a.raw);
  switch (a.set) {
    case 'profile':
      return profileFrom(body);
    case 'ledgers':
      return rows(body).map(ledgerFrom).toList();
    case 'bills':
      // `GET /bill` returns every company of the admin: keep the active
      // company's pending bills only.
      final Map<Object?, Object?> m = body is Map
          ? body
          : const <Object?, Object?>{};
      final List<Bill> recv = <Bill>[], pay = <Bill>[];
      for (final Map<String, Object?> b in rows(m['bills'])) {
        if (a.active == null || str(b['company_guid']) != a.active) continue;
        final Bill? x = billFrom(b, a.today);
        if (x == null) continue;
        (x.kind == 'pay' ? pay : recv).add(x);
      }
      final Object? s = m['summary'];
      return BillsParsed(
        recv..sort(_byDue),
        pay..sort(_byDue),
        s is Map ? toNum(s['receivables']) : null,
        s is Map ? toNum(s['payables']) : null,
      );
    case 'vouchers':
      // {"year":Y,"month":M,"complete":b,"pages":[<page JSON>, …]}
      final Map<Object?, Object?> m = body is Map
          ? body
          : const <Object?, Object?>{};
      final Set<String> seen = <String>{};
      final List<Voucher> out = <Voucher>[];
      if (m['pages'] is List) {
        for (final Object? page in m['pages']! as List<Object?>) {
          for (final Map<String, Object?> r in rows(page)) {
            final String g = str(r['voucher_guid']);
            if (g.isNotEmpty && !seen.add(g)) continue;
            final Voucher? v = voucherFrom(r);
            if (v != null) out.add(v);
          }
        }
      }
      return MonthParsed(
        (toNum(m['year']) ?? 0).toInt(),
        (toNum(m['month']) ?? 0).toInt(),
        out,
        m['complete'] != false,
      );
    case 'items':
      return rows(body, 'items').map(itemFrom).toList();
    case 'stock':
      return rows(body).map(stockFrom).toList();
    case 'activity':
      return rows(
        body,
      ).map((Map<String, Object?> r) => actFrom(r, a.now)).toList();
    case 'notifications':
      return rows(
        body,
        'notifications',
      ).map((Map<String, Object?> r) => notifFrom(r, a.now)).toList();
    case 'alerts':
      final Object? c = body is Map ? body['config'] : null;
      return c is Map
          ? <String, bool>{
              for (final MapEntry<Object?, Object?> e in c.entries)
                '${e.key}': e.value == true,
            }
          : null;
    case 'team':
      return rows(body).map(memberFrom).toList();
    case 'companies':
      return body; // small composite map, interpreted by the repository
  }
  throw ArgumentError(a.set);
}
