// LOGIN (Main.dc.html 495–516) and FORGOT PASSWORD (518–543).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_fields.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../widgets/common.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    // The keyboard takes the bottom of the screen: the form gets only what
    // is left (there is no Scaffold to shrink it), so the field being typed
    // in and Log In scroll into view instead of hiding behind the keyboard.
    final double kb = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          // Small phones (short screen, or the keyboard open): a tighter
          // header, fields and gaps so the whole form fits without being cut.
          final bool compact = box.maxHeight < 720 || box.maxWidth < 360;
          final double bottom =
              (compact ? 12 : 20) +
              (kb > 0 ? 0 : MediaQuery.paddingOf(context).bottom);
          final double fieldH = compact ? 48 : 52;
          final EdgeInsets gap = EdgeInsets.only(bottom: compact ? 10 : 14);
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(16, topIn(context), 16, bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(0, box.maxHeight - topIn(context) - bottom),
              ),
              child: Padding(
                padding: EdgeInsets.only(top: compact ? 4 : 12, bottom: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Small phones: the TC icon beside the name (one row).
                    if (compact)
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          LMark(
                            key: ValueKey<String>('loginMark'),
                            size: 46,
                            radius: 15,
                          ),
                          SizedBox(width: 10),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Brand(size: 28),
                            ),
                          ),
                        ],
                      )
                    else ...<Widget>[
                      const Center(
                        child: LMark(key: ValueKey<String>('loginMark')),
                      ),
                      const SizedBox(height: 10),
                      const Brand(size: 34),
                    ],
                    H1(
                      'Welcome back',
                      center: true,
                      size: compact ? 26 : 34,
                      margin: compact
                          ? const EdgeInsets.fromLTRB(4, 4, 4, 2)
                          : const EdgeInsets.fromLTRB(4, 10, 4, 4),
                    ),
                    Sub(
                      'Log in to see your business',
                      center: true,
                      margin: compact
                          ? const EdgeInsets.fromLTRB(4, 0, 4, 10)
                          : const EdgeInsets.fromLTRB(4, 0, 4, 16),
                    ),
                    Glass(
                      padding: EdgeInsets.all(compact ? 14 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          // Required by the server (`loginType`): owner
                          // accounts log in as Admin, team members as User.
                          Fld(
                            label: 'Log in as',
                            margin: gap,
                            child: Seg(
                              items: const <String>['Admin', 'User'],
                              selected: c.loginType == 'USER' ? 1 : 0,
                              onPick: (int i) => c.update(
                                () => c.loginType = i == 0 ? 'ADMIN' : 'USER',
                              ),
                              margin: EdgeInsets.zero,
                            ),
                          ),
                          Fld(
                            label: c.repo.isRemote
                                ? 'Email'
                                : 'Username or email',
                            margin: gap,
                            child: Inp(
                              height: fieldH,
                              value: c.f('user'),
                              onChanged: (String v) => c.setF('user', v),
                              placeholder: c.repo.isRemote
                                  ? 'name@example.com'
                                  : 'e.g. workk72002',
                              icon: 'person',
                              keyboard: TextInputType.emailAddress,
                            ),
                          ),
                          Fld(
                            label: 'Password',
                            margin: gap,
                            child: Inp(
                              height: fieldH,
                              value: c.f('pass'),
                              onChanged: (String v) => c.setF('pass', v),
                              placeholder: 'Enter your password',
                              icon: 'lock',
                              obscure: !c.showPass,
                              trailing: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () =>
                                    c.update(() => c.showPass = !c.showPass),
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Center(
                                    child: Ic(
                                      c.showPass ? 'eyeOff' : 'eye',
                                      color: p.ink3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Transform.translate(
                            offset: const Offset(0, -8),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: LinkBtn(
                                'Forgot password?',
                                onTap: c.goForgot,
                              ),
                            ),
                          ),
                          Btn(
                            height: compact ? 50 : 54,
                            label: c.busy ? 'Logging in…' : 'Log In',
                            icon: 'arrow',
                            iconAfter: true,
                            enabled: !c.busy,
                            onTap: c.doLogin,
                          ),
                          OrDivider(compact: compact),
                          GlassRow(
                            onTap: () => c.go('help'),
                            children: <Widget>[
                              Ico(
                                'help',
                                size: IcoSize.xs,
                                color: p.navy,
                                icon: IcSize.s,
                              ),
                              const Expanded(
                                child: RTx(
                                  'Need help logging in?',
                                  'Questions, call or email us',
                                ),
                              ),
                              chevR(),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const FNote('Version 19.6.2'),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// `.link` text button (accent, 15/700, padding 8 2).
class LinkBtn extends StatelessWidget {
  const LinkBtn(
    this.text, {
    super.key,
    this.onTap,
    this.fontSize = 15,
    this.padding = const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
  });
  final String text;
  final VoidCallback? onTap;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: padding,
      child: Text(
        text,
        style: ts(fontSize, w: w700, c: Tc.of(context).acc),
      ),
    ),
  );
}

/// `.or` divider.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key, this.compact = false});

  /// Less space above and below (small phones).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 16),
      child: Row(
        children: <Widget>[
          Expanded(child: Container(height: 1, color: navyA(.12))),
          const SizedBox(width: 10),
          Text(
            'OR',
            style: ts(13, w: w700, c: p.ink3, ls: 1.04),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: navyA(.12))),
        ],
      ),
    );
  }
}

/// `.fnote`.
class FNote extends StatelessWidget {
  const FNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: ts(13, c: Tc.of(context).ink3),
    ),
  );
}

class ForgotScreen extends ConsumerWidget {
  const ForgotScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    return Scr(
      children: <Widget>[
        NavRow(children: <Widget>[PBtn('Log in', onTap: c.back)]),
        const SizedBox(height: 16),
        Center(
          child: Ico('key', color: p.acc, box: 72, radius: 24, icon: IcSize.l),
        ),
        const H1('Forgot password?', center: true),
        Sub(
          c.forgotDone
              ? 'Your password has been changed.'
              : (c.forgotSent
                    ? 'Enter the 6-digit code we emailed to ${c.f('fEmail').trim()} and choose a new password.'
                    : 'Type the email you use for TallyConnect. We will email you a code to make a new password.'),
          center: true,
        ),
        if (!c.forgotSent)
          Glass(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Fld(
                  label: 'Email address',
                  child: Inp(
                    value: c.f('fEmail'),
                    onChanged: (String v) => c.setF('fEmail', v),
                    placeholder: 'name@example.com',
                    icon: 'mail',
                    keyboard: TextInputType.emailAddress,
                  ),
                ),
                Btn(
                  label: c.busy ? 'Sending…' : 'Send code',
                  icon: 'send',
                  enabled: !c.busy,
                  onTap: c.sendReset,
                ),
              ],
            ),
          ),
        // Step 2: code + new password.
        if (c.forgotSent && !c.forgotDone)
          Rise(
            ms: 400,
            child: Glass(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Fld(
                    label: '6-digit code',
                    req: true,
                    child: Inp(
                      value: c.f('fCode'),
                      onChanged: (String v) => c.setF('fCode', v),
                      placeholder: '••••••',
                      icon: 'key',
                      keyboard: TextInputType.number,
                      maxLength: 6,
                      formatters: kDigits,
                      letterSpacing: 4,
                    ),
                  ),
                  Fld(
                    label: 'New password',
                    req: true,
                    child: Inp(
                      value: c.f('fPass'),
                      onChanged: (String v) => c.setF('fPass', v),
                      placeholder: 'At least 8 characters',
                      icon: 'lock',
                      obscure: !c.showPass,
                      trailing: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => c.update(() => c.showPass = !c.showPass),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: Ic(
                              c.showPass ? 'eyeOff' : 'eye',
                              color: p.ink3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Fld(
                    label: 'Confirm new password',
                    req: true,
                    child: Inp(
                      value: c.f('fPass2'),
                      onChanged: (String v) => c.setF('fPass2', v),
                      placeholder: 'Type it again',
                      icon: 'lock',
                      obscure: !c.showPass,
                    ),
                  ),
                  if (c.f('fCode').isNotEmpty && c.resetError != null)
                    InfoBox(
                      c.resetError!,
                      icon: 'info',
                      margin: const EdgeInsets.only(bottom: 12),
                    ),
                  Btn(
                    label: c.busy ? 'Saving…' : 'Set new password',
                    icon: 'check',
                    enabled: !c.busy && c.resetError == null,
                    onTap: c.confirmReset,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Btn(
                          label: 'Change email',
                          kind: BtnKind.g,
                          enabled: !c.busy,
                          onTap: () => c.update(() => c.forgotSent = false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Btn(
                          label: 'Resend code',
                          kind: BtnKind.g,
                          enabled: !c.busy,
                          onTap: c.sendReset,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'The code works for 10 minutes. Check spam if it does not arrive.',
                      textAlign: TextAlign.center,
                      style: rsStyle(context, 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Done.
        if (c.forgotDone)
          Rise(
            ms: 400,
            child: Glass(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: <Widget>[
                  const Tk(true, size: 56, iconSize: IcSize.l),
                  const SizedBox(height: 10),
                  Text(
                    'Password changed',
                    textAlign: TextAlign.center,
                    style: rtStyle(context, 19),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 6, 0, 16),
                    child: Text(
                      'Log in with your email and the new password.',
                      textAlign: TextAlign.center,
                      style: ts(15, h: 1.3, c: p.ink3),
                    ),
                  ),
                  Btn(label: 'Back to Log in', onTap: c.back),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
