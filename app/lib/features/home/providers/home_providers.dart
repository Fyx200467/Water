import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../shared/models/animal_character.dart';
import '../../../shared/models/drink_entry.dart';
import '../../../shared/models/preferred_unit.dart';
import '../../../shared/models/user_profile.dart';
import '../../drink/services/hydration_calculator.dart';

/// PRD §2.1 用户档案
final profileProvider = StateNotifierProvider<ProfileNotifier, UserProfile?>((ref) {
  return ProfileNotifier(ref);
});

class ProfileNotifier extends StateNotifier<UserProfile?> {
  ProfileNotifier(this.ref, {UserProfile? initial}) : super(initial) {
    // 仅当未预加载时才异步读取（避免覆盖 main.dart 预加载的初始值）
    if (initial == null) _load();
  }
  final Ref ref;

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
  }

  Future<void> select(PreferredUnit unit) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.savePreferredUnit(unit.name);
    state = unit;
  }
}

/// PRD §2.2 当日动物形象
final dailyAnimalProvider = FutureProvider<AnimalCharacter>((ref) async {
  final storage = await ref.read(localStorageProvider.future);
  return storage.pickOrLoadDailyAnimal();
});

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
    final list = await storage.loadEntriesForDay(DateTime.now());
    state = list;
  }

  Future<void> add(DrinkEntry entry) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.insertDrinkEntry(entry);
    await _load();
  }

  Future<void> remove(String clientId) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.softDeleteEntry(clientId);
    await _load();
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
