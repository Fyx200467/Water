import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/time/logical_day.dart';
import '../../shared/models/preferred_unit.dart';
import '../home/providers/home_providers.dart';
import 'providers/stats_providers.dart';
import 'widgets/month_calendar.dart';

/// PRD §2.5 数据统计：日 / 周 / 月 + 连续打卡
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  DateTime _selectedDay = LogicalDay.today();
  DateTime _month = DateTime.now();

  @override
  Widget build(BuildContext context) {
    ref.watch(preferredUnitProvider);
    final theme = Theme.of(context);
    final streakAsync = ref.watch(streakProvider);
    final goal = ref.watch(profileProvider)?.dailyGoalMl ?? 2000;

    return Scaffold(
      appBar: AppBar(title: const Text('数据统计')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // 连续打卡卡片
          streakAsync.maybeWhen(
            data: (s) => Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _statBlock(theme, '${s.current}', '当前连续 (天)'),
                    _divider(theme),
                    _statBlock(theme, '${s.longest}', '最长连续 (天)'),
                    _divider(theme),
                    _statBlock(theme, '${s.totalCompleteDays}', '累计达标 (天)'),
                  ],
                ),
              ),
            ),
            orElse: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          DefaultTabController(
            length: 3,
            child: Column(
              children: [
                TabBar(
                  tabs: const [Tab(text: '日'), Tab(text: '周'), Tab(text: '月')],
                  dividerColor: Colors.transparent,
                ),
                SizedBox(
                  height: 430,
                  child: TabBarView(
                    children: [
                      _dayTab(theme, goal),
                      _weekTab(theme, goal),
                      _monthTab(theme, goal),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBlock(ThemeData theme, String value, String label) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: theme.textTheme.displayMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.bodyMedium),
        ],
      );

  Widget _divider(ThemeData theme) => Container(
        width: 1,
        height: 36,
        color: theme.dividerColor,
      );

  // ---------------- 日 Tab ----------------

  Widget _dayTab(ThemeData theme, int goal) {
    final dayEntriesAsync =
        ref.watch(dayEntriesForProvider(_selectedDay));
    final isFuture = _selectedDay.isAfter(LogicalDay.today());
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() {
                _selectedDay = _selectedDay.subtract(1.days);
              }),
            ),
            Text(
              DateFormat('yyyy-MM-dd EEEE', 'zh').format(_selectedDay),
              style: theme.textTheme.titleLarge,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: isFuture
                  ? null
                  : () => setState(() {
                        _selectedDay = _selectedDay.add(1.days);
                      }),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: dayEntriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败: $e')),
            data: (entries) {
              final eff = entries.fold<int>(0, (s, e) => s + e.effectiveMl);
              final vol = entries.fold<int>(0, (s, e) => s + e.volumeMl);
              final complete = eff >= goal;
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                  '有效水分  ${UnitFormat.number(eff)} / ${UnitFormat.volume(goal)}',
                                  style: theme.textTheme.titleLarge),
                              Icon(
                                complete
                                    ? Icons.emoji_events
                                    : Icons.water_drop_outlined,
                                color: theme.colorScheme.primary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: goal == 0 ? 0 : (eff / goal).clamp(0, 1),
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '原始摄入 ${UnitFormat.volume(vol)} · 记录 ${entries.length} 次'
                            '${complete ? ' · 达标' : ''}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text('这一天还没有记录',
                            style: theme.textTheme.bodyMedium),
                      ),
                    )
                  else
                    ...entries.map(
                      (e) => ListTile(
                        leading: Icon(e.beverageCategory.icon,
                            color: e.beverageCategory.color),
                        title: Text(
                            '${e.beverageName} · ${UnitFormat.volume(e.volumeMl)}'),
                        subtitle: Text(
                            '有效 ${UnitFormat.volume(e.effectiveMl)} · ${DateFormat('HH:mm').format(e.drankAt)}'),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------- 周 Tab ----------------

  Widget _weekTab(ThemeData theme, int goal) {
    final weekAsync = ref.watch(last7DaysProvider);
    return weekAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (days) {
        final completeCount = days.where((d) => d.complete).length;
        final avg = days.isEmpty
            ? 0
            : days.fold<int>(0, (s, d) => s + d.effectiveMl) ~/ days.length;
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SizedBox(
                      height: 220,
                      child: BarChart(
                        BarChartData(
                          maxY: (goal * 1.2).toDouble(),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(),
                            rightTitles: const AxisTitles(),
                            leftTitles: const AxisTitles(),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (v, _) {
                                  final idx = v.toInt();
                                  if (idx < 0 || idx >= days.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final d = days[idx].day;
                                  const labels = [
                                    '一', '二', '三', '四', '五', '六', '日'
                                  ];
                                  final wd = d.weekday - 1;
                                  return Text(labels[wd],
                                      style: theme.textTheme.labelSmall);
                                },
                              ),
                            ),
                          ),
                          barGroups: [
                            for (var i = 0; i < days.length; i++)
                              BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: days[i].effectiveMl.toDouble(),
                                    width: 16,
                                    borderRadius: BorderRadius.circular(4),
                                    color: days[i].complete
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.primary
                                            .withValues(alpha: 0.35),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Text('日均 ${UnitFormat.volume(avg)}',
                            style: theme.textTheme.bodyLarge),
                        Text('达标 $completeCount / 7 天',
                            style: theme.textTheme.bodyLarge),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('柱形满格 = 当日目标 ${UnitFormat.volume(goal)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
          ],
        );
      },
    );
  }

  // ---------------- 月 Tab ----------------

  Widget _monthTab(ThemeData theme, int goal) {
    final monthAsync = ref.watch(monthDataProvider(_month));
    final canGoNext = _month.year != DateTime.now().year ||
        _month.month != DateTime.now().month;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() {
                _month = DateTime(_month.year, _month.month - 1, 1);
              }),
            ),
            Text(DateFormat('yyyy年M月').format(_month),
                style: theme.textTheme.titleLarge),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: !canGoNext
                  ? null
                  : () => setState(() {
                        _month = DateTime(_month.year, _month.month + 1, 1);
                      }),
            ),
          ],
        ),
        const SizedBox(height: 8),
        monthAsync.when(
          loading: () => const SizedBox(
            height: 300,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Center(child: Text('加载失败: $e')),
          data: (map) {
            final totals = <int, DayTotalLite>{
              for (final e in map.entries)
                e.value.day.day: DayTotalLite(
                  effectiveMl: e.value.effectiveMl,
                  volumeMl: e.value.volumeMl,
                  complete: e.value.complete,
                ),
            };
            final completeDays = totals.values.where((t) => t.complete).length;
            final recorded = totals.values.where((t) => t.effectiveMl > 0);
            return Column(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: MonthCalendar(
                      month: _month,
                      dayTotals: totals,
                      goalMl: goal,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text('达标 $completeDays 天',
                        style: theme.textTheme.bodyLarge),
                    Text('有记录 ${recorded.length} 天',
                        style: theme.textTheme.bodyLarge),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
