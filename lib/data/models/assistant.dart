// AI financial assistant (`/api/assistant/*`): the chat turns and answers.
// Answers come from Gemini with data the TallyConnect server read for the
// signed-in user's active company only.
library;

/// One KPI card value. [format]: `money` | `count` | `text`.
class AiKpi {
  const AiKpi(this.label, this.value, {this.format = 'text', this.tone});
  final String label;
  final Object? value;
  final String format;

  /// `primary` (main total), `neg` (overdue…) or null.
  final String? tone;
}

/// A table column. [format]: `money` | `count` | `date` | `text`.
class AiColumn {
  const AiColumn(this.label, {this.format = 'text'});
  final String label, format;
  bool get numeric => format == 'money' || format == 'count';
}

/// Cards / tables / notes shown with an answer, built by the server from
/// the data it looked up (never from the AI's text).
class AiBlock {
  const AiBlock.kpis(this.title, this.items)
    : type = 'kpis',
      columns = const <AiColumn>[],
      rows = const <List<Object?>>[],
      totalRows = 0,
      empty = '';
  const AiBlock.table(
    this.title,
    this.columns,
    this.rows, {
    this.totalRows = 0,
    this.empty = '',
  }) : type = 'table',
       items = const <AiKpi>[];
  const AiBlock.note(this.title)
    : type = 'note',
      items = const <AiKpi>[],
      columns = const <AiColumn>[],
      rows = const <List<Object?>>[],
      totalRows = 0,
      empty = '';

  final String type, title, empty;
  final List<AiKpi> items;
  final List<AiColumn> columns;
  final List<List<Object?>> rows;

  /// All matching rows (only the first ones are in [rows]).
  final int totalRows;

  static AiBlock? fromJson(Object? o) {
    if (o is! Map) return null;
    final String title = '${o['title'] ?? ''}';
    switch (o['type']) {
      case 'kpis':
        final Object? it = o['items'];
        return AiBlock.kpis(title, <AiKpi>[
          if (it is List)
            for (final Object? x in it)
              if (x is Map)
                AiKpi(
                  '${x['label'] ?? ''}',
                  x['value'],
                  format: '${x['format'] ?? 'text'}',
                  tone: x['tone'] is String ? x['tone'] as String : null,
                ),
        ]);
      case 'table':
        final Object? cs = o['columns'];
        final Object? rs = o['rows'];
        final List<AiColumn> cols = <AiColumn>[
          if (cs is List)
            for (final Object? x in cs)
              if (x is Map)
                AiColumn(
                  '${x['label'] ?? ''}',
                  format: '${x['format'] ?? 'text'}',
                ),
        ];
        if (cols.isEmpty) return null;
        final List<List<Object?>> rows = <List<Object?>>[
          if (rs is List)
            for (final Object? r in rs)
              if (r is List && r.length == cols.length) List<Object?>.of(r),
        ];
        final Object? total = o['total_rows'];
        return AiBlock.table(
          title,
          cols,
          rows,
          totalRows: total is num ? total.toInt() : rows.length,
          empty: '${o['empty'] ?? ''}',
        );
      case 'note':
        final String t = '${o['text'] ?? ''}'.trim();
        return t.isEmpty ? null : AiBlock.note(t);
    }
    return null;
  }
}

/// One chat message. `role`: `user` | `model`.
class AiTurn {
  const AiTurn(
    this.role,
    this.text, {
    this.error = false,
    this.blocks = const <AiBlock>[],
  });
  final String role, text;

  /// Cards / tables for this answer (model turns).
  final List<AiBlock> blocks;

  /// A failure shown in the chat (never sent back to Gemini as history).
  final bool error;

  bool get mine => role == 'user';

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role,
    'text': text,
  };
}

class AssistantReply {
  const AssistantReply({
    required this.answer,
    this.toolsUsed = const <String>[],
    this.blocks = const <AiBlock>[],
  });
  final String answer;

  /// The data lookups the server made for this answer.
  final List<String> toolsUsed;

  /// Cards / tables from those lookups (an older server sends none).
  final List<AiBlock> blocks;

  static AssistantReply fromJson(Object? o) {
    final Map<Object?, Object?> m = o is Map ? o : const <Object?, Object?>{};
    final Object? t = m['tools_used'];
    final Object? b = m['blocks'];
    return AssistantReply(
      answer: '${m['answer'] ?? ''}'.trim(),
      toolsUsed: t is List
          ? <String>[for (final Object? x in t) '$x']
          : const <String>[],
      blocks: <AiBlock>[
        if (b is List)
          for (final Object? x in b) ?AiBlock.fromJson(x),
      ],
    );
  }
}
