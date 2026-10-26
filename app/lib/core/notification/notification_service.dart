import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../shared/models/preferred_unit.dart';

/// PRD §2.4 智能提醒 — 本地定时通知
/// Android: flutter_local_notifications + timezone
/// iOS: APNs 远程兜底（M5 服务端接入），本地通知同样生效
///
/// 调度模型（v2）：不再用 matchDateTimeComponents 每日重复（无法按
/// 星期过滤、无法"达到目标停止"），改为**未来若干天逐日逐槽一次性排程**：
/// - 每天先按「星期几」过滤，再排固定时间槽 + 间隔提醒槽（均为 one-shot）
/// - 今日剩余槽位结合实时数据智能裁剪：已达目标（达标停止）直接跳过；
///   间隔槽前 30 分钟内喝过水的跳过（"仅在你忘记喝水时才发送"）
/// - 排程时机：冷启动 / 回前台 / 当日记录或目标变化 / 设置页任何变更，
///   每轮只清理失效槽位再重排（绝不用 cancelAll，否则通知栏里已展示的
///   提醒会被一并抹掉），通知内容（剩余水量等）随之刷新
/// - 排程天数自适应：Android 12+ 约 500 个闹钟上限，按每日槽位数折算
///   天数（间隔越小排得越近，须常回 App 续排——每次打开都会重排）
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// iOS 待发本地通知上限 64 条，留 4 条余量（超出的会被系统静默丢弃）
  static const int _iosPendingLimit = 60;

  /// 日期键（同日不同月/年也可比较，用于 iOS 槽位按时间排序）
  static int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static Future<void> _ensureInit() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    // 状态栏小图标必须是纯白剪影；用 mipmap 彩色图标会被压成小色块
    const androidInit = AndroidInitializationSettings('ic_stat_water');
    // iOS：初始化时不弹权限框（由引导页/提醒页的 requestPermission 显式申请），
    // 但保留前台展示（App 正在用时到点同样弹横幅 + 响铃）
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );
    try {
      await _plugin.initialize(initSettings);
    } on PlatformException catch (e) {
      // 资源被 release 压缩器裁掉时兜底：退回 mipmap 启动图标，
      // 保证初始化成功（否则所有调用都会抛 invalid_icon）
      debugPrint('[notif] init failed: $e, fallback to mipmap');
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: darwinInit,
        ),
      );
    }
    // 插件只会在 show() 时自动创建渠道；本 App 仅用 zonedSchedule，
    // 渠道不存在时闹钟触发后系统会直接丢弃通知，故初始化时预建
    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'daily_reminder',
        '每日喝水提醒',
        description: '按设定时间提醒你喝水',
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'interval_reminder',
        '间隔喝水提醒',
        description: '每隔固定时间提醒你喝水',
        importance: Importance.high,
      ),
    );
    _initialized = true;
  }

  /// PRD §2.1 首次启动申请通知权限
  /// 返回 true 表示已授权
  static Future<bool> requestPermission() async {
    await _ensureInit();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      try {
        final granted = await android.requestNotificationsPermission();
        return granted ?? false;
      } on PlatformException catch (e) {
        // 连点开关时插件会并发发起权限请求，第二次抛
        // permissionRequestInProgress——此时读当前授权状态兜底
        if (e.code == 'permissionRequestInProgress') {
          return await android.areNotificationsEnabled() ?? false;
        }
        rethrow;
      }
    }
    // iOS：首次调用弹系统权限框，之后调用只返回当前授权状态
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      try {
        final granted =
            await ios.requestPermissions(alert: true, badge: true, sound: true);
        return granted ?? false;
      } on PlatformException catch (e) {
        debugPrint('[notif] request ios permission failed: $e');
        return false;
      }
    }
    return true;
  }

  /// 随机抽一张角色卡并栅格化为 PNG，作为通知右侧大图标
  static String? _charIconPath;
  static final math.Random _rand = math.Random();

  static Future<String?> _characterIcon() async {
    final cached = _charIconPath;
    if (cached != null && File(cached).existsSync()) return cached;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final cards = manifest
          .listAssets()
          .where((a) =>
              a.startsWith('assets/images/characters/') && a.endsWith('.svg'))
          .toList();
      if (cards.isEmpty) return null;
      final info = await vg.loadPicture(
        SvgAssetLoader(cards[_rand.nextInt(cards.length)]),
        null,
      );
      const iconSize = 192;
      final scale = iconSize / math.max(info.size.width, info.size.height);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(scale, scale);
      canvas.drawPicture(info.picture);
      final image = await recorder.endRecording().toImage(iconSize, iconSize);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return null;
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/notif_character.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      _charIconPath = file.path;
      return file.path;
    } catch (e) {
      debugPrint('[notif] character icon failed: $e');
      return null;
    }
  }

  // ==================== 调度 ====================

  /// 记录的「相对今天 0 点分钟数」。
  /// 重置时间 > 0 时，逻辑日「今天」可能落在自然日昨天：这些记录返回负数，
  /// 智能跳过才能正确判断「30 分钟内是否喝过水」而不是把昨晚的分钟数
  /// 误当成今夜同一时刻。
  static int relativeMinute(DateTime now, DateTime t) {
    final m = t.hour * 60 + t.minute;
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? m : m - 1440;
  }

  ///PRD §2.4 按全部设置重排提醒（先取消再排）
  ///
  /// [times] 固定时间槽（"HH:mm"，自定义提醒页已开启的时间）
  /// [intervalMinutes] 非空时在 [windowStartMin, windowEndMin) 窗口内
  /// 按间隔铺槽（智能提醒）；[weekdays] 生效星期（1=周一 … 7=周日）
  /// [todayDrinkMinutes] 今日饮水记录的 drankAt 分钟数（智能跳过用）
  static Future<void> reschedule({
    required bool enabled,
    required List<String> times,
    required String message,
    String? customMessage,
    int? intervalMinutes,
    int? windowStartMin,
    int? windowEndMin,
    Set<int> weekdays = const {1, 2, 3, 4, 5, 6, 7},
    List<int> todayDrinkMinutes = const [],
    required int todayEffectiveMl,
    required int goalMl,
    bool stopAtGoal = false,
    bool progressTitle = false,
    bool motivationalTitle = false,
    bool waterFacts = false,
    bool stickers = false,
  }) async {
    await _ensureInit();
    if (!enabled) {
      // 关闭提醒：已排定的闹钟与已展示的通知一并清除
      await _plugin.cancelAll();
      return;
    }

    final now = DateTime.now();
    final goalReached = stopAtGoal && goalMl > 0 && todayEffectiveMl >= goalMl;
    final remainingMl = math.max(0, goalMl - todayEffectiveMl);
    // vivo 等厂商会在后台冻结应用，普通闹钟广播被挂起（extras 被剥离），
    // 到点收不到通知；改用 setAlarmClock，系统按"闹钟"对待，不受后台
    // 冻结与 Doze 影响。
    //
    // 注意：setAlarmClock 也属于精确闹钟，Android 12+ 需要
    // SCHEDULE_EXACT_ALARM 被授予（Android 14 起新装默认关闭）。
    // 未授予时插件抛 exact_alarms_not_permitted，整轮排程会全部失败、
    // 一条提醒都收不到——此时降级为 inexactAllowWhileIdle（无需权限，
    // 可能被 Doze 延后几分钟，但绝不会静默丢失）。
    var scheduleMode = AndroidScheduleMode.alarmClock;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final exactAllowed = await android?.canScheduleExactNotifications();
      if (exactAllowed == false) {
        scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
      }
    } catch (e) {
      debugPrint('[notif] read exact-alarm state failed: $e');
    }

    final slots = _collectSlots(
      now: now,
      times: times,
      intervalMinutes: intervalMinutes,
      windowStartMin: windowStartMin,
      windowEndMin: windowEndMin,
      weekdays: weekdays,
      todayDrinkMinutes: todayDrinkMinutes,
      goalReached: goalReached,
    );
    // iOS 系统只保留最早的 64 条待发本地通知（超出的会被静默丢弃），
    // 故按时间排序后只保留最近的一批；每次打开 App / 记录变化都会重排补足
    if (Platform.isIOS && slots.length > _iosPendingLimit) {
      slots.sort((a, b) {
        final byDay = _dayKey(a.date).compareTo(_dayKey(b.date));
        return byDay != 0 ? byDay : a.minute.compareTo(b.minute);
      });
      slots.removeRange(_iosPendingLimit, slots.length);
    }

    // ---- 只清理已失效的排程，不动通知栏里已展示的通知 ----
    // 注意：不能用 cancelAll()，它会把刚弹出的提醒一并抹掉（通知自己消失）
    final newIds = <int>{
      for (final s in slots) s.id,
    };
    final pending = await () async {
      // 清理步骤失败不能阻断后续排程（否则一条旧槽位异常会让整轮通知全丢）
      try {
        return await _plugin.pendingNotificationRequests();
      } catch (e) {
        debugPrint('[notif] read pending failed: $e');
        return const <PendingNotificationRequest>[];
      }
    }();
    for (final p in pending) {
      if (!newIds.contains(p.id)) {
        await _plugin.cancel(p.id);
      }
    }
    if (slots.isEmpty) return;

    // 贴纸开关 → 随机角色卡栅格化后作为通知右侧大图标（每轮重排换一张）
    // iOS 没有通知大图标位，跳过渲染
    final iconPath =
        stickers && !Platform.isIOS ? await _characterIcon() : null;

    // ---- 逐槽排程（并行提交，缩短整轮重排耗时）----
    final futures = <Future<void>>[];
    for (final s in slots) {
      final date = s.date;
      final m = s.minute;
      final isInterval = s.isInterval;
      final id = s.id;
      final (String title, String body) = _composeContent(
        slotId: id,
        message: message,
        customMessage: customMessage,
        progressTitle: progressTitle,
        motivationalTitle: motivationalTitle,
        waterFacts: waterFacts,
        // 未来天的通知不显示"今天的"剩余量，否则会给出过期进度
        remainingMl: date.difference(now).inDays == 0 ? remainingMl : null,
      );
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          isInterval ? 'interval_reminder' : 'daily_reminder',
          isInterval ? '间隔喝水提醒' : '每日喝水提醒',
          channelDescription:
              isInterval ? '每隔固定时间提醒你喝水' : '按设定时间提醒你喝水',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
          // 角色卡贴纸：通知右侧大图标；生成失败时回退应用图标，
          // 关闭贴纸开关则完全不带大图标
          largeIcon: iconPath != null
              ? FilePathAndroidBitmap(iconPath)
              : (stickers
                  ? const DrawableResourceAndroidBitmap('@mipmap/ic_launcher')
                  : null),
        ),
        // iOS：App 在前台时也弹横幅 + 播系统提示音
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
      );
      futures.add(_plugin
          .zonedSchedule(
            id,
            title,
            body,
            _slotTime(date, m, now),
            details,
            androidScheduleMode: scheduleMode,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          )
          // 单槽失败不中断整轮（如同分钟边界、厂商限制），只记日志
          .catchError((Object e) {
        debugPrint('[notif] slot $id schedule failed: $e');
      }));
    }
    await Future.wait(futures);
    var pendingNow = -1;
    try {
      pendingNow = (await _plugin.pendingNotificationRequests()).length;
    } catch (_) {}
    debugPrint(
        '[notif] rescheduled ${slots.length} slots, ${scheduleMode.name}, '
        'pending=$pendingNow');
  }

  static Future<void> cancelAll() async {
    await _ensureInit();
    await _plugin.cancelAll();
  }

  /// 打开系统的「本应用通知设置」页。Android 上用户永久拒绝通知权限后
  /// 再调 requestPermission 不会再弹框，必须引导到系统设置手动开启
  static Future<bool> openNotificationSettings() async {
    try {
      return await const MethodChannel('app.notification.settings')
              .invokeMethod<bool>('open') ??
          false;
    } catch (e) {
      debugPrint('[notif] open notification settings failed: $e');
      return false;
    }
  }

  /// 系统通知权限当前是否开启（提醒页状态提示用）
  static Future<bool> notificationsEnabled() async {
    await _ensureInit();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      try {
        final options = await ios.checkPermissions();
        return options?.isEnabled ?? true;
      } catch (e) {
        debugPrint('[notif] read ios notification state failed: $e');
        return true;
      }
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? true;
  }

  /// Android 12+ 精确闹钟权限：关闭时排程会降级为 inexact（可能延后）。
  /// iOS 本地通知由系统精确调度、无此权限概念；非 Android 或读取失败
  /// 一律按可用处理，不影响排程
  static Future<bool> exactAlarmsAllowed() async {
    await _ensureInit();
    if (Platform.isIOS) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.canScheduleExactNotifications() ?? true;
    } catch (e) {
      debugPrint('[notif] read exact-alarm state failed: $e');
      return true;
    }
  }

  /// 打开系统「闹钟和提醒」授权页（Android 12+）
  static Future<void> openExactAlarmSettings() async {
    await _ensureInit();
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint('[notif] request exact alarms failed: $e');
    }
  }

  /// 下一次提醒的真实触发时刻（无排程或未开启时返回 null）。
  /// 纯计算、无平台调用，可直接在 build 中取值
  static DateTime? nextSlotAt({
    required bool enabled,
    required List<String> times,
    int? intervalMinutes,
    int? windowStartMin,
    int? windowEndMin,
    Set<int> weekdays = const {1, 2, 3, 4, 5, 6, 7},
    List<int> todayDrinkMinutes = const [],
    required int todayEffectiveMl,
    required int goalMl,
    bool stopAtGoal = false,
  }) {
    if (!enabled) return null;
    final now = DateTime.now();
    final goalReached = stopAtGoal && goalMl > 0 && todayEffectiveMl >= goalMl;
    final slots = _collectSlots(
      now: now,
      times: times,
      intervalMinutes: intervalMinutes,
      windowStartMin: windowStartMin,
      windowEndMin: windowEndMin,
      weekdays: weekdays,
      todayDrinkMinutes: todayDrinkMinutes,
      goalReached: goalReached,
    );
    DateTime? best;
    for (final s in slots) {
      // 用 epoch 转成真正的本地时间：TZDateTime.toLocal() 依赖 tz.local，
      // 未设置本地时区时会返回 UTC 墙上时间（界面上会显示成早 8 小时）
      final t = DateTime.fromMillisecondsSinceEpoch(
          _slotTime(s.date, s.minute, now).millisecondsSinceEpoch);
      if (best == null || t.isBefore(best)) best = t;
    }
    return best;
  }

  /// 槽位收集：未来若干天逐日按星期过滤，铺固定时间槽 + 间隔槽
  static List<_NotificationSlot> _collectSlots({
    required DateTime now,
    required List<String> times,
    int? intervalMinutes,
    int? windowStartMin,
    int? windowEndMin,
    Set<int> weekdays = const {1, 2, 3, 4, 5, 6, 7},
    List<int> todayDrinkMinutes = const [],
    bool goalReached = false,
  }) {
    final nowMinutes = now.hour * 60 + now.minute;
    final out = <_NotificationSlot>[];

    // 间隔槽每日槽位数 → 排程天数自适应（Android 12+ 约 500 闹钟上限）
    final step = intervalMinutes == null ? 0 : intervalMinutes.clamp(15, 300);
    var winStart = (windowStartMin ?? 0).clamp(0, 1439).toInt();
    var winEnd = (windowEndMin ?? 1440).clamp(1, 1440).toInt();
    if (winStart >= winEnd) {
      // 非法窗口（开始不早于结束）：不铺间隔槽。此处不能回落成
      // 0:00~24:00，否则会静默变成全天提醒（含深夜）
      winStart = winEnd;
    }
    final intervalPerDay =
        step == 0 ? 0 : ((winEnd - winStart) + step - 1) ~/ step;
    final perDay = times.length + intervalPerDay;
    final days = perDay == 0 ? 0 : (450 ~/ perDay).clamp(1, 7);

    // 与当天固定时间槽同一分钟时不重复发（两个槽 id 不同会双弹）
    final fixedMinutes = <int>{
      for (final t in times)
        if (t.split(':').length == 2 &&
            int.tryParse(t.split(':')[0]) != null &&
            int.tryParse(t.split(':')[1]) != null)
          int.parse(t.split(':')[0]) * 60 + int.parse(t.split(':')[1]),
    };

    for (var d = 0; d < days; d++) {
      final date = now.add(Duration(days: d));
      // 星期几过滤（weekday: 1=周一 … 7=周日，与设置页口径一致）
      if (!weekdays.contains(date.weekday)) continue;
      final isToday = d == 0;

      // 固定时间槽（自定义提醒）
      for (final t in times) {
        final parts = t.split(':');
        if (parts.length != 2) continue;
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour == null || minute == null) continue;
        final m = hour * 60 + minute;
        // 今天「当前分钟及更早」的槽一律跳过：若把这一分钟也重排到 2 秒后，
        // 每次改设置/切前后台/新增记录都会立刻补弹一条重复提醒
        if (isToday && m <= nowMinutes) continue;
        // 达标停止：今日剩余槽全跳（未来天喝水情况未知，正常排）
        if (isToday && goalReached) continue;
        // 智能语义（固定时间同样适用）：槽位前 30 分钟内刚喝过水 → 跳过
        if (isToday && todayDrinkMinutes.any((dm) => dm > m - 30 && dm <= m)) {
          continue;
        }
        out.add(_NotificationSlot(date, m, false));
      }

      // 间隔槽（智能提醒）
      if (step == 0) continue;
      for (var m = winStart; m < winEnd; m += step) {
        if (isToday && m <= nowMinutes) continue;
        if (isToday && goalReached) continue;
        if (fixedMinutes.contains(m)) continue;
        // 智能语义：槽位前 30 分钟内刚喝过水 → 你没忘记，跳过
        if (isToday && todayDrinkMinutes.any((dm) => dm > m - 30 && dm <= m)) {
          continue;
        }
        out.add(_NotificationSlot(date, m, true));
      }
    }
    return out;
  }

  /// 预览用：随机一张角色卡 SVG 资源路径（与真实通知的随机逻辑一致）
  static Future<String?> randomCharacterAsset() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final cards = manifest
          .listAssets()
          .where((a) =>
              a.startsWith('assets/images/characters/') && a.endsWith('.svg'))
          .toList();
      if (cards.isEmpty) return null;
      return cards[_rand.nextInt(cards.length)];
    } catch (e) {
      debugPrint('[notif] random character failed: $e');
      return null;
    }
  }

  /// 预览用：与真实通知同源的标题/正文（同一套随机文案引擎）
  static (String, String) previewContent({
    required int seed,
    required String message,
    String? customMessage,
    required bool progressTitle,
    required bool motivationalTitle,
    required bool waterFacts,
    required int? remainingMl,
  }) =>
      _composeContent(
        slotId: seed,
        message: message,
        customMessage: customMessage,
        progressTitle: progressTitle,
        motivationalTitle: motivationalTitle,
        waterFacts: waterFacts,
        remainingMl: remainingMl,
      );

  // ==================== 通知内容引擎 ====================

  /// 槽位通知内容：标题按进度/激励开关合成（进度在前、激励在后），
  /// 正文 = 提醒语 + 饮水事实同一行，自定义信息另起一行；随机内容以
  /// 槽位 id 为种子，同轮排程内各槽观感不重复
  static (String, String) _composeContent({
    required int slotId,
    required String message,
    required String? customMessage,
    required bool progressTitle,
    required bool motivationalTitle,
    required bool waterFacts,
    required int? remainingMl,
  }) {
    final showRemaining = progressTitle && (remainingMl ?? 0) > 0;
    final remainingText = UnitFormat.volume(remainingMl ?? 0, compact: true);
    final motivation = _motivations[slotId % _motivations.length];
    final title = motivationalTitle
        ? (showRemaining ? '剩余 $remainingText，$motivation' : motivation)
        : (showRemaining ? '该喝水啦 · 剩余 $remainingText' : '该喝水啦');

    // 提醒语与饮水事实排在同一行，提醒语在前
    var body = message;
    if (waterFacts) body += '  💧 ${_facts[slotId % _facts.length]}';
    final custom = customMessage?.trim() ?? '';
    if (custom.isNotEmpty) body += '\n$custom';
    return (title, body);
  }

  static const _motivations = [
    '你做到了！', '继续保持！', '加油，快喝完啦！', '喝水小能手就是你！',
    '为健康干杯！', '离目标越来越近啦！',
  ];

  static const _facts = [
    '人体约 60% 由水组成',
    '大脑约 75% 是水，缺水会让人迟钝',
    '轻度脱水就会影响注意力和情绪',
    '饭前喝一杯水有助于控制食量',
    '充足饮水能促进新陈代谢',
    '运动后 30 分钟内补水效果最好',
    '每天喝够水，皮肤会更水润',
    '水是唯一零卡路里的天然饮品',
    '缺水是疲劳感的常见原因之一',
    '晨起一杯温水可以唤醒肠胃',
    '充足饮水有助于肾脏排出代谢废物',
    '温水比冰水更容易被身体吸收',
  ];

  // ==================== 时间工具 ====================

  /// 指定日期的本地墙钟时刻 → 真实 UTC 瞬间（零依赖时区方案）：
  /// 设备本地墙钟 W 对应 UTC 瞬间 = W - offset
  static tz.TZDateTime _instanceFor(DateTime date, int hour, int minute) {
    final offset = date.timeZoneOffset;
    return tz.TZDateTime(
      tz.UTC, date.year, date.month, date.day, hour, minute,
    ).subtract(offset);
  }

  /// 槽位最终触发时刻：同一分钟内设置的槽（墙钟时刻已过）推到
  /// 2 秒后立即触发——插件要求 scheduledDate 必须严格在未来，
  /// 排过去会抛 Invalid argument 并中断整轮排程
  static tz.TZDateTime _slotTime(DateTime date, int minute, DateTime now) {
    var when = _instanceFor(date, minute ~/ 60, minute % 60);
    if (when.isBefore(now.add(const Duration(seconds: 2)))) {
      // 落到当前分钟：改为 2 秒后的真实时刻（不能用墙钟分钟拼时间，
      // 否则秒数会被当成分钟、分钟会被当成小时，排到错误时刻）
      final t = DateTime.now().add(const Duration(seconds: 2));
      when = _instanceFor(t, t.hour, t.minute)
          .add(Duration(seconds: t.second));
    }
    return when;
  }
}

/// 单轮排程中的一个通知槽位（日期 + 当日分钟数 + 是否间隔槽）
class _NotificationSlot {
  const _NotificationSlot(this.date, this.minute, this.isInterval);

  final DateTime date;
  final int minute;
  final bool isInterval;

  /// 排程 id：跨天唯一、同轮稳定（固定槽与间隔槽分开段位）。
  /// 用「月*32+日」作日期键而不是与 now 的天数差——后者在夏令时/
  /// 时区改写导致某天只有 23 小时时会算出 0 天，与当天 id 撞车
  int get id =>
      (date.month * 32 + date.day) * 100000 +
      (isInterval ? 50000 : 0) +
      minute;
}


