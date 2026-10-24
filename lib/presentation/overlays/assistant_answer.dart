// AI assistant answers, formatted for the phone: KPI cards and tables built
// from the figures the server looked up, plus the AI's short summary drawn
// from a small Markdown subset (headings, bullets, numbered steps, bold,
// ₹ amounts highlighted) — never shown as raw Markdown.
library;

import 'package:flutter/material.dart';

import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/utils/format.dart';
import '../../data/models/models.dart';

/// `2026-10-12` → `12 Oct 2026`; `2026-10` → `Oct 2026`; else as is.
String aiDate(String s) {
  final RegExpMatch? d = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (d != null) return dmy(DateTime.tryParse(s));
  final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(s);
  if (m != null) {
    final int mo = int.parse(m[2]!);
    if (mo >= 1 && mo <= 12) return '${kMonths[mo - 1]} ${m[1]}';
  }
  return s;
}

/// ISO dates inside a title (`… as on 2026-10-12`) in the app's format.
String aiTitle(String s) => s.replaceAllMapped(
  RegExp(r'\b\d{4}-\d{2}-\d{2}\b'),
  (Match m) => aiDate(m[0]!),
);

/// One value formatted for its column / card.
String aiValue(Object? v, String format) {
  if (v == null) return '—';
  switch (format) {
    case 'money':
      final num? n = v is num ? v : num.tryParse('$v');
      return n == null ? '$v' : inr(n);
    case 'count':
      final num? n = v is num ? v : num.tryParse('$v');
      return n == null ? '$v' : grouped(n.round());
    case 'date':
      return aiDate('$v');
  }
  final String s = '$v'.trim();
  return s.isEmpty ? '—' : s;
}

/// A model answer: notes, KPI cards, the summary, then tables.
class AiAnswer extends StatelessWidget {
  const AiAnswer(this.turn, {super.key});
  final AiTurn turn;

  @override
  Widget build(BuildContext context) {
    final List<AiBlock> b = turn.blocks;
    final List<Widget> parts = <Widget>[
      for (final AiBlock x in b)
        if (x.type == 'note') _Note(x.title),
      for (final AiBlock x in b)
        if (x.type == 'kpis') _Kpis(x),
      if (turn.text.trim().isNotEmpty) AiMarkdown(turn.text),
      for (final AiBlock x in b)
        if (x.type == 'table') _Table(x),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < parts.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 12),
          parts[i],
        ],
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Ic('info', size: IcSize.s, color: p.ink2),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: ts(14, h: 1.4, c: p.ink2)),
        ),
      ],
    );
  }
}

/// KPI cards: two per row (one per row on very narrow screens).
class _Kpis extends StatelessWidget {
  const _Kpis(this.b);
  final AiBlock b;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Column(
      key: const ValueKey<String>('aiKpis'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (b.title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              aiTitle(b.title),
              style: ts(13, w: w700, c: p.ink3),
            ),
          ),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            const double gap = 8;
            final int cols = box.maxWidth < 220 ? 1 : 2;
            final double w = (box.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                for (final AiKpi k in b.items)
                  SizedBox(width: w, child: _KpiCard(k)),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard(this.k);
  final AiKpi k;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final bool primary = k.tone == 'primary';
    final Color fg = primary
        ? p.acc
        : k.tone == 'neg'
        ? p.neg
        : p.ink;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: primary
            ? p.acc.withValues(alpha: .10)
            : Colors.white.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primary ? p.acc.withValues(alpha: .28) : navyA(.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            k.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ts(12, w: w600, c: p.ink3),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              aiValue(k.value, k.format),
              maxLines: 1,
              style: ts(17, w: w800, c: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// A readable table: the first text column takes the room (two lines at
/// most), numbers sit right-aligned; wide tables swipe sideways.
class _Table extends StatelessWidget {
  const _Table(this.b);
  final AiBlock b;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final List<AiColumn> cols = b.columns;
    final TextStyle head = ts(11.5, w: w700, c: p.ink3);
    final TextStyle cell = ts(13.5, h: 1.3, c: p.ink);
    final TextStyle num = ts(13.5, w: w700, c: p.ink);
    Widget cellAt(int c, Object? v) {
      final AiColumn col = cols[c];
      final String s = aiValue(v, col.format);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(
          s,
          maxLines: c == 0 ? 2 : 1,
          softWrap: c == 0,
          overflow: TextOverflow.ellipsis,
          textAlign: col.numeric ? TextAlign.right : TextAlign.left,
          style: col.format == 'money' ? num : cell,
        ),
      );
    }

    final Widget body = b.rows.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Text(
              b.empty.isNotEmpty ? b.empty : 'No data found.',
              style: ts(13.5, c: p.ink2),
            ),
          )
        : LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              // Many columns on a narrow phone: keep each readable and let
              // the table swipe sideways instead of squeezing it.
              final double minW = 120.0 + (cols.length - 1) * 92.0;
              final bool scroll = minW > box.maxWidth;
              final Widget table = Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: <int, TableColumnWidth>{
                  for (int c = 0; c < cols.length; c++)
                    c: c == 0
                        ? const FlexColumnWidth()
                        : (cols[c].numeric || cols[c].format == 'date'
                              ? const IntrinsicColumnWidth()
                              : const FlexColumnWidth(.8)),
                },
                children: <TableRow>[
                  TableRow(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: navyA(.12))),
                    ),
                    children: <Widget>[
                      for (int c = 0; c < cols.length; c++)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
                          child: Text(
                            cols[c].label.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: cols[c].numeric
                                ? TextAlign.right
                                : TextAlign.left,
                            style: head,
                          ),
                        ),
                    ],
                  ),
                  for (int r = 0; r < b.rows.length; r++)
                    TableRow(
                      decoration: BoxDecoration(
                        color: r.isOdd ? navyA(.03) : null,
                        border: r == b.rows.length - 1
                            ? null
                            : Border(bottom: BorderSide(color: navyA(.06))),
                      ),
                      children: <Widget>[
                        for (int c = 0; c < cols.length; c++)
                          cellAt(c, b.rows[r][c]),
                      ],
                    ),
                ],
              );
              return scroll
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(width: minW, child: table),
                    )
                  : table;
            },
          );
    final int more = b.totalRows - b.rows.length;
    return Container(
      key: const ValueKey<String>('aiTable'),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: navyA(.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (b.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Text(
                aiTitle(b.title),
                style: ts(14, w: w800, c: p.ink),
              ),
            ),
          body,
          if (more > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: Text(
                '+ ${grouped(more)} more — open the app’s screens for the full list',
                style: ts(12, c: p.ink3),
              ),
            ),
        ],
      ),
    );
  }
}

/// The AI's summary from a small Markdown subset. Anything else (code
/// fences, links, stray symbols) is shown as plain text, never raw syntax.
class AiMarkdown extends StatelessWidget {
  const AiMarkdown(this.text, {super.key});
  final String text;

  static final RegExp _bold = RegExp(r'\*\*(.+?)\*\*|__(.+?)__');
  static final RegExp _money = RegExp(r'[−-]?₹\s?[\d,]+(?:\.\d+)?');

  /// Inline text: **bold** and ₹ amounts highlighted; other markup removed.
  List<InlineSpan> _inline(String s, TextStyle base, TextStyle strong) {
    final String clean = s
        .replaceAll(RegExp(r'`+'), '')
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (Match m) => m[1]!);
    final List<InlineSpan> out = <InlineSpan>[];
    int at = 0;
    void plain(String t) {
      // ₹ amounts outside **…** are highlighted too.
      int i = 0;
      for (final RegExpMatch m in _money.allMatches(t)) {
        if (m.start > i) {
          out.add(TextSpan(text: _strip(t.substring(i, m.start)), style: base));
        }
        out.add(TextSpan(text: m[0], style: strong));
        i = m.end;
      }
      if (i < t.length) {
        out.add(TextSpan(text: _strip(t.substring(i)), style: base));
      }
    }

    for (final RegExpMatch m in _bold.allMatches(clean)) {
      if (m.start > at) plain(clean.substring(at, m.start));
      out.add(TextSpan(text: m[1] ?? m[2], style: strong));
      at = m.end;
    }
    if (at < clean.length) plain(clean.substring(at));
    return out;
  }

  /// Single `*` / `_` emphasis markers left over.
  static String _strip(String s) => s.replaceAllMapped(
    RegExp(r'(^|\s)[*_]([^*_\s][^*_]*)[*_](?=\s|$|[.,;:!?])'),
    (Match m) => '${m[1]}${m[2]}',
  );

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final TextStyle base = ts(14.5, h: 1.45, c: p.ink);
    final TextStyle strong = ts(14.5, h: 1.45, w: w800, c: p.ink);
    final List<Widget> out = <Widget>[];
    void gap(double h) {
      if (out.isNotEmpty) out.add(SizedBox(height: h));
    }

    final List<String> lines = text
        .replaceAll('\r', '')
        .split('\n')
        .where((String l) => !l.trimLeft().startsWith('```'))
        .toList();
    List<String>? tableRows;
    void flushTable() {
      final List<String>? t = tableRows;
      tableRows = null;
      if (t == null) return;
      // A Markdown table the AI wrote anyway: shown as aligned rows.
      final List<List<String>> cells = <List<String>>[
        for (final String r in t)
          if (!RegExp(r'^\|?\s*:?-{2,}').hasMatch(r.trim()))
            r
                .trim()
                .replaceAll(RegExp(r'^\||\|$'), '')
                .split('|')
                .map((String c) => c.trim())
                .toList(),
      ];
      if (cells.isEmpty) return;
      gap(6);
      out.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < cells.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    for (int c = 0; c < cells[i].length; c++)
                      Expanded(
                        flex: c == 0 ? 3 : 2,
                        child: Text.rich(
                          TextSpan(
                            children: _inline(
                              cells[i][c],
                              i == 0 ? strong : base,
                              strong,
                            ),
                          ),
                          textAlign: c == 0 ? TextAlign.left : TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    for (final String raw in lines) {
      final String l = raw.trim();
      if (l.startsWith('|')) {
        (tableRows ??= <String>[]).add(l);
        continue;
      }
      flushTable();
      if (l.isEmpty) continue;
      final RegExpMatch? h = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(l);
      final RegExpMatch? bullet = RegExp(r'^[-*•]\s+(.*)$').firstMatch(l);
      final RegExpMatch? numbered = RegExp(
        r'^(\d{1,2})[.)]\s+(.*)$',
      ).firstMatch(l);
      if (h != null) {
        gap(10);
        out.add(
          Text.rich(
            TextSpan(
              children: _inline(
                h[1]!.replaceAll('*', ''),
                ts(15.5, w: w800, c: p.ink),
                ts(15.5, w: w800, c: p.ink),
              ),
            ),
          ),
        );
      } else if (bullet != null || numbered != null) {
        gap(5);
        out.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 22,
                child: numbered != null
                    ? Text(
                        '${numbered[1]}.',
                        style: ts(14.5, h: 1.45, w: w700, c: p.acc),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: p.acc,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: _inline(
                      (bullet?[1] ?? numbered![2])!,
                      base,
                      strong,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        gap(8);
        out.add(Text.rich(TextSpan(children: _inline(l, base, strong))));
      }
    }
    flushTable();
    return SelectionArea(
      child: Column(
        key: const ValueKey<String>('aiText'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: out,
      ),
    );
  }
}

// ------------------------------------------------- sharing (WhatsApp)
/// The AI's Markdown in WhatsApp's own style: `**bold**` / headings →
/// `*bold*`, `- item` → `• item`.
String aiWhatsAppText(String md) => md
    .split('\n')
    .map((String l) {
      String x = l.trimRight();
      final RegExpMatch? h = RegExp(r'^\s*#{1,6}\s+(.*)$').firstMatch(x);
      if (h != null) x = '*${h[1]!.replaceAll('**', '')}*';
      x = x.replaceFirstMapped(
        RegExp(r'^(\s*)[-*]\s+'),
        (Match m) => '${m[1]}• ',
      );
      return x.replaceAllMapped(
        RegExp(r'\*\*(.+?)\*\*'),
        (Match m) => '*${m[1]}*',
      );
    })
    .join('\n')
    .trim();

/// One answer as text: notes, KPI figures, the summary and its tables
/// (each table's first rows; a table is cut short with "…N more").
String aiAnswerText(AiTurn t, {int maxRows = 15}) {
  final List<String> out = <String>[];
  for (final AiBlock b in t.blocks) {
    switch (b.type) {
      case 'note':
        out.add('_${b.title}_');
      case 'kpis':
        if (b.title.isNotEmpty) out.add('*${aiTitle(b.title)}*');
        for (final AiKpi k in b.items) {
          out.add('• ${k.label}: ${aiValue(k.value, k.format)}');
        }
    }
  }
  final String summary = aiWhatsAppText(t.text);
  if (summary.isNotEmpty) out.add(summary);
  for (final AiBlock b in t.blocks.where((AiBlock x) => x.type == 'table')) {
    out.add('');
    if (b.title.isNotEmpty) out.add('*${aiTitle(b.title)}*');
    if (b.rows.isEmpty) {
      out.add(b.empty.isEmpty ? 'Nothing found.' : b.empty);
      continue;
    }
    for (final List<Object?> r in b.rows.take(maxRows)) {
      out.add(
        '• ${<String>[for (int i = 0; i < b.columns.length; i++) aiValue(r[i], b.columns[i].format)].join(' · ')}',
      );
    }
    final int more =
        (b.totalRows > b.rows.length ? b.totalRows : b.rows.length) -
        (b.rows.length < maxRows ? b.rows.length : maxRows);
    if (more > 0) out.add('…$more more');
  }
  return out.join('\n').trim();
}

/// One message with the question it answers: `Q: …` then the answer.
String aiMessageShare(List<AiTurn> turns, int i, String company) {
  final AiTurn t = turns[i];
  AiTurn? q;
  for (int j = i - 1; j >= 0; j--) {
    if (turns[j].mine) {
      q = turns[j];
      break;
    }
  }
  return <String>[
    if (q != null && !t.mine) '*Q:* ${q.text.trim()}',
    if (q != null && !t.mine) '',
    if (t.mine) t.text.trim() else aiAnswerText(t),
    '',
    '— TallyConnect AI · $company',
  ].join('\n');
}

/// The whole conversation (failed answers left out).
String aiChatShare(List<AiTurn> turns, String company) => <String>[
  '*TallyConnect AI · $company*',
  for (final AiTurn t in turns)
    if (!t.error) ...<String>[
      '',
      if (t.mine) '*Q:* ${t.text.trim()}' else aiAnswerText(t),
    ],
].join('\n');
