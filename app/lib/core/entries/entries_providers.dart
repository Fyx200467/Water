import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/drink_entry.dart';
import '../analytics/analytics.dart';
import '../health/health_sync_service.dart';
import '../profile/profile_provider.dart';
import '../sound/sound_service.dart';
import '../storage/providers.dart';
import '../sync/sync_service.dart';
import '../time/logical_day.dart';
import '../widget/widget_settings_provider.dart';

/// 今日目标刚被跨过的信号：真实加水（add）跨过目标时 +1
///
/// 首页据此点亮角色并播放庆祝音效。用显式信号而不是监听进度变化，
/// 避免「删除记录 / 重载数据」等进度回落再回升造成的误庆祝。
final goalCrossedProvider = StateProvider<int>((ref) => 0);

/// 会话纪元：登录 / 退出 / 被其他设备顶下线时 +1。
///
/// 所有按「当前归属账号」读取的数据 provider 都 watch 它：会话一变就
/// 用新的 owner 立即重新查库，避免首页出现「记录还是账号的、进度却已
/// 切回游客」这种混合状态（顶号后记录与总量对不上的根因）。
final sessionEpochProvider = StateProvider<int>((ref) => 0);

/// PRD §2.3 当日饮水记录
final todayEntriesProvider =
    StateNotifierProvider<TodayEntriesNotifier, List<DrinkEntry>>((ref) {
      // 会话切换（登录/退出/顶号）后自动按新归属重新加载
      ref.watch(sessionEpochProvider);
      return TodayEntriesNotifier(ref);
    });

class TodayEntriesNotifier extends StateNotifier<List<DrinkEntry>> {
  TodayEntriesNotifier(this.ref) : super(const []) {
    loaded = _load();
  }
  final Ref ref;

  /// 首轮磁盘加载完成信号
  late final Future<void> loaded;

  Future<void> _load() async {
    // 首次失败（登录瞬间的库迁移/锁冲突等偶发错误）自动重试一次，
    // 否则错误被吞掉后列表会一直停在空值，直到下次手动触发
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final storage = await ref.read(localStorageProvider.future);
        // 「今天」= 逻辑日：重置时刻（默认 00:00）之前仍算昨天
        final list = await storage.loadEntriesForDay(LogicalDay.today());
        if (!mounted) return;
        state = list;
        return;
      } catch (e) {
        // 查询失败时保留上一次成功的列表，避免首页数字瞬间归零
        debugPrint('[home] load today entries failed ($attempt): $e');
        if (attempt == 0 && mounted) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    }
  }

  /// [celebrate] 为 false 时不发声/不庆祝（小组件后台 isolate 录入用）
  Future<void> add(DrinkEntry entry, {bool celebrate = true}) async {
    final storage = await ref.read(localStorageProvider.future);
    final goalMl = ref.read(profileProvider)?.dailyGoalMl ?? 2000;
    final beforeMl = _sumEffective(state);
    await storage.insertDrinkEntry(entry);
    await _load();
    // 本地写入后立刻让「待同步 N 条」刷新（同步完成时还会再刷一次）
    ref.read(syncRevisionProvider.notifier).state++;
    // 健康同步开启时，把这条新记录立刻写进健康 App（失败只记日志）
    unawaited(HealthSyncService.afterEntryAdded(storage));
    // 云同步：开启无感同步时把本地记录推到服务端（离线则留待下次启动/回前台）
    unawaited(SyncService.autoSync(storage));
    final afterMl = _sumEffective(state);
    // 漏斗辅助指标：有真实打卡行为的用户数（含游客，服务端按 actor 去重）
    // 补录历史日期不算「今天打卡」，否则回填旧记录会虚增当日活跃
    if (entry.belongsToDay(LogicalDay.today())) {
      Analytics.track(
        'checkin',
        props: {
          'volumeMl': entry.volumeMl,
          'effectiveMl': entry.effectiveMl,
          'beverage': entry.beverageId,
        },
      );
    }
    // 只有「真实加水后跨过目标」才庆祝：
    // 删除记录、回前台重载、数据抖动都不会触发（避免误播音效/误点亮）
    if (celebrate &&
        beforeMl < goalMl &&
        afterMl >= goalMl &&
        afterMl > beforeMl) {
      ref.read(goalCrossedProvider.notifier).state++;
      unawaited(SoundService.goalReached());
    }
    unawaited(ref.read(widgetSyncTriggerProvider)());
  }

  /// 回前台时重载当日记录：小组件后台录入（不拉起 App）在独立 isolate
  /// 直接写库，进程存活期间内存态会滞后，靠这里追平
  Future<void> refresh() => _load();

  Future<void> remove(String clientId) async {
    // 删除前取快照：删除后本地已查不到这条，埋点/指标需要原始数值
    DrinkEntry? removed;
    for (final e in state) {
      if (e.clientId == clientId) {
        removed = e;
        break;
      }
    }
    final storage = await ref.read(localStorageProvider.future);
    await storage.softDeleteEntry(clientId);
    await _load();
    // 删除同样会产生待上行的墓碑，立即刷新待同步提示
    ref.read(syncRevisionProvider.notifier).state++;
    // 健康同步开启时，把已导出的样本从健康 App 撤掉
    unawaited(HealthSyncService.afterEntryRemoved(storage));
    unawaited(SyncService.autoSync(storage));
    // 删除是与打卡相反的修正行为，单独上报（不计入 checkin 漏斗），
    // 用于观察误录率：删得多的用户往往是把「补录」当「打卡」
    if (removed != null) {
      Analytics.track(
        'entry_remove',
        props: {
          'volumeMl': removed.volumeMl,
          'effectiveMl': removed.effectiveMl,
          'beverage': removed.beverageId,
          'sameDay': removed.belongsToDay(LogicalDay.today()) ? 1 : 0,
        },
      );
    }
    unawaited(ref.read(widgetSyncTriggerProvider)());
  }
}

int _sumEffective(List<DrinkEntry> entries) =>
    entries.fold<int>(0, (s, e) => s + e.effectiveMl);
