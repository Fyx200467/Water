import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/health/health_sync_service.dart';
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
final profileProvider = StateNotifierProvider<ProfileNotifier, UserProfile?>((ref) {
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
  }

  Future<void> updateGoal(int newGoal) async {
    final cur = state;
    if (cur == null) return;
    final next = cur.copyWith(dailyGoalMl: newGoal.clamp(1000, 5000));
    await save(next);
    unawaited(pushHomeWidget(ref));
  }
}

/// 单位偏好（首次启动在欢迎页选择）
final preferredUnitProvider =
    StateNotifierProvider<PreferredUnitNotifier, PreferredUnit>((ref) {
  return PreferredUnitNotifier(ref);
});

class PreferredUnitNotifier extends StateNotifier<PreferredUnit> {
  PreferredUnitNotifier(this.ref) : super(PreferredUnit.ml) {
    _load();
  }
  final Ref ref;

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final raw = storage.loadPreferredUnit();
    state = raw == 'oz' ? PreferredUnit.oz : PreferredUnit.ml;
    UnitFormat.unit = state;
  }

  Future<void> select(PreferredUnit unit) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.savePreferredUnit(unit.name);
    state = unit;
    UnitFormat.unit = unit;
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

/// PRD §2.3 当日饮水记录
final todayEntriesProvider = StateNotifierProvider<TodayEntriesNotifier, List<DrinkEntry>>((ref) {
  return TodayEntriesNotifier(ref);
});

class TodayEntriesNotifier extends StateNotifier<List<DrinkEntry>> {
  TodayEntriesNotifier(this.ref) : super(const []) {
    _load();
  }
  final Ref ref;

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    // 「今天」= 逻辑日：重置时刻（默认 00:00）之前仍算昨天
    final list = await storage.loadEntriesForDay(LogicalDay.today());
    state = list;
  }

  /// [celebrate] 为 false 时不发声/不庆祝（小组件后台 isolate 录入用）
  Future<void> add(DrinkEntry entry, {bool celebrate = true}) async {
    final storage = await ref.read(localStorageProvider.future);
    final goalMl = ref.read(profileProvider)?.dailyGoalMl ?? 2000;
    final beforeMl = HydrationCalculator.sumEffective(state);
    await storage.insertDrinkEntry(entry);
    await _load();
    // 健康同步开启时，把这条新记录立刻写进健康 App（失败只记日志）
    unawaited(HealthSyncService.afterEntryAdded(storage));
    // 云同步：先把本地记录推到服务端（离线则留待下次启动/回前台）
    unawaited(SyncService.syncNow(storage));
    final afterMl = HydrationCalculator.sumEffective(state);
    // 只有「真实加水后跨过目标」才庆祝：
    // 删除记录、回前台重载、数据抖动都不会触发（避免误播音效/误点亮）
    if (celebrate && beforeMl < goalMl && afterMl >= goalMl && afterMl > beforeMl) {
      ref.read(goalCrossedProvider.notifier).state++;
      unawaited(SoundService.goalReached());
    }
    unawaited(pushHomeWidget(ref));
  }

  /// 回前台时重载当日记录：小组件后台录入（不拉起 App）在独立 isolate
  /// 直接写库，进程存活期间内存态会滞后，靠这里追平
  Future<void> refresh() => _load();

  Future<void> remove(String clientId) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.softDeleteEntry(clientId);
    await _load();
    // 健康同步开启时，把已导出的样本从健康 App 撤掉
    unawaited(HealthSyncService.afterEntryRemoved(storage));
    unawaited(SyncService.syncNow(storage));
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
