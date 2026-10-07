// Accounting rules shared by the sample-data and the server repositories, so
// both compute totals, statuses and ageing the same way. Every figure comes
// from the rows passed in — nothing is estimated.
library;

import '../core/utils/format.dart';
import 'models/models.dart';

/// Maps a Tally voucher-type name to an app kind. Order, note, return and
/// memo types are not accounting sales/purchases and stay `other` so they are
/// never added to Sales / Purchase / Receipt / Payment totals.
///
/// The backend only sends the voucher-type *name* (no parent type), so custom
/// type names are matched by keyword — see BACKEND_CHANGE_REQUIRED in the
/// integration report.
String voucherKind(String? type) {
  final String s = (type ?? '').trim().toLowerCase();
  if (s.isEmpty) return 'other';
  const List<String> notBooks = <String>[
    'order',
    'quotation',
    'note',
    'return',
    'memo',
    'rejection',
    'reversing',
    'physical',
    'stock journal',
    'manufactur',
    'attendance',
    'payroll',
  ];
  if (notBooks.any(s.contains)) return 'other';
  if (s.contains('sales') || s == 'sale') return 'sales';
  if (s.contains('purchase')) return 'purchase';
  if (s.contains('receipt')) return 'receipt';
  if (s.contains('payment')) return 'payment';
  if (s.contains('contra')) return 'contra';
  if (s.contains('journal')) return 'journal';
  return 'other';
}

/// Due status of a pending bill relative to [today]:
/// `late` (past due), `soon` (due within 7 days) or `ok` (later / no date).
({String st, String txt}) billStatus(DateTime? due, DateTime today) {
  if (due == null) return (st: 'ok', txt: 'No due date');
  final int d = dayDiff(today, due);
  if (d < 0) return (st: 'late', txt: '${-d} ${-d == 1 ? 'day' : 'days'} late');
  if (d == 0) return (st: 'soon', txt: 'Due today');
  if (d == 1) return (st: 'soon', txt: 'Due tomorrow');
  if (d <= 7) return (st: 'soon', txt: 'Due in $d days');
  return (st: 'ok', txt: 'Due in $d days');
}

/// Totals, late amount and ageing of one side (receivable or payable).
OutstandingSummary summarise(
  List<Bill> bills,
  DateTime today, {
  num? serverTotal,
}) {
  num total = 0, late = 0;
  int lateBills = 0;
  final List<num> ageing = <num>[0, 0, 0, 0];
  final Set<String> parties = <String>{};
  for (final Bill b in bills) {
    total += b.amt;
    parties.add(b.ledgerGuid ?? b.party);
    final DateTime? due = b.dueDate;
    final int daysLate = due == null ? 0 : -dayDiff(today, due);
    if (daysLate <= 0) {
      ageing[0] += b.amt;
    } else {
      late += b.amt;
      lateBills++;
      ageing[daysLate <= 30 ? 1 : (daysLate <= 60 ? 2 : 3)] += b.amt;
    }
  }
  return OutstandingSummary(
    total: paise(total),
    parties: parties.length,
    late: paise(late),
    lateBills: lateBills,
    ageing: ageing.map(paise).toList(),
    serverTotal: serverTotal,
  );
}

/// Bills due between today and 7 days from now, soonest first.
List<Bill> dueSoon(List<Bill> recv, List<Bill> pay, DateTime today) {
  final List<Bill> all =
      <Bill>[
        ...recv.map((Bill b) => b.withKind('recv')),
        ...pay.map((Bill b) => b.withKind('pay')),
      ].where((Bill b) {
        if (b.dueDate == null) return false;
        final int d = dayDiff(today, b.dueDate!);
        return d >= 0 && d <= 7;
      }).toList();
  all.sort((Bill a, Bill b) => a.dueDate!.compareTo(b.dueDate!));
  return all;
}

/// This-month amount and count per kind. [complete] is false when the
/// voucher list was cut short, in which case no amount is reported.
MonthTotals monthTotals(
  List<Voucher> vouchers,
  DateTime today, {
  bool complete = true,
}) {
  final Map<String, num> amt = <String, num>{};
  final Map<String, int> cnt = <String, int>{};
  for (final Voucher v in vouchers) {
    final DateTime? d = v.date;
    if (d == null || d.year != today.year || d.month != today.month) continue;
    amt[v.kind] = (amt[v.kind] ?? 0) + v.amt;
    cnt[v.kind] = (cnt[v.kind] ?? 0) + 1;
  }
  return MonthTotals(
    complete
        ? amt.map((String k, num v) => MapEntry<String, num>(k, paise(v)))
        : const <String, num>{},
    cnt,
  );
}

/// Amount and count per kind over every voucher passed in (all history).
/// [complete] false → amounts are withheld (shown as `—`), counts kept.
MonthTotals kindTotals(List<Voucher> vouchers, {bool complete = true}) {
  final Map<String, num> amt = <String, num>{};
  final Map<String, int> cnt = <String, int>{};
  for (final Voucher v in vouchers) {
    amt[v.kind] = (amt[v.kind] ?? 0) + v.amt;
    cnt[v.kind] = (cnt[v.kind] ?? 0) + 1;
  }
  return MonthTotals(
    complete
        ? amt.map((String k, num v) => MapEntry<String, num>(k, paise(v)))
        : const <String, num>{},
    cnt,
  );
}

/// Running sales / purchase summary of one item (the [itemTrade] rules,
/// fed one voucher at a time so a long history can be streamed page by
/// page without keeping it in memory).
class ItemAcc {
  num amount = 0, qty = 0;
  int count = 0;
  DateTime? last;
  num? lastRate, minRate, maxRate;

  /// Adds the lines of [v] that belong to the item [key] (lower-case name).
  void add(Voucher v, String key) {
    bool hit = false;
    for (final VoucherItem i in v.items) {
      if (i.name.trim().toLowerCase() != key) continue;
      hit = true;
      amount += i.amt ?? 0;
      qty += i.qty ?? 0;
      final num? r = i.rate;
      if (r != null) {
        minRate = minRate == null || r < minRate! ? r : minRate;
        maxRate = maxRate == null || r > maxRate! ? r : maxRate;
        final DateTime? d = v.date;
        if (lastRate == null ||
            (d != null && (last == null || d.isAfter(last!)))) {
          lastRate = r;
        }
      }
      final DateTime? d = v.date;
      if (d != null && (last == null || d.isAfter(last!))) last = d;
    }
    if (hit) count++;
  }

  ItemTrade get trade => ItemTrade(
    amount: paise(amount),
    qty: qty,
    vouchers: count,
    lastDate: last,
    lastRate: lastRate,
    minRate: minRate,
    maxRate: maxRate,
  );
}

/// Sales (`kind` = sales) or purchase summary of one item from the item
/// lines of [vouchers] (newest first). Item names match case-insensitively.
ItemTrade itemTrade(List<Voucher> vouchers, String item, String kind) {
  final String key = item.trim().toLowerCase();
  final ItemAcc acc = ItemAcc();
  for (final Voucher v in vouchers) {
    if (v.kind == kind) acc.add(v, key);
  }
  return acc.trade;
}
