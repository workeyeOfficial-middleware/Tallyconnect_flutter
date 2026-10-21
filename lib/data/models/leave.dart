// Leave management (`/api/leave/*`): the admin's settings (leave year,
// weekly off, half days, leave types, holidays), a member's balances and
// requests, the admin's approvals. Every rule is the server's; the app only
// shows it and sends requests / decisions.
library;

num _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
num? _nn(Object? v) => v == null ? null : _n(v);
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

/// "1", "1.5" — leave days as the admin and members read them.
String leaveDays(num d) =>
    d == d.roundToDouble() ? '${d.round()}' : d.toStringAsFixed(1);

/// "1 day" / "2.5 days".
String leaveDaysLabel(num d) => '${leaveDays(d)} ${d == 1 ? 'day' : 'days'}';

const List<String> kLeaveWeekdays = <String>[
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

const List<String> kLeaveMonths = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// The account's leave settings (admin's Leave settings).
class LeaveSettings {
  const LeaveSettings({
    this.enabled = false,
    this.yearStartMonth = 4,
    this.weeklyOff = const <int>[0],
    this.halfDay = true,
    this.backdateDays = 7,
    this.maxRequestDays = 30,
  });
  final bool enabled, halfDay;

  /// 1 = January … 12 = December.
  final int yearStartMonth;

  /// 0 = Sunday … 6 = Saturday.
  final List<int> weeklyOff;
  final int backdateDays, maxRequestDays;

  /// "Sunday", "Saturday, Sunday", "None".
  String get weeklyOffLabel {
    if (weeklyOff.isEmpty) return 'None';
    // Monday first, Sunday last (as a week is read here).
    final List<int> d = <int>[...weeklyOff]
      ..sort((int a, int b) => ((a + 6) % 7).compareTo((b + 6) % 7));
    return d.map((int x) => kLeaveWeekdays[x]).join(', ');
  }

  bool isWeeklyOff(DateTime d) => weeklyOff.contains(d.weekday % 7);

  static LeaveSettings fromJson(Object? o) {
    final Map<Object?, Object?> m = _map(o);
    return LeaveSettings(
      enabled: m['enabled'] == true,
      yearStartMonth: _n(m['year_start_month'] ?? 4).toInt().clamp(1, 12),
      weeklyOff: <int>[
        for (final Object? x in _list(m['weekly_off'])) _n(x).toInt(),
      ],
      halfDay: m['half_day'] != false,
      backdateDays: _n(m['backdate_days'] ?? 7).toInt(),
      maxRequestDays: _n(m['max_request_days'] ?? 30).toInt(),
    );
  }
}

/// A leave type (Casual, Sick, …). [yearlyQuota] null: no limit.
class LeaveType {
  const LeaveType({
    required this.id,
    required this.name,
    this.yearlyQuota,
    this.paid = true,
    this.carryForward = false,
    this.maxCarry,
    this.active = true,
  });
  final int id;
  final String name;
  final num? yearlyQuota, maxCarry;
  final bool paid, carryForward, active;

  /// "12 days a year · Paid · Carries forward (max 5)".
  String get summary => <String>[
    yearlyQuota == null ? 'No limit' : '${leaveDaysLabel(yearlyQuota!)} a year',
    paid ? 'Paid' : 'Unpaid',
    if (carryForward)
      maxCarry == null
          ? 'Carries forward'
          : 'Carries forward (max ${leaveDays(maxCarry!)})',
    if (!active) 'Hidden',
  ].join(' · ');

  static LeaveType fromJson(Object? o) {
    final Map<Object?, Object?> m = _map(o);
    return LeaveType(
      id: _n(m['id']).toInt(),
      name: _s(m['name']),
      yearlyQuota: _nn(m['yearly_quota']),
      paid: m['paid'] != false,
      carryForward: m['carry_forward'] == true,
      maxCarry: _nn(m['max_carry']),
      active: m['active'] != false,
    );
  }

  static List<LeaveType> list(Object? v) => <LeaveType>[
    for (final Object? x in _list(v)) LeaveType.fromJson(x),
  ];
}

class LeaveHoliday {
  const LeaveHoliday({required this.date, required this.name});
  final DateTime? date;
  final String name;

  static List<LeaveHoliday> list(Object? v) => <LeaveHoliday>[
    for (final Object? x in _list(v))
      LeaveHoliday(date: _d(_map(x)['date']), name: _s(_map(x)['name'])),
  ];
}

/// A leave year: 1 Apr 2026 – 31 Mar 2027, "2026-27".
class LeaveYear {
  const LeaveYear({this.from, this.to, this.label = ''});
  final DateTime? from, to;
  final String label;

  static LeaveYear fromJson(Object? o) {
    final Map<Object?, Object?> m = _map(o);
    return LeaveYear(
      from: _d(m['from']),
      to: _d(m['to']),
      label: _s(m['label']),
    );
  }
}

/// One leave type's balance in a leave year. [available] / [entitled]
/// null: no limit.
class LeaveBalance {
  const LeaveBalance({
    required this.typeId,
    required this.name,
    required this.paid,
    required this.active,
    this.quota,
    this.carried = 0,
    this.entitled,
    this.used = 0,
    this.pending = 0,
    this.available,
  });
  final int typeId;
  final String name;
  final bool paid, active;
  final num? quota, entitled, available;
  final num carried, used, pending;

  bool get unlimited => entitled == null;

  static List<LeaveBalance> list(Object? v) => <LeaveBalance>[
    for (final Object? x in _list(v))
      LeaveBalance(
        typeId: _n(_map(x)['type_id']).toInt(),
        name: _s(_map(x)['name']),
        paid: _map(x)['paid'] != false,
        active: _map(x)['active'] != false,
        quota: _nn(_map(x)['quota']),
        carried: _n(_map(x)['carried']),
        entitled: _nn(_map(x)['entitled']),
        used: _n(_map(x)['used']),
        pending: _n(_map(x)['pending']),
        available: _nn(_map(x)['available']),
      ),
  ];
}

/// `pending` (waiting for the admin), `approved`, `rejected`, `cancelled`.
enum LeaveStatus { pending, approved, rejected, cancelled }

LeaveStatus leaveStatusOf(Object? v) => switch ('$v') {
  'approved' => LeaveStatus.approved,
  'rejected' => LeaveStatus.rejected,
  'cancelled' => LeaveStatus.cancelled,
  _ => LeaveStatus.pending,
};

extension LeaveStatusLabel on LeaveStatus {
  String get label => switch (this) {
    LeaveStatus.pending => 'Waiting for approval',
    LeaveStatus.approved => 'Approved',
    LeaveStatus.rejected => 'Rejected',
    LeaveStatus.cancelled => 'Cancelled',
  };
  String get key => name;
}

/// A leave request.
class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.userId,
    required this.typeId,
    required this.typeName,
    required this.from,
    required this.to,
    required this.days,
    required this.status,
    this.username = '',
    this.halfDay,
    this.reason,
    this.decidedAt,
    this.decisionNote,
    this.createdAt,
  });
  final int id, typeId;
  final String userId, username, typeName;
  final DateTime? from, to, decidedAt, createdAt;

  /// `first` / `second` half of [from]; null: whole days.
  final String? halfDay;
  final num days;
  final LeaveStatus status;
  final String? reason, decisionNote;

  bool get pending => status == LeaveStatus.pending;

  /// "First half" / "Second half" / null.
  String? get halfLabel => switch (halfDay) {
    'first' => 'First half',
    'second' => 'Second half',
    _ => null,
  };

  /// Approved leave covering [d].
  bool covers(DateTime d) {
    if (status != LeaveStatus.approved || from == null || to == null) {
      return false;
    }
    final DateTime x = DateTime(d.year, d.month, d.day);
    return !x.isBefore(from!) && !x.isAfter(to!);
  }

  static LeaveRequest fromJson(Object? o) {
    final Map<Object?, Object?> m = _map(o);
    String? text(Object? v) => _s(v).trim().isEmpty ? null : _s(v).trim();
    return LeaveRequest(
      id: _n(m['id']).toInt(),
      userId: _s(m['user_id']),
      username: _s(m['username']),
      typeId: _n(m['type_id']).toInt(),
      typeName: _s(m['type_name']),
      from: _d(m['from']),
      to: _d(m['to']),
      halfDay: text(m['half_day']),
      days: _n(m['days']),
      reason: text(m['reason']),
      status: leaveStatusOf(m['status']),
      decidedAt: _t(m['decided_at']),
      decisionNote: text(m['decision_note']),
      createdAt: _t(m['created_at']),
    );
  }

  static List<LeaveRequest> list(Object? v) => <LeaveRequest>[
    for (final Object? x in _list(v)) LeaveRequest.fromJson(x),
  ];
}

/// What today is for this login: `working`, `holiday` or `weekly_off`,
/// and the approved leave covering it.
class LeaveToday {
  const LeaveToday({this.date, this.kind = 'working', this.leave});
  final DateTime? date;
  final String kind;
  final LeaveRequest? leave;
}

/// `GET /api/leave/me` (member) or `/api/leave/team/:id` (admin): the
/// leave year with balances, requests and holidays.
class LeaveMe {
  const LeaveMe({
    required this.enabled,
    required this.isAdmin,
    required this.settings,
    this.year = const LeaveYear(),
    this.balances = const <LeaveBalance>[],
    this.requests = const <LeaveRequest>[],
    this.holidays = const <LeaveHoliday>[],
    this.today,
    this.userId,
    this.username = '',
  });
  final bool enabled, isAdmin;
  final LeaveSettings settings;
  final LeaveYear year;
  final List<LeaveBalance> balances;
  final List<LeaveRequest> requests;
  final List<LeaveHoliday> holidays;
  final LeaveToday? today;

  /// The member, on the admin's view.
  final String? userId;
  final String username;

  static LeaveMe fromJson(Object? o) {
    final Map<Object?, Object?> m = _map(o);
    final Map<Object?, Object?> t = _map(m['today']);
    final Map<Object?, Object?> who = _map(m['member']);
    final LeaveSettings s = LeaveSettings.fromJson(m['settings']);
    return LeaveMe(
      // The admin's view of a member has no `enabled`; settings say it.
      enabled: m.containsKey('enabled') ? m['enabled'] == true : s.enabled,
      isAdmin: m['is_admin'] == true,
      settings: s,
      year: LeaveYear.fromJson(m['year']),
      balances: LeaveBalance.list(m['balances']),
      requests: LeaveRequest.list(m['requests']),
      holidays: LeaveHoliday.list(m['holidays']),
      today: m['today'] is Map
          ? LeaveToday(
              date: _d(t['date']),
              kind: _s(t['kind']).isEmpty ? 'working' : _s(t['kind']),
              leave: t['leave'] is Map
                  ? LeaveRequest.fromJson(t['leave'])
                  : null,
            )
          : null,
      userId: who['user_id'] == null ? null : _s(who['user_id']),
      username: _s(who['username']),
    );
  }
}

/// `GET /api/leave/settings` (admin): settings, types, the leave year's
/// holidays.
class LeaveAdmin {
  const LeaveAdmin({
    required this.settings,
    this.year = const LeaveYear(),
    this.types = const <LeaveType>[],
    this.holidays = const <LeaveHoliday>[],
  });
  final LeaveSettings settings;
  final LeaveYear year;
  final List<LeaveType> types;
  final List<LeaveHoliday> holidays;

  LeaveAdmin copyWith({
    LeaveSettings? settings,
    List<LeaveType>? types,
    List<LeaveHoliday>? holidays,
  }) => LeaveAdmin(
    settings: settings ?? this.settings,
    year: year,
    types: types ?? this.types,
    holidays: holidays ?? this.holidays,
  );

  static LeaveAdmin fromJson(Object? o) {
    final Map<Object?, Object?> m = _map(o);
    return LeaveAdmin(
      settings: LeaveSettings.fromJson(m['settings']),
      year: LeaveYear.fromJson(m['year']),
      types: LeaveType.list(m['types']),
      holidays: LeaveHoliday.list(m['holidays']),
    );
  }
}

/// `GET /api/leave/calendar`: approved leave, holidays and weekly off in a
/// range (a member: own leave; the admin: the team's).
class LeaveCalendar {
  const LeaveCalendar({
    this.from,
    this.to,
    this.weeklyOff = const <int>[],
    this.holidays = const <LeaveHoliday>[],
    this.leaves = const <LeaveRequest>[],
  });
  final DateTime? from, to;
  final List<int> weeklyOff;
  final List<LeaveHoliday> holidays;
  final List<LeaveRequest> leaves;

  LeaveHoliday? holidayOn(DateTime d) => holidays
      .where(
        (LeaveHoliday h) =>
            h.date != null &&
            h.date!.year == d.year &&
            h.date!.month == d.month &&
            h.date!.day == d.day,
      )
      .firstOrNull;

  /// Approved leave of [userId] (or anyone's) on [d].
  LeaveRequest? leaveOn(DateTime d, {String? userId}) => leaves
      .where(
        (LeaveRequest r) =>
            r.covers(d) && (userId == null || r.userId == userId),
      )
      .firstOrNull;

  bool weeklyOffOn(DateTime d) => weeklyOff.contains(d.weekday % 7);

  static LeaveCalendar fromJson(Object? o) {
    final Map<Object?, Object?> m = _map(o);
    return LeaveCalendar(
      from: _d(m['from']),
      to: _d(m['to']),
      weeklyOff: <int>[
        for (final Object? x in _list(m['weekly_off'])) _n(x).toInt(),
      ],
      holidays: LeaveHoliday.list(m['holidays']),
      leaves: LeaveRequest.list(m['leaves']),
    );
  }
}
