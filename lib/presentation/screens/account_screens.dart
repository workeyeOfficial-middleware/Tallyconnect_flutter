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
import '../../core/share/links.dart';
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
        Expanded(
          child: RTx(
            co.name,
            c.repo.isRemote ? c.syncText(co.id) : (sub ?? co.sub),
          ),
        ),
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
              onTap: c.repo.isRemote
                  ? c.refreshNow
                  : () => c.say('Company list refreshed from Tally'),
            ),
          ],
        ),
        const H1('Companies', afterNav: true),
        const Sub('Your companies in Tally'),
        const InfoBox(
          'Pick a company. Reports, bills and stock will show for that company.',
          icon: 'info',
        ),
        if (c.repo.isRemote && !c.isAdmin)
          const InfoBox(
            'Only your admin can switch the company for the team.',
            icon: 'lock',
          ),
        for (final Company co in c.repo.companies()) CompanyRow(co),
        if (c.repo.companies().isEmpty)
          EmptyBox(c.emptyText('companies', 'No company selected yet.')),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
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
        if (c.repo.plans().isEmpty)
          EmptyBox(
            'Your plan: ${c.repo.user?.plan ?? '—'}. Plan prices and switching are not available from the server yet.',
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
        const H1('Refer a friend', afterNav: true),
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
                'Share TallyConnect',
                textAlign: TextAlign.center,
                style: rtStyle(context, 19),
              ),
              const SizedBox(height: 2),
              Text(
                'Know a business that runs on Tally? Send them TallyConnect on '
                'WhatsApp in one tap.',
                textAlign: TextAlign.center,
                style: ts(15, h: 1.3, c: p.ink3),
              ),
              // The message they will receive.
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
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'THEY WILL GET',
                          style: ts(11, w: w800, ls: .88, c: p.ink3),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          AppController.kReferMessage,
                          style: ts(14, h: 1.45, c: p.ink2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Btn(
                label: 'Share on WhatsApp',
                icon: 'chat',
                kind: BtnKind.a,
                onTap: c.referOnWhatsApp,
              ),
              const SizedBox(height: 10),
              Btn(
                label: 'Share another way',
                icon: 'share',
                kind: BtnKind.g,
                onTap: c.referOtherApps,
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
                    '1. Send the message',
                    'WhatsApp opens with it ready — pick a contact',
                  ),
                  (
                    'globe',
                    'party',
                    '2. They visit tally-connect.com',
                    'And see how TallyConnect works with Tally',
                  ),
                  (
                    'check',
                    'receipt',
                    '3. They get started',
                    'Sign up, pick a plan and connect their Tally',
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
      ],
    );
  }
}

/// Help: product explanation and FAQs from https://tally-connect.com/, and
/// the support contacts published there (each opens its app).
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final List<Faq> faqs = c.repo.faqs();
    Widget link(
      String ic,
      String cc,
      String t,
      String s,
      Uri uri,
      String fail,
    ) => RowX(
      onTap: () => c.openExternal(uri, fail),
      children: <Widget>[
        Ico(ic, size: IcoSize.xs, color: p.cat(cc), icon: IcSize.s),
        Expanded(child: RTx(t, s)),
        chevR(),
      ],
    );
    return Scr(
      children: <Widget>[
        const BackNav(),
        const H1('Help', afterNav: true),
        const Sub('Answers and support'),
        // What it is and how it works (from the website).
        Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Ico('laptop', size: IcoSize.xs, color: p.acc, icon: IcSize.s),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'How TallyConnect works',
                      style: rtStyle(context, 17),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final (String, String) st in const <(String, String)>[
                (
                  'Sync app on your Tally computer',
                  'A small app on the Windows computer running Tally Prime '
                      'sends new entries and changes every 5 minutes.',
                ),
                (
                  'Your data, on every device',
                  'Dashboards and reports from your Tally data — no need to '
                      'open Tally for a number.',
                ),
                (
                  'Entries go back to Tally',
                  'Vouchers and bills made here are pushed into Tally Prime '
                      'automatically.',
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Ic('check', size: IcSize.s, color: p.pos),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: RTx(st.$1, st.$2, titleSize: 15)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const Sec('Common questions'),
        Glass(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
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
            link(
              'mail',
              'party',
              'Email support',
              '${TcSite.supportEmail} · ${TcSite.supportHours}',
              Uri(
                scheme: 'mailto',
                path: TcSite.supportEmail,
                query: 'subject=${Uri.encodeComponent('TallyConnect app support')}',
              ),
              'No email app found. Write to ${TcSite.supportEmail}',
            ),
            link(
              'phone',
              'receipt',
              'Call support',
              TcSite.supportPhone,
              Uri(scheme: 'tel', path: TcSite.supportPhone.replaceAll(' ', '')),
              'Could not open the dialer. Call ${TcSite.supportPhone}',
            ),
            link(
              'globe',
              'sales',
              'Website',
              'tally-connect.com',
              Uri.parse(TcSite.website),
              'Could not open the browser',
            ),
            link(
              'laptop',
              'vouchers',
              'Web dashboard',
              'dashboard.tally-connect.com',
              Uri.parse(TcSite.dashboard),
              'Could not open the browser',
            ),
          ],
        ),
        const Sec('Company'),
        Glass(
          padding: const EdgeInsets.all(16),
          child: RTx(TcSite.company, TcSite.address, titleSize: 15),
        ),
        const FNote('Version 19.6.2'),
      ],
    );
  }
}
