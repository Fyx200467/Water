import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// 同步数据到 Android 桌面小组件（视图对标 App 内「小组件」设置页预览卡）
///
/// 数据键约定（原生 WaterLlamaWidgetProvider 读取）：
/// - `goal_label`：当日饮水总量展示文案（如「2.3升」「850ml」）
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
  const WidgetDrinkData({required this.ml, required this.name, this.iconFile});

  final int ml;
  final String name;
  final File? iconFile; // 已渲染的饮品图标 PNG
}

Future<void> syncHomeWidget({
  required int todayMl,
  required int goalMl,
  required int streakDays,
  Color? themeColor, // null = 默认白底
  bool showStreak = true, // 连续徽章显隐
  int tileColor = -1, // 饮料格底色（-1 = 默认灰底）
  List<WidgetDrinkData> drinks = const [],
}) async {
  // 仅 Android 执行（kIsWeb 需先排除：Web 平台没有 dart:io 的 Platform）
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    // 左上大字：当日饮水总量（与 App 内预览卡实时绑定；整千显示 N升，
    // 其余一位小数，不足 1 升直接 ml）
    String volumeLabel;
    if (todayMl >= 1000) {
      final liters = todayMl / 1000;
      volumeLabel = liters == liters.roundToDouble()
          ? '${liters.toStringAsFixed(0)}升'
          : '${liters.toStringAsFixed(1)}升';
    } else {
      volumeLabel = '${todayMl}ml';
    }
    final percent =
        goalMl > 0 ? (todayMl * 100 / goalMl).round().clamp(0, 999) : 0;

    await HomeWidget.saveWidgetData<String>('goal_label', volumeLabel);
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
          'drink${i}_ml', d == null ? '' : '${d.ml}ml');
      await HomeWidget.saveWidgetData<String>('drink${i}_name', d?.name ?? '');
      await HomeWidget.saveWidgetData<String>(
          'drink${i}_icon', d?.iconFile?.path ?? '');
    }
    // androidName 不能带前导点：插件按「包名 + androidName」反射查找 Provider 类
    await HomeWidget.updateWidget(
      name: 'WaterLlamaWidgetProvider',
      androidName: 'WaterLlamaWidgetProvider',
    );
  } catch (_) {
    // 静默失败：桌面端/测试环境没有插件实现，小组件同步不应影响主流程
  }
}
