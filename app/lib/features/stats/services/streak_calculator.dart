import 'dart:math' as math;

/// PRD §2.5 连续打卡统计
/// 打卡定义：当日有效水分 >= 目标
class StreakInfo {
  const StreakInfo({
    required this.current,
    required this.longest,
    required this.totalCompleteDays,
  });

  final int current; // 从今天（或昨天）往前数的连续打卡天数
  final int longest; // 历史最长
  final int totalCompleteDays;
}

class StreakCalculator {
  StreakCalculator._();

  /// [effectiveByDay]: 当日有效水分（key 为自然日，时间部分会被截断）
  static StreakInfo compute(
    Map<DateTime, int> effectiveByDay,
    int goalMl,
    DateTime today,
  ) {
    DateTime dayKey(DateTime d) => DateTime(d.year, d.month, d.day);
    final complete = <DateTime>{};
    for (final e in effectiveByDay.entries) {
      if (e.value >= goalMl) complete.add(dayKey(e.key));
    }

    var current = 0;
    var cursor = dayKey(today);
    // 今天还没达标不算断签，从昨天开始数
    if (!complete.contains(cursor)) cursor = cursor.subtract(const Duration(days: 1));
    while (complete.contains(cursor)) {
      current++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    var longest = 0;
    if (complete.isNotEmpty) {
      final sorted = complete.toList()..sort();
      var run = 1;
      longest = 1;
      for (var i = 1; i < sorted.length; i++) {
        final prev = sorted[i - 1];
        final cur = sorted[i];
        if (cur.difference(prev) == const Duration(days: 1)) {
          run++;
        } else {
          run = 1;
        }
        longest = math.max(longest, run);
      }
    }

    return StreakInfo(
      current: current,
      longest: math.max(longest, current),
      totalCompleteDays: complete.length,
    );
  }
}
