import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/sync/sync_api.dart';
import '../../core/time/logical_day.dart';
import '../../shared/models/drink_entry.dart';
import '../home/providers/home_providers.dart';
import '../points/points_provider.dart';
import '../stats/providers/stats_providers.dart';
import 'challenge_catalog.dart';

/// 单个挑战的进度快照
class ChallengeProgress {
  const ChallengeProgress({
    required this.plan,
    required this.joinedAt,
    required this.doneDays,
    required this.todayDone,
    required this.todayMl,
    required this.goalMl,
    required this.claimed,
    this.todayForbidden = false,
    this.dailyMl = const [],
    this.dailyForbidden = const [],
  });

  final HabitData plan;
  final DateTime? joinedAt;
  final int doneDays;
  final bool todayDone;
  final int todayMl;
  final int goalMl;
  final bool claimed;

  /// 今日是否饮用了挑战禁止的饮品
  final bool todayForbidden;

  /// 挑战第 1..N 天的有效饮水量（未来/未开始的天为 0）
  final List<int> dailyMl;

  /// 挑战第 1..N 天是否喝到禁止饮品
  final List<bool> dailyForbidden;

  bool get joined => joinedAt != null;
  bool get completed => doneDays >= plan.days;
}

String _kStartKey(String id) => 'challenge_start_$id';
String _kClaimedKey(String id) => 'challenge_claimed_$id';

/// 开始挑战：记录起始逻辑日（幂等，重复点击不覆盖已有起点）
Future<void> startChallenge(String id) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(_kStartKey(id)) != null) return;
  await prefs.setString(_kStartKey(id), LogicalDay.keyString(LogicalDay.today()));
}

/// 结束挑战：清除起始记录（进度归零），已领取的奖励标记保留，
/// 避免结束后重开同一挑战重复领取积分
Future<void> endChallenge(String id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kStartKey(id));
}

/// 进度刷新信号：开始挑战 / 领取奖励后 +1，页面重新计算
final challengeRevisionProvider = StateProvider<int>((ref) => 0);

/// 服务端下发的挑战目录（拉取失败或为空时回退内置 9 张）
final challengesCatalogProvider = FutureProvider<List<HabitData>>((ref) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client.getUrl(
      Uri.parse('${SyncApi.baseUrl}/v1/catalog/challenges'),
    );
    final res = await req.close().timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) return HabitData.all;
    final body = await res.transform(utf8.decoder).join();
    final data = jsonDecode(body);
    if (data is! Map) return HabitData.all;
    final raw = data['items'];
    if (raw is! List) return HabitData.all;
    final list = <HabitData>[];
    for (final e in raw) {
      if (e is Map<String, dynamic>) {
        try {
          list.add(HabitData.fromJson(e));
        } catch (_) {
          // 单条脏数据跳过，不影响其他挑战
        }
      }
    }
    // 后台成功的空目录：视为「暂无上架挑战」，不回退内置 9 张
    return list;
  } catch (_) {
    return HabitData.all;
  } finally {
    client.close(force: true);
  }
});

/// 当前挑战目录（服务端未就绪时用内置 9 张兜底）
List<HabitData> challengePlans(WidgetRef ref) =>
    ref.watch(challengesCatalogProvider).valueOrNull ?? HabitData.all;

/// 已开始的挑战 id 集合（只读 prefs，首页轻量展示用）
final startedChallengesProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(challengeRevisionProvider);
  final plans = ref.watch(challengesCatalogProvider).valueOrNull ?? HabitData.all;
  final prefs = await SharedPreferences.getInstance();
  return {
    for (final c in plans)
      if (prefs.getString(_kStartKey(c.id)) != null) c.id,
  };
});

/// 全部挑战的进度（首页计数与详情页共用）
final challengeOverviewProvider =
    FutureProvider<Map<String, ChallengeProgress>>((ref) async {
  ref.watch(challengeRevisionProvider);
  // 今日记录变化（喝水达标）或目标调整时自动重算
  ref.watch(todayEntriesProvider);
  final goalMl = ref.watch(profileProvider)?.dailyGoalMl ?? 2000;
  final prefs = await SharedPreferences.getInstance();
  final entries = await ref.watch(yearEntriesProvider.future);

  // 按逻辑日聚合：总有效水量 + 是否出现挑战禁止的饮品
  final byDay = <DateTime, List<DrinkEntry>>{};
  for (final e in entries) {
    byDay.putIfAbsent(LogicalDay.of(e.drankAt), () => []).add(e);
  }
  final today = LogicalDay.today();

  bool hasForbidden(HabitData plan, List<DrinkEntry> list) {
    for (final e in list) {
      if (e.deleted) continue;
      if (plan.forbids(e.beverageCategory, e.beverageName)) return true;
    }
    return false;
  }

  int totalMl(List<DrinkEntry> list) {
    var total = 0;
    for (final e in list) {
      if (!e.deleted) total += e.effectiveMl;
    }
    return total;
  }

  final result = <String, ChallengeProgress>{};
  final plans =
      ref.watch(challengesCatalogProvider).valueOrNull ?? HabitData.all;
  for (final plan in plans) {
    final startStr = prefs.getString(_kStartKey(plan.id));
    final claimed = prefs.getBool(_kClaimedKey(plan.id)) ?? false;
    if (startStr == null) {
      result[plan.id] = ChallengeProgress(
        plan: plan,
        joinedAt: null,
        doneDays: 0,
        todayDone: false,
        todayMl: 0,
        goalMl: goalMl,
        claimed: claimed,
      );
      continue;
    }
    // 起始值存的是逻辑日 key（零点），按天向后累计到今天
    final joinedKey = DateTime.tryParse(startStr) ?? LogicalDay.today();
    final joinedAt = DateTime(joinedKey.year, joinedKey.month, joinedKey.day);
    // 每日水量/禁止标记（长度 = 挑战天数，用于进度卡里的迷你图表）
    final dailyMl = List<int>.filled(plan.days, 0);
    final dailyForbidden = List<bool>.filled(plan.days, false);
    var doneDays = 0;
    var d = joinedAt;
    // 挑战只结算前 plan.days 天，过期后不再累计
    for (var i = 0; i < plan.days && !d.isAfter(today); i++) {
      final list = byDay[d] ?? const <DrinkEntry>[];
      final ml = totalMl(list);
      final forbidden = hasForbidden(plan, list);
      dailyMl[i] = ml;
      dailyForbidden[i] = forbidden;
      // 完成一天 = 当日饮水达标且没有喝到挑战禁止的饮品
      if (ml >= goalMl && !forbidden) doneDays += 1;
      d = d.add(const Duration(days: 1));
    }
    final todayList = byDay[today] ?? const <DrinkEntry>[];
    final todayMl = totalMl(todayList);
    final todayForbidden = hasForbidden(plan, todayList);
    result[plan.id] = ChallengeProgress(
      plan: plan,
      joinedAt: joinedAt,
      doneDays: doneDays,
      todayDone: todayMl >= goalMl && !todayForbidden,
      todayMl: todayMl,
      goalMl: goalMl,
      claimed: claimed,
      todayForbidden: todayForbidden,
      dailyMl: dailyMl,
      dailyForbidden: dailyForbidden,
    );
  }
  return result;
});

/// 正在发放奖励的挑战 id（避免首页与详情页并发重复发放）
final Set<String> _rewardInFlight = {};

/// 完成挑战后自动发放积分（每个挑战只发一次）
///
/// 返回本次到账积分；游客或已领取返回 0。
Future<int> ensureChallengeReward(WidgetRef ref, ChallengeProgress p) async {
  if (!p.joined || !p.completed || p.claimed) return 0;
  final id = p.plan.id;
  if (!_rewardInFlight.add(id)) return 0;
  try {
    final prefs = await SharedPreferences.getInstance();
    // await 期间可能已被另一处发放
    if (prefs.getBool(_kClaimedKey(id)) ?? false) return 0;
    final granted = await ref.read(pointsProvider.notifier).earn(
          source: 'challenge',
          amount: p.plan.rewardPoints,
          dailyCap: p.plan.rewardPoints,
          ignoreDailyCap: true,
        );
    if (granted <= 0) return 0;
    await prefs.setBool(_kClaimedKey(id), true);
    ref.read(challengeRevisionProvider.notifier).state += 1;
    return granted;
  } finally {
    _rewardInFlight.remove(id);
  }
}
