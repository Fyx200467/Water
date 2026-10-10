import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../shared/models/drink_entry.dart';
import '../../home/providers/home_providers.dart';
import '../services/streak_calculator.dart';

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
    final idx = DateTime(e.drankAt.year, e.drankAt.month, e.drankAt.day)
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

/// 近 7 天（含今天）
final last7DaysProvider = FutureProvider<List<DayTotal>>((ref) async {
  final storage = await ref.read(localStorageProvider.future);
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day).subtract(6.days);
  final entries = await storage.loadEntriesForRange(
    start,
    DateTime(today.year, today.month, today.day + 1),
  );
  final map = _aggregate(entries, start, 7, _goalOf(ref));
  return [for (var i = 0; i < 7; i++) map[i]!];
});

/// 指定月份的每日聚合
final monthDataProvider =
    FutureProvider.family<Map<int, DayTotal>, DateTime>((ref, month) async {
  final storage = await ref.read(localStorageProvider.future);
  final first = DateTime(month.year, month.month, 1);
  final next = DateTime(month.year, month.month + 1, 1);
  final entries = await storage.loadEntriesForRange(first, next);
  return _aggregate(entries, first, next.difference(first).inDays, _goalOf(ref));
});

/// 指定日的原始记录（日 Tab 明细）
final dayEntriesForProvider =
    FutureProvider.family<List<DrinkEntry>, DateTime>((ref, day) async {
  final storage = await ref.read(localStorageProvider.future);
  return storage.loadEntriesForDay(day);
});

/// 连续打卡（扫描近 365 天）
final streakProvider = FutureProvider<StreakInfo>((ref) async {
  final storage = await ref.read(localStorageProvider.future);
  final today = DateTime.now();
  final start = DateTime(today.year - 1, today.month, today.day);
  final entries = await storage.loadEntriesForRange(
    start,
    DateTime(today.year, today.month, today.day + 1),
  );
  final byDay = <DateTime, int>{};
  for (final e in entries) {
    final d = DateTime(e.drankAt.year, e.drankAt.month, e.drankAt.day);
    byDay[d] = (byDay[d] ?? 0) + e.effectiveMl;
  }
  return StreakCalculator.compute(byDay, _goalOf(ref), today);
});

/// 近 365 天每日聚合（key = 当日零点），供历史页周/月图表本地聚合
final yearDailyProvider = FutureProvider<Map<DateTime, DayTotal>>((ref) async {
  final storage = await ref.read(localStorageProvider.future);
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day).subtract(364.days);
  final entries = await storage.loadEntriesForRange(
    start,
    DateTime(today.year, today.month, today.day + 1),
  );
  final goalMl = _goalOf(ref);
  final byDay = <DateTime, DayTotal>{};
  for (final e in entries) {
    final d = DateTime(e.drankAt.year, e.drankAt.month, e.drankAt.day);
    final prev = byDay[d];
    final eff = (prev?.effectiveMl ?? 0) + e.effectiveMl;
    final vol = (prev?.volumeMl ?? 0) + e.volumeMl;
    byDay[d] = DayTotal(
      day: d,
      effectiveMl: eff,
      volumeMl: vol,
      count: (prev?.count ?? 0) + 1,
      complete: eff >= goalMl,
    );
  }
  return byDay;
});

/// 供 stats 模块使用的日期便捷扩展（命名导出，跨库可见）
extension StatsDayX on int {
  Duration get days => Duration(days: this);
}
