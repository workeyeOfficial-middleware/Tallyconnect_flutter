// Device notifications for outstanding-bill reminders and payment alerts:
// scheduled with the OS alarm manager, so they ring at the set time even
// when the app is closed (and are re-armed after a reboot by the plugin's
// boot receiver). The app controller only talks to [ReminderAlarms]; tests
// use [NoReminderAlarms].
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// A tapped notification (or one of its buttons).
class AlarmTap {
  const AlarmTap(this.payload, [this.action]);

  /// `rem:<reminder id>` or `auto:<bill key>`.
  final String payload;

  /// `done` / `snooze`, or null for a tap on the notification itself.
  final String? action;
}

/// One notification to ring at [at] (local time).
class AlarmSpec {
  const AlarmSpec({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
    this.actions = true,
  });
  final int id;
  final DateTime at;
  final String title, body, payload;

  /// Mark done / Snooze buttons (bill reminders).
  final bool actions;
}

/// Result of asking the user for notification permissions.
enum AlarmAccess {
  /// Notifications allowed and exact alarms allowed: rings on time.
  exact,

  /// Notifications allowed, exact alarms refused: may ring a little late.
  inexact,

  /// Notifications blocked: nothing can be shown.
  blocked,
}

/// Stable 31-bit notification id for [key] (FNV-1a).
int alarmId(String key) {
  int h = 0x811c9dc5;
  for (final int c in key.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h & 0x7FFFFFFF;
}

abstract class ReminderAlarms {
  /// Taps on notifications while the app runs.
  Stream<AlarmTap> get taps;

  /// Sets up the plugin and time zone; returns the tap that launched the
  /// app (closed app → notification tap), if any.
  Future<AlarmTap?> init();

  /// Asks for notification + exact-alarm permission (once per need).
  Future<AlarmAccess> requestAccess();

  /// Schedules [a], replacing a pending one with the same id.
  Future<void> schedule(AlarmSpec a);

  Future<void> cancel(int id);
}

/// No device notifications (tests, sample data on desktop).
class NoReminderAlarms implements ReminderAlarms {
  NoReminderAlarms();

  /// Scheduled alarms by id (what a device would ring), for tests.
  final Map<int, AlarmSpec> pending = <int, AlarmSpec>{};
  final StreamController<AlarmTap> _taps =
      StreamController<AlarmTap>.broadcast();

  /// Simulates a tap on a notification.
  void tap(AlarmTap t) => _taps.add(t);

  @override
  Stream<AlarmTap> get taps => _taps.stream;
  @override
  Future<AlarmTap?> init() async => null;
  @override
  Future<AlarmAccess> requestAccess() async => AlarmAccess.exact;
  @override
  Future<void> schedule(AlarmSpec a) async => pending[a.id] = a;
  @override
  Future<void> cancel(int id) async => pending.remove(id);
}

/// Android / iOS notifications via flutter_local_notifications.
class DeviceReminderAlarms implements ReminderAlarms {
  DeviceReminderAlarms();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<AlarmTap> _taps =
      StreamController<AlarmTap>.broadcast();
  Future<AlarmTap?>? _ready;
  bool _exact = false;

  /// Channel: high importance (heads-up), own chime, alarm-style audio.
  /// Android fixes a channel's sound when it is first created, so a new
  /// sound needs a new channel id.
  static const String channelId = 'tc_reminders_v1';

  @override
  Stream<AlarmTap> get taps => _taps.stream;

  @override
  Future<AlarmTap?> init() => _ready ??= _init();

  Future<AlarmTap?> _init() async {
    tzdata.initializeTimeZones();
    try {
      final TimezoneInfo local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      // Unknown zone name: keep UTC offsets correct via DateTime below.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_reminder'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse r) {
        final String? p = r.payload;
        if (p != null && p.isNotEmpty) _taps.add(AlarmTap(p, r.actionId));
      },
    );
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    _exact = await android?.canScheduleExactNotifications() ?? true;
    final NotificationAppLaunchDetails? launch = await _plugin
        .getNotificationAppLaunchDetails();
    final NotificationResponse? r = launch?.notificationResponse;
    if ((launch?.didNotificationLaunchApp ?? false) &&
        r != null &&
        (r.payload ?? '').isNotEmpty) {
      return AlarmTap(r.payload!, r.actionId);
    }
    return null;
  }

  @override
  Future<AlarmAccess> requestAccess() async {
    await init();
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      bool on = await android.areNotificationsEnabled() ?? false;
      if (!on) on = await android.requestNotificationsPermission() ?? false;
      if (!on) return AlarmAccess.blocked;
      _exact = await android.canScheduleExactNotifications() ?? false;
      if (!_exact) {
        await android.requestExactAlarmsPermission();
        _exact = await android.canScheduleExactNotifications() ?? false;
      }
      return _exact ? AlarmAccess.exact : AlarmAccess.inexact;
    }
    final IOSFlutterLocalNotificationsPlugin? ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final bool ok =
          await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
      _exact = ok;
      return ok ? AlarmAccess.exact : AlarmAccess.blocked;
    }
    return AlarmAccess.exact;
  }

  @override
  Future<void> schedule(AlarmSpec a) async {
    await init();
    final tz.TZDateTime when = tz.TZDateTime.from(a.at, tz.local);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id: a.id,
      scheduledDate: when,
      title: a.title,
      body: a.body,
      payload: a.payload,
      // Exact (alarm-style) when allowed; otherwise the OS may batch it by
      // a few minutes. Both still ring with the app closed / phone idle.
      androidScheduleMode: _exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Bill reminders',
          channelDescription:
              'Outstanding-bill reminders and payment alerts at the time you set',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          sound: const RawResourceAndroidNotificationSound('tc_reminder'),
          audioAttributesUsage: AudioAttributesUsage.alarm,
          enableVibration: true,
          vibrationPattern: Int64List.fromList(<int>[0, 400, 250, 400]),
          visibility: NotificationVisibility.public,
          color: const Color(0xFF8C1D3F),
          styleInformation: BigTextStyleInformation(a.body),
          ticker: a.title,
          actions: a.actions
              ? const <AndroidNotificationAction>[
                  AndroidNotificationAction(
                    'done',
                    'Mark done',
                    showsUserInterface: true,
                  ),
                  AndroidNotificationAction(
                    'snooze',
                    'Snooze 10 min',
                    showsUserInterface: true,
                  ),
                ]
              : null,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
    );
  }

  @override
  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id: id);
  }
}
