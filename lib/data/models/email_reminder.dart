// Outstanding email reminders (`/api/reminders/*`). The app sends only the
// party (ledger GUID) and bill numbers; amounts, due dates and the
// recipient always come back from the server, which reads them from the
// synced Tally data. Nothing here is ever written to Tally.
library;

num _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
String _str(Object? v) => v == null ? '' : '$v';
List<String> _strs(Object? v) => v is List
    ? <String>[
        for (final Object? x in v)
          if (x != null) '$x',
      ]
    : const <String>[];
DateTime? _date(Object? v) {
  final String s = _str(v);
  if (s.isEmpty) return null;
  final DateTime? d = DateTime.tryParse(s);
  return d == null ? null : (s.length <= 10 ? d : d.toLocal());
}

/// One bill as the server read it.
class ReminderBill {
  const ReminderBill({
    required this.no,
    required this.amount,
    this.billDate,
    this.dueDate,
    this.overdueDays = 0,
  });
  final String no;
  final num amount;
  final DateTime? billDate, dueDate;
  final int overdueDays;

  static ReminderBill fromJson(Map<Object?, Object?> m) => ReminderBill(
    no: _str(m['bill_name']),
    amount: _num(m['pending_amount']),
    billDate: _date(m['bill_date']),
    dueDate: _date(m['due_date']),
    overdueDays: _num(m['overdue_days']).toInt(),
  );
}

/// An email template of the account (`id` null = the built-in one).
class ReminderTemplate {
  const ReminderTemplate({
    required this.id,
    required this.name,
    required this.subject,
    required this.body,
    this.isDefault = false,
  });
  final int? id;
  final String name, subject, body;
  final bool isDefault;

  bool get builtIn => id == null;

  static ReminderTemplate fromJson(Map<Object?, Object?> m) => ReminderTemplate(
    id: m['id'] == null ? null : _num(m['id']).toInt(),
    name: _str(m['name']),
    subject: _str(m['subject']),
    body: _str(m['body']),
    isDefault: m['is_default'] == true,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'subject': subject,
    'body': body,
    'is_default': isDefault,
  };
}

/// `GET /api/reminders/templates`.
class ReminderTemplates {
  const ReminderTemplates({
    required this.templates,
    required this.placeholders,
    required this.canEdit,
    required this.emailConfigured,
  });
  final List<ReminderTemplate> templates;
  final List<String> placeholders;

  /// The account admin may manage templates.
  final bool canEdit;

  /// The server has its email settings.
  final bool emailConfigured;

  static ReminderTemplates fromJson(Object? o) {
    final Map<Object?, Object?> m = o is Map ? o : const <Object?, Object?>{};
    final Object? d = m['data'];
    return ReminderTemplates(
      templates: <ReminderTemplate>[
        if (d is List)
          for (final Object? x in d)
            if (x is Map) ReminderTemplate.fromJson(x),
      ],
      placeholders: _strs(m['placeholders']),
      canEdit: m['can_edit'] == true,
      emailConfigured: m['email_configured'] == true,
    );
  }
}

/// What the email will contain (`POST /api/reminders/preview`).
class ReminderPreview {
  const ReminderPreview({
    required this.ledgerGuid,
    required this.party,
    required this.company,
    required this.recipients,
    required this.subject,
    required this.text,
    required this.bills,
    required this.missingBills,
    required this.total,
    required this.templateId,
    required this.templateName,
    required this.emailConfigured,
    required this.canSend,
    required this.problems,
  });
  final String ledgerGuid, party, company, subject, text, templateName;
  final List<String> recipients, missingBills, problems;
  final List<ReminderBill> bills;
  final num total;
  final int? templateId;
  final bool emailConfigured, canSend;

  static ReminderPreview fromJson(Object? o) {
    final Object? d = o is Map ? o['data'] : null;
    final Map<Object?, Object?> m = d is Map ? d : const <Object?, Object?>{};
    final Object? t = m['template'];
    final Object? bl = m['bills'];
    return ReminderPreview(
      ledgerGuid: _str(m['ledger_guid']),
      party: _str(m['party']),
      company: _str(m['company']),
      recipients: _strs(m['recipients']),
      subject: _str(m['subject']),
      text: _str(m['text']),
      bills: <ReminderBill>[
        if (bl is List)
          for (final Object? x in bl)
            if (x is Map) ReminderBill.fromJson(x),
      ],
      missingBills: _strs(m['missing_bills']),
      total: _num(m['total']),
      templateId: t is Map && t['id'] != null ? _num(t['id']).toInt() : null,
      templateName: t is Map ? _str(t['name']) : '',
      emailConfigured: m['email_configured'] == true,
      canSend: m['can_send'] == true,
      problems: _strs(m['problems']),
    );
  }
}

/// One reminder in the history (`reminder_log`).
class ReminderLog {
  const ReminderLog({
    required this.id,
    required this.ledgerGuid,
    required this.party,
    required this.recipients,
    required this.subject,
    required this.bills,
    required this.total,
    required this.status,
    this.error,
    this.attempts = 0,
    this.sentBy,
    this.createdAt,
    this.sentAt,
  });
  final int id;
  final String ledgerGuid, party, subject;
  final List<String> recipients;
  final List<ReminderBill> bills;
  final num total;

  /// `pending` | `accepted` (Microsoft 365 accepted it for delivery — not a
  /// delivery confirmation) | `failed`.
  final String status;
  final String? error, sentBy;
  final int attempts;
  final DateTime? createdAt, sentAt;

  bool get failed => status == 'failed';
  bool get accepted => status == 'accepted';

  static ReminderLog fromJson(Map<Object?, Object?> m) {
    final Object? bl = m['bills'];
    final String err = _str(m['error']);
    final String by = _str(m['sent_by']);
    return ReminderLog(
      id: _num(m['id']).toInt(),
      ledgerGuid: _str(m['ledger_guid']),
      party: _str(m['party']),
      recipients: _strs(m['recipients']),
      subject: _str(m['subject']),
      bills: <ReminderBill>[
        if (bl is List)
          for (final Object? x in bl)
            if (x is Map) ReminderBill.fromJson(x),
      ],
      total: _num(m['total']),
      status: _str(m['status']),
      error: err.isEmpty ? null : err,
      attempts: _num(m['attempts']).toInt(),
      sentBy: by.isEmpty ? null : by,
      createdAt: _date(m['created_at']),
      sentAt: _date(m['sent_at']),
    );
  }
}

/// Result of a send / retry, exactly as the server reported it.
class ReminderOutcome {
  const ReminderOutcome({
    required this.ok,
    required this.message,
    this.code,
    this.log,
    this.unknown = false,
  });

  /// Microsoft 365 accepted the email for delivery.
  final bool ok;
  final String message;

  /// Server reason when not sent (`send_failed`, `email_not_configured`,
  /// `duplicate`, `changed`, `nothing_pending`, `no_email`, `rate_limited`…).
  final String? code;
  final ReminderLog? log;

  /// No answer from the server: it may or may not have been sent.
  final bool unknown;
}
