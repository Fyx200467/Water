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
