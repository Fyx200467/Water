import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notification/notification_service.dart';
import '../../../core/storage/providers.dart';

/// PRD §2.4 提醒设置
class ReminderSettings {
  const ReminderSettings({
    required this.enabled,
    required this.times, // "HH:mm" 列表
    required this.message,
    required this.dndEnabled,
    this.dndStart,
    this.dndEnd,
  });

  final bool enabled;
  final List<String> times;
  final String message;
  final bool dndEnabled;
  final String? dndStart;
  final String? dndEnd;

  static const defaultTimes = ['10:00', '15:00', '20:00'];
  static const defaultMessage = '别忘了喝水哦，小动物在等你~';

  ReminderSettings copyWith({
    bool? enabled,
    List<String>? times,
    String? message,
    bool? dndEnabled,
    String? dndStart,
    String? dndEnd,
  }) {
    return ReminderSettings(
      enabled: enabled ?? this.enabled,
      times: times ?? this.times,
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
          enabled: false,
          times: ReminderSettings.defaultTimes,
          message: ReminderSettings.defaultMessage,
          dndEnabled: false,
        )) {
    _load();
  }
  final Ref ref;

  static const _kEnabled = 'reminder_enabled';
  static const _kTimes = 'reminder_times';
  static const _kMessage = 'reminder_message';
  static const _kDndEnabled = 'reminder_dnd_enabled';
  static const _kDndStart = 'reminder_dnd_start';
  static const _kDndEnd = 'reminder_dnd_end';

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final p = storage.prefs;
    final timesRaw = p.getString(_kTimes);
    state = ReminderSettings(
      enabled: p.getBool(_kEnabled) ?? false,
      times: timesRaw == null || timesRaw.isEmpty
          ? ReminderSettings.defaultTimes
          : timesRaw.split(','),
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
    await p.setString(_kMessage, next.message);
    await p.setBool(_kDndEnabled, next.dndEnabled);
    if (next.dndStart != null) {
      await p.setString(_kDndStart, next.dndStart!);
    }
    if (next.dndEnd != null) {
      await p.setString(_kDndEnd, next.dndEnd!);
    }
    state = next;
    await NotificationService.reschedule(
      enabled: next.enabled,
      times: next.times,
      message: next.message,
      dndStart: next.dndEnabled ? next.dndStart : null,
      dndEnd: next.dndEnabled ? next.dndEnd : null,
    );
  }

  Future<void> disable() async {
    await update(state.copyWith(enabled: false));
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
// 其他通知开关（饮水回顾 / 节假日 / 限时挑战 / 饮水提示 / 特别优惠）
// 持久化到 SharedPreferences，参考 soundEnabledProvider 写法
// ============================================================

/// 你的进度回顾通知
final progressReviewEnabledProvider =
    StateNotifierProvider<NotificationToggleNotifier, bool>((ref) {
  return NotificationToggleNotifier(ref, 'notif_progress_review', true);
});

/// 节假日通知
final holidayEnabledProvider =
    StateNotifierProvider<NotificationToggleNotifier, bool>((ref) {
  return NotificationToggleNotifier(ref, 'notif_holiday', true);
});

/// 限时挑战通知
final challengeEnabledProvider =
    StateNotifierProvider<NotificationToggleNotifier, bool>((ref) {
  return NotificationToggleNotifier(ref, 'notif_challenge', true);
});

/// 饮水提示通知
final drinkTipEnabledProvider =
    StateNotifierProvider<NotificationToggleNotifier, bool>((ref) {
  return NotificationToggleNotifier(ref, 'notif_drink_tip', true);
});

/// 特别优惠通知
final specialOfferEnabledProvider =
    StateNotifierProvider<NotificationToggleNotifier, bool>((ref) {
  return NotificationToggleNotifier(ref, 'notif_special_offer', true);
});

/// 通用通知开关 Notifier（持久化到 SharedPreferences）
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
// 提醒模式与高级设置（智能/自定义 Tab、间隔、杯子、声音、星期）
// ============================================================

/// 提醒模式：'smart' 智能提醒 / 'custom' 自定义提醒
final reminderModeProvider =
    StateNotifierProvider<ReminderModeNotifier, String>((ref) {
  return ReminderModeNotifier(ref);
});

class ReminderModeNotifier extends StateNotifier<String> {
  ReminderModeNotifier(this.ref) : super('smart') {
    _load();
  }
  final Ref ref;
  static const _k = 'reminder_mode';

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    state = storage.prefs.getString(_k) ?? 'smart';
  }

  Future<void> set(String v) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(_k, v);
    state = v;
  }
}

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

/// 提醒音效 id，默认 'bamboo'
final reminderSoundProvider =
    StateNotifierProvider<StringSettingNotifier, String>((ref) {
  return StringSettingNotifier(ref, 'reminder_sound', 'bamboo');
});

/// 提醒生效的星期（7 位 `List<bool>`，索引 0=周日）
final reminderWeekdaysProvider =
    StateNotifierProvider<WeekdaysNotifier, List<bool>>((ref) {
  return WeekdaysNotifier(ref);
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

/// 星期几选择 Notifier（7 位 `List<bool>`，序列化为 "1,1,1,1,1,0,0"）
class WeekdaysNotifier extends StateNotifier<List<bool>> {
  WeekdaysNotifier(this.ref) : super(List.filled(7, true)) {
    _load();
  }
  final Ref ref;
  static const _k = 'reminder_weekdays';

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final raw = storage.prefs.getString(_k);
    if (raw == null || raw.isEmpty) {
      state = List.filled(7, true);
      return;
    }
    final parts = raw.split(',');
    state = List<bool>.generate(
      7,
      (i) => i < parts.length && parts[i] == '1',
      growable: false,
    );
  }

  Future<void> toggle(int dayIndex) async {
    final next = List<bool>.from(state);
    next[dayIndex] = !next[dayIndex];
    state = next;
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(_k, next.map((b) => b ? '1' : '0').join(','));
  }
}
