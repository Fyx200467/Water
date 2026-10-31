import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics/analytics.dart';
import '../core/app_info.dart';
import '../core/health/health_sync_service.dart';
import '../core/settings/account_settings.dart';
import '../core/storage/providers.dart';
import '../core/sync/character_sync.dart';
import '../core/sync/points_sync.dart';
import '../core/sync/container_icon_sync.dart';
import '../core/sync/profile_sync.dart';
import '../core/sync/session_watch.dart';
import '../core/sync/sync_api.dart';
import '../core/sync/sync_service.dart';
import '../features/challenges/challenge_service.dart';
import '../features/characters/character_catalog.dart';
import '../features/drink/providers/beverage_catalog_provider.dart';
import '../features/drink/providers/custom_beverage_provider.dart';
import '../features/drink/widgets/svg_container.dart'
    show invalidateSvgContainerIdsCache;
import '../features/home/providers/home_providers.dart';
import '../features/membership/membership_provider.dart';
import '../features/points/points_provider.dart';
import '../features/reminder/reminder_providers.dart';
import '../features/settings/cloud_backup_screen.dart'
    show cloudBackupStateProvider;
import '../features/settings/widget_settings_screen.dart'
    show widgetSettingsProvider;
import '../features/stats/providers/stats_providers.dart';
import '../shared/models/preferred_unit.dart';
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
  Timer? _catalogTimer;
  bool _revokedDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 账号在别的设备登录时，SSE 实时通道 / 同步会收到 session_revoked，统一弹窗告知
    SyncService.onSessionRevoked = _showSessionRevokedDialog;
    SessionWatch.onRevoked = _showSessionRevokedDialog;
    // 登录 / 退出 / 被顶下线：推进会话纪元，按账号归属读取的数据统一重载
    SyncService.onSessionChanged = _handleSessionChanged;
    // 云端账号级偏好（单位 / 角色 / 自定义饮品）应用到本机后刷新界面
    SyncService.onSettingsSynced = _handleSettingsSynced;
    // 每轮同步（成功/失败）结束：刷新账号卡的待同步条数与上次同步时间
    SyncService.onSyncFinished = () {
      if (!mounted) return;
      ref.read(syncRevisionProvider.notifier).state++;
    };
    // 云端积分余额 / 明细合并到本机后刷新积分页
    PointsSync.onSynced = _handlePointsSynced;
    // 头像在后台同步（如另一台设备换头像）后，刷新账号页展示
    ProfileSync.onAvatarSynced = () {
      if (mounted) ref.invalidate(cloudBackupStateProvider);
    };
    // 账号档案以云端为准时，刷新主页目标与进度
    ProfileSync.onProfileSynced = () {
      if (!mounted) return;
      ref.invalidate(profileProvider);
      ref.invalidate(todayEntriesProvider);
    };
    // 冷启动：已登录则建立会话实时通道，另一台设备登录时立即收到通知
    unawaited(() async {
      final storage = await ref.read(localStorageProvider.future);
      if (storage.hasAccountSession) {
        SessionWatch.start(storage.syncToken!);
      }
    }());
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
    // 冷启动：挑战目录与后台对齐（后台新增/下架挑战无需重启 App）
    Timer(const Duration(seconds: 2), () {
      if (mounted) ref.invalidate(challengesCatalogProvider);
    });
    // 前台常驻：角色目录定时与后台对齐，后台改分类 / 权益 / 角色后无需
    // 重启或切后台即可生效（后台无推送，用轻量轮询实现「实时同步」）
    _catalogTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final state = WidgetsBinding.instance.lifecycleState;
      if (state != null && state != AppLifecycleState.resumed) return;
      unawaited(_syncCharacters());
      // 饮品目录同样定时对齐：后台改图标 / 排序 / 新增后最多 30 秒生效
      unawaited(_syncBeverages());
      // 挑战目录同样轻量轮询：后台发布/下架挑战最多 30 秒生效
      ref.invalidate(challengesCatalogProvider);
      // 会员状态 / 审核结果轮询：后台通过或拒绝后 30 秒内即可在 App 内看到
      unawaited(_pollMembership());
      // 账号资料（头像 / 饮水目标）对齐，跨设备修改最多 30 秒同步
      unawaited(() async {
        final storage = await ref.read(localStorageProvider.future);
        await ProfileSync.sync(storage);
      }());
    });
    // 冷启动：检查内测新版本，后台发布后提示更新，避免用户长期停留在旧包
    Timer(const Duration(seconds: 4), () {
      if (mounted) _checkAppUpdate();
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
    SyncService.onSessionChanged = null;
    SyncService.onSettingsSynced = null;
    SyncService.onSyncFinished = null;
    PointsSync.onSynced = null;
    ProfileSync.onAvatarSynced = null;
    ProfileSync.onProfileSynced = null;
    if (SessionWatch.onRevoked == _showSessionRevokedDialog) {
      SessionWatch.onRevoked = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _reschedTimer?.cancel();
    _catalogTimer?.cancel();
    super.dispose();
  }

  /// 内测版本提示：后台发布更高 build 号后，冷启动弹窗提醒（可配置强制更新）
  Future<void> _checkAppUpdate() async {
    try {
      final platform = kIsWeb ? 'android' : Platform.operatingSystem;
      final res = await SyncApi.appVersion(platform);
      final latest = (res['versionCode'] as num?)?.toInt() ?? 0;
      if (latest <= kAppVersionCode || !mounted) return;
      final force = res['forceUpdate'] == true;
      final notes = (res['notes'] as String?)?.trim();
      final downloadUrl = (res['downloadUrl'] as String?)?.trim();
      await showDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text('发现新版本 ${res['versionName'] ?? ''}'.trim()),
          content: Text(
            '${notes?.isNotEmpty == true ? notes : '内测版本已更新，建议升级后再体验。'}\n\n'
            '${downloadUrl?.isNotEmpty == true ? '下载地址：$downloadUrl' : '请到内测群获取最新安装包。'}',
            style: const TextStyle(height: 1.5),
          ),
          actions: [
            if (!force)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('稍后'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
    } catch (_) {
      // 版本检查失败不影响启动
    }
  }

  /// 会话归属账号发生变化：推进会话纪元，让所有按 owner 读取的数据
  /// （首页记录 / 进度 / 历史 / 统计）用同一份新归属数据一起刷新，
  /// 避免出现「记录还是账号的、填充和总量已经归零」的混合渲染。
  void _handleSessionChanged() {
    if (!mounted) return;
    ref.read(sessionEpochProvider.notifier).state++;
    ref.invalidate(profileProvider);
    ref.invalidate(cloudBackupStateProvider);
    // 按归属账号读取的数据要显式失效：不能只靠「今日记录列表内容变化」
    // 驱动下游重算——新旧归属的数据恰好都为空时（退出/顶号回到游客），
    // 列表还是同一个 const []，Riverpod 不会通知下游，历史/统计会继续
    // 显示上一归属的缓存，出现「首页 0ml 但历史仍有记录」的混合状态
    ref.invalidate(todayEntriesProvider);
    ref.invalidate(yearEntriesProvider);
    ref.invalidate(checkinDaysProvider);
    ref.invalidate(bestCheckinDaysProvider);
    ref.invalidate(monthDataProvider);
    ref.invalidate(dayEntriesForProvider);
    // 立刻按新归属完成一次加载，首页不用等下一次触发才追上
    unawaited(ref.read(todayEntriesProvider.notifier).loaded);
    // 账号级偏好也要立刻切到新归属：单位是静态全局值，只能显式重读
    unawaited(_applyOwnerUnit());
    // 会员状态以服务端为准：登录后主动拉一次，不依赖定时轮询
    unawaited(_refreshMembershipOnLogin());
    // 退出 / 被顶下线：会员是账号权益，立刻清掉本机会员状态
    unawaited(_resetMembershipOnLogout());
  }

  Future<void> _resetMembershipOnLogout() async {
    final storage = await ref.read(localStorageProvider.future);
    if (!mounted || storage.hasAccountSession) return;
    await ref.read(membershipProvider.notifier).reset();
  }

  /// 登录后按服务端会员状态刷新本机会员（离线失败时保留本地缓存）
  Future<void> _refreshMembershipOnLogin() async {
    final storage = await ref.read(localStorageProvider.future);
    if (!mounted || !storage.hasAccountSession) return;
    try {
      await ref.read(membershipProvider.notifier).restore();
    } catch (_) {
      // 未登录 / 网络不可达：保留本地状态，定时轮询会再校正
    }
  }

  /// 云端账号级偏好已应用到本机：刷新偏好 provider 与全局单位
  void _handleSettingsSynced() {
    if (!mounted) return;
    ref.read(accountSettingsRevisionProvider.notifier).state++;
    unawaited(_applyOwnerUnit());
  }

  /// 云端积分已合并到本机：积分页按账号重新加载
  void _handlePointsSynced() {
    if (!mounted) return;
    ref.read(pointsRevisionProvider.notifier).state++;
  }

  /// 按当前归属账号重读单位偏好，并同步到全局格式化 / 桌面小组件
  Future<void> _applyOwnerUnit() async {
    final storage = await ref.read(localStorageProvider.future);
    final raw = storage.loadPreferredUnit();
    if (!mounted) return;
    UnitFormat.unit = raw == 'oz' ? PreferredUnit.oz : PreferredUnit.ml;
    // 单位切换后桌面小组件文案立即跟随（ml ↔ oz）
    unawaited(ref.read(widgetSettingsProvider.notifier).refreshWidget());
  }

  /// 其他设备登录后本机会话已失效：弹窗告知（本机数据保留，不自动删除）
  void _showSessionRevokedDialog() {
    unawaited(_handleSessionRevoked());
  }

  Future<void> _handleSessionRevoked() async {
    if (!mounted || _revokedDialogShown) return;
    _revokedDialogShown = true;
    SessionWatch.stop();
    final storage = await ref.read(localStorageProvider.future);
    // 恢复游客档案并清掉本机账号会话（重复调用是幂等的；内部会推进会话纪元）
    await SyncService.handleSessionRevoked(storage);
    if (!mounted) return;
    ref.invalidate(cloudBackupStateProvider);
    ref.invalidate(profileProvider);
    // 会员是账号权益，会话失效后同样不能留在本机
    await ref.read(membershipProvider.notifier).reset();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('账号已在其他设备登录'),
        content: const Text(
          '当前设备已自动退出登录，本机饮水记录仍然保留在本地。\n'
          '退出状态下展示本机游客数据，重新登录即可恢复该账号的记录与目标。',
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

  /// 会员状态轮询：
  /// - 后台确认后本机自动开通，无需重进会员页；
  /// - 后台拒绝后弹窗告知（同一订单只提示一次）。
  Future<void> _pollMembership() async {
    if (!mounted) return;
    final storage = await ref.read(localStorageProvider.future);
    if (!storage.hasAccountSession) return;
    final token = storage.syncToken!;
    try {
      final status = await SyncApi.membershipStatus(token);
      final notifier = ref.read(membershipProvider.notifier);
      if (status['isMember'] == true) {
        final planCode = (status['planCode'] as String?) ?? 'member';
        final expireAt = DateTime.tryParse(
          status['expireAt']?.toString() ?? '',
        );
        final permanent = status['permanent'] == true;
        final current = ref.read(membershipProvider);
        final changed =
            !current.hasPaidOrder ||
            current.planCode != planCode ||
            (permanent
                ? current.expireAt != null
                : current.expireAt != expireAt);
        if (changed) {
          await notifier.applyServer(
            planCode: planCode,
            expireAt: expireAt,
            permanent: permanent,
          );
        }
      } else if (ref.read(membershipProvider).hasPaidOrder) {
        // 服务端已无有效会员（如过期 / 被后台收回）：只清付费部分，保留积分兑换
        await notifier.restore();
      }

      final latest = await SyncApi.latestMembershipOrder(token);
      final statusText = latest?['status']?.toString();
      if (statusText != 'rejected') return;
      final orderId = latest?['id']?.toString() ?? '';
      if (orderId.isEmpty ||
          storage.lastRejectedNoticeOrderId == orderId ||
          !mounted) {
        return;
      }
      await storage.setLastRejectedNoticeOrderId(orderId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('会员申请未通过'),
          content: const Text(
            '运营未通过本次开通申请，你可以回到会员页重新选择套餐提交。',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (e is SyncApiException && e.isSessionRevoked) {
        _showSessionRevokedDialog();
      }
      // 离线 / 服务端异常静默跳过，下轮再试
    }
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

  /// 饮品目录同步：刷新目录后把本机饮品顺序对齐到后台排序
  Future<void> _syncBeverages() async {
    await ref.read(beverageCatalogProvider.notifier).refresh();
    final library = ref.read(beverageLibraryProvider);
    if (library.isEmpty) return;
    await ref.read(homeDrinksProvider.notifier).syncCatalogOrder([
      for (final b in library) b.id,
    ]);
  }

  /// 回前台：补排期间流逝的槽位（数据/设置可能由小组件后台路径改写）
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 切回前台先把上次入队的埋点补发掉（离线时静默失败）
      unawaited(Analytics.flush());
      _scheduleReschedule();
      // 回到前台：先对齐会员状态，后台刚确认/拒绝时无需重进页面
      unawaited(_pollMembership());
      // 回到前台且已联网：图标库、角色目录、饮品目录、账号数据各补跑一轮
      unawaited(_syncContainerIcons());
      unawaited(_syncCharacters());
      unawaited(_syncBeverages());
      unawaited(() async {
        final storage = await ref.read(localStorageProvider.future);
        // 系统可能回收了后台长连接，回前台立即重连实时通道
        if (storage.hasAccountSession) {
          SessionWatch.start(storage.syncToken!);
        }
        final result = await SyncService.autoSync(storage);
        if ((result?.pulled ?? 0) > 0 && mounted) {
          ref.invalidate(todayEntriesProvider);
          ref.invalidate(yearEntriesProvider);
        }
      }());
    } else if (state == AppLifecycleState.paused) {
      // 进后台前尽量把队列里的埋点发出去，避免随进程被杀而丢失
      unawaited(Analytics.flush());
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
