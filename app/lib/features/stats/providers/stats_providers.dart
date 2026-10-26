import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/time/logical_day.dart';
import '../../../shared/models/drink_entry.dart';
import '../../home/providers/home_providers.dart';
import '../services/streak_calculator.dart';

/// 历史窗口：近 3 年（含今天），天数 = 1095
const int historyWindowDays = 1095;

/// 饮品筛选 token：`全部` | `id:<beverageId>` | `name:<beverageName>`
///
/// 优先按 id 匹配，饮品改名后历史记录不会从筛选结果里断链；
/// 仅对「饮品已被删除」的历史记录回退到名称匹配。
bool matchesBeverageFilter(DrinkEntry e, String filter) {
  if (filter.isEmpty || filter == '全部') return true;
  if (filter.startsWith('id:')) return e.beverageId == filter.substring(3);
  if (filter.startsWith('name:')) return e.beverageName == filter.substring(5);
  return e.beverageName == filter;
}

/// 单日聚合
@immutable
class DayTotal {
  const DayTotal({
    required this.day,
    required this.effectiveMl,
    required this.volumeMl,
    required this.count,
    required this.complete,
  });

  final DateTime day;
  final int effectiveMl;
  final int volumeMl;
  final int count;
  final bool complete;
}

Map<int, DayTotal> _aggregate(
  List<DrinkEntry> entries,
  DateTime firstDay,
  int days,
  int goalMl,
) {
  final map = <int, List<DrinkEntry>>{};
  for (final e in entries) {
    // 逻辑日归属：重置时刻之前的记录计入前一天
    final idx = LogicalDay.of(e.drankAt)
        .difference(DateTime(firstDay.year, firstDay.month, firstDay.day))
        .inDays;
    if (idx >= 0 && idx < days) {
      map.putIfAbsent(idx, () => []).add(e);
    }
  }
  final out = <int, DayTotal>{};
  for (var i = 0; i < days; i++) {
    final list = map[i] ?? const [];
    final eff = list.fold<int>(0, (s, e) => s + e.effectiveMl);
    final vol = list.fold<int>(0, (s, e) => s + e.volumeMl);
    out[i] = DayTotal(
      day: DateTime(firstDay.year, firstDay.month, firstDay.day + i),
      effectiveMl: eff,
      volumeMl: vol,
      count: list.length,
      complete: eff >= goalMl,
    );
  }
  return out;
}

int _goalOf(Ref ref) => ref.watch(profileProvider)?.dailyGoalMl ?? 2000;

/// 近 3 年原始记录（逻辑日窗口，含今天）。
///
/// 历史页的列表、趋势图、各饮品面板、连续签到全部从这一份数据本地派生，
/// 同一轮刷新只查一次数据库。
final yearEntriesProvider = FutureProvider<List<DrinkEntry>>((ref) async {
  ref.watch(todayEntriesProvider); // 新增/删除饮水后立即重算
  final storage = await ref.read(localStorageProvider.future);
  final today = LogicalDay.today();
  final start = today.subtract(Duration(days: historyWindowDays - 1));
  return storage.loadEntriesForRange(
    LogicalDay.startOf(start),
    LogicalDay.endOf(today),
  );
});

/// 近 3 年每日聚合（key = 逻辑日零点），供历史页周/月图表本地聚合
final yearDailyProvider = FutureProvider<Map<DateTime, DayTotal>>((ref) async {
  final entries = await ref.watch(yearEntriesProvider.future);
  final today = LogicalDay.today();
  final start = today.subtract(Duration(days: historyWindowDays - 1));
  final map = _aggregate(entries, start, historyWindowDays, _goalOf(ref));
  return {for (final t in map.values) t.day: t};
});

/// 近 3 年每日聚合（按饮品筛选），供历史页周/月柱形图筛选
final filteredYearDailyProvider =
    FutureProvider.family<Map<DateTime, DayTotal>, String>((ref, filter) async {
  final all = await ref.watch(yearEntriesProvider.future);
  final entries =
      all.where((e) => matchesBeverageFilter(e, filter)).toList();
  final today = LogicalDay.today();
  final start = today.subtract(Duration(days: historyWindowDays - 1));
  final map = _aggregate(entries, start, historyWindowDays, _goalOf(ref));
  return {for (final t in map.values) t.day: t};
});

/// 近 7 天（含今天）
final last7DaysProvider = FutureProvider<List<DayTotal>>((ref) async {
  final entries = await ref.watch(yearEntriesProvider.future);
  final today = LogicalDay.today();
  final start = today.subtract(6.days);
  final map = _aggregate(entries, start, 7, _goalOf(ref));
  return [for (var i = 0; i < 7; i++) map[i]!];
});

/// 近 7 天（含今天），按饮品筛选（'全部'=不过滤）
/// 用于历史页天 Tab 柱形图筛选
final filteredLast7DaysProvider =
    FutureProvider.family<List<DayTotal>, String>((ref, filter) async {
  final all = await ref.watch(yearEntriesProvider.future);
  final entries =
      all.where((e) => matchesBeverageFilter(e, filter)).toList();
  final today = LogicalDay.today();
  final start = today.subtract(6.days);
  final map = _aggregate(entries, start, 7, _goalOf(ref));
  return [for (var i = 0; i < 7; i++) map[i]!];
});

/// 指定月份的每日聚合（月历可翻到任意月份，因此单独查询）
final monthDataProvider =
    FutureProvider.family<Map<int, DayTotal>, DateTime>((ref, month) async {
  ref.watch(todayEntriesProvider); // 新增/删除饮水后重算日历圆点
  final storage = await ref.read(localStorageProvider.future);
  final first = DateTime(month.year, month.month, 1);
  final next = DateTime(month.year, month.month + 1, 1);
  // 逻辑月窗口 = [1 号 + 重置时刻, 下月 1 号 + 重置时刻)
  final entries = await storage.loadEntriesForRange(
    LogicalDay.startOf(first),
    LogicalDay.startOf(next),
  );
  return _aggregate(entries, first, next.difference(first).inDays, _goalOf(ref));
});

/// 指定日的原始记录（日 Tab 明细）
final dayEntriesForProvider =
    FutureProvider.family<List<DrinkEntry>, DateTime>((ref, day) async {
  ref.watch(todayEntriesProvider); // 记录变化后当日明细实时刷新
  final storage = await ref.read(localStorageProvider.future);
  return storage.loadEntriesForDay(day);
});

/// 连续打卡（扫描近 3 年）
final streakProvider = FutureProvider<StreakInfo>((ref) async {
  final entries = await ref.watch(yearEntriesProvider.future);
  final byDay = <DateTime, int>{};
  for (final e in entries) {
    final d = LogicalDay.of(e.drankAt);
    byDay[d] = (byDay[d] ?? 0) + e.effectiveMl;
  }
  return StreakCalculator.compute(byDay, _goalOf(ref), LogicalDay.today());
});

/// 签到日集合：近 3 年内有任何饮水记录的日子（不管正负容量，与月历点亮
/// 「有条目即点亮」规则一致）。完全以饮水数据为准：无任何记录
/// （如清除数据后）连续签到为 0，今天喝下第一口即变 1；
/// 删除某天全部记录该日自动退出、实时回退。
Future<Set<String>> _signinDayKeys(Ref ref) async {
  final entries = await ref.watch(yearEntriesProvider.future);
  return {
    for (final e in entries) LogicalDay.keyString(LogicalDay.of(e.drankAt)),
  };
}

/// 连续签到（当前连续没有断签的天数）：从今天往前数连续签到日；
/// 今天还没有饮水记录则从昨天起数（昨天累计照常显示，不断签；
/// 今天喝下第一口即 +1；昨天也没有记录才是 0）
final checkinDaysProvider = FutureProvider<int>((ref) async {
  final days = await _signinDayKeys(ref);
  final today = LogicalDay.today();
  // 今天未签到不断签：起点退到昨天，保留已有连续链
  var cursor = days.contains(LogicalDay.keyString(today))
      ? today
      : today.subtract(const Duration(days: 1));
  var streak = 0;
  while (days.contains(LogicalDay.keyString(cursor))) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
});

/// 最长连续签到（历史所有签到日里最长的一段连续天数，含当前段）
final bestCheckinDaysProvider = FutureProvider<int>((ref) async {
  final days = await _signinDayKeys(ref);
  // 'yyyy-MM-dd' 字符串排序即日期序；相邻差一天则连续段 +1
  var best = 0;
  var run = 0;
  DateTime? prev;
  for (final k in days.toList()..sort()) {
    final d = DateTime.parse(k);
    run = (prev != null && d.difference(prev) == const Duration(days: 1))
        ? run + 1
        : 1;
    if (run > best) best = run;
    prev = d;
  }
  return best;
});

/// 供 stats 模块使用的日期便捷扩展（命名导出，跨库可见）
extension StatsDayX on int {
  Duration get days => Duration(days: this);
}
