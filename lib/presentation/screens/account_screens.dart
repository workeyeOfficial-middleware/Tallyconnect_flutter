// COMPANIES (1323–1335), BILLING / PLANS (1337–1353), REFER (1355–1377),
// HELP (1379–1399).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/utils/format.dart';
import '../../data/models/models.dart';
import '../widgets/common.dart';
import 'auth_screens.dart' show FNote;

/// A company choice row (`.glass.row` + `.selrow` + `.tk`), shared with the
/// company sheet.
class CompanyRow extends ConsumerWidget {
  const CompanyRow(this.co, {super.key, this.sub});
  final Company co;
  final String? sub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final bool sel = co.id == c.company;
    return GlassRow(
      margin: const EdgeInsets.only(bottom: 10),
      border: sel ? Border.all(color: p.navy, width: 2) : null,
      onTap: () => c.pickCompany(co),
      children: <Widget>[
        Ico('building', size: IcoSize.sm, color: p.navy),
        Expanded(child: RTx(co.name, sub ?? co.sub)),
        Tk(sel),
      ],
    );
  }
}

class CompaniesScreen extends ConsumerWidget {
  const CompaniesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn(
              'sync',
              onTap: () => c.say('Company list refreshed from Tally'),
            ),
          ],
        ),
        const H1('Companies'),
        const Sub('Your companies in Tally'),
        const InfoBox(
          'Pick a company. Reports, bills and stock will show for that company.',
          icon: 'info',
        ),
        for (final Company co in c.repo.companies()) CompanyRow(co),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Text(
            'New companies show here once they are opened in Tally.',
            style: rsStyle(context),
          ),
        ),
      ],
    );
  }
}

class BillingScreen extends ConsumerWidget {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    return Scr(
      children: <Widget>[
        const BackNav(),
        const TitleBadge('Plans'),
        const Sub('Choose what fits your business'),
        Seg(
          items: const <String>['Yearly', 'Monthly'],
          selected: c.yearly ? 0 : 1,
          onPick: (int i) => c.update(() => c.yearly = i == 0),
        ),
        for (final Plan pl in c.repo.plans())
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Glass(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Ico(pl.ic, size: IcoSize.sm, color: p.cat(pl.c)),
                      const SizedBox(width: 12),
                      Expanded(child: RTx(pl.t, pl.s, titleSize: 19)),
                      if (pl.current)
                        const Bdg('Your plan', kind: BadgeKind.ok, dot: true),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 8),
                    child: Text.rich(
                      TextSpan(
                        text: pl.current
                            ? 'Custom'
                            : inr(c.yearly ? pl.y : pl.m),
                        children: <InlineSpan>[
                          TextSpan(
                            text:
                                ' ${pl.current ? '· talk to us' : (c.yearly ? '/ year' : '/ month')}',
                            style: ts(14, w: w600, c: p.ink3),
                          ),
                        ],
                      ),
                      style: ts(30, w: w800, ls: -.6, c: p.ink),
                    ),
                  ),
                  for (final String f in pl.feats)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: <Widget>[
                          Ic('check', size: IcSize.s, color: p.cat('receipt')),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(f, style: ts(15, c: p.ink2)),
                          ),
                        ],
                      ),
                    ),
                  if (!pl.current)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Btn(
                        label: 'Switch to ${pl.t}',
                        kind: BtnKind.g,
                        color: p.navy,
                        onTap: () =>
                            c.say('We will call you to switch to ${pl.t}'),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class ReferScreen extends ConsumerWidget {
  const ReferScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    return Scr(
      children: <Widget>[
        const BackNav(),
        const H1('Refer a friend'),
        const Sub('Invite other businesses that use Tally'),
        Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Ico(
                  'gift',
                  color: p.acc,
                  box: 66,
                  radius: 22,
                  icon: IcSize.xl,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Share your code',
                textAlign: TextAlign.center,
                style: rtStyle(context, 19),
              ),
              const SizedBox(height: 2),
              Text(
                'When they sign up with it, they show in your list below.',
                textAlign: TextAlign.center,
                style: ts(15, h: 1.3, c: p.ink3),
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 14),
                child: CustomPaint(
                  painter: DashedRRect(
                    BorderRadius.circular(18),
                    mix(p.acc, .35),
                    2,
                    fill: whiteA(.7),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'YOUR CODE',
                                style: ts(11, w: w800, ls: .88, c: p.ink3),
                              ),
                              Text(
                                'TC-WORKK72',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontFamilyFallback: const <String>[
                                    'Menlo',
                                    'Courier',
                                  ],
                                  fontSize: 22,
                                  fontWeight: w700,
                                  letterSpacing: 1.32,
                                  color: p.acc,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ChipBtn(
                          'Copy',
                          color: p.acc,
                          onTap: () => c.say('Code copied'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Btn(
                label: 'Share invite',
                icon: 'send',
                kind: BtnKind.a,
                onTap: () => c.say('Share sheet opened'),
              ),
            ],
          ),
        ),
        const H2Row('How it works'),
        GlassList(
          children: <Widget>[
            for (final (String, String, String, String) r
                in const <(String, String, String, String)>[
                  (
                    'chat',
                    'sales',
                    '1. Share your code',
                    'Send it on WhatsApp, SMS or email',
                  ),
                  (
                    'userPlus',
                    'party',
                    '2. Your friend signs up',
                    'They type your code when they join',
                  ),
                  (
                    'check',
                    'receipt',
                    '3. See them here',
                    'Track who has joined below',
                  ),
                ])
              RowX(
                children: <Widget>[
                  Ico(
                    r.$1,
                    size: IcoSize.xs,
                    color: p.cat(r.$2),
                    icon: IcSize.s,
                  ),
                  Expanded(child: RTx(r.$3, r.$4)),
                ],
              ),
          ],
        ),
        const H2Row('Your referrals'),
        const EmptyBox('No one has joined yet. Share your code to start.'),
      ],
    );
  }
}

class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final List<Faq> faqs = c.repo.faqs();
    return Scr(
      children: <Widget>[
        const BackNav(),
        const H1('Help'),
        const Sub('Answers and support'),
        Glass(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Row(
                  children: <Widget>[
                    Ico(
                      'help',
                      size: IcoSize.xs,
                      color: p.navy,
                      icon: IcSize.s,
                    ),
                    const SizedBox(width: 10),
                    Text('Common questions', style: rtStyle(context, 17)),
                  ],
                ),
              ),
              for (int i = 0; i < faqs.length; i++) ...<Widget>[
                if (i > 0) listDivider(),
                Tap(
                  onTap: () => c.update(() => c.faq = c.faq == i ? -1 : i),
                  radius: 16,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            faqs[i].q,
                            style: ts(
                              16,
                              w: w700,
                              c: c.faq == i ? p.acc : p.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Ic(
                          c.faq == i ? 'chevU' : 'chevD',
                          size: IcSize.s,
                          color: p.ink3,
                        ),
                      ],
                    ),
                  ),
                ),
                if (c.faq == i)
                  Rise(
                    ms: 300,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(faqs[i].a, style: ts(15, h: 1.5, c: p.ink2)),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const Sec('Talk to us'),
        GlassList(
          children: <Widget>[
            for (final (String, String, String, String, String) r
                in const <(String, String, String, String, String)>[
                  (
                    'phone',
                    'receipt',
                    'Call support',
                    '[YOUR SUPPORT NUMBER]',
                    'Calling support…',
                  ),
                  (
                    'chat',
                    'sales',
                    'WhatsApp chat',
                    '[YOUR WHATSAPP NUMBER]',
                    'Opening WhatsApp…',
                  ),
                  (
                    'mail',
                    'party',
                    'Email support',
                    '[YOUR SUPPORT EMAIL]',
                    'Opening email…',
                  ),
                ])
              RowX(
                onTap: () => c.say(r.$5),
                children: <Widget>[
                  Ico(
                    r.$1,
                    size: IcoSize.xs,
                    color: p.cat(r.$2),
                    icon: IcSize.s,
                  ),
                  Expanded(child: RTx(r.$3, r.$4)),
                  chevR(),
                ],
              ),
          ],
        ),
        const FNote('Version 19.6.2'),
      ],
    );
  }
}
