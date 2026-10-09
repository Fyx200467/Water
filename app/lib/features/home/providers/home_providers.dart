import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../shared/models/animal_character.dart';
import '../../../shared/models/drink_entry.dart';
import '../../../shared/models/member_state.dart';
import '../../../shared/models/user_profile.dart';
import '../../drink/services/hydration_calculator.dart';

/// PRD §2.1 用户档案
final profileProvider = StateNotifierProvider<ProfileNotifier, UserProfile?>((ref) {
  return ProfileNotifier(ref);
});

class ProfileNotifier extends StateNotifier<UserProfile?> {
  ProfileNotifier(this.ref) : super(null) {
    _load();
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

/// PRD §2.7 会员状态
final memberProvider = StateNotifierProvider<MemberNotifier, MemberState>((ref) {
  return MemberNotifier(ref);
});

class MemberNotifier extends StateNotifier<MemberState> {
  MemberNotifier(this.ref) : super(MemberState.free()) {
    _load();
  }
  final Ref ref;

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    state = storage.loadMember();
  }

  Future<void> upgrade(MemberPlan plan, DateTime expireAt) async {
    final next = MemberState(
      isMember: true,
      plan: plan,
      expireAt: expireAt,
      benefits: const MemberBenefits.premium(),
    );
    final storage = await ref.read(localStorageProvider.future);
    await storage.saveMember(next);
    state = next;
  }
}

/// PRD §2.2 当日动物形象
final dailyAnimalProvider = FutureProvider<AnimalCharacter>((ref) async {
  final storage = await ref.read(localStorageProvider.future);
  final member = ref.watch(memberProvider);
  return storage.pickOrLoadDailyAnimal(isMember: member.isValid);
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
