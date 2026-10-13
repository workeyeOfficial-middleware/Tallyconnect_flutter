// AI financial assistant: the floating chat button on Home and the chat
// sheet. The user connects their own Gemini API key; questions are answered
// by the TallyConnect server from the active company's data the user may
// see (never demo data).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_fields.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../data/models/models.dart';
import '../widgets/common.dart';
import 'assistant_answer.dart';

/// Home: round chat button at the bottom right, above the tab bar.
class AssistantFab extends ConsumerWidget {
  const AssistantFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    return Positioned(
      right: 16,
      bottom: wtBottom(context) - 8,
      child: Semantics(
        button: true,
        label: 'AI assistant',
        child: Tap(
          key: const ValueKey<String>('assistantFab'),
          onTap: c.openAssistant,
          radius: 28,
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.acc,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: .25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Ic('chat', size: IcSize.m, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class AssistantSheet extends ConsumerWidget {
  const AssistantSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    return Sheet(
      top: 60,
      flex: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          12 + MediaQuery.paddingOf(context).bottom * .5,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SheetHead(
              'AI assistant',
              sub: c.aiConnected
                  ? 'Answers from ${c.companyName} · Gemini'
                  : 'Ask about your Tally data with your own Gemini key',
            ),
            Expanded(
              child: c.aiConnected ? _Chat(c: c) : _Connect(c: c),
            ),
          ],
        ),
      ),
    );
  }
}

class _Connect extends StatelessWidget {
  const _Connect({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Fld(
            label: 'Gemini API key',
            req: true,
            child: Inp(
              key: const ValueKey<String>('aiKeyField'),
              value: c.f('aiKey'),
              onChanged: (String v) => c.setF('aiKey', v),
              placeholder: 'Paste your key',
              icon: 'lock',
              obscure: true,
            ),
          ),
          if (c.aiError != null) InfoBox(c.aiError!, icon: 'alert'),
          Btn(
            key: const ValueKey<String>('aiConnect'),
            label: c.aiConnecting ? 'Checking key…' : 'Connect',
            icon: 'check',
            enabled: !c.aiConnecting,
            onTap: c.connectAssistant,
          ),
          const SizedBox(height: 14),
          Tap(
            onTap: () =>
                c.openUri(Uri.parse('https://aistudio.google.com/apikey')),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Get a free key at aistudio.google.com/apikey',
                textAlign: TextAlign.center,
                style: ts(14, w: w700, c: p.acc),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const InfoBox(
            'Your key is kept only on this phone (secure storage) and is sent '
            'to TallyConnect with each question; the server does not save it. '
            'Your question and the Tally figures needed to answer it are sent '
            'to Google Gemini under your key. The assistant can only read '
            'data — it never changes anything in Tally.',
            icon: 'shield',
          ),
        ],
      ),
    );
  }
}

class _Chat extends StatelessWidget {
  const _Chat({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final List<AiTurn> turns = c.aiTurns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: turns.isEmpty
              ? SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text('Try asking', style: rsStyle(context)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final String s in AppController.kAiSuggestions)
                            ChipBtn(
                              s,
                              height: 36,
                              fontSize: 13.5,
                              onTap: () => c.askAssistant(s),
                            ),
                        ],
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  key: const ValueKey<String>('aiList'),
                  reverse: true,
                  itemCount: turns.length + (c.aiBusy ? 1 : 0),
                  itemBuilder: (BuildContext context, int i) {
                    if (c.aiBusy && i == 0) {
                      return const _Bubble(
                        AiTurn('model', 'Looking at your Tally data…'),
                        busy: true,
                      );
                    }
                    final AiTurn t =
                        turns[turns.length - 1 - (i - (c.aiBusy ? 1 : 0))];
                    return _Bubble(t);
                  },
                ),
        ),
        const SizedBox(height: 10),
        // Type, or tap the mic and speak (the words fill the field; the
        // user checks them and taps Send).
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Inp(
                key: const ValueKey<String>('aiQuestion'),
                value: c.f('aiQ'),
                onChanged: (String v) => c.setF('aiQ', v),
                placeholder: c.aiVoiceOn
                    ? 'Listening…'
                    : 'Ask about outstanding, sales…',
                maxLength: 1000,
                capitalization: TextCapitalization.sentences,
                trailing: Semantics(
                  button: true,
                  label: c.aiVoiceOn ? 'Stop voice input' : 'Ask by voice',
                  child: GestureDetector(
                    key: const ValueKey<String>('aiMic'),
                    behavior: HitTestBehavior.opaque,
                    onTap: c.aiBusy ? null : c.toggleAssistantVoice,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Ic(
                          c.aiVoiceOn ? 'micStop' : 'mic',
                          color: c.aiVoiceOn ? p.acc : p.ink3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CBtn(
              'send',
              key: const ValueKey<String>('aiSend'),
              color: p.acc,
              onTap: c.aiBusy ? null : () => c.askAssistant(),
            ),
          ],
        ),
        if (c.voiceNote != null)
          Padding(
            key: const ValueKey<String>('aiVoiceNote'),
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
            child: Text(
              c.voiceNote!,
              style: ts(13, w: w600, c: c.aiVoiceOn ? p.acc : p.ink2),
            ),
          ),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Answers can be wrong — check important figures in Tally.',
                style: ts(12, c: p.ink3),
              ),
            ),
            Tap(
              key: const ValueKey<String>('aiDisconnect'),
              onTap: c.disconnectAssistant,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Remove key',
                  style: ts(12.5, w: w700, c: p.neg),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.t, {this.busy = false});
  final AiTurn t;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final bool mine = t.mine;
    // An answer: a full-width card with KPI cards, the formatted summary
    // and tables (never raw Markdown).
    if (!mine && !t.error && !busy) {
      return Container(
        key: const ValueKey<String>('aiAnswer'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .7)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: navyA(.08),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Ic('chat', size: IcSize.xs, color: p.acc),
                const SizedBox(width: 6),
                Text(
                  'TallyConnect AI',
                  style: ts(12, w: w800, c: p.acc, ls: .3),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AiAnswer(t),
          ],
        ),
      );
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .78,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine
              ? p.acc
              : t.error
              ? p.neg.withValues(alpha: .10)
              : navyA(.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          t.text,
          style: ts(
            14.5,
            h: 1.4,
            c: mine
                ? Colors.white
                : (t.error ? p.neg : (busy ? p.ink3 : p.ink)),
          ),
        ),
      ),
    );
  }
}
