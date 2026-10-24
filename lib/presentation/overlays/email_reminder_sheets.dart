// Outstanding email reminders: the reminder sheet (customer → bills →
// preview → confirm → result), the party's reminder history, and the
// admin's email templates. The server reads the bills, amounts and email
// address itself; every result shown is what it reported ("Accepted" =
// Microsoft 365 accepted the email for delivery, not "delivered").
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_fields.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/utils/format.dart';
import '../../data/models/models.dart';
import '../widgets/common.dart';

/// Two buttons at the bottom of a sheet (secondary, primary).
Widget _foot(Widget left, Widget right) => Padding(
  padding: const EdgeInsets.only(top: 14),
  child: Row(
    children: <Widget>[
      Expanded(flex: 10, child: left),
      const SizedBox(width: 12),
      Expanded(flex: 17, child: right),
    ],
  ),
);

String _billsText(int n) => '$n ${n == 1 ? 'bill' : 'bills'}';

class EmailReminderSheet extends ConsumerWidget {
  const EmailReminderSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    return Sheet(
      child: KeyedSubtree(
        key: ValueKey<String>('emStep-${c.emStep}'),
        child: switch (c.emStep) {
          'bills' => _Bills(c: c),
          'preview' => _Preview(c: c),
          'confirm' => _Confirm(c: c),
          'result' => _Result(c: c),
          _ => _Parties(c: c),
        },
      ),
    );
  }
}

class _Parties extends StatelessWidget {
  const _Parties({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final List<({String party, int bills, num total})> ps = c.emParties;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SheetHead(
          'Email reminder',
          sub: 'Choose a customer with pending bills',
        ),
        _DueToday(c: c),
        if (ps.isEmpty)
          const EmptyBox('No pending receivable bills.')
        else
          GlassList(
            children: <Widget>[
              for (final ({String party, int bills, num total}) x in ps)
                RowX(
                  key: ValueKey<String>('emParty-${x.party}'),
                  onTap: () => c.pickEmailParty(x.party),
                  children: <Widget>[
                    Av(initials(x.party), size: Av.sm),
                    Expanded(
                      child: RTx(
                        x.party,
                        '${_billsText(x.bills)} · ${inr(x.total)}',
                        ell: true,
                      ),
                    ),
                    chevR(),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}

class _Bills extends StatelessWidget {
  const _Bills({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final bool all =
        c.emBills.isNotEmpty && c.emPicked.length == c.emBills.length;
    final List<ReminderTemplate> tpls =
        c.emTemplates?.templates ?? const <ReminderTemplate>[];
    final int n = c.emPicked.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SheetHead(c.emParty, sub: 'Choose the bills to remind about'),
        if (c.emError != null) InfoBox(c.emError!, icon: 'info'),
        if (c.emBills.isNotEmpty) ...<Widget>[
          GlassList(
            children: <Widget>[
              RowX(
                key: const ValueKey<String>('emAllBills'),
                minHeight: 52,
                onTap: () => c.emailAllBills(!all),
                children: <Widget>[
                  Tk(all),
                  Expanded(
                    child: Text(
                      'All pending bills',
                      style: rtStyle(context, 15.5),
                    ),
                  ),
                ],
              ),
              for (final Bill b in c.emBills)
                RowX(
                  key: ValueKey<String>('emBill-${b.no}'),
                  onTap: () => c.toggleEmailBill(b.no),
                  children: <Widget>[
                    Tk(c.emPicked.contains(b.no)),
                    Expanded(
                      child: RTx(b.no, 'Due ${b.due} · ${b.txt}', ell: true),
                    ),
                    Text(
                      inr(b.amt),
                      style: amtStyle(context, size: 15, cls: 'in'),
                    ),
                  ],
                ),
            ],
          ),
          if (tpls.length > 1) ...<Widget>[
            const Sec('Template', margin: EdgeInsets.fromLTRB(8, 16, 8, 8)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final ReminderTemplate t in tpls)
                  ChipBtn(
                    t.isDefault ? '${t.name} · default' : t.name,
                    height: 36,
                    fontSize: 13.5,
                    on:
                        c.emTemplateId == t.id ||
                        (c.emTemplateId == null && t.isDefault),
                    onTap: () => c.setEmailTemplate(t.id),
                  ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Amounts and the email address are checked again with your '
              'Tally data on the server before anything is sent.',
              style: ts(13, h: 1.4, c: p.ink3),
            ),
          ),
        ],
        _foot(
          Btn(label: 'Back', kind: BtnKind.g, onTap: c.emailBack),
          Btn(
            key: const ValueKey<String>('emPreviewBtn'),
            label: c.emBusy
                ? 'Checking…'
                : n == 0
                ? 'Preview'
                : 'Preview · ${inr(c.emPickedTotal)}',
            icon: 'eye',
            enabled: !c.emBusy && n > 0 && c.emLedger != null,
            onTap: c.previewEmailReminder,
          ),
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final ReminderPreview pv = c.emPreview!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SheetHead(
          'Check the email',
          sub: 'Nothing is sent until you confirm.',
        ),
        KvList(<(String, String, bool)>[
          (
            'To',
            pv.recipients.isEmpty
                ? 'No email address in Tally'
                : pv.recipients.join(', '),
            false,
          ),
          ('Party', pv.party, false),
          if (pv.company.isNotEmpty) ('From company', pv.company, false),
          ('Subject', pv.subject, false),
          if (pv.templateName.isNotEmpty) ('Template', pv.templateName, false),
        ], margin: const EdgeInsets.only(bottom: 12)),
        GlassList(
          children: <Widget>[
            for (final ReminderBill b in pv.bills)
              RowX(
                key: ValueKey<String>('emPvBill-${b.no}'),
                minHeight: 56,
                children: <Widget>[
                  Expanded(
                    child: RTx(
                      b.no,
                      'Due ${dmy(b.dueDate)}'
                      '${b.overdueDays > 0 ? ' · ${b.overdueDays} days overdue' : ''}',
                      ell: true,
                    ),
                  ),
                  Text(inr(b.amount), style: amtStyle(context, size: 15)),
                ],
              ),
          ],
        ),
        Tot(
          margin: const EdgeInsets.only(top: 10, bottom: 12),
          child: Row(
            children: <Widget>[
              Expanded(child: Text('Total · ${_billsText(pv.bills.length)}')),
              Text(
                inr(pv.total),
                key: const ValueKey<String>('emPvTotal'),
                style: amtStyle(context, size: 17),
              ),
            ],
          ),
        ),
        if (pv.missingBills.isNotEmpty)
          InfoBox(
            'Left out — no longer pending in Tally: '
            '${pv.missingBills.join(', ')}',
            icon: 'info',
          ),
        for (final String x in pv.problems) InfoBox(x, icon: 'alert'),
        const Sec('Message', margin: EdgeInsets.fromLTRB(8, 4, 8, 8)),
        Glass(
          padding: const EdgeInsets.all(14),
          child: Text(
            pv.text,
            key: const ValueKey<String>('emPvText'),
            style: ts(14, h: 1.45, c: p.ink2),
          ),
        ),
        _foot(
          Btn(label: 'Back', kind: BtnKind.g, onTap: c.emailBack),
          Btn(
            key: const ValueKey<String>('emSendBtn'),
            label: 'Send email',
            icon: 'send',
            enabled: pv.canSend,
            onTap: c.confirmEmailReminder,
          ),
        ),
      ],
    );
  }
}

class _Confirm extends StatelessWidget {
  const _Confirm({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final ReminderPreview pv = c.emPreview!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SheetHead('Send this reminder?'),
        Text(
          'Email ${pv.party} at ${pv.recipients.join(', ')} about '
          '${_billsText(pv.bills.length)} totalling ${inr(pv.total)}?',
          key: const ValueKey<String>('emConfirmText'),
          style: ts(16, h: 1.45, c: p.ink),
        ),
        const SizedBox(height: 14),
        const InfoBox(
          'Sent by TallyConnect with your email as the reply-to address. '
          'Nothing is changed in Tally.',
          icon: 'info',
        ),
        _foot(
          Btn(
            label: 'Cancel',
            kind: BtnKind.g,
            onTap: c.emBusy ? null : c.emailBack,
          ),
          Btn(
            key: const ValueKey<String>('emConfirmSend'),
            label: c.emBusy ? 'Sending…' : 'Yes, send',
            icon: 'send',
            enabled: !c.emBusy,
            onTap: c.sendEmailReminder,
          ),
        ),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final ReminderOutcome r = c.emResult!;
    final String title = r.ok
        ? 'Accepted for delivery'
        : r.unknown
        ? 'No answer from the server'
        : 'Not sent';
    // Worth trying again: no answer, a send failure, or data that changed.
    final bool again =
        !r.ok && (r.unknown || r.code == 'send_failed' || r.code == 'changed');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SheetHead(title),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Ico(
              r.ok ? 'check' : 'alert',
              size: IcoSize.sm,
              color: r.ok ? p.pos : (r.unknown ? p.warn : p.neg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                r.message,
                key: const ValueKey<String>('emResultText'),
                style: ts(15, h: 1.45, c: p.ink),
              ),
            ),
          ],
        ),
        _foot(
          Btn(
            label: r.ok ? 'Back' : 'Close',
            kind: BtnKind.g,
            onTap: r.ok ? c.emailBack : c.closeOv,
          ),
          again
              ? Btn(
                  key: const ValueKey<String>('emTryAgain'),
                  label: c.emBusy
                      ? 'Please wait…'
                      : r.code == 'changed'
                      ? 'Review again'
                      : 'Try again',
                  icon: 'sync',
                  enabled: !c.emBusy,
                  onTap: c.emailTryAgain,
                )
              : Btn(
                  key: const ValueKey<String>('emDone'),
                  label: 'Done',
                  icon: 'check',
                  onTap: c.closeOv,
                ),
        ),
      ],
    );
  }
}

/// Party detail: reminders sent to this party (this company), with their
/// real status, and a button to send one.
class PartyReminders extends ConsumerWidget {
  const PartyReminders({super.key, required this.party});
  final Party party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String g = party.guid ?? '';
    final String? blocked = c.emBlocked;
    final bool pending = c.repo.receivables().any(
      (Bill b) => b.party == party.name && b.amt > 0,
    );
    final List<ReminderLog>? logs = c.reminderLogs(g);
    final String? err = c.reminderLogsError(g);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Sec('Email reminders'),
        if (blocked != null)
          InfoBox(blocked, icon: 'info')
        else ...<Widget>[
          if (pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Btn(
                key: const ValueKey<String>('partyEmailRem'),
                label: 'Email reminder',
                icon: 'mail',
                kind: BtnKind.g,
                onTap: () => c.openEmailReminder(party: party.name),
              ),
            ),
          if (err != null)
            InfoBox(err, icon: 'info')
          else if (logs == null)
            EmptyBox(
              c.reminderLogsLoading(g)
                  ? 'Loading reminders…'
                  : 'Reminders appear here.',
            )
          else if (logs.isEmpty)
            const EmptyBox('No email reminders sent yet.')
          else
            GlassList(
              children: <Widget>[
                for (final ReminderLog l in logs)
                  RowX(
                    key: ValueKey<String>('remLog-${l.id}'),
                    cross: CrossAxisAlignment.start,
                    children: <Widget>[
                      Ico(
                        'mail',
                        size: IcoSize.xs,
                        color: p.navy,
                        icon: IcSize.s,
                      ),
                      Expanded(
                        child: RTx(
                          '${dmy(l.createdAt)} · ${_billsText(l.bills.length)} · ${inr(l.total)}',
                          <String>[
                            switch (l.status) {
                              'accepted' =>
                                'Accepted by Microsoft 365 for delivery',
                              'failed' => 'Not sent: ${l.error ?? 'failed'}',
                              _ => 'Sending…',
                            },
                            if (l.recipients.isNotEmpty)
                              'To ${l.recipients.join(', ')}',
                            if (l.sentBy != null) 'By ${l.sentBy}',
                          ].join(' · '),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Bdg(
                            switch (l.status) {
                              'accepted' => 'Accepted',
                              'failed' => 'Failed',
                              _ => 'Sending',
                            },
                            kind: switch (l.status) {
                              'accepted' => BadgeKind.ok,
                              'failed' => BadgeKind.bad,
                              _ => BadgeKind.warn,
                            },
                            dot: true,
                          ),
                          if (l.failed) ...<Widget>[
                            const SizedBox(height: 6),
                            ChipBtn(
                              c.retrying(l.id) ? 'Retrying…' : 'Retry',
                              key: ValueKey<String>('remRetry-${l.id}'),
                              height: 32,
                              fontSize: 13,
                              onTap: () => c.retryEmailReminder(l),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
              ],
            ),
        ],
      ],
    );
  }
}

/// Settings → Email templates (account admin only).
class ReminderTemplatesSheet extends ConsumerWidget {
  const ReminderTemplatesSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final ReminderTemplates? t = c.emTemplates;
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetHead(
            'Email templates',
            sub:
                'Used for outstanding reminders. The default one is chosen '
                'first.',
          ),
          if (t == null)
            const EmptyBox('Loading templates…')
          else ...<Widget>[
            if (!t.emailConfigured)
              const InfoBox(
                'Email sending is not configured on the server yet, so '
                'reminders cannot be sent.',
                icon: 'alert',
              ),
            GlassList(
              children: <Widget>[
                for (final ReminderTemplate x in t.templates)
                  RowX(
                    key: ValueKey<String>('tpl-${x.id ?? 'builtin'}'),
                    onTap: () => c.editReminderTemplate(x),
                    children: <Widget>[
                      Expanded(child: RTx(x.name, x.subject, subEll: true)),
                      if (x.builtIn)
                        const Bdg('Built-in')
                      else if (x.isDefault)
                        const Bdg('Default', kind: BadgeKind.ok),
                      if (!x.builtIn)
                        CBtn(
                          'trash',
                          key: ValueKey<String>('tplDel-${x.id}'),
                          small: true,
                          onTap: () => c.deleteReminderTemplate(x),
                        ),
                    ],
                  ),
              ],
            ),
          ],
          _foot(
            Btn(label: 'Close', kind: BtnKind.g, onTap: c.closeOv),
            Btn(
              key: const ValueKey<String>('tplNew'),
              label: 'New template',
              icon: 'plus',
              enabled: t != null && !c.emTplBusy,
              onTap: () => c.editReminderTemplate(null),
            ),
          ),
        ],
      ),
    );
  }
}

class ReminderTemplateEditSheet extends ConsumerWidget {
  const ReminderTemplateEditSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final ReminderTemplate? e = c.emTplEdit;
    if (e == null) return const SizedBox.shrink();
    final List<String> ph = c.emTemplates?.placeholders.isNotEmpty == true
        ? c.emTemplates!.placeholders
        : const <String>[
            'party',
            'company',
            'bills',
            'total',
            'count',
            'sender',
          ];
    final String? formErr = c.templateFormError;
    void back() => c.openReminderTemplates();
    return Sheet(
      onClose: back,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHead(
            e.id == null ? 'New template' : 'Edit template',
            onClose: back,
          ),
          Fld(
            label: 'Name',
            req: true,
            child: Inp(
              key: const ValueKey<String>('rtName'),
              value: c.f('rtName'),
              onChanged: (String v) => c.setF('rtName', v),
              placeholder: 'e.g. Friendly reminder',
              maxLength: 80,
            ),
          ),
          Fld(
            label: 'Subject',
            req: true,
            child: Inp(
              key: const ValueKey<String>('rtSubject'),
              value: c.f('rtSubject'),
              onChanged: (String v) => c.setF('rtSubject', v),
              maxLength: 200,
            ),
          ),
          Fld(
            label: 'Message',
            req: true,
            child: Inp(
              key: const ValueKey<String>('rtBody'),
              value: c.f('rtBody'),
              onChanged: (String v) => c.setF('rtBody', v),
              textarea: true,
              maxLength: 5000,
              capitalization: TextCapitalization.sentences,
            ),
          ),
          InfoBox(
            'Placeholders: ${ph.map((String x) => '{{$x}}').join('  ')}. '
            '{{bills}} becomes the table of selected bills.',
            icon: 'info',
          ),
          GlassList(
            children: <Widget>[
              RowX(
                key: const ValueKey<String>('rtDefault'),
                onTap: c.toggleTemplateDefault,
                children: <Widget>[
                  const Expanded(
                    child: RTx(
                      'Default template',
                      'Chosen first for new reminders',
                    ),
                  ),
                  Sw(e.isDefault),
                ],
              ),
            ],
          ),
          if (c.emTplError != null)
            InfoBox(
              c.emTplError!,
              icon: 'alert',
              margin: const EdgeInsets.only(top: 12),
            ),
          _foot(
            Btn(label: 'Cancel', kind: BtnKind.g, onTap: back),
            Btn(
              key: const ValueKey<String>('rtSave'),
              label: c.emTplBusy ? 'Saving…' : (formErr ?? 'Save template'),
              icon: 'check',
              enabled: formErr == null && !c.emTplBusy,
              onTap: c.saveReminderTemplate,
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings → Payment reminders: when reminders are due (before / after /
/// both the due date, days, hour) and how they go out (Automatic: the server
/// emails each party at that hour; Manual: your team sends them). The admin
/// changes them; everyone else sees them.
class ReminderSettingsSheet extends ConsumerWidget {
  const ReminderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final ReminderSettings s = c.remDraft ?? c.remSettings;
    final bool edit = c.remSettings.canEdit && !c.remSetBusy;
    final TcPalette p = Tc.of(context);
    String days(int n) => n == 1 ? '1 day' : '$n days';
    Widget line(
      String key,
      String title,
      String value, {
      VoidCallback? dec,
      VoidCallback? inc,
    }) => RowX(
      key: ValueKey<String>(key),
      minHeight: 60,
      children: <Widget>[
        Expanded(child: RTx(title, value)),
        if (edit) Stepper2(label: '', onDec: dec, onInc: inc),
      ],
    );
    const List<String> timings = <String>['before', 'after', 'both'];
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHead(
            'Payment reminders',
            sub: c.remSettings.canEdit
                ? 'When customers are reminded about their bills'
                : 'Set by your admin',
          ),
          if (!c.remSettings.ready)
            const InfoBox(
              'Reminder settings are not available on the server yet. The '
              'defaults are shown.',
              icon: 'info',
            ),
          if (s.automatic && !c.remSettings.emailConfigured)
            const InfoBox(
              'Email sending is not configured on the server yet, so '
              'automatic reminders cannot go out.',
              icon: 'alert',
            ),
          if (c.remSetError != null) InfoBox(c.remSetError!, icon: 'alert'),
          const Sec('Delivery', margin: EdgeInsets.fromLTRB(8, 6, 8, 8)),
          IgnorePointer(
            ignoring: !edit,
            child: Seg(
              key: const ValueKey<String>('remMode'),
              items: const <String>['Automatic', 'Manual'],
              selected: s.automatic ? 0 : 1,
              onPick: (int i) => c.editRemDraft(
                (ReminderSettings x) =>
                    x.copyWith(mode: i == 0 ? 'automatic' : 'manual'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Text(
              s.automatic
                  ? 'TallyConnect emails each customer by itself at the time '
                        'below, using your default email template. Only '
                        'customers with an email address in Tally get one.'
                  : 'Nothing is sent by itself. Customers due for a reminder '
                        'are listed in Email reminder, and your team sends '
                        'them.',
              style: ts(13, c: p.ink3, h: 1.35),
            ),
          ),
          const Sec('When', margin: EdgeInsets.fromLTRB(8, 6, 8, 8)),
          IgnorePointer(
            ignoring: !edit,
            child: Seg(
              key: const ValueKey<String>('remTiming'),
              items: const <String>['Before due', 'After due', 'Both'],
              selected: timings.indexOf(s.timing).clamp(0, 2),
              onPick: (int i) => c.editRemDraft(
                (ReminderSettings x) => x.copyWith(timing: timings[i]),
              ),
            ),
          ),
          GlassList(
            children: <Widget>[
              if (s.before)
                line(
                  'remBefore',
                  'Before the due date',
                  days(s.beforeDays),
                  dec: s.beforeDays > 1
                      ? () => c.editRemDraft(
                          (ReminderSettings x) =>
                              x.copyWith(beforeDays: x.beforeDays - 1),
                        )
                      : null,
                  inc: s.beforeDays < 60
                      ? () => c.editRemDraft(
                          (ReminderSettings x) =>
                              x.copyWith(beforeDays: x.beforeDays + 1),
                        )
                      : null,
                ),
              if (s.after) ...<Widget>[
                line(
                  'remAfter',
                  'After the due date',
                  days(s.afterDays),
                  dec: s.afterDays > 1
                      ? () => c.editRemDraft(
                          (ReminderSettings x) =>
                              x.copyWith(afterDays: x.afterDays - 1),
                        )
                      : null,
                  inc: s.afterDays < 90
                      ? () => c.editRemDraft(
                          (ReminderSettings x) =>
                              x.copyWith(afterDays: x.afterDays + 1),
                        )
                      : null,
                ),
                line(
                  'remRepeat',
                  'Then again every',
                  s.repeatDays == 0 ? 'Once only' : days(s.repeatDays),
                  dec: s.repeatDays > 0
                      ? () => c.editRemDraft(
                          (ReminderSettings x) =>
                              x.copyWith(repeatDays: x.repeatDays - 1),
                        )
                      : null,
                  inc: s.repeatDays < 30
                      ? () => c.editRemDraft(
                          (ReminderSettings x) =>
                              x.copyWith(repeatDays: x.repeatDays + 1),
                        )
                      : null,
                ),
              ],
              line(
                'remHour',
                'Time (India time)',
                clock(DateTime(2000, 1, 1, s.sendHour)),
                dec: () => c.editRemDraft(
                  (ReminderSettings x) =>
                      x.copyWith(sendHour: (x.sendHour + 23) % 24),
                ),
                inc: () => c.editRemDraft(
                  (ReminderSettings x) =>
                      x.copyWith(sendHour: (x.sendHour + 1) % 24),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
            child: Text(
              'Reminders: ${c.remRuleText(s)}. The due-date alerts on this '
              'phone follow the same days and time.',
              key: const ValueKey<String>('remSummary'),
              style: ts(13, c: p.ink3, h: 1.35),
            ),
          ),
          if (c.remSettings.canEdit)
            _foot(
              Btn(label: 'Cancel', kind: BtnKind.g, onTap: c.closeOv),
              Btn(
                key: const ValueKey<String>('remSave'),
                label: c.remSetBusy ? 'Saving…' : 'Save',
                icon: 'check',
                enabled: !c.remSetBusy && c.remSettings.ready,
                onTap: c.saveReminderSettings,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Btn(label: 'Close', kind: BtnKind.g, onTap: c.closeOv),
            ),
        ],
      ),
    );
  }
}

/// Email reminder → customers due for a reminder today by the settings.
class _DueToday extends StatelessWidget {
  const _DueToday({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final List<DueReminder> due = c.dueToday ?? const <DueReminder>[];
    if (due.isEmpty) return const SizedBox.shrink();
    String why(String r) => switch (r) {
      'before' => 'due soon',
      'after' => 'overdue',
      _ => 'due soon and overdue',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Sec(
          'Due for a reminder today (${due.length})',
          margin: const EdgeInsets.fromLTRB(8, 2, 8, 8),
        ),
        GlassList(
          children: <Widget>[
            for (final DueReminder d in due)
              RowX(
                key: ValueKey<String>('emDue-${d.ledgerGuid}'),
                onTap: () => c.pickEmailParty(
                  d.party,
                  only: <String>{for (final ReminderBill b in d.bills) b.no},
                ),
                children: <Widget>[
                  Av(initials(d.party), size: Av.sm),
                  Expanded(
                    child: RTx(
                      d.party,
                      '${_billsText(d.bills.length)} ${why(d.reason)} · '
                      '${inr(d.total)}'
                      '${d.emails.isEmpty ? ' · no email in Tally' : ''}',
                      ell: true,
                    ),
                  ),
                  chevR(),
                ],
              ),
          ],
        ),
        const Sec('All customers', margin: EdgeInsets.fromLTRB(8, 14, 8, 8)),
      ],
    );
  }
}
