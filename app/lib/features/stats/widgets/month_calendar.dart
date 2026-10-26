import 'package:flutter/material.dart';

import '../../../core/time/logical_day.dart';
import '../../../shared/models/drink_entry.dart';

/// PRD §2.5 月历打卡视图
/// 绿色圆点 = 当日达标；半透明点 = 有记录未达标
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.dayTotals,
    required this.goalMl,
  });

  final DateTime month; // 任意代表日，取年月
  final Map<int, DayTotalLite> dayTotals; // key: 1..31
  final int goalMl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // 一周起始随「一周开始时间」设置（周日或周一）
    final leadingBlanks = LogicalDay.leadingBlanksOf(first);
    final weekLabels = LogicalDay.weekHeaderLabels;

    final cells = <Widget>[
      for (final w in weekLabels)
        Center(
          child: Text(w,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ),
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++) _dayCell(context, d),
    ];

    return Column(
      children: [
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.9,
          children: cells,
        ),
      ],
    );
  }

  Widget _dayCell(BuildContext context, int d) {
    final theme = Theme.of(context);
    final total = dayTotals[d];
    final isToday = _isToday(d);
    // 有饮水条目即点亮（不看正负）：负容量记录的日子同样算有记录
    final hasRecord = total != null;
    final complete = total?.complete ?? false;

    final Color bg;
    if (complete) {
      bg = theme.colorScheme.primary;
    } else if (hasRecord) {
      bg = theme.colorScheme.primary.withValues(alpha: 0.25);
    } else {
      bg = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    }

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: isToday
            ? Border.all(color: theme.colorScheme.primary, width: 2)
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$d',
            style: theme.textTheme.labelLarge?.copyWith(
              color: complete
                  ? Colors.white
                  : theme.colorScheme.onSurface.withValues(alpha: 0.85),
              fontWeight: isToday || complete ? FontWeight.w700 : null,
            ),
          ),
          if (hasRecord) ...[
            const SizedBox(height: 2),
            Text(
              '${total.effectiveMl}',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: complete ? Colors.white70 : theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isToday(int d) {
    final t = LogicalDay.today();
    return t.year == month.year && t.month == month.month && t.day == d;
  }
}

/// 轻量日聚合（避免依赖 stats_providers 形成循环导入）
class DayTotalLite {
  const DayTotalLite({
    required this.effectiveMl,
    this.volumeMl = 0,
    required this.complete,
  });
  final int effectiveMl;
  final int volumeMl;
  final bool complete;

  factory DayTotalLite.fromEntries(List<DrinkEntry> entries, int goalMl) {
    final eff = entries.fold<int>(0, (s, e) => s + e.effectiveMl);
    final vol = entries.fold<int>(0, (s, e) => s + e.volumeMl);
    return DayTotalLite(
      effectiveMl: eff,
      volumeMl: vol,
      complete: eff >= goalMl,
    );
  }
}
