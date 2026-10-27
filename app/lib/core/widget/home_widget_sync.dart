import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../shared/models/preferred_unit.dart';

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
    this.id = '',
    this.iconFile,
    this.effectiveMl, // 折算后水量（原生点按累加口径；null = 未折算）
  });

  final int ml;
  final String name;

  /// 饮品 id：原生点按队列随条目携带，App 补录时按当时的饮品入库，
  /// 避免用户点完又改了饮品格配置导致入错饮品
  final String id;
  final File? iconFile; // 已渲染的饮品图标 PNG

  /// 折算后水量：与 App 内 HydrationCalculator 同口径（如咖啡按系数折算）。
  /// 原生快捷录入按它累加今日总量/百分比，避免点按后桌面与 App 数字轻微不一致
  final int? effectiveMl;
}

/// 饮料格容量文案（跟随全局测量单位；ml 模式 <1000 显示「Nml」，≥1000 换算升）
String tileMlLabel(int ml) {
  if (UnitFormat.unit == PreferredUnit.oz) {
    return UnitFormat.volume(ml, compact: true);
  }
  if (ml >= 1000) {
    final liters = ml / 1000;
    final text = liters == liters.roundToDouble()
        ? liters.toStringAsFixed(0)
        : liters.toStringAsFixed(1);
    return '${text}L';
  }
  return '${ml}ml';
}

/// iOS App Group 只设置一次（Plugin 内部会缓存到 method channel 侧）
bool _appGroupConfigured = false;

Future<void> syncHomeWidget({
  required int todayMl,
  required int goalMl,
  required int streakDays,
  Color? themeColor, // null = 默认白底
  bool showStreak = true, // 连续徽章显隐
  int tileColor = -2, // 饮料格底色（-2 = 默认灰底；-1 是合法颜色值，不能当哨兵）
  List<WidgetDrinkData> drinks = const [],
  bool recordEnabled = true, // 未完成初始化引导时 false：只展示不可录入
  int resetMinutes = 0, // 逻辑日重置时刻（距零点分钟数），原生跨天判定用
  String? streakAnchor, // 连续链已计入的最后一个逻辑日（yyyy-MM-dd）；null = 数据未就绪不覆盖
  bool widgetSounds = true, // 小部件点按是否播放提示音（原生 QuickAddReceiver 读取）
}) async {
  // 仅移动端执行（kIsWeb 需先排除：Web 平台没有 dart:io 的 Platform）
  if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
  try {
    // iOS WidgetKit 通过 App Group 共享 UserDefaults，首次写入前设置组名
    if (Platform.isIOS && !_appGroupConfigured) {
      await HomeWidget.setAppGroupId('group.com.waterllama.waterLlama');
      _appGroupConfigured = true;
    }
    // 左上大字：当日饮水总量（与 App 内预览卡实时绑定）。
    // 数字/单位拆成两键两 TextView 同行——单 TextView 混排在 vivo
    // launcher 上会被异常换行/裁切。≥1L 一位小数（1.0升），否则 ml
    final String goalNum;
    final String goalUnit;
    if (UnitFormat.unit == PreferredUnit.oz) {
      goalNum = UnitFormat.number(todayMl);
      goalUnit = 'oz';
    } else if (todayMl >= 1000) {
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
          'drink${i}_ml', d == null ? '' : tileMlLabel(d.ml));
      // 未初始化闸门：录入数值强制 0 → 原生 QuickAddReceiver 的
      // ml<=0 检查天然拒绝（方案 A）；界面文案/图标照常展示
      await HomeWidget.saveWidgetData<int>(
          'drink${i}_ml_value', recordEnabled ? (d?.ml ?? 0) : 0);
      // -1 = 未折算（原生回退按原容量累加）；0 合法（无水合贡献的饮品）
      await HomeWidget.saveWidgetData<int>(
          'drink${i}_eff_ml_value',
          !recordEnabled ? 0 : (d?.effectiveMl ?? -1));
      // 饮品 id：原生点按队列条目随身携带，App 补录按点按时配置入库
      await HomeWidget.saveWidgetData<String>('drink${i}_id', d?.id ?? '');
      await HomeWidget.saveWidgetData<String>('drink${i}_name', d?.name ?? '');
      await HomeWidget.saveWidgetData<String>(
          'drink${i}_icon', d?.iconFile?.path ?? '');
    }
    // 原生快速路径键：vivo 冻结窗口内点按录入由 QuickAddReceiver 直接
    // 读写这些数值（不拉起 Dart 引擎），跨天用 widget_date 判定归零
    await HomeWidget.saveWidgetData<int>('widget_today_ml', todayMl);
    await HomeWidget.saveWidgetData<int>('goal_ml', goalMl);
    // 逻辑日：跨天分界不是午夜而是用户设置的「一天重置时间」，
    // 原生侧无法读 App 设置，故把重置时刻与今天的逻辑日 key 一并下发
    await HomeWidget.saveWidgetData<int>('reset_hour', resetMinutes ~/ 60);
    await HomeWidget.saveWidgetData<int>('reset_minute', resetMinutes % 60);
    if (streakAnchor != null) {
      await HomeWidget.saveWidgetData<String>('streak_anchor', streakAnchor);
    }
    // 原生双保险闸门键（方案 B）：QuickAddReceiver 见 false 拒绝录入
    await HomeWidget.saveWidgetData<bool>(
        'profile_initialized', recordEnabled);
    // 点按音效开关：原生快捷录入路径在播放提示音前读取
    await HomeWidget.saveWidgetData<bool>('widget_sounds', widgetSounds);
    final now = DateTime.now();
    var logicalDay = DateTime(now.year, now.month, now.day);
    if (now.hour * 60 + now.minute < resetMinutes) {
      logicalDay = logicalDay.subtract(const Duration(days: 1));
    }
    await HomeWidget.saveWidgetData<String>(
        'widget_date',
        '${logicalDay.year}-${logicalDay.month.toString().padLeft(2, '0')}-'
        '${logicalDay.day.toString().padLeft(2, '0')}');
    // androidName 不能带前导点：插件按「包名 + androidName」反射查找 Provider 类
    // iOSName 对应 WidgetKit 的 kind（Swift 侧 kind = "WaterLlamaWidget"）
    await HomeWidget.updateWidget(
      name: 'WaterLlamaWidgetProvider',
      androidName: 'WaterLlamaWidgetProvider',
      iOSName: 'WaterLlamaWidget',
    );
  } catch (_) {
    // 静默失败：桌面端/测试环境没有插件实现，小组件同步不应影响主流程
  }
}
