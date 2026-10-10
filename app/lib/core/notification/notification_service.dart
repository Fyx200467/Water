import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// PRD §2.4 智能提醒 — 本地定时通知
/// Android: flutter_local_notifications + timezone
/// iOS: APNs 远程兜底（M5 服务端接入），本地通知同样生效
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> _ensureInit() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  /// PRD §2.1 首次启动申请通知权限
  /// 返回 true 表示已授权
  static Future<bool> requestPermission() async {
    await _ensureInit();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
  }

  ///PRD §2.4 按设置重排全部提醒（先取消再排）
  /// times 为 "HH:mm" 列表；dnd 窗口内的时间不排（免打扰）
  static Future<void> reschedule({
    required bool enabled,
    required List<String> times,
    required String message,
    String? dndStart, // "HH:mm" or null
    String? dndEnd,
  }) async {
    await _ensureInit();
    await _plugin.cancelAll();
    if (!enabled) return;

    for (final t in times) {
      final parts = t.split(':');
      if (parts.length != 2) continue;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) continue;
      if (_inDnd(hour, minute, dndStart, dndEnd)) continue;

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder',
          '每日喝水提醒',
          channelDescription: '按设定时间提醒你喝水',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(message),
        ),
      );
      await _plugin.zonedSchedule(
        _idFor(hour, minute),
        '该喝水啦',
        message,
        _nextInstanceOf(hour, minute),
        details,
        androidScheduleMode: AndroidScheduleMode.inexact,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  static Future<void> cancelAll() async {
    await _ensureInit();
    await _plugin.cancelAll();
  }

  static int _idFor(int hour, int minute) => hour * 100 + minute;

  /// 免打扰判断：支持跨午夜窗口（如 22:00-07:00）
  static bool _inDnd(int hour, int minute, String? start, String? end) {
    if (start == null || end == null) return false;
    final sp = start.split(':'), ep = end.split(':');
    if (sp.length != 2 || ep.length != 2) return false;
    final sh = int.tryParse(sp[0]), sm = int.tryParse(sp[1]);
    final eh = int.tryParse(ep[0]), em = int.tryParse(ep[1]);
    if (sh == null || sm == null || eh == null || em == null) return false;
    final cur = hour * 60 + minute;
    final s = sh * 60 + sm, e = eh * 60 + em;
    if (s <= e) return cur >= s && cur <= e;
    return cur >= s || cur <= e; // 跨午夜
  }

  /// 构造下一次触发时刻（零依赖时区方案）：
  /// 设备本地墙钟 W 对应 UTC 瞬间 = W - offset。
  /// 用 tz.UTC 构造"UTC 墙钟 = W"再减 offset，即得真实瞬间。
  /// matchDateTimeComponents.time 使其每日重复。
  static tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    var scheduled = tz.TZDateTime(
      tz.UTC, now.year, now.month, now.day, hour, minute,
    ).subtract(offset);
    if (!scheduled.isAfter(DateTime.now().toUtc())) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
