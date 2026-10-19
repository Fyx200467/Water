import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// 同步数据到 Android 桌面小组件（视图对标 App 内「小组件」设置页预览卡）
///
/// 数据键约定（原生 WaterLlamaWidgetProvider 读取）：
/// - `goal_num`/`goal_unit`：当日饮水总量数字与单位（如「2.3」+「升」，
///   拆分写入以规避 vivo launcher 混排换行/裁切）
/// - `percent`：完成百分比（含 % 号）
/// - `streak_days`：连续签到天数（徽章数字）
/// - `bg_color`：主题色 ARGB（-1 = 默认白底）
/// - `dark_text`：背景为深色时文字切换白色
/// - `streak_badge`：是否显示连续徽章（布尔）
/// - `tile_color`：饮料格底色 ARGB（-1 = 默认灰底 #F1F1F4）
/// - `character_frame_0..15`：液体波浪动画帧 PNG 绝对路径（按当前填充/
///   点亮态离屏渲染，ViewFlipper 在 launcher 进程内轮播）
/// - `character_icon`：静态单图回退路径（无帧数据时显示）
/// - `drink{i}_ml/name/icon`：右列饮料格（icon 为 PNG 绝对路径，
///   原生侧 BitmapFactory 解码后 setImageViewBitmap）
///
/// 点击约定：饮料格以 `waterllama://quick-add?slot={1..3}` 启动 App，
/// Dart 侧监听 initiallyLaunchedFromHomeWidget / widgetClicked 完成快速录入

/// 单个饮料格数据（预览卡右侧竖排）
class WidgetDrinkData {
  const WidgetDrinkData({
    required this.ml,
    required this.name,
    this.iconFile,
    this.effectiveMl, // 折算后水量（原生点按累加口径；null = 未折算）
  });

  final int ml;
  final String name;
  final File? iconFile; // 已渲染的饮品图标 PNG

  /// 折算后水量：与 App 内 HydrationCalculator 同口径（如咖啡按系数折算）。
  /// 原生快捷录入按它累加今日总量/百分比，避免点按后桌面与 App 数字轻微不一致
  final int? effectiveMl;
}

/// 饮料格容量文案：<1000 显示「Nml」，≥1000 换算升显示「NL/N.NL」
/// （去尾零：1000→1L，1500→1.5L）
String _tileMlLabel(int ml) {
  if (ml >= 1000) {
    final liters = ml / 1000;
    final text = liters == liters.roundToDouble()
        ? liters.toStringAsFixed(0)
        : liters.toStringAsFixed(1);
    return '${text}L';
  }
  return '${ml}ml';
}

Future<void> syncHomeWidget({
  required int todayMl,
  required int goalMl,
  required int streakDays,
  Color? themeColor, // null = 默认白底
  bool showStreak = true, // 连续徽章显隐
  int tileColor = -1, // 饮料格底色（-1 = 默认灰底）
  List<WidgetDrinkData> drinks = const [],
  bool recordEnabled = true, // 未完成初始化引导时 false：只展示不可录入
}) async {
  // 仅 Android 执行（kIsWeb 需先排除：Web 平台没有 dart:io 的 Platform）
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    // 左上大字：当日饮水总量（与 App 内预览卡实时绑定）。
    // 数字/单位拆成两键两 TextView 同行——单 TextView 混排在 vivo
    // launcher 上会被异常换行/裁切。≥1L 一位小数（1.0升），否则 ml
    final String goalNum;
    final String goalUnit;
    if (todayMl >= 1000) {
      goalNum = (todayMl / 1000).toStringAsFixed(1);
      goalUnit = '升';
    } else {
      goalNum = '$todayMl';
      goalUnit = 'ml';
    }
    // 百分比与 App 显示层一致封顶 100（超目标不显示 114% 之类）
    final percent =
        goalMl > 0 ? (todayMl * 100 / goalMl).round().clamp(0, 100) : 0;

    await HomeWidget.saveWidgetData<String>('goal_num', goalNum);
    await HomeWidget.saveWidgetData<String>('goal_unit', goalUnit);
    // 当日达标 → 小组件徽章 ✓ 与天数轮播（与 App 首页左上角按钮同款）
    await HomeWidget.saveWidgetData<bool>(
        'streak_done', goalMl > 0 && todayMl >= goalMl);
    await HomeWidget.saveWidgetData<String>('percent', '$percent%');
    await HomeWidget.saveWidgetData<String>('streak_days', '$streakDays');
    await HomeWidget.saveWidgetData<int>(
        'bg_color', themeColor?.toARGB32().toSigned(32) ?? -1);
    await HomeWidget.saveWidgetData<bool>(
        'dark_text', themeColor != null && themeColor.computeLuminance() <= 0.55);
    await HomeWidget.saveWidgetData<bool>('streak_badge', showStreak);
    await HomeWidget.saveWidgetData<int>('tile_color', tileColor);
    for (var i = 1; i <= 3; i++) {
      final d = i <= drinks.length ? drinks[i - 1] : null;
      await HomeWidget.saveWidgetData<String>(
          'drink${i}_ml', d == null ? '' : _tileMlLabel(d.ml));
      // 未初始化闸门：录入数值强制 0 → 原生 QuickAddReceiver 的
      // ml<=0 检查天然拒绝（方案 A）；界面文案/图标照常展示
      await HomeWidget.saveWidgetData<int>(
          'drink${i}_ml_value', recordEnabled ? (d?.ml ?? 0) : 0);
      // -1 = 未折算（原生回退按原容量累加）；0 合法（无水合贡献的饮品）
      await HomeWidget.saveWidgetData<int>(
          'drink${i}_eff_ml_value',
          !recordEnabled ? 0 : (d?.effectiveMl ?? -1));
      await HomeWidget.saveWidgetData<String>('drink${i}_name', d?.name ?? '');
      await HomeWidget.saveWidgetData<String>(
          'drink${i}_icon', d?.iconFile?.path ?? '');
    }
    // 原生快速路径键：vivo 冻结窗口内点按录入由 QuickAddReceiver 直接
    // 读写这些数值（不拉起 Dart 引擎），跨天用 widget_date 判定归零
    final now = DateTime.now();
    await HomeWidget.saveWidgetData<int>('widget_today_ml', todayMl);
    await HomeWidget.saveWidgetData<int>('goal_ml', goalMl);
    // 原生双保险闸门键（方案 B）：QuickAddReceiver 见 false 拒绝录入
    await HomeWidget.saveWidgetData<bool>(
        'profile_initialized', recordEnabled);
    await HomeWidget.saveWidgetData<String>(
        'widget_date',
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}');
    // androidName 不能带前导点：插件按「包名 + androidName」反射查找 Provider 类
    await HomeWidget.updateWidget(
      name: 'WaterLlamaWidgetProvider',
      androidName: 'WaterLlamaWidgetProvider',
    );
  } catch (_) {
    // 静默失败：桌面端/测试环境没有插件实现，小组件同步不应影响主流程
  }
}
