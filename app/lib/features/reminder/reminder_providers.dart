import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notification/notification_service.dart';
import '../../../core/storage/providers.dart';
import '../drink/services/hydration_calculator.dart';
import '../home/providers/home_providers.dart';

/// PRD §2.4 提醒设置
class ReminderSettings {
  const ReminderSettings({
    required this.enabled,
    required this.times, // "HH:mm" 全部已添加时间
    this.disabledTimes = const [], // 其中被单独关闭的时间
    this.hiddenTimes = const [], // 被改走的整点：不再出现在默认整点网格里
    required this.message,
  });

  final bool enabled;
  final List<String> times;
  final List<String> disabledTimes;

  /// 07:00~22:00 默认整点网格中被「编辑成别的时刻」的整点，
  /// 用于把该格从网格中移除，避免一次编辑同时出现旧整点和新时刻
  final List<String> hiddenTimes;
  final String message;

  /// 当前生效（参与调度）的时间 = 全部时间 - 单独关闭的
  List<String> get activeTimes =>
      times.where((t) => !disabledTimes.contains(t)).toList();

  /// 首次使用的默认值：只开启当天第一个整点（07:00），
  /// 其余整点在界面上显示为关闭，避免新装即被高频提醒轰炸
  static const defaultTimes = ['07:00'];
  static const defaultMessage = '别忘了喝水';

  ReminderSettings copyWith({
    bool? enabled,
    List<String>? times,
    List<String>? disabledTimes,
    List<String>? hiddenTimes,
    String? message,
  }) {
    return ReminderSettings(
      enabled: enabled ?? this.enabled,
      times: times ?? this.times,
      disabledTimes: disabledTimes ?? this.disabledTimes,
      hiddenTimes: hiddenTimes ?? this.hiddenTimes,
      message: message ?? this.message,
    );
  }
}

final reminderProvider =
    StateNotifierProvider<ReminderNotifier, ReminderSettings>((ref) {
  return ReminderNotifier(ref);
});

class ReminderNotifier extends StateNotifier<ReminderSettings> {
  ReminderNotifier(this.ref)
      : super(const ReminderSettings(
          enabled: true,
          times: ReminderSettings.defaultTimes,
          message: ReminderSettings.defaultMessage,
        )) {
    _load();
  }
  final Ref ref;

  static const _kEnabled = 'reminder_enabled';
  static const _kTimes = 'reminder_times';
  static const _kDisabledTimes = 'reminder_disabled_times';
  static const _kHiddenTimes = 'reminder_hidden_times';
  static const _kMessage = 'reminder_message';

  /// 初始异步加载完成信号：重排前必须等待，否则会用默认值排一轮
  final Completer<void> _loaded = Completer<void>();

  Future<void> _ensureLoaded() => _loaded.future;

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final p = storage.prefs;
    final timesRaw = p.getString(_kTimes);
    final disabledRaw = p.getString(_kDisabledTimes);
    final hiddenRaw = p.getString(_kHiddenTimes);
    state = ReminderSettings(
      // 总开关（「饮水提醒」卡）：持久化，关闭即取消全部已排提醒
      enabled: p.getBool(_kEnabled) ?? true,
      times: timesRaw == null || timesRaw.isEmpty
          ? ReminderSettings.defaultTimes
          : timesRaw.split(','),
      disabledTimes: disabledRaw == null || disabledRaw.isEmpty
          ? const []
          : disabledRaw.split(','),
      hiddenTimes: hiddenRaw == null || hiddenRaw.isEmpty
          ? const []
          : hiddenRaw.split(','),
      message: _migrateMessage(p.getString(_kMessage)),
    );
    _loaded.complete();
  }

  /// 旧版默认提示语（新版已删除「，小动物在等你~」后半句）：
  /// 已持久化的旧文案在加载时自动迁移，避免新装与老用户文案不一致
  static const _legacyDefaultMessage = '别忘了喝水哦，小动物在等你~';

  static String _migrateMessage(String? raw) {
    if (raw == null || raw.isEmpty || raw == _legacyDefaultMessage) {
      return ReminderSettings.defaultMessage;
    }
    return raw;
  }

  Future<void> update(ReminderSettings next) async {
    final storage = await ref.read(localStorageProvider.future);
    final p = storage.prefs;
    await p.setBool(_kEnabled, next.enabled);
    await p.setString(_kTimes, next.times.join(','));
    await p.setString(_kDisabledTimes, next.disabledTimes.join(','));
    await p.setString(_kHiddenTimes, next.hiddenTimes.join(','));
    await p.setString(_kMessage, next.message);
    state = next;
    await rescheduleNow();
  }

  Future<void> rescheduleNow() async {
    await _ensureLoaded();
    final s = state;
    final intervalMin = ref.read(notificationIntervalMinutesProvider);
    final entries = ref.read(todayEntriesProvider);
    final goalMl = ref.read(profileProvider)?.dailyGoalMl ?? 2000;
    final now = DateTime.now();
    await NotificationService.reschedule(
      enabled: s.enabled,
      times: s.activeTimes,
      message: s.message,
      customMessage: ref.read(customMessageProvider),
      intervalMinutes: intervalMin,
      windowStartMin: ref.read(reminderWindowStartProvider),
      windowEndMin: ref.read(reminderWindowEndProvider),
      weekdays: ref.read(reminderWeekdaysProvider),
      todayDrinkMinutes: [
        for (final e in entries)
          NotificationService.relativeMinute(now, e.drankAt),
      ],
      todayEffectiveMl: HydrationCalculator.sumEffective(entries),
      goalMl: goalMl,
      stopAtGoal: ref.read(stopAtGoalEnabledProvider),
      progressTitle: ref.read(progressTitleEnabledProvider),
      motivationalTitle: ref.read(motivationalTitleEnabledProvider),
      waterFacts: ref.read(waterFactsEnabledProvider),
      stickers: ref.read(stickersEnabledProvider),
      soundKey: ref.read(reminderSoundProvider),
    );
  }
}

/// 深浅色模式（PRD §2.8 / §4.3）
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref);
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this.ref) : super(ThemeMode.system) {
    _load();
  }
  final Ref ref;

  static const _kTheme = 'theme_mode';

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final raw = storage.prefs.getString(_kTheme);
    state = switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode mode) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(
      _kTheme,
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        _ => 'system',
      },
    );
    state = mode;
  }
}

// ============================================================
// 高级设置开关（达到目标停止 / 进度标题 / 激励标题 / 饮水事实 /
// 快速添加 / 贴纸）持久化到 SharedPreferences
// ============================================================
class NotificationToggleNotifier extends StateNotifier<bool> {
  NotificationToggleNotifier(this.ref, this._key, this._defaultValue)
      : super(_defaultValue) {
    _load();
  }
  final Ref ref;
  final String _key;
  final bool _defaultValue;

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    state = storage.prefs.getBool(_key) ?? _defaultValue;
  }

  Future<void> set(bool v) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setBool(_key, v);
    state = v;
  }
}

// ============================================================
// 间隔提醒与高级设置（间隔分钟数、杯子、开关组）
// ============================================================

/// 高级设置开关：达到目标停止
final stopAtGoalEnabledProvider =
    StateNotifierProvider<NotificationToggleNotifier, bool>((ref) {
  return NotificationToggleNotifier(ref, 'notif_stop_at_goal', true);
});

/// 高级设置开关：饮水进度标题
final progressTitleEnabledProvider =
    StateNotifierProvider<NotificationToggleNotifier, bool>((ref) {
  return NotificationToggleNotifier(ref, 'notif_progress_title', true);
});

/// 高级设置开关：激励性标题
final motivationalTitleEnabledProvider =
    StateNotifierProvider<NotificationToggleNotifier, bool>((ref) {
  return NotificationToggleNotifier(ref, 'notif_motivational_title', false);
});

/// 高级设置开关：饮水事实
final waterFactsEnabledProvider =
    StateNotifierProvider<NotificationToggleNotifier, bool>((ref) {
  return NotificationToggleNotifier(ref, 'notif_water_facts', true);
});

/// 高级设置开关：贴纸
final stickersEnabledProvider =
    StateNotifierProvider<NotificationToggleNotifier, bool>((ref) {
  return NotificationToggleNotifier(ref, 'notif_stickers', true);
});

/// 提醒音效（key 对应 NotificationService.soundLabels），默认系统默认音
final reminderSoundProvider =
    StateNotifierProvider<StringSettingNotifier, String>((ref) {
  return StringSettingNotifier(ref, 'reminder_sound', 'default');
});

/// 智能提醒间隔（分钟），默认 120
final notificationIntervalMinutesProvider =
    StateNotifierProvider<IntSettingNotifier, int>((ref) {
  return IntSettingNotifier(ref, 'notif_interval_min', 120);
});

/// 智能提醒生效窗口开始（当日分钟数，含），默认 08:00 ——
/// 间隔提醒槽位仅在该窗口内排程（见 NotificationService.reschedule）
final reminderWindowStartProvider =
    StateNotifierProvider<IntSettingNotifier, int>((ref) {
  return IntSettingNotifier(ref, 'reminder_window_start_min', 8 * 60);
});

/// 智能提醒生效窗口结束（当日分钟数，不含），默认 22:00
final reminderWindowEndProvider =
    StateNotifierProvider<IntSettingNotifier, int>((ref) {
  return IntSettingNotifier(ref, 'reminder_window_end_min', 22 * 60);
});

/// 智能提醒生效星期（1=周一 … 7=周日，默认全选）。
/// 调度侧按星期过滤：逐日逐槽一次性排程，仅排生效星期的槽位
final reminderWeekdaysProvider =
    StateNotifierProvider<WeekdaysNotifier, Set<int>>((ref) {
  return WeekdaysNotifier(ref);
});

class WeekdaysNotifier extends StateNotifier<Set<int>> {
  WeekdaysNotifier(this.ref) : super(const {1, 2, 3, 4, 5, 6, 7}) {
    _load();
  }
  final Ref ref;
  static const _k = 'reminder_weekdays';

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final raw = storage.prefs.getStringList(_k);
    if (raw == null) return;
    // 允许空集合：用户主动取消全部星期后，重启不能恢复成全选
    state = raw
        .map(int.tryParse)
        .whereType<int>()
        .where((d) => d >= 1 && d <= 7)
        .toSet();
  }

  Future<void> toggle(int day) async {
    final next = {...state};
    if (next.contains(day)) {
      next.remove(day);
    } else {
      next.add(day);
    }
    state = next;
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setStringList(_k, next.map((d) => '$d').toList());
    // 星期变更立即生效：按新星期集重排（切换日历天不再收到通知）
    await ref.read(reminderProvider.notifier).rescheduleNow();
  }
}

/// 通知自定义信息（提醒正文中追加的个人文本），空串 = 未设置
final customMessageProvider =
    StateNotifierProvider<CustomMessageNotifier, String>((ref) {
  return CustomMessageNotifier(ref);
});

class CustomMessageNotifier extends StateNotifier<String> {
  CustomMessageNotifier(this.ref) : super('') {
    _load();
  }
  final Ref ref;
  static const _k = 'notif_custom_message';

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    state = storage.prefs.getString(_k) ?? '';
  }

  Future<void> set(String v) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(_k, v);
    state = v;
  }
}

/// 通用 String 设置 Notifier（持久化）
class StringSettingNotifier extends StateNotifier<String> {
  StringSettingNotifier(this.ref, this._key, this._defaultValue)
      : super(_defaultValue) {
    _load();
  }
  final Ref ref;
  final String _key;
  final String _defaultValue;

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    state = storage.prefs.getString(_key) ?? _defaultValue;
  }

  Future<void> set(String v) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(_key, v);
    state = v;
  }
}

/// 通用 int 设置 Notifier（持久化）
class IntSettingNotifier extends StateNotifier<int> {
  IntSettingNotifier(this.ref, this._key, this._defaultValue)
      : super(_defaultValue) {
    _load();
  }
  final Ref ref;
  final String _key;
  final int _defaultValue;

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    state = storage.prefs.getInt(_key) ?? _defaultValue;
  }

  Future<void> set(int v) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setInt(_key, v);
    state = v;
  }
}
