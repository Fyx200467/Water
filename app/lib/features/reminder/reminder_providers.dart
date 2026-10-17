import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notification/notification_service.dart';
import '../../../core/storage/providers.dart';

/// PRD §2.4 提醒设置
class ReminderSettings {
  const ReminderSettings({
    required this.enabled,
    required this.times, // "HH:mm" 全部已添加时间
    this.disabledTimes = const [], // 其中被单独关闭的时间
    required this.message,
    required this.dndEnabled,
    this.dndStart,
    this.dndEnd,
  });

  final bool enabled;
  final List<String> times;
  final List<String> disabledTimes;
  final String message;
  final bool dndEnabled;
  final String? dndStart;
  final String? dndEnd;

  /// 当前生效（参与调度）的时间 = 全部时间 - 单独关闭的
  List<String> get activeTimes =>
      times.where((t) => !disabledTimes.contains(t)).toList();

  static const defaultTimes = ['10:00', '15:00', '20:00'];
  static const defaultMessage = '别忘了喝水哦，小动物在等你~';

  ReminderSettings copyWith({
    bool? enabled,
    List<String>? times,
    List<String>? disabledTimes,
    String? message,
    bool? dndEnabled,
    String? dndStart,
    String? dndEnd,
  }) {
    return ReminderSettings(
      enabled: enabled ?? this.enabled,
      times: times ?? this.times,
      disabledTimes: disabledTimes ?? this.disabledTimes,
      message: message ?? this.message,
      dndEnabled: dndEnabled ?? this.dndEnabled,
      dndStart: dndStart ?? this.dndStart,
      dndEnd: dndEnd ?? this.dndEnd,
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
          dndEnabled: false,
        )) {
    _load();
  }
  final Ref ref;

  static const _kEnabled = 'reminder_enabled';
  static const _kTimes = 'reminder_times';
  static const _kDisabledTimes = 'reminder_disabled_times';
  static const _kMessage = 'reminder_message';
  static const _kDndEnabled = 'reminder_dnd_enabled';
  static const _kDndStart = 'reminder_dnd_start';
  static const _kDndEnd = 'reminder_dnd_end';

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final p = storage.prefs;
    final timesRaw = p.getString(_kTimes);
    final disabledRaw = p.getString(_kDisabledTimes);
    state = ReminderSettings(
      // 总开关 UI 已移除，提醒始终按各行开关调度
      enabled: true,
      times: timesRaw == null || timesRaw.isEmpty
          ? ReminderSettings.defaultTimes
          : timesRaw.split(','),
      disabledTimes: disabledRaw == null || disabledRaw.isEmpty
          ? const []
          : disabledRaw.split(','),
      message: p.getString(_kMessage) ?? ReminderSettings.defaultMessage,
      dndEnabled: p.getBool(_kDndEnabled) ?? false,
      dndStart: p.getString(_kDndStart),
      dndEnd: p.getString(_kDndEnd),
    );
  }

  Future<void> update(ReminderSettings next) async {
    final storage = await ref.read(localStorageProvider.future);
    final p = storage.prefs;
    await p.setBool(_kEnabled, next.enabled);
    await p.setString(_kTimes, next.times.join(','));
    await p.setString(_kDisabledTimes, next.disabledTimes.join(','));
    await p.setString(_kMessage, next.message);
    await p.setBool(_kDndEnabled, next.dndEnabled);
    if (next.dndStart != null) {
      await p.setString(_kDndStart, next.dndStart!);
    }
    if (next.dndEnd != null) {
      await p.setString(_kDndEnd, next.dndEnd!);
    }
    state = next;
    await rescheduleNow();
  }

  /// 按当前全部设置重排通知（含间隔提醒开关与间隔分钟数）
  Future<void> rescheduleNow() async {
    final s = state;
    final intervalOn = ref.read(intervalEnabledProvider);
    final intervalMin = ref.read(notificationIntervalMinutesProvider);
    await NotificationService.reschedule(
      enabled: s.enabled,
      times: s.activeTimes,
      message: s.message,
      dndStart: s.dndEnabled ? s.dndStart : null,
      dndEnd: s.dndEnabled ? s.dndEnd : null,
      intervalMinutes: intervalOn ? intervalMin : null,
    );
  }
}

/// 音效开关（PRD §2.8）
final soundEnabledProvider =
    StateNotifierProvider<SoundEnabledNotifier, bool>((ref) {
  return SoundEnabledNotifier(ref);
});

class SoundEnabledNotifier extends StateNotifier<bool> {
  SoundEnabledNotifier(this.ref) : super(true) {
    _load();
  }
  final Ref ref;

  static const _kSound = 'sound_enabled';

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    state = storage.prefs.getBool(_kSound) ?? true;
  }

  Future<void> set(bool v) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setBool(_kSound, v);
    state = v;
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
// 间隔提醒与高级设置（间隔开关/分钟数、杯子、开关组）
// ============================================================

/// 间隔提醒开关（「每隔 N 分钟提醒一次」行）
final intervalEnabledProvider =
    StateNotifierProvider<NotificationToggleNotifier, bool>((ref) {
  return NotificationToggleNotifier(ref, 'reminder_interval_enabled', true);
});

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

/// 高级设置开关：快速添加
final quickAddEnabledProvider =
    StateNotifierProvider<NotificationToggleNotifier, bool>((ref) {
  return NotificationToggleNotifier(ref, 'notif_quick_add', true);
});

/// 高级设置开关：贴纸
final stickersEnabledProvider =
    StateNotifierProvider<NotificationToggleNotifier, bool>((ref) {
  return NotificationToggleNotifier(ref, 'notif_stickers', true);
});

/// 智能提醒间隔（分钟），默认 120
final notificationIntervalMinutesProvider =
    StateNotifierProvider<IntSettingNotifier, int>((ref) {
  return IntSettingNotifier(ref, 'notif_interval_min', 120);
});

/// 快速添加默认杯子容量（ml），默认 250
final quickAddCupMlProvider =
    StateNotifierProvider<IntSettingNotifier, int>((ref) {
  return IntSettingNotifier(ref, 'quick_add_cup_ml', 250);
});

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
