// E-invoices: each sales invoice's e-invoice as TallyPrime created it —
// the Reports tile, the report (counts, alerts, list), the e-invoice section
// on an invoice and the details sheet. Read only: e-invoices are created in
// Tally.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/utils/format.dart';
import '../../data/models/models.dart';
import '../widgets/common.dart';
import '../widgets/report_loader.dart';
import '../widgets/report_card.dart';
import 'cashflow_screens.dart' show FromToBar;

BadgeKind _badge(EinvStatus s) => switch (s) {
  EinvStatus.done => BadgeKind.ok,
  EinvStatus.pending => BadgeKind.warn,
  EinvStatus.cancelled => BadgeKind.bad,
  EinvStatus.notNeeded => BadgeKind.info,
};

/// Reports: the E-invoices tile (same access as the financial reports).
class EinvoiceTile extends ConsumerWidget {
  const EinvoiceTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    if (c.finCanView != true || !c.repo.isRemote || c.demo) {
      return const SizedBox.shrink();
    }
    return ReportCard(
      key: const ValueKey<String>('einvTile'),
      icon: 'receipt',
      title: 'E-invoices',
      subtitle: 'IRN status, pending and alerts',
      onTap: () {
        if (c.guardTap('fin', 'einv')) c.openEinvoices();
      },
    );
  }
}

/// The e-invoice lines of one invoice (IRN, acknowledgement, e-way bill,
/// alerts) — shared by the invoice screen and the details sheet.
List<Widget> einvDetails(BuildContext context, EinvRow r) {
  final TcPalette p = Tc.of(context);
  return <Widget>[
    KvList(<(String, String, bool)>[
      ('Status', r.status.label, false),
      if (r.irn != null) ('IRN', r.irn!, false),
      if (r.ackNo != null) ('Ack No', r.ackNo!, false),
      if (r.ackDate != null) ('Ack date', dmy(r.ackDate), false),
      if (r.partyGstin != null) ('Customer GSTIN', r.partyGstin!, false),
      if (r.partyGstin == null && r.registrationType != null)
        ('Customer GST', r.registrationType!, false),
      if (r.status == EinvStatus.pending && r.daysLeft != null)
        ('Days left of 30', '${r.daysLeft}', false),
      for (final MapEntry<String, String> e in r.eway.entries)
        ('E-way bill ${e.key.toLowerCase()}', e.value, false),
    ]),
    for (final String a in r.alerts)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          einvAlertLabel(a),
          key: ValueKey<String>('einvAlert-$a'),
          style: ts(13, w: w700, c: p.warn),
        ),
      ),
  ];
}

/// Invoice screen: its e-invoice (only when Tally created one or it is
/// needed and pending).
class EinvoiceSection extends ConsumerWidget {
  const EinvoiceSection(this.v, {super.key});
  final Voucher v;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final EinvRow? r = c.einvOf(v);
    if (r == null || r.status == EinvStatus.notNeeded) {
      return const SizedBox.shrink();
    }
    return Column(
      key: const ValueKey<String>('einvSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(child: Sec('E-invoice')),
            Padding(
              padding: const EdgeInsets.only(top: 14, right: 8),
              child: Bdg(r.status.label, kind: _badge(r.status), dot: true),
            ),
          ],
        ),
        ...einvDetails(context, r),
        if (r.irn != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 6, right: 6),
            child: Text(
              'The QR code is printed on this invoice\'s PDF (See bill PDF / Share).',
              style: rsStyle(context),
            ),
          ),
      ],
    );
  }
}

/// A report row's details (when the invoice is not on the phone).
class EinvoiceRowSheet extends ConsumerWidget {
  const EinvoiceRowSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final EinvRow? r = c.einvSel;
    if (r == null) return const SizedBox.shrink();
    return Sheet(
      child: Column(
        key: const ValueKey<String>('einvRowSheet'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHead(
            r.voucherNo ?? 'Invoice',
            sub: <String>[
              if (r.partyName != null) r.partyName!,
              if (r.date != null) dmy(r.date),
              if (r.amount != null) inr(r.amount),
            ].join(' · '),
          ),
          ...einvDetails(context, r),
          const SizedBox(height: 14),
          Btn(label: 'Close', kind: BtnKind.g, onTap: c.closeOv),
        ],
      ),
    );
  }
}

/// Reports → E-invoices.
class EinvoicesScreen extends ConsumerWidget {
  const EinvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final EinvList? l = c.einvList;
    final EinvSummary s = l?.summary ?? const EinvSummary();
    final (DateTime from, DateTime to) = c.einvRange;
    final List<(String, String, int, Color)> stats =
        <(String, String, int, Color)>[
          ('done', 'E-invoiced', s.done, p.pos),
          ('pending', 'Pending', s.pending, p.warn),
          ('alerts', 'Alerts', s.alerts, p.neg),
          ('not_needed', 'Not needed', s.notNeeded, p.ink3),
        ];
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn('sync', onTap: c.einvBusy ? null : c.loadEinvoices),
          ],
        ),
        const H1('E-invoices', afterNav: true),
        Sub(
          <String>[
            if ((l?.company ?? '').isNotEmpty) l!.company else c.companyName,
          ].join(' · '),
        ),
        FromToBar(
          from: from,
          to: to,
          onTap: c.einvBusy ? null : c.openEinvRange,
        ),
        const SizedBox(height: 12),
        Grid(
          cols: 2,
          gap: 10,
          children: <Widget>[
            for (final (String, String, int, Color) x in stats)
              Tap(
                key: ValueKey<String>('einvStat-${x.$1}'),
                onTap: () =>
                    c.setEinvStatus(c.einvStatus == x.$1 ? 'all' : x.$1),
                child: Glass(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          x.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(
                            13.5,
                            w: c.einvStatus == x.$1 ? w800 : w600,
                            c: p.ink2,
                          ),
                        ),
                      ),
                      Text(
                        '${x.$3}',
                        style: ts(19, w: w800, c: x.$4),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        Chips(
          margin: const EdgeInsets.only(top: 12, bottom: 12),
          children: <Widget>[
            for (final (String, String) f in AppController.kEinvStatuses)
              ChipBtn(
                f.$2,
                key: ValueKey<String>('einvFilter-${f.$1}'),
                on: c.einvStatus == f.$1,
                onTap: () => c.setEinvStatus(f.$1),
              ),
          ],
        ),
        if (c.einvError != null)
          InfoBox(c.einvError!, icon: 'info')
        else if (l == null)
          (c.einvBusy ? const ReportLoader() : EmptyBox('Not loaded yet.'))
        else ...<Widget>[
          if (c.einvBusy)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (l.rows.isEmpty)
            EmptyBox(
              s.total == 0
                  ? 'No invoices synced for these dates yet. The Agent sends '
                        'e-invoice details with the next sync.'
                  : 'No invoices in this list.',
            )
          else
            GlassList(
              margin: const EdgeInsets.only(bottom: 12),
              children: <Widget>[for (final EinvRow r in l.rows) _Row(r)],
            ),
          if (l.truncated)
            const InfoBox(
              'Showing the first 500. Choose shorter dates to see the rest.',
              icon: 'info',
            ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'E-invoices are created in TallyPrime; this shows what Tally '
            'saved. Pending: a tax invoice to a GST-registered customer '
            'without an IRN. Businesses with turnover ₹10 crore or more '
            'must e-invoice within 30 days of the invoice date.',
            style: ts(12.5, h: 1.4, c: p.ink3),
          ),
        ),
      ],
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row(this.r);
  final EinvRow r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String line = <String>[
      if (r.date != null) dmy(r.date),
      if (r.voucherType != null) r.voucherType!,
      if (r.status == EinvStatus.done && r.ackDate != null)
        'Ack ${dmy(r.ackDate)}',
      if (r.status == EinvStatus.pending && r.daysLeft != null)
        r.daysLeft == 0 ? 'Past 30 days' : '${r.daysLeft} days left',
    ].join(' · ');
    return RowX(
      key: ValueKey<String>('einvRow-${r.voucherGuid}'),
      minHeight: 64,
      onTap: () => c.openEinvRow(r),
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${r.voucherNo ?? '—'} · ${r.partyName ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts(15, w: w700, c: p.ink),
              ),
              Text(
                line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ts(12.5, c: p.ink3),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  Bdg(r.status.label, kind: _badge(r.status), fontSize: 11.5),
                  if (r.alerts.isNotEmpty)
                    const Bdg('Check', kind: BadgeKind.bad, fontSize: 11.5),
                ],
              ),
            ],
          ),
        ),
        Text(
          r.amount == null ? '—' : inr(r.amount),
          style: amtStyle(context, size: 14),
        ),
      ],
    );
  }
}
