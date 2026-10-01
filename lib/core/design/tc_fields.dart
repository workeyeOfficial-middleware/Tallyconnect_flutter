// Form controls: `.fld` / `.lab` / `.inp` / `.iw` / `.selbtn` and the date
// input (lines 102–112).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tc_icons.dart';
import 'tc_kit.dart';
import 'tc_palette.dart';

/// `.fld`: label + control, gap 7, margin-bottom 16.
class Fld extends StatelessWidget {
  const Fld({
    super.key,
    this.label,
    this.icon,
    this.req = false,
    required this.child,
    this.margin = const EdgeInsets.only(bottom: 16),
  });
  final String? label;
  final String? icon;
  final bool req;
  final Widget child;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Lab(label!, icon: icon, req: req),
          const SizedBox(height: 7),
        ],
        child,
      ],
    ),
  );
}

/// `.lab` 14.5/700 ink2 with optional `.i.xs` and required `*`.
class Lab extends StatelessWidget {
  const Lab(this.text, {super.key, this.icon, this.req = false});
  final String text;
  final String? icon;
  final bool req;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Row(
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Ic(icon!, size: IcSize.xs, color: p.ink2),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text.rich(
            TextSpan(
              text: text,
              children: <InlineSpan>[
                if (req)
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: p.neg),
                  ),
              ],
            ),
            style: ts(14.5, w: w700, c: p.ink2),
          ),
        ),
      ],
    );
  }
}

/// `.inp` text input (56 high, radius 16) with optional `.iw` leading icon.
class Inp extends StatefulWidget {
  const Inp({
    super.key,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.icon,
    this.obscure = false,
    this.keyboard,
    this.maxLength,
    this.textarea = false,
    this.trailing,
    this.prefix,
    this.fontSize = 17,
    this.fontWeight = w400,
    this.letterSpacing = 0,
    this.formatters,
    this.height,
    this.textAlign = TextAlign.start,
    this.leftPad,
    this.capitalization = TextCapitalization.none,
    this.textColor,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? placeholder;
  final String? icon;
  final bool obscure;
  final TextInputType? keyboard;
  final int? maxLength;
  final bool textarea;
  final Widget? trailing;

  /// Absolute-positioned prefix such as `₹` or `#`.
  final Widget? prefix;
  final double fontSize;
  final FontWeight fontWeight;
  final double letterSpacing;
  final List<TextInputFormatter>? formatters;
  final double? height;
  final TextAlign textAlign;
  final double? leftPad;
  final TextCapitalization capitalization;
  final Color? textColor;

  @override
  State<Inp> createState() => _InpState();
}

class _InpState extends State<Inp> {
  late final TextEditingController _c = TextEditingController(
    text: widget.value,
  );
  final FocusNode _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(Inp old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text) {
      _c.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final bool focus = _f.hasFocus;
    final double h = widget.height ?? (widget.textarea ? 84 : 56);
    final double left =
        widget.leftPad ??
        (widget.icon != null || widget.prefix != null ? 48 : 16);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: h,
      decoration: BoxDecoration(
        color: whiteA(.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: focus ? p.navy2 : navyA(.13)),
        boxShadow: focus
            ? <BoxShadow>[BoxShadow(color: mix(p.navy2, .15), spreadRadius: 4)]
            : const <BoxShadow>[],
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                left: left,
                right: widget.trailing != null ? 52 : 16,
                top: widget.textarea ? 13 : 0,
              ),
              child: Align(
                alignment: widget.textarea
                    ? Alignment.topLeft
                    : Alignment.centerLeft,
                child: TextField(
                  controller: _c,
                  focusNode: _f,
                  obscureText: widget.obscure,
                  keyboardType:
                      widget.keyboard ??
                      (widget.textarea
                          ? TextInputType.multiline
                          : TextInputType.text),
                  maxLines: widget.textarea ? 3 : 1,
                  minLines: 1,
                  textAlign: widget.textAlign,
                  textCapitalization: widget.capitalization,
                  inputFormatters: <TextInputFormatter>[
                    if (widget.maxLength != null)
                      LengthLimitingTextInputFormatter(widget.maxLength),
                    ...?widget.formatters,
                  ],
                  onChanged: widget.onChanged,
                  cursorColor: p.navy2,
                  style: ts(
                    widget.fontSize,
                    w: widget.fontWeight,
                    c: widget.textColor ?? p.ink,
                    ls: widget.letterSpacing,
                    h: widget.textarea ? 1.35 : null,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: widget.placeholder,
                    hintStyle: ts(
                      widget.fontSize,
                      w: w400,
                      c: p.ink3.withValues(alpha: .75),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.icon != null)
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(child: Ic(widget.icon!, color: p.ink3)),
            ),
          if (widget.prefix != null)
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(child: widget.prefix),
            ),
          if (widget.trailing != null)
            Positioned(right: 6, top: 6, child: widget.trailing!),
        ],
      ),
    );
  }
}

/// `.selbtn`: select-style button (avatar/icon + value + chevron).
class SelBtn extends StatelessWidget {
  const SelBtn({
    super.key,
    required this.leading,
    required this.text,
    this.onTap,
  });
  final Widget leading;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Tap(
      onTap: onTap,
      radius: 16,
      child: Container(
        height: 56,
        padding: const EdgeInsets.only(left: 8, right: 12),
        decoration: BoxDecoration(
          color: whiteA(.88),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: navyA(.13)),
        ),
        child: Row(
          children: <Widget>[
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts(17, w: w700, c: p.ink),
              ),
            ),
            const SizedBox(width: 10),
            const Ic('chevD', size: IcSize.s, color: Color(0xFF8A94AC)),
          ],
        ),
      ),
    );
  }
}

/// `<input type=date>` — shows dd/mm/yyyy, opens the platform date picker.
class DateInp extends StatelessWidget {
  const DateInp({
    super.key,
    required this.value,
    required this.onChanged,
    this.fontSize = 17,
    this.hPad = 16,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final double fontSize;
  final double hPad;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final List<String> parts = value.split('-');
    final String shown = parts.length == 3
        ? '${parts[2]}/${parts[1]}/${parts[0]}'
        : 'dd/mm/yyyy';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final DateTime init = DateTime.tryParse(value) ?? DateTime(2026, 9, 26);
        final DateTime? d = await showDatePicker(
          context: context,
          initialDate: init,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          builder: (BuildContext c, Widget? child) => Theme(
            data: Theme.of(c).copyWith(
              colorScheme: ColorScheme.light(
                primary: p.navy,
                onPrimary: Colors.white,
                onSurface: p.ink,
              ),
            ),
            child: child!,
          ),
        );
        if (d != null) {
          onChanged(
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
          );
        }
      },
      child: Container(
        height: 56,
        padding: EdgeInsets.symmetric(horizontal: hPad),
        decoration: BoxDecoration(
          color: whiteA(.88),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: navyA(.13)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                shown,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: ts(fontSize, c: p.ink),
              ),
            ),
            Ic('calendar', size: IcSize.s, color: p.ink),
          ],
        ),
      ),
    );
  }
}

/// Digits-only formatter (`inputmode="numeric"`).
final List<TextInputFormatter> kDigits = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
];

/// Decimal formatter (`inputmode="decimal"`).
final List<TextInputFormatter> kDecimal = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
];
