import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/storage/local_storage.dart';
import '../../core/storage/providers.dart';
import '../../shared/models/beverage.dart';
import '../../shared/models/drink_entry.dart';
import '../drink/providers/custom_beverage_provider.dart';
import '../drink/services/hydration_calculator.dart';
import '../home/providers/home_providers.dart';
import '../stats/providers/stats_providers.dart';
import 'widget_settings_screen.dart';

/// 小组件饮料格后台录入回调（点按不启动 App）
///
/// 原生侧饮料格 PendingIntent 为 HomeWidgetBackgroundIntent 广播，
/// 插件在 headless Dart 引擎里执行本回调——主进程 UI 完全不拉起。
/// 录入走与手动/小组件跳转录入完全相同的 DrinkEntry.create 折算管线；
/// add() 内部写库后自动触发 pushHomeWidget → syncWidgetFromSettings，
/// 桌面数字/饮品图标随之刷新（角色帧渲染在无视图引擎里会静默失败，
/// 沿用上一批帧，不影响数字与图标更新）
@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) async {
  debugPrint('[widget-bg] callback enter uri=$uri');
  try {
    if (uri == null || uri.host != 'quick-add') return;
    final slot = int.tryParse(uri.queryParameters['slot'] ?? '');
    debugPrint('[widget-bg] slot=$slot');
    if (slot == null || slot < 1 || slot > 3) return;
    WidgetsFlutterBinding.ensureInitialized();
    // 后台 isolate 没有 UI 侧的 ProviderScope，独立构建容器读盘
    final container = ProviderContainer(overrides: [
      localStorageProvider.overrideWith((ref) => LocalStorage.init()),
    ]);
    try {
      // 等设置/自定义饮品从磁盘加载完成（后台冷 isolate 必然经历这个窗口）
      await container.read(widgetSettingsProvider.notifier).loaded;
      await container.read(customBeveragesProvider.notifier).loaded;
      final s = container.read(widgetSettingsProvider);
      final (String id, int vol) = switch (slot) {
        1 => (s.drink1, s.vol1),
        2 => (s.drink2, s.vol2),
        _ => (s.drink3, s.vol3),
      };
      if (vol <= 0) return;
      final customs = container.read(customBeveragesProvider);
      final all = [...Beverage.presets, ...customs];
      final b = all.firstWhere((x) => x.id == id, orElse: () => all.first);
      final entry = DrinkEntry.create(beverage: b, volumeMl: vol);
      debugPrint('[widget-bg] adding ${b.id} $vol ml');
      // 后台 isolate 不播庆祝音效（无 UI 且用户不在前台）；
      // 小组件点按音效由原生 QuickAddReceiver 负责
      await container.read(todayEntriesProvider.notifier).add(entry, celebrate: false);
      debugPrint('[widget-bg] inserted ok');
      // add() 内部的 pushHomeWidget 是 unawaited，而容器马上要销毁——
      // 那条推送会在容器 disposed 后读状态而失败，updateWidget 永远不执行
      // （真机实测：数据入库但桌面不刷新）。这里显式等待一次完整推送
      // （数据文本/饮料格写入 → 帧渲染失败跳过 → updateWidget 重绘 RemoteViews）
      // 目标值同理：先等用户档案加载完再读，否则按 2000 兜底导致百分比虚高
      await container.read(profileProvider.notifier).loaded;
      await syncWidgetFromSettings(
        container.read,
        todayMl: HydrationCalculator.sumEffective(
            container.read(todayEntriesProvider)),
        goalMl: container.read(profileProvider)?.dailyGoalMl ?? 2000,
        streakDays: await container.read(checkinDaysProvider.future),
      );
      debugPrint('[widget-bg] widget pushed');
    } finally {
      container.dispose();
    }
  } catch (e, st) {
    // 后台录入失败静默：不影响主流程，App 内仍可正常录入
    debugPrint('[widget-bg] failed: $e\n$st');
  }
}

/// App 启动时注册一次：回调句柄持久化到原生侧，进程被杀后点按仍能拉起
/// 后台引擎执行录入
Future<void> registerHomeWidgetBackgroundCallback() {
  return HomeWidget.registerInteractivityCallback(homeWidgetBackgroundCallback);
}
