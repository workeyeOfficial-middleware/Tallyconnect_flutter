// AI financial assistant (`/api/assistant/*`): the chat turns and answers.
// Answers come from Gemini with data the TallyConnect server read for the
// signed-in user's active company only.
library;

/// One chat message. `role`: `user` | `model`.
class AiTurn {
  const AiTurn(this.role, this.text, {this.error = false});
  final String role, text;

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
  });
  final String answer;

  /// The data lookups the server made for this answer.
  final List<String> toolsUsed;

  static AssistantReply fromJson(Object? o) {
    final Map<Object?, Object?> m = o is Map ? o : const <Object?, Object?>{};
    final Object? t = m['tools_used'];
    return AssistantReply(
      answer: '${m['answer'] ?? ''}'.trim(),
      toolsUsed: t is List
          ? <String>[for (final Object? x in t) '$x']
          : const <String>[],
    );
  }
}
