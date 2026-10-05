// The root frame (`.root`, Main.dc.html 488–1609): wallpaper, the active
// screen with its inF/inB entry, tab bar, overlays, floating layers, toast.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_state.dart';
import '../app/providers.dart';
import '../core/design/tc_kit.dart';
import '../core/design/tc_palette.dart';
import '../core/design/tc_wallpaper.dart';
import 'overlays/overlays.dart';
import 'screens/account_screens.dart';
import 'screens/auth_screens.dart';
import 'screens/dues_screens.dart';
import 'screens/flow_screen.dart';
import 'screens/home_screen.dart';
import 'screens/hub_screens.dart';
import 'screens/insight_screens.dart';
import 'screens/settings_screen.dart';
import 'screens/stock_party_screens.dart';
import 'screens/voucher_screens.dart';
import 'widgets/common.dart' show EnterAnim;
import 'widgets/tab_bar.dart';

/// Screen key → widget (the prototype's 27 `is.*` screens).
Widget screenFor(String s) => switch (s) {
  'login' => const LoginScreen(),
  'forgot' => const ForgotScreen(),
  'home' => const HomeScreen(),
  'notifs' => const NotifsScreen(),
  'createWs' => const CreateWsScreen(),
  'manageWs' => const ManageWsScreen(),
  'newEntry' => const NewEntryScreen(),
  'flow' => const FlowScreen(),
  'vHub' => const VHubScreen(),
  'vList' => const VListScreen(),
  'entryDetail' => const EntryDetailScreen(),
  'outHub' => const OutHubScreen(),
  'outList' => const OutListScreen(),
  'billDetail' => const BillDetailScreen(),
  'items' => const ItemsScreen(),
  'itemDetail' => const ItemDetailScreen(),
  'party' => const PartyScreen(),
  'partyDetail' => const PartyDetailScreen(),
  'reports' => const ReportsScreen(),
  'report' => const ReportScreen(),
  'activity' => const ActivityScreen(),
  'actDetail' => const ActDetailScreen(),
  'team' => const TeamScreen(),
  'settings' => const SettingsScreen(),
  'companies' => const CompaniesScreen(),
  'billing' => const BillingScreen(),
  'refer' => const ReferScreen(),
  'help' => const HelpScreen(),
  _ => const HomeScreen(),
};

/// Every screen key, in prototype order.
const List<String> kScreens = <String>[
  'login',
  'forgot',
  'home',
  'notifs',
  'createWs',
  'manageWs',
  'newEntry',
  'flow',
  'vHub',
  'vList',
  'entryDetail',
  'outHub',
  'outList',
  'billDetail',
  'items',
  'itemDetail',
  'party',
  'partyDetail',
  'reports',
  'report',
  'activity',
  'actDetail',
  'team',
  'settings',
  'companies',
  'billing',
  'refer',
  'help',
];

class Shell extends ConsumerWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = c.palette;
    c.setScreenSize(MediaQuery.sizeOf(context));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        if (!c.handleSystemBack()) SystemNavigator.pop();
      },
      child: Tc(
        p: p,
        child: Material(
          type: MaterialType.transparency,
          child: DefaultTextStyle(
            style: ts(16, c: p.ink),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                TcWallpaper(opacity: c.bgOpacity / 100, shade: c.bgShade / 100),
                Positioned.fill(
                  child: KeyedSubtree(
                    key: ValueKey<String>(c.screen),
                    child: EnterAnim(
                      back: c.dir == 'bk',
                      child: screenFor(c.screen),
                    ),
                  ),
                ),
                if (c.showTabs) const TcTabBar(),
                const Positioned.fill(child: OverlayLayer()),
                if (c.overlay == 'hiddenPanel')
                  const Positioned.fill(child: HiddenPanel()),
                if (c.cmenu != null) const Positioned.fill(child: CardMenu()),
                const ListGhost(),
                const ToastView(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
