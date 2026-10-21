// Selecting several rows of a list (vouchers, parties): the row checkbox
// and the floating action bar with Select all / Clear and the shares.
library;

import 'package:flutter/material.dart';

import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';

/// WhatsApp's own green (the Share via WhatsApp button).
const Color kWhatsAppGreen = Color(0xFF1FAF55);

/// A rounded checkbox for a list row (ticked: accent fill + white tick).
class SelectBox extends StatelessWidget {
  const SelectBox({super.key, required this.checked, this.size = 24});
  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Semantics(
      checked: checked,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: checked ? p.acc : whiteA(.55),
          borderRadius: BorderRadius.circular(size * .3),
          border: Border.all(color: checked ? p.acc : p.ink3, width: 1.8),
          boxShadow: checked
              ? <BoxShadow>[css(0, 4, 10, -4, mix(p.acc, .7))]
              : const <BoxShadow>[],
        ),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 160),
          scale: checked ? 1 : 0,
          child: Ic('check', px: size * .66, stroke: 2.6, color: Colors.white),
        ),
      ),
    );
  }
}

/// One extra action of [BulkBar] (an icon button with a short label).
class BulkAction {
  const BulkAction(this.label, this.icon, this.onTap, {this.key});
  final String label, icon;
  final VoidCallback onTap;
  final Key? key;
}

/// The floating bar while selecting: "n selected · detail", Select all /
/// Clear, Share via WhatsApp and [actions]. Slides in from the bottom.
class BulkBar extends StatelessWidget {
  const BulkBar({
    super.key,
    required this.count,
    required this.detail,
    required this.allSelected,
    required this.onSelectAll,
    required this.onClear,
    required this.onWhatsApp,
    this.actions = const <BulkAction>[],
    this.selectAllLabel = 'Select all',
    this.emptyText = 'Tap rows to select them',
    this.keyPrefix = 'bulk',
  });

  final int count;

  /// Shown under the count (total, balances…).
  final String detail;
  final bool allSelected;
  final VoidCallback onSelectAll, onClear, onWhatsApp;
  final List<BulkAction> actions;
  final String selectAllLabel, emptyText;

  /// Keys of the parts: `<prefix>Bar`, `<prefix>Count`, `<prefix>All`,
  /// `<prefix>Clear`, `<prefix>Wa`.
  final String keyPrefix;

  ValueKey<String> _k(String s) => ValueKey<String>('$keyPrefix$s');

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final bool any = count > 0;
    Widget textBtn(String label, VoidCallback onTap, Key key) => Tap(
      key: key,
      onTap: onTap,
      radius: 12,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Text(label, style: ts(13.5, w: w700, c: p.acc)),
      ),
    );
    return Glass(
      key: _k('Bar'),
      blur: true,
      radius: 24,
      // Denser than cards: the rows scrolling behind stay out of the way.
      fill: p.sheetFill,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      shadows: <BoxShadow>[
        css(0, 14, 30, -14, navyA(.32)),
        css(0, 2, 8, -2, navyA(.1)),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      any ? '$count selected' : emptyText,
                      key: _k('Count'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(15, w: w800, c: p.ink),
                    ),
                    if (any && detail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(12.5, w: w600, c: p.ink3, tab: true),
                        ),
                      ),
                  ],
                ),
              ),
              if (!allSelected) textBtn(selectAllLabel, onSelectAll, _k('All')),
              if (any) textBtn('Clear', onClear, _k('Clear')),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !any
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: _WhatsAppButton(
                            key: _k('Wa'),
                            onTap: onWhatsApp,
                          ),
                        ),
                        for (final BulkAction a in actions) ...<Widget>[
                          const SizedBox(width: 8),
                          _ActionBtn(a),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _WhatsAppButton extends StatelessWidget {
  const _WhatsAppButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tap(
    onTap: onTap,
    radius: 16,
    child: Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF2BD46A), kWhatsAppGreen],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          css(0, 8, 16, -8, kWhatsAppGreen.withValues(alpha: .8)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Ic('whatsapp', size: IcSize.s, color: Colors.white),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Share via WhatsApp',
                maxLines: 1,
                style: ts(14.5, w: w800, c: Colors.white),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn(this.a);
  final BulkAction a;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Semantics(
      button: true,
      label: a.label,
      child: Tap(
        key: a.key,
        onTap: a.onTap,
        radius: 16,
        child: Container(
          width: 54,
          height: 46,
          decoration: BoxDecoration(
            color: p.fieldFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: navyA(.1)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Ic(a.icon, size: IcSize.s, color: p.ink),
              const SizedBox(height: 2),
              Text(
                a.label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: ts(10.5, w: w700, c: p.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
