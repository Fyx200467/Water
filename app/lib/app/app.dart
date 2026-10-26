import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/health/health_sync_service.dart';
import '../core/storage/providers.dart';
import '../core/sync/sync_service.dart';
import '../features/home/providers/home_providers.dart';
import '../features/reminder/reminder_providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// App 根组件：除主题/路由外，还承担提醒通知的**全局调度触发器**——
/// 冷启动 / 回前台 / 当日记录或目标变化时防抖重排通知（通知内容里的
/// 「剩余水量」、达标停止、智能跳过都依赖最新数据），以及前台快速
/// 添加按钮的录入回调注入
class WaterLlamaApp extends ConsumerStatefulWidget {
  const WaterLlamaApp({super.key});

  @override
  ConsumerState<WaterLlamaApp> createState() => _WaterLlamaAppState();
}

class _WaterLlamaAppState extends ConsumerState<WaterLlamaApp>
    with WidgetsBindingObserver {
  Timer? _reschedTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 冷启动：等存储与各设置 provider 完成首载后重排一轮
    //（上次排程的槽位可能已被设置变更/时间流逝作废）
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        ref.read(reminderProvider.notifier).rescheduleNow();
      }
    });
    // 冷启动：健康同步开着就静默补跑一轮（6 小时内不重复），
    // 补上小组件后台录入、以及在健康 App 里新增的外部饮水
    Timer(const Duration(seconds: 3), () async {
      if (!mounted) return;
      final storage = await ref.read(localStorageProvider.future);
      final report = await HealthSyncService.maybeAutoSync(storage);
      if (report.imported > 0 && mounted) {
        ref.invalidate(todayEntriesProvider);
      }
    });
    // 冷启动：注册匿名身份并跑一轮云同步（断网失败不影响本地使用）
    Timer(const Duration(seconds: 2), () async {
      if (!mounted) return;
      final storage = await ref.read(localStorageProvider.future);
      final result = await SyncService.syncNow(storage);
      if (result.pulled > 0 && mounted) {
        ref.invalidate(todayEntriesProvider);
      }
    });
    // 当日记录 / 目标变化：达标停止与剩余水量随数据实时刷新
    ref.listenManual(todayEntriesProvider, (_, _) => _scheduleReschedule());
    ref.listenManual(profileProvider, (_, _) => _scheduleReschedule());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reschedTimer?.cancel();
    super.dispose();
  }

  /// 回前台：补排期间流逝的槽位（数据/设置可能由小组件后台路径改写）
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleReschedule();
      // 回前台补跑一轮同步（可能在别的设备上改过数据）
      unawaited(() async {
        final storage = await ref.read(localStorageProvider.future);
        final result = await SyncService.syncNow(storage);
        if (result.pulled > 0 && mounted) {
          ref.invalidate(todayEntriesProvider);
        }
      }());
    }
  }

  /// 防抖重排：1.5 秒内的连续触发（如批量补录、连续改设置）只排最后一轮
  void _scheduleReschedule() {
    _reschedTimer?.cancel();
    _reschedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        ref.read(reminderProvider.notifier).rescheduleNow();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: '吨吨',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
