import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置项共享标志（重置时间 / 一周开始 / 卡路里开关），
/// 供设置页角标与对应子页面实时同步，持久化为单条 JSON
class SettingsFlags extends ChangeNotifier {
  SettingsFlags._();
  static final SettingsFlags instance = SettingsFlags._();

  static const _kKey = 'settings_flags';

  bool trackCalories = true;
  bool foodCalories = false;
  int resetHour = 0;
  int resetMinute = 0;
  int weekStart = 0; // 0 = 星期日，1 = 星期一

  // 「App、声音、动画」页五个开关（对标原版默认全开）
  bool dailyReview = true;
  bool celebrateDay = true;
  bool appSounds = true;
  bool widgetSounds = true;
  bool cupAnimations = true;

  bool _loaded = false;

  String get resetLabel =>
      '${resetHour.toString().padLeft(2, '0')}:${resetMinute.toString().padLeft(2, '0')}';

  /// 清除全部数据时同步复位内存缓存：否则 prefs.clear() 后内存里仍是
  /// 旧值，下次 save 会把清掉的设置原样写回
  void resetToDefaults() {
    trackCalories = true;
    foodCalories = false;
    resetHour = 0;
    resetMinute = 0;
    weekStart = 0;
    dailyReview = true;
    celebrateDay = true;
    appSounds = true;
    widgetSounds = true;
    cupAnimations = true;
    notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        trackCalories = (m['trackCalories'] as bool?) ?? true;
        foodCalories = (m['foodCalories'] as bool?) ?? false;
        resetHour = (m['resetHour'] as num?)?.toInt() ?? 0;
        resetMinute = (m['resetMinute'] as num?)?.toInt() ?? 0;
        weekStart = (m['weekStart'] as num?)?.toInt() ?? 0;
        dailyReview = (m['dailyReview'] as bool?) ?? true;
        celebrateDay = (m['celebrateDay'] as bool?) ?? true;
        appSounds = (m['appSounds'] as bool?) ?? true;
        widgetSounds = (m['widgetSounds'] as bool?) ?? true;
        cupAnimations = (m['cupAnimations'] as bool?) ?? true;
        notifyListeners();
      }
    } catch (_) {
      // 数据异常保持默认
    }
  }

  /// 局部更新并持久化（null 字段保持原值）
  Future<void> save({
    bool? trackCalories,
    bool? foodCalories,
    int? resetHour,
    int? resetMinute,
    int? weekStart,
    bool? dailyReview,
    bool? celebrateDay,
    bool? appSounds,
    bool? widgetSounds,
    bool? cupAnimations,
  }) async {
    if (trackCalories != null) this.trackCalories = trackCalories;
    if (foodCalories != null) this.foodCalories = foodCalories;
    if (resetHour != null) this.resetHour = resetHour;
    if (resetMinute != null) this.resetMinute = resetMinute;
    if (weekStart != null) this.weekStart = weekStart;
    if (dailyReview != null) this.dailyReview = dailyReview;
    if (celebrateDay != null) this.celebrateDay = celebrateDay;
    if (appSounds != null) this.appSounds = appSounds;
    if (widgetSounds != null) this.widgetSounds = widgetSounds;
    if (cupAnimations != null) this.cupAnimations = cupAnimations;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, jsonEncode({
        'trackCalories': this.trackCalories,
        'foodCalories': this.foodCalories,
        'resetHour': this.resetHour,
        'resetMinute': this.resetMinute,
        'weekStart': this.weekStart,
        'dailyReview': this.dailyReview,
        'celebrateDay': this.celebrateDay,
        'appSounds': this.appSounds,
        'widgetSounds': this.widgetSounds,
        'cupAnimations': this.cupAnimations,
      }));
    } catch (_) {
      // 持久化失败不阻塞 UI
    }
  }
}
