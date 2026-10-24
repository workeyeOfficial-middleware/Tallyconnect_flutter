// Bill PDF layout (NEW feature): company logo, the fields a bill shows,
// address / terms text, a preview, and Save as this user's default for the
// active company — or, before a share, changes used for that share only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_fields.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/share/bill_layout.dart';
import '../widgets/common.dart';

class BillLayoutSheet extends ConsumerWidget {
  const BillLayoutSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final BillLayout l = c.billDraft;
    final bool temp = c.billTemp;
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHead(
            temp ? 'Bill layout for this share' : 'Bill PDF layout',
            sub: temp
                ? 'Changes here are used for this share only'
                : 'Saved for you and this company on this phone',
          ),
          // ---- logo
          Fld(
            label: 'Company logo',
            child: Row(
              children: <Widget>[
                Container(
                  key: const ValueKey<String>('billLogoBox'),
                  width: 72,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: whiteA(.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.ink3.withValues(alpha: .25)),
                  ),
                  child: c.billDraftLogo == null
                      ? Text('No logo', style: ts(12, c: p.ink3))
                      : Padding(
                          padding: const EdgeInsets.all(4),
                          child: Image.memory(
                            c.billDraftLogo!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Btn(
                    key: const ValueKey<String>('billLogoPick'),
                    label: c.billLogoBusy
                        ? 'Loading…'
                        : (c.billDraftLogo == null ? 'Upload' : 'Change'),
                    icon: 'upload',
                    kind: BtnKind.g,
                    height: 46,
                    enabled: !c.billLogoBusy,
                    onTap: c.pickBillLogo,
                  ),
                ),
                if (c.billDraftLogo != null) ...<Widget>[
                  const SizedBox(width: 8),
                  CBtn(
                    'trash',
                    key: const ValueKey<String>('billLogoRemove'),
                    onTap: c.removeBillLogo,
                  ),
                ],
              ],
            ),
          ),
          // ---- fields
          const Sec(
            'Show on the bill',
            margin: EdgeInsets.fromLTRB(4, 4, 4, 8),
          ),
          GlassList(
            key: const ValueKey<String>('billFields'),
            children: <Widget>[
              for (final (String, String) f in BillLayout.kFields)
                RowX(
                  key: ValueKey<String>('billField-${f.$1}'),
                  minHeight: 52,
                  onTap: () => c.toggleBillField(f.$1),
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        f.$2,
                        style: ts(15, w: w600, c: p.ink),
                      ),
                    ),
                    Sw(l.on(f.$1)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Fld(
            label: 'Address / GSTIN lines',
            child: Inp(
              key: const ValueKey<String>('billSeller'),
              value: l.seller,
              textarea: true,
              maxLength: BillLayout.kMaxText,
              onChanged: (String v) => c.setBillText(seller: v),
              placeholder: 'Shop address\nGSTIN: …\nPhone: …',
            ),
          ),
          Fld(
            label: 'Terms / bank details',
            child: Inp(
              key: const ValueKey<String>('billTerms'),
              value: l.terms,
              textarea: true,
              maxLength: BillLayout.kMaxText,
              onChanged: (String v) => c.setBillText(terms: v),
              placeholder: 'e.g. Bank: … · IFSC: … · Thank you!',
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: Btn(
                  key: const ValueKey<String>('billPreview'),
                  label: 'Preview',
                  icon: 'file',
                  kind: BtnKind.g,
                  onTap: c.previewBillLayout,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: temp
                    ? Btn(
                        key: const ValueKey<String>('billShareNow'),
                        label: 'Share',
                        icon: 'share',
                        onTap: c.shareWithBillDraft,
                      )
                    : Btn(
                        key: const ValueKey<String>('billSave'),
                        label: 'Save',
                        icon: 'check',
                        onTap: c.saveBillLayout,
                      ),
              ),
            ],
          ),
          if (!temp && l != BillLayout.standard)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(
                child: TextButton(
                  key: const ValueKey<String>('billReset'),
                  onPressed: c.resetBillDraft,
                  child: Text(
                    'Back to the standard layout',
                    style: ts(14, w: w600, c: p.acc2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
