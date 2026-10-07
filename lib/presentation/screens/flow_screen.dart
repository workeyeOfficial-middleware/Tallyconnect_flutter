// ENTRY FLOW (Main.dc.html 718–867; view model 2399–2469): Sales, Purchase,
// Money In, Money Out and Adjustment, with steps, GST totals, payment modes,
// journal balancing and the summary check.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_fields.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/utils/format.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../widgets/common.dart';
import 'auth_screens.dart' show LinkBtn;

class FlowScreen extends ConsumerWidget {
  const FlowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final FlowType cfg = kFlowTypes[c.flowType]!;
    final int step = c.flowStep;
    final int last = cfg.steps.length - 1;
    final List<Line> lines = c.lines[c.flowType] ?? <Line>[];
    final ({num sub, num gst, num total}) tot = c.totals(lines);
    final String pf = cfg.p;
    final num payAmt = numOf(c.form['${pf}Amt']);
    final bool balanced = c.drSum == c.crSum && c.drSum > 0;
    final bool nextOff =
        (cfg.items && step == 1 && lines.isEmpty) ||
        (c.flowType == 'journal' && step == 1 && !balanced) ||
        (step == 0 && c.f('${pf}Party').isEmpty);

    Widget body;
    if (step == last) {
      body = _Summary(cfg: cfg, tot: tot, payAmt: payAmt);
    } else if (step == 0) {
      body = _Details(cfg: cfg);
    } else if (cfg.items && step == 1) {
      body = _Items(lines: lines, tot: tot);
    } else if (cfg.items && step == 2) {
      body = _Pay(cfg: cfg, tot: tot, payAmt: payAmt);
    } else if (c.flowType == 'journal') {
      body = const _Ledgers();
    } else {
      body = _Mode(cfg: cfg, payAmt: payAmt);
    }

    return FlowScr(
      foot: <Widget>[
        Expanded(
          flex: 10,
          child: Btn(
            label: step == 0 ? 'Cancel' : 'Back',
            kind: BtnKind.g,
            onTap: c.flowPrev,
          ),
        ),
        if (step < last)
          Expanded(
            flex: 17,
            child: Btn(
              label: 'Next',
              icon: 'chevR',
              iconAfter: true,
              enabled: !nextOff,
              onTap: c.flowNext,
            ),
          ),
        if (step == last)
          Expanded(
            flex: 17,
            child: Btn(
              label: c.busy ? 'Saving…' : 'Save',
              icon: 'check',
              kind: BtnKind.a,
              enabled: !c.busy,
              onTap: () => c.saveFlow(false),
            ),
          ),
      ],
      children: <Widget>[
        Row(
          children: <Widget>[
            CBtn('chevL', onTap: c.flowPrev),
            const SizedBox(width: 10),
            Ico(cfg.ic, size: IcoSize.xs, color: p.cat(cfg.c), icon: IcSize.s),
            const SizedBox(width: 10),
            Expanded(child: RTx(cfg.title, cfg.sub, titleSize: 18)),
            const SizedBox(width: 10),
            CBtn('help', onTap: () => c.go('help')),
          ],
        ),
        const SizedBox(height: 6),
        _Steps(steps: cfg.steps, cur: step),
        KeyedSubtree(key: ValueKey<String>('${c.flowType}-$step'), child: body),
      ],
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.steps, required this.cur});
  final List<String> steps;
  final int cur;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Glass(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
      child: CustomPaint(
        painter: _StepLines(steps.length, cur, p.acc2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < steps.length; i++)
              Expanded(
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < cur
                            ? p.acc
                            : (i == cur ? p.navy : Colors.white),
                        border: i < cur || i == cur
                            ? null
                            : Border.all(color: navyA(.12)),
                        boxShadow: i == cur
                            ? <BoxShadow>[
                                BoxShadow(color: navyA(.14), spreadRadius: 5),
                              ]
                            : null,
                      ),
                      child: i < cur
                          ? const Ic(
                              'check',
                              size: IcSize.xs,
                              color: Colors.white,
                            )
                          : Text(
                              '${i + 1}',
                              style: ts(
                                14,
                                w: w800,
                                c: i == cur ? Colors.white : p.ink3,
                              ),
                            ),
                    ),
                    const SizedBox(height: 6),
                    // Shrinks on narrow phones instead of wrapping into the
                    // neighbouring step label.
                    AmtText(
                      steps[i],
                      align: Alignment.center,
                      style: ts(
                        12.5,
                        w: w700,
                        c: i < cur ? p.pos : (i == cur ? p.ink : p.ink3),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepLines extends CustomPainter {
  _StepLines(this.n, this.cur, this.on);
  final int n, cur;
  final Color on;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width / n;
    for (int i = 1; i < n; i++) {
      final Paint pt = Paint()..color = i <= cur ? on : navyA(.1);
      canvas.drawRRect(
        RRect.fromLTRBR(
          w * (i - 1) + w / 2,
          16,
          w * i + w / 2,
          19,
          const Radius.circular(2),
        ),
        pt,
      );
    }
  }

  @override
  bool shouldRepaint(_StepLines old) =>
      old.cur != cur || old.on != on || old.n != n;
}

Widget _rupee(BuildContext c) => Text(
  '₹',
  style: ts(19, w: w800, c: Tc.of(c).ink),
);

class _Details extends ConsumerWidget {
  const _Details({required this.cfg});
  final FlowType cfg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String pf = cfg.p;
    final String type = c.flowType;
    final bool journal = type == 'journal';
    // Same 12 px gap below the step bar as every other step's card (this
    // card had none, so it sat under the step bar's edge and shadow).
    return Rise(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Fld(
                      label: cfg.noLabel,
                      icon: 'hash',
                      child: Inp(
                        value: c.f('${pf}No'),
                        onChanged: (String v) => c.setF('${pf}No', v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Fld(
                      label: 'Date',
                      icon: 'calendar',
                      req: true,
                      child: DateInp(
                        value: c.f('${pf}Date'),
                        onChanged: (String v) => c.setF('${pf}Date', v),
                        fontSize: 15,
                        hPad: 10,
                      ),
                    ),
                  ),
                ],
              ),
              Fld(
                label: cfg.partyLabel,
                req: true,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: SelBtn(
                        leading: Av(initials(c.f('${pf}Party')), size: Av.sm),
                        text: c.f('${pf}Party'),
                        onTap: () {
                          if (journal) {
                            c.openPick(
                              'Choose account',
                              'jParty',
                              c.repo.ledgers(),
                            );
                          } else {
                            c.openPick(
                              'Choose ${cfg.list == 'c' ? 'customer' : 'supplier'}',
                              '${pf}Party',
                              c
                                  .partyPool()
                                  .where((Party x) => x.type == cfg.list)
                                  .map(
                                    (Party x) => Opt(
                                      x.name,
                                      '${x.type == 'c' ? 'Customer' : 'Supplier'} · ${x.city.isNotEmpty ? x.city : (x.group ?? '')}',
                                    ),
                                  )
                                  .toList(),
                            );
                          }
                        },
                      ),
                    ),
                    if (!journal) ...<Widget>[
                      const SizedBox(width: 10),
                      CBtn(
                        'plus',
                        size: 56,
                        radius: 16,
                        color: p.navy,
                        onTap: () => c.openNewParty(
                          key: '${pf}Party',
                          type: cfg.list ?? 'c',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (type == 'purchase')
                Fld(
                  label: "Seller's bill no.",
                  icon: 'hash',
                  child: Inp(
                    value: c.f('pSupInv'),
                    onChanged: (String v) => c.setF('pSupInv', v),
                  ),
                ),
              if (!cfg.items && !journal) ...<Widget>[
                Fld(
                  label: cfg.amtLabel,
                  req: true,
                  child: Inp(
                    value: c.f('${pf}Amt'),
                    onChanged: (String v) => c.setF('${pf}Amt', v),
                    prefix: _rupee(context),
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    formatters: kDecimal,
                    fontSize: 20,
                    fontWeight: w800,
                  ),
                ),
                Fld(
                  label: 'Against which bill? (optional)',
                  icon: 'hash',
                  child: Inp(
                    value: c.f('${pf}Ref'),
                    onChanged: (String v) => c.setF('${pf}Ref', v),
                  ),
                ),
              ],
              if (cfg.items)
                Fld(
                  label: 'Pay by date',
                  icon: 'calendar',
                  child: DateInp(
                    value: c.f('${pf}Due'),
                    onChanged: (String v) => c.setF('${pf}Due', v),
                  ),
                ),
              Fld(
                label: 'Note (optional)',
                icon: 'note',
                margin: EdgeInsets.zero,
                child: Inp(
                  value: c.f('${pf}Note'),
                  onChanged: (String v) => c.setF('${pf}Note', v),
                  textarea: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Items extends ConsumerWidget {
  const _Items({required this.lines, required this.tot});
  final List<Line> lines;
  final ({num sub, num gst, num total}) tot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    void openPicker() => c.update(() {
      c.overlay = 'picker';
      c.form['pickQ'] = '';
    });
    return Rise(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GlassRow(
            margin: const EdgeInsets.only(top: 12),
            minHeight: 56,
            onTap: openPicker,
            children: <Widget>[
              Ic('search', color: p.ink3),
              Expanded(
                child: Text('Search item name', style: ts(16, c: p.ink3)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Glass(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Items (${lines.length})',
                            style: rtStyle(context, 17),
                          ),
                        ),
                        Text('Rate × quantity', style: rsStyle(context)),
                      ],
                    ),
                  ),
                  for (int i = 0; i < lines.length; i++) ...<Widget>[
                    if (i > 0) listDivider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    RTx(
                                      lines[i].name,
                                      '${inr(lines[i].rate)} × ${lines[i].qty} ${lines[i].unit} · GST ${qty(lines[i].gst)}%',
                                    ),
                                    // This line's rate / GST (this bill only).
                                    Tap(
                                      onTap: () => c.openLineEdit(i),
                                      radius: 8,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            Ic(
                                              'edit',
                                              size: IcSize.xs,
                                              color: Tc.of(context).acc,
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                'Edit rate / GST',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: ts(
                                                  13.5,
                                                  w: w700,
                                                  c: Tc.of(context).acc,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                inr(lines[i].rate * lines[i].qty),
                                style: amtStyle(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: <Widget>[
                              Stepper2(
                                label: '${lines[i].qty} ${lines[i].unit}',
                                onDec: () => c.updLine(
                                  i,
                                  (int q) => q - 1 < 1 ? 1 : q - 1,
                                ),
                                onInc: () => c.updLine(i, (int q) => q + 1),
                              ),
                              const Spacer(),
                              DelBtn(onTap: () => c.delLine(i)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (lines.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        'No items yet. Tap “Add item”.',
                        textAlign: TextAlign.center,
                        style: rsStyle(context, 15),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                    child: DashBtn(
                      onTap: openPicker,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Ic('plus', color: p.navy),
                          const SizedBox(width: 8),
                          Text(
                            'Add item',
                            style: ts(16, w: w800, c: p.navy),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          KvList(<(String, String, bool)>[
            ('Before GST', inr(tot.sub), false),
            ('GST', inr(tot.gst), false),
            ('Bill total', inr(tot.total), true),
          ], margin: const EdgeInsets.only(top: 12)),
        ],
      ),
    );
  }
}

class _Modes extends ConsumerWidget {
  const _Modes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String mode = c.modes[c.flowType] ?? 'cash';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < kModes.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Tap(
                onTap: () => c.setMode(kModes[i].id),
                radius: 18,
                child: kModes[i].id == mode
                    ? CustomPaint(
                        painter: OuterShadow(
                          BorderRadius.circular(18),
                          <BoxShadow>[css(0, 12, 22, -10, navyA(.75))],
                        ),
                        child: Container(
                          height: 72,
                          decoration: BoxDecoration(
                            color: p.navy,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: _modeInner(kModes[i], Colors.white),
                        ),
                      )
                    : Glass(
                        radius: 18,
                        height: 72,
                        child: _modeInner(kModes[i], p.ink2),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _modeInner(PayMode m, Color c) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      Ic(m.ic, color: c),
      const SizedBox(height: 5),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: AmtText(
          m.t,
          align: Alignment.center,
          style: ts(13, w: w700, c: c),
        ),
      ),
    ],
  );
}

class _Pay extends ConsumerWidget {
  const _Pay({required this.cfg, required this.tot, required this.payAmt});
  final FlowType cfg;
  final ({num sub, num gst, num total}) tot;
  final num payAmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final String pf = cfg.p;
    final num bal = paise(tot.total - payAmt);
    return Rise(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Lab('How was it paid?', req: true),
              ),
              const _Modes(),
              Fld(
                label: cfg.amtLabel,
                child: Inp(
                  value: c.f('${pf}Amt'),
                  onChanged: (String v) => c.setF('${pf}Amt', v),
                  prefix: _rupee(context),
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  formatters: kDecimal,
                  fontSize: 20,
                  fontWeight: w800,
                ),
              ),
              Tot(
                child: Row(
                  children: <Widget>[
                    const Expanded(child: Text('Bill total')),
                    Text(inr(tot.total), style: amtStyle(context)),
                  ],
                ),
              ),
              Tot(
                kind: bal > 0 ? 'b' : 'c',
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(cfg.balLabel ?? '')),
                    Text(inr(bal > 0 ? bal : 0), style: amtStyle(context)),
                  ],
                ),
              ),
              Fld(
                label: 'Payment note (optional)',
                icon: 'note',
                margin: EdgeInsets.zero,
                child: Inp(
                  value: c.f('${pf}PayNote'),
                  onChanged: (String v) => c.setF('${pf}PayNote', v),
                  textarea: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Mode extends ConsumerWidget {
  const _Mode({required this.cfg, required this.payAmt});
  final FlowType cfg;
  final num payAmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String pf = cfg.p;
    final String mode = c.modes[c.flowType] ?? 'cash';
    final String acc = c.f('${pf}Acc');
    return Rise(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Lab('How was it paid?', req: true),
              ),
              const _Modes(),
              if (mode != 'cash') ...<Widget>[
                Fld(
                  label: 'Bank name',
                  icon: 'bank',
                  child: Inp(
                    value: c.f('${pf}Bank'),
                    onChanged: (String v) => c.setF('${pf}Bank', v),
                  ),
                ),
                Fld(
                  label: 'Reference / UTR no.',
                  icon: 'hash',
                  child: Inp(
                    value: c.f('${pf}Utr'),
                    onChanged: (String v) => c.setF('${pf}Utr', v),
                  ),
                ),
              ],
              Fld(
                label: cfg.accLabel,
                child: SelBtn(
                  leading: Ico(
                    acc.contains('Cash') ? 'cash' : 'bank',
                    size: IcoSize.xs,
                    color: p.navy,
                    icon: IcSize.s,
                  ),
                  text: acc,
                  onTap: () => c.openPick(
                    cfg.accLabel ?? '',
                    '${pf}Acc',
                    c.repo.accounts(),
                  ),
                ),
              ),
              Tot(
                margin: EdgeInsets.zero,
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(cfg.amtLabel ?? '')),
                    Text(inr(payAmt), style: amtStyle(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ledgers extends ConsumerWidget {
  const _Ledgers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final num dr = c.drSum, cr = c.crSum;
    final bool balanced = dr == cr && dr > 0;
    return Rise(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Which accounts?', style: rtStyle(context, 17)),
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 12),
                child: Text.rich(
                  const TextSpan(
                    children: <InlineSpan>[
                      TextSpan(text: 'Money goes '),
                      TextSpan(
                        text: 'to',
                        style: TextStyle(fontWeight: w700),
                      ),
                      TextSpan(text: ' one account and comes '),
                      TextSpan(
                        text: 'from',
                        style: TextStyle(fontWeight: w700),
                      ),
                      TextSpan(text: ' another. Both sides must match.'),
                    ],
                  ),
                  style: rsStyle(context),
                ),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Tot(
                      kind: 'c',
                      margin: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Goes to (Dr)',
                            style: ts(13.5, w: w700, c: p.pos),
                          ),
                          AmtText(
                            inr(dr),
                            align: Alignment.centerLeft,
                            style: amtStyle(context, size: 19),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Tot(
                      margin: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Comes from (Cr)',
                            style: ts(13.5, w: w700, c: p.navy),
                          ),
                          AmtText(
                            inr(cr),
                            align: Alignment.centerLeft,
                            style: amtStyle(context, size: 19),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (balanced)
                const Banner2('Matched — both sides are equal', ok: true)
              else
                Banner2(
                  'Not matching yet · difference ${inr(paise((dr - cr).abs()))}',
                  ok: false,
                ),
              for (int i = 0; i < c.jl.length; i++) ...<Widget>[
                if (i > 0) listDivider(),
                Container(
                  constraints: const BoxConstraints(minHeight: 60),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: <Widget>[
                      Tap(
                        onTap: () => c.updJl(
                          i,
                          (JLine x) =>
                              x.copyWith(side: x.side == 'Dr' ? 'Cr' : 'Dr'),
                        ),
                        radius: 11,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 62),
                          height: 34,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.jl[i].side == 'Dr'
                                ? mix(p.pos, .12)
                                : navyA(.1),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Text(
                            c.jl[i].side == 'Dr' ? 'Goes to' : 'From',
                            style: ts(
                              12.5,
                              w: w800,
                              c: c.jl[i].side == 'Dr' ? p.pos : p.navy,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: RTx(
                          c.jl[i].name,
                          c.jl[i].grp,
                          titleSize: 15,
                          ell: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _JInp(
                        value: c.jl[i].amt == 0 && c.repo.isRemote
                            ? ''
                            : qty(c.jl[i].amt),
                        onChanged: (String v) => c.updJl(
                          i,
                          (JLine x) => x.copyWith(amt: num.tryParse(v) ?? 0),
                        ),
                      ),
                      const SizedBox(width: 12),
                      DelBtn(size: 38, onTap: () => c.updJl(i, (_) => null)),
                    ],
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: DashBtn(
                  onTap: () =>
                      c.openPick('Add account', '__jl', c.repo.ledgers()),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Ic('plus', color: p.navy),
                      const SizedBox(width: 8),
                      Text(
                        'Add account',
                        style: ts(16, w: w800, c: p.navy),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.jinp` amount box.
class _JInp extends StatefulWidget {
  const _JInp({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_JInp> createState() => _JInpState();
}

class _JInpState extends State<_JInp> {
  late final TextEditingController _c = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_JInp old) {
    super.didUpdateWidget(old);
    // Keep what the user typed ("12." / "12.50") while it means the same.
    if (widget.value != _c.text &&
        num.tryParse(widget.value) != num.tryParse(_c.text)) {
      _c.text = widget.value;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Container(
      width: 118,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: navyA(.13)),
      ),
      child: TextField(
        controller: _c,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
        ],
        onChanged: widget.onChanged,
        style: ts(15, w: w700, c: p.ink),
        decoration: const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.cfg, required this.tot, required this.payAmt});
  final FlowType cfg;
  final ({num sub, num gst, num total}) tot;
  final num payAmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String type = c.flowType;
    final String? blocker = c.flowBlocker;
    final String pf = cfg.p;
    final List<Line> lines = c.lines[type] ?? <Line>[];
    final String mode = c.modes[type] ?? 'cash';
    final String modeName = kModes
        .firstWhere((PayMode m) => m.id == mode, orElse: () => kModes.first)
        .t;
    final num bal = paise(tot.total - payAmt);
    String v(String k) => c.f('$pf$k');
    final String no = type == 'sales' && !c.repo.isRemote
        ? 'Sales ${v('No')}'
        : (v('No').isEmpty ? '(number from Tally)' : v('No'));
    String orDash(String s) => s.isEmpty ? '—' : s;

    final List<(String, int, List<(String, String, bool)>)> sections;
    if (cfg.items) {
      sections = <(String, int, List<(String, String, bool)>)>[
        (
          'Details',
          0,
          <(String, String, bool)>[
            (cfg.noLabel, no, false),
            ('Date', fdate(v('Date')), false),
            (type == 'sales' ? 'Customer' : 'Supplier', v('Party'), false),
            if (type == 'purchase')
              ("Seller's bill no.", c.f('pSupInv'), false),
            ('Pay by', fdate(v('Due')), false),
            ('Note', orDash(v('Note')), false),
          ],
        ),
        (
          'Items (${lines.length})',
          1,
          <(String, String, bool)>[
            for (final Line l in lines)
              ('${l.name} × ${l.qty} ${l.unit}', inr(l.rate * l.qty), false),
            ('Before GST', inr(tot.sub), false),
            ('GST', inr(tot.gst), false),
            ('Bill total', inr(tot.total), true),
          ],
        ),
        (
          'Payment',
          2,
          <(String, String, bool)>[
            ('Paid by', modeName, false),
            (cfg.amtLabel ?? '', inr(payAmt), false),
            (cfg.balLabel ?? '', inr(bal > 0 ? bal : 0), true),
          ],
        ),
      ];
    } else if (type == 'journal') {
      sections = <(String, int, List<(String, String, bool)>)>[
        (
          'Details',
          0,
          <(String, String, bool)>[
            (cfg.noLabel, v('No'), false),
            ('Date', fdate(v('Date')), false),
            ('Main account', v('Party'), false),
            ('Note', orDash(v('Note')), false),
          ],
        ),
        (
          'Accounts (${c.jl.length})',
          1,
          <(String, String, bool)>[
            for (final JLine j in c.jl)
              (
                '${j.side == 'Dr' ? 'Goes to · ' : 'Comes from · '}${j.name}',
                inr(j.amt),
                false,
              ),
          ],
        ),
      ];
    } else {
      sections = <(String, int, List<(String, String, bool)>)>[
        (
          'Details',
          0,
          <(String, String, bool)>[
            (cfg.noLabel, v('No'), false),
            ('Date', fdate(v('Date')), false),
            (cfg.partyLabel, v('Party'), false),
            ('Against bill', orDash(v('Ref')), false),
            (cfg.amtLabel ?? '', inr(payAmt), true),
            ('Note', orDash(v('Note')), false),
          ],
        ),
        (
          'How paid',
          1,
          <(String, String, bool)>[
            ('Paid by', modeName, false),
            if (mode != 'cash') ...<(String, String, bool)>[
              ('Bank name', orDash(v('Bank')), false),
              ('Reference no.', orDash(v('Utr')), false),
            ],
            (cfg.accLabel ?? '', v('Acc'), false),
          ],
        ),
      ];
    }
    final num heroAmt = cfg.items
        ? tot.total
        : (type == 'journal' ? c.drSum : payAmt);
    return Rise(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Glass(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Ico(cfg.ic, size: IcoSize.sm, color: p.cat(cfg.c)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '${cfg.sub} · check before saving',
                              style: ts(13.5, w: w700, h: 1.3, c: p.ink3),
                            ),
                            Text(no, style: rtStyle(context, 20)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .42,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Text('Total', style: rsStyle(context)),
                            const SizedBox(height: 4),
                            AmtText(
                              inr(heroAmt),
                              style: amtStyle(context, size: 22),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Date: ${fdate(v('Date'))}${cfg.items ? ' · Pay by: ${fdate(v('Due'))}' : ''}',
                    style: rsStyle(context),
                  ),
                  const SizedBox(height: 8),
                  Banner2(
                    blocker ?? 'Ready to send to Tally',
                    ok: blocker == null,
                    margin: const EdgeInsets.only(top: 2),
                  ),
                ],
              ),
            ),
          ),
          for (final (String, int, List<(String, String, bool)>) s in sections)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Glass(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(s.$1, style: rtStyle(context, 17)),
                          ),
                          ChipBtn(
                            'Change',
                            icon: 'edit',
                            iconSize: IcSize.xs,
                            height: 36,
                            fontSize: 14,
                            color: p.navy,
                            onTap: () => c.setStep(s.$2),
                          ),
                        ],
                      ),
                    ),
                    for (int i = 0; i < s.$3.length; i++)
                      Kv(
                        s.$3[i].$1,
                        s.$3[i].$2,
                        strong: s.$3[i].$3,
                        divider: i > 0,
                      ),
                  ],
                ),
              ),
            ),
          if (cfg.draft)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: LinkBtn(
                  'Save as draft on this phone',
                  onTap: () => c.saveFlow(true),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
