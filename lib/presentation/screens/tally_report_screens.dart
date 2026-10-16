// Official Tally reports: Trial Balance, Profit & Loss, Balance Sheet and
// Cash Flow exactly as TallyPrime calculated them (the Agent fetches one
// report at a time). Lines as Tally lists them; a line opens its ledgers.
// Read-only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/share/share_doc.dart';
import '../../core/utils/format.dart';
import '../../data/models/models.dart';
import '../widgets/common.dart';

/// "₹1,200 Dr" / "₹1,200 Cr" (Tally sign: Dr −, Cr +).
String drCr(num v) =>
    v == 0 ? inr(0) : '${inr(v.abs())} ${v < 0 ? 'Dr' : 'Cr'}';

/// A period chip's text.
String trPeriodLabel(String report, TallyPeriod p, DateTime today) {
  final bool isToday =
      p.to.year == today.year &&
      p.to.month == today.month &&
      p.to.day == today.day;
  final String to = isToday ? 'Today' : dmy(p.to);
  return report == 'profit_loss' || report == 'cash_flow'
      ? '${dm(p.from)} – $to'
      : (isToday ? 'Today' : 'As on $to');
}

/// Tally column tag → a readable heading (Cash Flow and others).
String tagLabel(String tag) {
  final String t = tag
      .replaceAll(RegExp(r'^(DSP|BS|PL|CF)'), '')
      .replaceAll(RegExp(r'(AMTA|AMT)$'), '')
      .replaceAll('.', ' ')
      .trim();
  if (t.isEmpty) return 'Amount';
  return t[0] + t.substring(1).toLowerCase();
}

class TallyReportScreen extends ConsumerWidget {
  const TallyReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TallyReport? r = c.trData;
    final String title = kTallyReportTitles[c.trReport] ?? 'Report';
    final List<TallyPeriod> periods =
        c.trPeriods?.of(c.trReport) ?? const <TallyPeriod>[];
    final String? calcKind = <String, String>{
      'trial_balance': 'tb',
      'profit_loss': 'pl',
      'balance_sheet': 'bs',
    }[c.trReport];
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn(
              'file',
              key: const ValueKey<String>('trShare'),
              onTap: r == null || c.trBusy
                  ? null
                  : () => c.previewDoc(tallyReportDoc(c, r)),
            ),
            CBtn('sync', onTap: c.trBusy ? null : c.loadTallyReport),
          ],
        ),
        H1(title, afterNav: true),
        Sub(
          <String>[
            if ((r?.company ?? '').isNotEmpty) r!.company else c.companyName,
            'From Tally',
          ].join(' · '),
        ),
        if (periods.length > 1)
          Chips(
            margin: const EdgeInsets.only(top: 2, bottom: 14),
            children: <Widget>[
              for (int i = 0; i < periods.length; i++)
                ChipBtn(
                  trPeriodLabel(c.trReport, periods[i], c.today),
                  key: ValueKey<String>('trPeriod-$i'),
                  height: 38,
                  fontSize: 13.5,
                  on:
                      r != null &&
                      r.to != null &&
                      _sameDay(r.to!, periods[i].to) &&
                      r.from != null &&
                      _sameDay(r.from!, periods[i].from),
                  onTap: c.trBusy ? null : () => c.setTallyPeriod(periods[i]),
                ),
            ],
          ),
        if (c.trError != null)
          InfoBox(c.trError!, icon: 'info')
        else if (r == null)
          EmptyBox(c.trBusy ? 'Loading Tally figures…' : 'No figures yet.')
        else ...<Widget>[
          if (c.trBusy)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          _Meta(r),
          ...switch (r.report) {
            'trial_balance' => <Widget>[_TrialBalance(r)],
            'balance_sheet' => <Widget>[
              _Side(r, 'Liabilities', credit: true),
              _Side(r, 'Assets', credit: false),
            ],
            'profit_loss' => <Widget>[
              _Side(r, 'Income', credit: true),
              _Side(r, 'Expenses', credit: false),
            ],
            _ => <Widget>[_Lines(r)],
          },
        ],
        if (calcKind != null)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Center(
              child: Tap(
                key: const ValueKey<String>('trCalculated'),
                onTap: () => c.openFinancial(calcKind),
                radius: 12,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'Show the calculated report',
                    style: ts(13.5, w: w700, c: Tc.of(context).acc),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Period, when Tally's figures were fetched, and the sides check.
class _Meta extends StatelessWidget {
  const _Meta(this.r);
  final TallyReport r;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final String period = r.report == 'profit_loss' || r.report == 'cash_flow'
        ? '${dmy(r.from)} – ${dmy(r.to)}'
        : 'As on ${dmy(r.to)}';
    final String fetched = r.fetchedAt == null
        ? ''
        : ' · fetched ${dmy(r.fetchedAt)} ${clock(r.fetchedAt!)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(
            '$period$fetched',
            key: const ValueKey<String>('trMeta'),
            style: ts(13, w: w600, c: p.ink3),
          ),
        ),
        if (r.balanced == true)
          Banner2(
            r.report == 'trial_balance'
                ? 'Debit ${inr(r.debit)} = Credit ${inr(r.credit)}'
                : 'Both sides are equal',
            ok: true,
            margin: const EdgeInsets.only(bottom: 12),
          )
        else if (r.balanced == false)
          Banner2(
            'Sides differ by ${inr(r.difference)} — compare with Tally',
            ok: false,
            margin: const EdgeInsets.only(bottom: 12),
          ),
      ],
    );
  }
}

/// One side of the Balance Sheet / P&L: Tally's lines with their sign
/// (Cr: liabilities / income; Dr: assets / expenses), each opening its
/// ledgers.
class _Side extends ConsumerWidget {
  const _Side(this.r, this.title, {required this.credit});
  final TallyReport r;
  final String title;
  final bool credit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final List<TallyRow> rows = r.rows.where((TallyRow x) {
      final num? v = x.main;
      return v != null && v != 0 && (credit ? v > 0 : v < 0);
    }).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    final num total = rows.fold<num>(
      0,
      (num a, TallyRow x) => a + x.main!.abs(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Sec(title),
        GlassList(
          children: <Widget>[
            for (final TallyRow x in rows) ...<Widget>[
              RowX(
                key: ValueKey<String>('trRow-${x.name}'),
                onTap: x.ledgers.isEmpty ? null : () => c.toggleTrOpen(x.name),
                children: <Widget>[
                  Expanded(
                    child: RTx(
                      x.name,
                      x.ledgers.isEmpty
                          ? ''
                          : '${x.ledgers.length} ${x.ledgers.length == 1 ? 'ledger' : 'ledgers'}',
                      ell: false,
                    ),
                  ),
                  const SizedBox(width: 10),
                  AmtText(inr(x.main!.abs()), style: amtStyle(context)),
                  if (x.ledgers.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 6),
                    Ic(
                      c.trOpen.contains(x.name) ? 'chevU' : 'chevD',
                      size: IcSize.s,
                      color: Tc.of(context).ink3,
                    ),
                  ],
                ],
              ),
              if (c.trOpen.contains(x.name))
                for (final TallyLedger l in x.ledgers)
                  _LedgerLine(l.name, l.group, l.amount),
            ],
            RowX(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Total',
                    style: ts(15, w: w800, c: Tc.of(context).ink),
                  ),
                ),
                AmtText(inr(total), style: amtStyle(context)),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _LedgerLine extends StatelessWidget {
  const _LedgerLine(this.name, this.group, this.amount);
  final String name, group;
  final num amount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 14),
    child: RowX(
      children: <Widget>[
        Expanded(child: RTx(name, group, ell: true, titleSize: 14)),
        const SizedBox(width: 10),
        AmtText(drCr(amount), style: rsStyle(context, 13)),
      ],
    ),
  );
}

/// Trial Balance: ledgers by group (a group opens its ledgers), Dr / Cr.
class _TrialBalance extends ConsumerWidget {
  const _TrialBalance(this.r);
  final TallyReport r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final Map<String, List<TbLedger>> byGroup = <String, List<TbLedger>>{};
    for (final TbLedger l in r.ledgers) {
      if (l.closing == 0) continue;
      (byGroup[l.parent] ??= <TbLedger>[]).add(l);
    }
    final List<String> groups = byGroup.keys.toList()..sort();
    if (groups.isEmpty) return const EmptyBox('No balances.');
    return GlassList(
      children: <Widget>[
        for (final String g in groups) ...<Widget>[
          RowX(
            key: ValueKey<String>('trRow-$g'),
            onTap: () => c.toggleTrOpen(g),
            children: <Widget>[
              Expanded(
                child: RTx(
                  g,
                  '${byGroup[g]!.length} ${byGroup[g]!.length == 1 ? 'ledger' : 'ledgers'}',
                  ell: false,
                ),
              ),
              const SizedBox(width: 10),
              AmtText(
                drCr(
                  byGroup[g]!.fold<num>(
                    0,
                    (num a, TbLedger l) => a + l.closing,
                  ),
                ),
                style: amtStyle(context),
              ),
              const SizedBox(width: 6),
              Ic(
                c.trOpen.contains(g) ? 'chevU' : 'chevD',
                size: IcSize.s,
                color: Tc.of(context).ink3,
              ),
            ],
          ),
          if (c.trOpen.contains(g))
            for (final TbLedger l
                in byGroup[g]!
                  ..sort((TbLedger a, TbLedger b) => a.name.compareTo(b.name)))
              _LedgerLine(l.name, 'Opening ${drCr(l.opening)}', l.closing),
        ],
      ],
    );
  }
}

/// Cash Flow and other reports: Tally's lines with every amount column.
class _Lines extends StatelessWidget {
  const _Lines(this.r);
  final TallyReport r;

  @override
  Widget build(BuildContext context) {
    final List<TallyRow> rows = r.rows
        .where((TallyRow x) => x.amounts.isNotEmpty)
        .toList();
    if (rows.isEmpty) {
      return const EmptyBox('Tally sent no figures for this period.');
    }
    return GlassList(
      children: <Widget>[
        for (final TallyRow x in rows)
          RowX(
            key: ValueKey<String>('trRow-${x.name}'),
            children: <Widget>[
              Expanded(
                child: RTx(
                  x.name,
                  <String>[
                    for (final MapEntry<String, num> e in x.amounts.entries)
                      '${tagLabel(e.key)} ${inr(e.value)}',
                  ].join(' · '),
                  ell: false,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// The report as a PDF: Tally's lines (Trial Balance: ledgers, Dr / Cr).
ShareDoc tallyReportDoc(AppController c, TallyReport r) {
  final String period = r.report == 'profit_loss' || r.report == 'cash_flow'
      ? '${dmy(r.from)} – ${dmy(r.to)}'
      : 'As on ${dmy(r.to)}';
  if (r.report == 'trial_balance') {
    final List<TbLedger> ls =
        r.ledgers.where((TbLedger l) => l.closing != 0).toList()..sort(
          (TbLedger a, TbLedger b) =>
              '${a.parent}${a.name}'.compareTo('${b.parent}${b.name}'),
        );
    return ShareDoc(
      title: r.title,
      subtitle: '$period · from Tally',
      company: r.company.isEmpty ? c.companyName : r.company,
      fileStem: 'Trial_Balance',
      table: DocTable(
        const <String>['Ledger', 'Group', 'Debit', 'Credit'],
        <List<String>>[
          for (final TbLedger l in ls)
            <String>[
              l.name,
              l.parent,
              l.closing < 0 ? inr(-l.closing) : '',
              l.closing > 0 ? inr(l.closing) : '',
            ],
        ],
        right: const <int>{2, 3},
      ),
      totals: <(String, String)>[
        ('Total debit', inr(r.debit)),
        ('Total credit', inr(r.credit)),
      ],
    );
  }
  return ShareDoc(
    title: r.title,
    subtitle: '$period · from Tally',
    company: r.company.isEmpty ? c.companyName : r.company,
    fileStem: r.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_'),
    table: DocTable(
      const <String>['Particulars', 'Amount'],
      <List<String>>[
        for (final TallyRow x in r.rows)
          if (x.main != null) <String>[x.name, drCr(x.main!)],
      ],
      right: const <int>{1},
    ),
  );
}
