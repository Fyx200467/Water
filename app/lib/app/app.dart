import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      title: '喝水养成',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
