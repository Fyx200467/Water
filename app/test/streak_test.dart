import 'package:flutter_test/flutter_test.dart';
import 'package:water_llama/features/stats/services/streak_calculator.dart';

/// PRD §2.5 连续打卡算法单测
void main() {
  final today = DateTime(2026, 10, 10);
  DateTime daysAgo(int n) => today.subtract(Duration(days: n));

  StreakInfo compute(Map<DateTime, int> byDay, {int goal = 2000}) =>
      StreakCalculator.compute(byDay, goal, today);

  test('空记录 → 全 0', () {
    final r = compute({});
    expect(r.current, 0);
    expect(r.longest, 0);
    expect(r.totalCompleteDays, 0);
  });

  test('今天达标 → 当前连续含今天', () {
    final r = compute({today: 2000});
    expect(r.current, 1);
    expect(r.longest, 1);
    expect(r.totalCompleteDays, 1);
  });

  test('今天未达标不断签，从昨天往前数', () {
    final r = compute({daysAgo(1): 2000, daysAgo(2): 2100});
    expect(r.current, 2);
    expect(r.longest, 2);
  });

  test('中间断一天 → 最长连续 2，累计达标 4', () {
    final r = compute({
      today: 2000,
      daysAgo(1): 2000,
      daysAgo(2): 100, // 断
      daysAgo(3): 2000,
      daysAgo(4): 2000,
    });
    expect(r.current, 2);
    expect(r.longest, 2);
    expect(r.totalCompleteDays, 4);
  });

  test('连续 5 天 → 最长 5', () {
    final r = compute({
      for (var i = 0; i < 5; i++) daysAgo(i): 2000,
    });
    expect(r.current, 5);
    expect(r.longest, 5);
    expect(r.totalCompleteDays, 5);
  });

  test('时间部分不被截断影响（带时分秒的 key）', () {
    final r = compute({
      DateTime(today.year, today.month, today.day, 9, 30): 2000,
      DateTime(daysAgo(1).year, daysAgo(1).month, daysAgo(1).day, 21, 0): 2000,
    });
    expect(r.current, 2);
  });

  test('目标高于摄入 → 不算达标', () {
    final r = compute({today: 1500}, goal: 2000);
    expect(r.current, 0);
    expect(r.totalCompleteDays, 0);
  });
}
