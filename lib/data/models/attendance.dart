// Sales team check-in / check-out (`/api/attendance/*`): a member's day and
// history, the admin's team view. Times are the server's; days are India
// dates. The app only shows them and sends check-in / check-out / ping.
library;

num _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
String _s(Object? v) => v == null ? '' : '$v';
DateTime? _t(Object? v) =>
    v == null ? null : DateTime.tryParse('$v')?.toLocal();
DateTime? _d(Object? v) {
  final DateTime? x = DateTime.tryParse(_s(v));
  return x == null ? null : DateTime(x.year, x.month, x.day);
}

List<Object?> _list(Object? v) => v is List ? v : const <Object?>[];
Map<Object?, Object?> _map(Object? v) =>
    v is Map ? v : const <Object?, Object?>{};

/// A person's state for a day: `active` (checked in, app seen in the last
/// 15 minutes), `idle` (checked in, not seen since), `checked_out` (worked,
/// nothing open) or `absent` (no check-in).
enum AttStatus { active, idle, checkedOut, absent }

AttStatus attStatusOf(Object? v) => switch ('$v') {
  'active' => AttStatus.active,
  'idle' => AttStatus.idle,
  'checked_out' => AttStatus.checkedOut,
  _ => AttStatus.absent,
};

extension AttStatusLabel on AttStatus {
  String get label => switch (this) {
    AttStatus.active => 'Active',
    AttStatus.idle => 'Checked in · idle',
    AttStatus.checkedOut => 'Checked out',
    AttStatus.absent => 'Not checked in',
  };
  bool get checkedIn => this == AttStatus.active || this == AttStatus.idle;
}

/// One check-in … check-out (open while [checkOut] is null).
class AttSession {
  const AttSession({
    required this.id,
    required this.date,
    required this.checkIn,
    required this.checkOut,
    required this.lastSeen,
    required this.minutes,
    this.inNote,
    this.outNote,
    this.closedBy,
  });
  final int id;
  final DateTime? date;
  final DateTime? checkIn, checkOut, lastSeen;
  final int minutes;
  final String? inNote, outNote;

  /// `user`, `auto` (closed at 23:59 when the check-out was forgotten) or
  /// `admin`.
  final String? closedBy;

  bool get open => checkOut == null;
  bool get auto => closedBy == 'auto';

  static AttSession fromJson(Object? o) {
    final Map<Object?, Object?> m = _map(o);
    String? note(Object? v) => _s(v).trim().isEmpty ? null : _s(v).trim();
    return AttSession(
      id: _n(m['id']).toInt(),
      date: _d(m['work_date']),
      checkIn: _t(m['check_in_at']),
      checkOut: _t(m['check_out_at']),
      lastSeen: _t(m['last_seen_at']),
      minutes: _n(m['minutes']).toInt(),
      inNote: note(m['in_note']),
      outNote: note(m['out_note']),
      closedBy: m['closed_by'] == null ? null : _s(m['closed_by']),
    );
  }

  static List<AttSession> list(Object? v) => <AttSession>[
    for (final Object? x in _list(v)) AttSession.fromJson(x),
  ];
}

/// `GET /api/attendance/me`: may this login check in, and today so far.
class AttMe {
  const AttMe({
    required this.enabled,
    required this.isAdmin,
    required this.status,
    required this.date,
    required this.sessions,
    required this.totalMinutes,
    this.serverTime,
  });
  final bool enabled, isAdmin;
  final AttStatus status;
  final DateTime? date, serverTime;
  final List<AttSession> sessions;
  final int totalMinutes;

  AttSession? get open => sessions.where((AttSession s) => s.open).firstOrNull;
  bool get checkedIn => open != null;

  static AttMe fromJson(Object? o) {
    final Map<Object?, Object?> m = _map(o);
    return AttMe(
      enabled: m['enabled'] == true,
      isAdmin: m['is_admin'] == true,
      status: attStatusOf(m['status']),
      date: _d(m['date']),
      serverTime: _t(m['server_time']),
      sessions: AttSession.list(m['sessions']),
      totalMinutes: _n(m['total_minutes']).toInt(),
    );
  }
}

/// One day of a history: first in, last out, total time, sessions.
class AttDay {
  const AttDay({
    required this.date,
    required this.firstIn,
    required this.lastOut,
    required this.totalMinutes,
    required this.autoClosed,
    required this.sessions,
  });
  final DateTime? date, firstIn, lastOut;
  final int totalMinutes;
  final bool autoClosed;
  final List<AttSession> sessions;

  static List<AttDay> list(Object? v) => <AttDay>[
    for (final Object? x in _list(v))
      AttDay(
        date: _d(_map(x)['date']),
        firstIn: _t(_map(x)['first_in']),
        lastOut: _t(_map(x)['last_out']),
        totalMinutes: _n(_map(x)['total_minutes']).toInt(),
        autoClosed: _map(x)['auto_closed'] == true,
        sessions: AttSession.list(_map(x)['sessions']),
      ),
  ];
}

/// A history (`/me/history` or `/team/:id/history`).
class AttHistory {
  const AttHistory({
    required this.from,
    required this.to,
    required this.days,
    this.userId,
    this.username = '',
  });
  final DateTime? from, to;
  final List<AttDay> days;
  final String? userId;
  final String username;

  int get totalMinutes =>
      days.fold<int>(0, (int a, AttDay d) => a + d.totalMinutes);

  static AttHistory fromJson(Object? o) {
    final Map<Object?, Object?> m = _map(o);
    final Map<Object?, Object?> who = _map(m['member']);
    return AttHistory(
      from: _d(m['from']),
      to: _d(m['to']),
      days: AttDay.list(m['days']),
      userId: who['user_id'] == null ? null : _s(who['user_id']),
      username: _s(who['username']),
    );
  }
}

/// One person on the admin's team view.
class AttMember {
  const AttMember({
    required this.userId,
    required this.username,
    required this.email,
    required this.onTeam,
    required this.status,
    required this.firstIn,
    required this.lastOut,
    required this.lastSeen,
    required this.totalMinutes,
    required this.autoClosed,
    required this.sessions,
  });
  final String userId, username, email;
  final bool onTeam, autoClosed;
  final AttStatus status;
  final DateTime? firstIn, lastOut, lastSeen;
  final int totalMinutes;
  final List<AttSession> sessions;
}

/// `GET /api/attendance/team?date=`: everyone's status that day.
class AttTeam {
  const AttTeam({
    required this.date,
    required this.company,
    required this.members,
  });
  final DateTime? date;
  final String company;
  final List<AttMember> members;

  int count(AttStatus s) =>
      members.where((AttMember m) => m.status == s).length;
  int get checkedIn =>
      members.where((AttMember m) => m.status.checkedIn).length;

  static AttTeam fromJson(Object? o) {
    final Map<Object?, Object?> m = _map(o);
    return AttTeam(
      date: _d(m['date']),
      company: _s(m['company']),
      members: <AttMember>[
        for (final Object? x in _list(m['members']))
          AttMember(
            userId: _s(_map(x)['user_id']),
            username: _s(_map(x)['username']),
            email: _s(_map(x)['email']),
            onTeam: _map(x)['on_team'] != false,
            status: attStatusOf(_map(x)['status']),
            firstIn: _t(_map(x)['first_in']),
            lastOut: _t(_map(x)['last_out']),
            lastSeen: _t(_map(x)['last_seen_at']),
            totalMinutes: _n(_map(x)['total_minutes']).toInt(),
            autoClosed: _map(x)['auto_closed'] == true,
            sessions: AttSession.list(_map(x)['sessions']),
          ),
      ],
    );
  }
}

/// "7h 05m" / "45m".
String hoursMinutes(int minutes) {
  final int h = minutes ~/ 60, m = minutes % 60;
  return h == 0 ? '${m}m' : '${h}h ${m.toString().padLeft(2, '0')}m';
}
