import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/health/health_sync_service.dart';
import '../../../core/settings/account_settings.dart';
import '../../../core/sync/profile_sync.dart';
import '../../../core/sound/sound_service.dart';
import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/time/logical_day.dart';
import '../../../shared/models/animal_character.dart';
import '../../../shared/models/drink_entry.dart';
import '../../../shared/models/preferred_unit.dart';
import '../../../shared/models/user_profile.dart';
import '../../drink/services/hydration_calculator.dart';
import '../../settings/widget_settings_screen.dart';
import '../../stats/providers/stats_providers.dart';

/// 数据变更源头推送：当日记录/目标变化后即时刷新桌面小组件
/// （不依赖各页面手动调用，避免遗漏导致小组件数据滞后）
Future<void> pushHomeWidget(Ref ref) async {
  try {
    final streak = await ref.read(checkinDaysProvider.future);
    await syncWidgetFromSettings(
      ref.read,
      todayMl: HydrationCalculator.sumEffective(ref.read(todayEntriesProvider)),
      goalMl: ref.read(profileProvider)?.dailyGoalMl ?? 2000,
      streakDays: streak,
    );
  } catch (_) {
    // 小组件推送失败不影响录入主流程
  }
}

/// PRD §2.1 用户档案
final profileProvider = StateNotifierProvider<ProfileNotifier, UserProfile?>((
  ref,
) {
  return ProfileNotifier(ref);
});

class ProfileNotifier extends StateNotifier<UserProfile?> {
  ProfileNotifier(this.ref, {UserProfile? initial}) : super(initial) {
    // 仅当未预加载时才异步读取（避免覆盖 main.dart 预加载的初始值）
    loaded = initial == null ? _load() : Future<void>.value();
  }
  final Ref ref;

  /// 磁盘加载完成信号：完成前 state 为 null。小组件后台录入回调若不
  /// 等待它，目标值会走 2000 兜底 → 桌面百分比虚高（如 56% vs App 53%）
  late final Future<void> loaded;

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    state = storage.loadProfile();
  }

  Future<void> save(UserProfile p) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.saveProfile(p);
    state = p;
    // 档案改了：立刻上行到服务端，后台用户列表 / 打卡明细与 App 保持一致
    unawaited(ProfileSync.pushProfile(storage));
  }

  Future<void> updateGoal(int newGoal) async {
    final cur = state;
    if (cur == null) return;
    final next = cur.copyWith(dailyGoalMl: newGoal.clamp(1000, 5000));
    await save(next);
    unawaited(pushHomeWidget(ref));
  }
}

/// 单位偏好（首次启动在欢迎页选择，之后跟随账号上云）
final preferredUnitProvider =
    StateNotifierProvider<PreferredUnitNotifier, PreferredUnit>((ref) {
      // 会话切换 / 云端偏好更新后，按新归属账号的单位重新加载
      ref.watch(sessionEpochProvider);
      ref.watch(accountSettingsRevisionProvider);
      return PreferredUnitNotifier(ref);
    });

class PreferredUnitNotifier extends StateNotifier<PreferredUnit> {
  PreferredUnitNotifier(this.ref) : super(PreferredUnit.ml) {
    _load();
  }
  final Ref ref;

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final raw = storage
        .readAccountSetting(AccountSettingKeys.preferredUnit)
        ?.toString();
    state = raw == 'oz' ? PreferredUnit.oz : PreferredUnit.ml;
    UnitFormat.unit = state;
  }

  Future<void> select(PreferredUnit unit) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.writeAccountSetting(
      AccountSettingKeys.preferredUnit,
      unit.name,
    );
    state = unit;
    UnitFormat.unit = unit;
    // 账号级偏好改动：联网时立即上行，其他设备与后台口径随之同步
    unawaited(SyncService.autoSync(storage));
  }
}

/// PRD §2.2 当日动物形象
final dailyAnimalProvider = FutureProvider<AnimalCharacter>((ref) async {
  final storage = await ref.read(localStorageProvider.future);
  return storage.pickOrLoadDailyAnimal();
});

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
    final beforeMl = HydrationCalculator.sumEffective(state);
    await storage.insertDrinkEntry(entry);
    await _load();
    // 本地写入后立刻让「待同步 N 条」刷新（同步完成时还会再刷一次）
    ref.read(syncRevisionProvider.notifier).state++;
    // 健康同步开启时，把这条新记录立刻写进健康 App（失败只记日志）
    unawaited(HealthSyncService.afterEntryAdded(storage));
    // 云同步：开启无感同步时把本地记录推到服务端（离线则留待下次启动/回前台）
    unawaited(SyncService.autoSync(storage));
    final afterMl = HydrationCalculator.sumEffective(state);
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
    unawaited(pushHomeWidget(ref));
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
    unawaited(pushHomeWidget(ref));
  }
}

/// 首页聚合状态：当前进度 / 剩余 / 完成率
final dailyProgressProvider = Provider<DailyProgress>((ref) {
  final profile = ref.watch(profileProvider);
  final entries = ref.watch(todayEntriesProvider);
  final goalMl = profile?.dailyGoalMl ?? 2000;
  return DailyProgress(
    goalMl: goalMl,
    totalEffectiveMl: HydrationCalculator.sumEffective(entries),
    totalVolumeMl: HydrationCalculator.sumVolume(entries),
    entries: entries,
    progress: HydrationCalculator.progress(entries, goalMl),
    remaining: HydrationCalculator.remaining(entries, goalMl),
  );
});

class DailyProgress {
  const DailyProgress({
    required this.goalMl,
    required this.totalEffectiveMl,
    required this.totalVolumeMl,
    required this.entries,
    required this.progress,
    required this.remaining,
  });
  final int goalMl;
  final int totalEffectiveMl;
  final int totalVolumeMl;
  final List<DrinkEntry> entries;
  final double progress;
  final int remaining;

  bool get isComplete => progress >= 1.0;
}
