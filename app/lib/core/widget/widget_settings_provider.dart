import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/providers.dart';

/// 小组件设置状态（持久化到 SharedPreferences）
class WidgetSettingsState {
  const WidgetSettingsState({
    this.colorIndex = 0,
    this.customColor,
    this.drink1 = 'water_pure',
    this.vol1 = 250,
    this.drink2 = 'milk_juice',
    this.vol2 = 300,
    this.drink3 = 'soda',
    this.vol3 = 330,
    this.colorfulButtons = true,
    this.colorfulCharacter = false,
    this.followDarkMode = false,
    this.streakBadge = true,
  });

  final int colorIndex; // 色板下标，-1 = 自定义色
  final int? customColor; // 自定义色 ARGB（colorIndex == -1 时生效）
  final String drink1;
  final int vol1;
  final String drink2;
  final int vol2;
  final String drink3;
  final int vol3;
  final bool colorfulButtons; // 彩色饮料按钮
  final bool colorfulCharacter; // 彩色字符层
  final bool followDarkMode; // 遵循深色模式规则（系统深色时强制深色底）
  final bool streakBadge; // 连续徽章

  Color get themeColor => colorIndex >= 0
      ? widgetPalette[colorIndex]
      : Color(customColor ?? 0xFFFFFFFF);

  WidgetSettingsState copyWith({
    int? colorIndex,
    int? customColor,
    String? drink1,
    int? vol1,
    String? drink2,
    int? vol2,
    String? drink3,
    int? vol3,
    bool? colorfulButtons,
    bool? colorfulCharacter,
    bool? followDarkMode,
    bool? streakBadge,
  }) =>
      WidgetSettingsState(
        colorIndex: colorIndex ?? this.colorIndex,
        customColor: customColor ?? this.customColor,
        drink1: drink1 ?? this.drink1,
        vol1: vol1 ?? this.vol1,
        drink2: drink2 ?? this.drink2,
        vol2: vol2 ?? this.vol2,
        drink3: drink3 ?? this.drink3,
        vol3: vol3 ?? this.vol3,
        colorfulButtons: colorfulButtons ?? this.colorfulButtons,
        colorfulCharacter: colorfulCharacter ?? this.colorfulCharacter,
        followDarkMode: followDarkMode ?? this.followDarkMode,
        streakBadge: streakBadge ?? this.streakBadge,
      );

  Map<String, dynamic> _toMap() => {
        'colorIndex': colorIndex,
        if (customColor != null) 'customColor': customColor,
        'drink1': drink1, 'vol1': vol1,
        'drink2': drink2, 'vol2': vol2,
        'drink3': drink3, 'vol3': vol3,
        'colorfulButtons': colorfulButtons,
        'colorfulCharacter': colorfulCharacter,
        'followDarkMode': followDarkMode,
        'streakBadge': streakBadge,
      };

  static WidgetSettingsState _fromMap(Map<String, dynamic> m) =>
      WidgetSettingsState(
        colorIndex: (m['colorIndex'] as num?)?.toInt() ?? 0,
        customColor: (m['customColor'] as num?)?.toInt(),
        drink1: m['drink1'] as String? ?? 'water_pure',
        vol1: (m['vol1'] as num?)?.toInt() ?? 250,
        drink2: m['drink2'] as String? ?? 'milk_juice',
        vol2: (m['vol2'] as num?)?.toInt() ?? 300,
        drink3: m['drink3'] as String? ?? 'soda',
        vol3: (m['vol3'] as num?)?.toInt() ?? 330,
        colorfulButtons: m['colorfulButtons'] as bool? ?? true,
        colorfulCharacter: m['colorfulCharacter'] as bool? ?? false,
        followDarkMode: m['followDarkMode'] as bool? ?? false,
        streakBadge: m['streakBadge'] as bool? ?? true,
      );
}

class WidgetSettingsNotifier extends StateNotifier<WidgetSettingsState> {
  WidgetSettingsNotifier(this.ref) : super(const WidgetSettingsState()) {
    loaded = _load();
  }

  final Ref ref;

  static const _kKey = 'widget_settings';

  /// 磁盘加载完成信号：加载完成前 state 是默认值（milk_juice 等），
  /// 冷启动小组件同步必须先等它，否则会把默认饮料格推上桌面
  late final Future<void> loaded;

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final raw = storage.prefs.getString(_kKey);
    if (raw == null || raw.isEmpty || !mounted) return;
    try {
      state = WidgetSettingsState._fromMap(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // 数据异常保持默认
    }
  }

  Future<void> update(WidgetSettingsState next) async {
    state = next;
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(_kKey, jsonEncode(state._toMap()));
    // 设置变化即时刷新桌面小组件（饮料格/主题色/徽章与预览卡保持一致）
    unawaited(ref.read(widgetSyncTriggerProvider)());
  }

  /// 外部数据（自定义饮品增删改）变更后主动刷新桌面小组件。
  /// 走 notifier 的 ref（Provider 级生命周期），避免页面销毁后
  /// 继续使用已释放的 WidgetRef
  Future<void> refreshWidget() => ref.read(widgetSyncTriggerProvider)();
}

/// 色板（对标原版 5 列 × 4 行）
const List<Color> widgetPalette = [
  Color(0xFFFFFFFF), Color(0xFFF2F2F4), Color(0xFFF5ECDC), Color(0xFF5D4037), Color(0xFF141414),
  Color(0xFFADE1F5), Color(0xFFBBD7F0), Color(0xFFC6E5C5), Color(0xFFA8E6CF), Color(0xFF43A047),
  Color(0xFFFFE45C), Color(0xFFFFB35C), Color(0xFFF48FB1), Color(0xFFE5605C), Color(0xFF8E2436),
  Color(0xFFF8BBD0), Color(0xFFD3C7F2), Color(0xFF7C4DFF), Color(0xFF1E44B8), Color(0xFF64748B),
];

final widgetSettingsProvider =
    StateNotifierProvider<WidgetSettingsNotifier, WidgetSettingsState>((ref) {
  return WidgetSettingsNotifier(ref);
});
/// 小组件同步触发：core 层不依赖 features，真实实现在 app 集成层注入
/// （未覆盖时为空实现，不触发推送，如后台 isolate）
final widgetSyncTriggerProvider =
    Provider<Future<void> Function()>((ref) => () async {});

/// 液体填充色：「彩色字符层」开启且有非白主题色时液体跟随主题色，
/// 否则保持品牌青（预览卡与桌面帧同规则）
Color widgetLiquidColor(WidgetSettingsState s) {
  final colorful =
      s.colorIndex != 0 || (s.colorIndex == -1 && s.customColor != null);
  if (s.colorfulCharacter && colorful) return s.themeColor;
  return const Color(0xFF4DB8D8);
}

/// 小组件卡面实际生效底色：预览卡与桌面推送同规则——
/// 「遵循深色模式规则」开启且系统处于深色时**强制深色底**（无论所选
/// 主题色为何），否则选了非白主题色时染主题色、默认白底。
/// 此前只有桌面推送做深色强制、预览卡直接用所选色，系统深色模式下
/// 出现「App 内改颜色、桌面永远不变」的观感错位
Color effectiveWidgetThemeColor(WidgetSettingsState s, {bool? systemDark}) {
  final dark = systemDark ??
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
  if (s.followDarkMode && dark) return const Color(0xFF1C1C22);
  final colorful =
      s.colorIndex != 0 || (s.colorIndex == -1 && s.customColor != null);
  return colorful ? s.themeColor : const Color(0xFFFFFFFF);
}