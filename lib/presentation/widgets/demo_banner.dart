// Demo data banner (always on screen while demo data is shown), the inset
// that keeps every screen below it, and the "Connect Tally" sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/share/links.dart' show TcSite;
import 'common.dart';

/// Height the banner takes below the status bar.
const double kDemoBannerH = 46;

/// Adds the banner's height to the top safe area, so every screen (which
/// already keeps below the safe area) moves down under the banner.
class DemoInset extends StatelessWidget {
  const DemoInset({super.key, required this.on, required this.child});
  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!on) return child;
    final MediaQueryData mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        padding: mq.padding.copyWith(top: mq.padding.top + kDemoBannerH),
        viewPadding: mq.viewPadding.copyWith(
          top: mq.viewPadding.top + kDemoBannerH,
        ),
      ),
      child: child,
    );
  }
}

/// "Demo data" strip under the status bar with Connect Tally / Use my data.
class DemoBanner extends ConsumerWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final double top = MediaQuery.paddingOf(context).top + 4;
    return Positioned(
      key: const ValueKey<String>('demoBanner'),
      top: top,
      left: 12,
      right: 12,
      height: kDemoBannerH - 6,
      child: Glass(
        radius: 14,
        blur: true,
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: p.warn, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: 'Demo data',
                        style: ts(13.5, w: w800, c: p.ink),
                      ),
                      TextSpan(
                        text: ' · sample, not your Tally',
                        style: ts(12.5, w: w600, c: p.ink2),
                      ),
                    ],
                  ),
                  maxLines: 1,
                ),
              ),
            ),
            Tap(
              key: const ValueKey<String>('demoConnect'),
              onTap: () => c.openOverlay('connectTally'),
              radius: 10,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: Text(
                  'Connect Tally',
                  style: ts(13, w: w800, c: p.acc),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How to get the account's own Tally data in, and a way to leave demo
/// data now.
class ConnectTallySheet extends ConsumerWidget {
  const ConnectTallySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    const List<(String, String)> steps = <(String, String)>[
      (
        'Install the Tally Connector agent',
        'On the computer that runs TallyPrime.',
      ),
      (
        'Sign in with this account',
        'Use the same email and password as this app.',
      ),
      (
        'Pick your company',
        'Menu → Companies, then choose your Tally company.',
      ),
      (
        'Run the first sync',
        'Your data replaces the demo data here by itself.',
      ),
    ];
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetHead(
            'Connect Tally',
            sub: 'You are looking at demo data from a sample company.',
          ),
          for (int i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: mix(p.acc, .12),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: ts(13, w: w800, c: p.acc),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: RTx(steps[i].$1, steps[i].$2)),
                ],
              ),
            ),
          const InfoBox(
            'Demo data stays on this phone. Nothing you do in demo mode is '
            'saved, sent to the server or to Tally.',
            icon: 'info',
            margin: EdgeInsets.only(bottom: 14),
          ),
          Btn(
            label: 'Get the agent · tally-connect.com',
            icon: 'globe',
            kind: BtnKind.g,
            onTap: () => c.openExternal(
              Uri.parse(TcSite.website),
              'Could not open ${TcSite.website}',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                flex: 10,
                child: Btn(label: 'Close', kind: BtnKind.g, onTap: c.closeOv),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 17,
                child: Btn(
                  key: const ValueKey<String>('useMyData'),
                  label: 'Use my data',
                  icon: 'check',
                  onTap: () {
                    c.closeOv();
                    c.useMyData();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
