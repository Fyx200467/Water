import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/health/health_sync_service.dart';
import '../core/storage/providers.dart';
import '../core/sync/character_sync.dart';
import '../core/sync/container_icon_sync.dart';
import '../core/sync/sync_service.dart';
import '../features/characters/character_catalog.dart';
import '../features/drink/widgets/svg_container.dart' show invalidateSvgContainerIdsCache;
import '../features/home/providers/home_providers.dart';
import '../features/reminder/reminder_providers.dart';
import '../features/settings/cloud_backup_screen.dart'
    show cloudBackupStateProvider;
import '../features/stats/providers/stats_providers.dart';
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
  bool _revokedDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 账号在别的设备登录时，同步会收到 session_revoked，这里统一弹窗告知
    SyncService.onSessionRevoked = _showSessionRevokedDialog;
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
    // 冷启动：已登录且开启无感同步时跑一轮（未登录为纯本地，断网失败均不影响使用）
    Timer(const Duration(seconds: 2), () async {
      if (!mounted) return;
      final storage = await ref.read(localStorageProvider.future);
      final result = await SyncService.autoSync(storage);
      if ((result?.pulled ?? 0) > 0 && mounted) {
        ref.invalidate(todayEntriesProvider);
        ref.invalidate(yearEntriesProvider);
      }
    });
    // 冷启动：容器图标库与服务器对齐（联网才生效，离线沿用上次缓存/内置图标）
    Timer(const Duration(seconds: 2), () {
      if (mounted) _syncContainerIcons();
    });
    // 冷启动：角色分类与角色素材与服务器对齐（后台新增/删除实时生效）
    Timer(const Duration(seconds: 2), () {
      if (mounted) _syncCharacters();
    });
    // 当日记录 / 目标变化：达标停止与剩余水量随数据实时刷新
    ref.listenManual(todayEntriesProvider, (_, _) => _scheduleReschedule());
    ref.listenManual(profileProvider, (_, _) => _scheduleReschedule());
  }

  @override
  void dispose() {
    if (SyncService.onSessionRevoked == _showSessionRevokedDialog) {
      SyncService.onSessionRevoked = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _reschedTimer?.cancel();
    super.dispose();
  }

  /// 其他设备登录后本机会话已失效：弹窗告知（本机数据保留，不自动删除）
  void _showSessionRevokedDialog() {
    if (!mounted || _revokedDialogShown) return;
    _revokedDialogShown = true;
    ref.invalidate(cloudBackupStateProvider);
    // 会话已失效：本机立刻切回游客视图，不再显示该账号的数据
    ref.invalidate(todayEntriesProvider);
    ref.invalidate(yearEntriesProvider);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('账号已在其他设备登录'),
        content: const Text(
          '当前设备已自动退出登录，本机饮水记录仍然保留。\n'
          '如需继续云同步，请重新登录。',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _revokedDialogShown = false;
            },
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 容器图标库同步：缺的下载、服务端已删除的清理；失败静默（离线可用）
  Future<void> _syncContainerIcons() async {
    final changed = await ContainerIconStore.sync();
    if (changed) invalidateSvgContainerIdsCache();
  }

  /// 角色目录同步：后台新增的分类/角色下载到本地，删除的从列表移除
  Future<void> _syncCharacters() async {
    final changed = await CharacterStore.sync();
    if (changed) ref.invalidate(characterCatalogProvider);
  }

  /// 回前台：补排期间流逝的槽位（数据/设置可能由小组件后台路径改写）
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleReschedule();
      // 回到前台且已联网：图标库、角色目录、账号数据各补跑一轮
      unawaited(_syncContainerIcons());
      unawaited(_syncCharacters());
      unawaited(() async {
        final storage = await ref.read(localStorageProvider.future);
        final result = await SyncService.autoSync(storage);
        if ((result?.pulled ?? 0) > 0 && mounted) {
          ref.invalidate(todayEntriesProvider);
          ref.invalidate(yearEntriesProvider);
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
