import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../shared/models/beverage.dart';
import '../../shared/models/drink_entry.dart';
import '../home/providers/home_providers.dart';
import '../onboarding/widgets/animal_silhouette.dart';
import 'providers/stats_providers.dart';

// 品牌色规范
const Color _kCyan = Color(0xFF4DB8D8);
const Color _kTextDark = Color(0xFF1C1C1E);
const Color _kHintGray = Color(0xFF8E8E93);
const Color _kFutureGray = Color(0xFFC7C7CC);

/// 彩虹渐变（「所有」行图标 / 统计卡徽章）
const LinearGradient _kRainbow = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFE05252), Color(0xFFF5C542), Color(0xFF7CB342)],
);

/// 对标原版 WaterLlama 历史记录页
///
/// 整页是单个可滚动列表（统计卡作为内容末尾随滚动，非固定底部）：
/// 1. 顶部居中大徽章：进度环 + 「%/今天的饮水量」↔「N/天 连续达到」每 2 秒交替
/// 2. 月历：今天黑圆白字，有记录的过去日期带圆点（达标青点）
/// 3. 羊驼区：达标显示全彩插画 + 当日总量大字 + 目标百分比
/// 4. 编辑记录 / 补上遗漏（会员带锁胶囊）
/// 5. 饮水记录列表（右上小按钮触发挥品筛选弹层）
/// 6. 统计卡：天/周/月三段切换 + 真实数据柱状图
/// 右上角灰色 X 悬浮固定，不随滚动
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  /// 当前统计 Tab：0=天 1=周 2=月
  int _tab = 0;

  /// 饮品筛选（'全部' 或具体饮品名）
  String _beverageFilter = '全部';

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(dailyProgressProvider);
    final streak = ref.watch(streakProvider);
    final now = DateTime.now();
    final todayKey = DateTime(now.year, now.month, now.day);
    final topInset = MediaQuery.of(context).padding.top;
    final dayEntries = ref.watch(dayEntriesForProvider(todayKey));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 状态栏深色图标（不用零高度 appBar，避免 SafeArea 失效按钮被状态栏遮挡）
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            // 底层：整页可滚动内容
            Positioned.fill(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(top: topInset + 60, bottom: 24),
                child: Column(
                  children: [
                    // 1. 顶部大徽章（% 与 连续天数 每 2 秒交替）
                    _TopBadge(
                      percent: progress.progress.clamp(0.0, 1.0),
                      streakDays: streak.valueOrNull?.current ?? 0,
                    ),
                    const SizedBox(height: 20),
                    // 2. 月历
                    _buildCalendar(todayKey),
                    const SizedBox(height: 16),
                    // 3. 羊驼 + 当日总量
                    _buildLlamaSection(progress),
                    const SizedBox(height: 16),
                    // 4. 编辑记录 / 补上遗漏
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _LockedPill(
                          icon: Icons.edit,
                          label: '编辑记录',
                          onTap: () => _showTip('编辑记录是会员功能'),
                        ),
                        const SizedBox(width: 12),
                        _LockedPill(
                          icon: Icons.add_circle_outline,
                          label: '补上遗漏',
                          onTap: () => _showTip('补上遗漏是会员功能'),
                        ),
                      ],
                    ),
                    // 5. 筛选入口 + 记录列表
                    _buildFilterTrigger(),
                    dayEntries.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: CircularProgressIndicator(),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                      data: _buildEntryList,
                    ),
                    const SizedBox(height: 20),
                    // 6. 统计卡（随内容滚动，非固定底部）
                    _buildStatsCard(),
                  ],
                ),
              ),
            ),
            // 顶层：右上角 X 悬浮固定，不随滚动
            Positioned(
              top: topInset + 8,
              right: 16,
              child: _CloseButton(onTap: () => Navigator.pop(context)),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 月历 ----------------

  Widget _buildCalendar(DateTime todayKey) {
    final monthData = ref.watch(
      monthDataProvider(DateTime(todayKey.year, todayKey.month)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: monthData.when(
        loading: () => const SizedBox(height: 240),
        error: (_, __) => const SizedBox(height: 240),
        data: (data) => _MonthCalendar(data: data, today: todayKey),
      ),
    );
  }

  // ---------------- 羊驼 + 当日总量 ----------------

  Widget _buildLlamaSection(DailyProgress progress) {
    return Column(
      children: [
        AnimalSilhouette(
          animalId: 'llama',
          fillRatio: progress.progress.clamp(0.0, 1.0),
          accentColor: _kCyan,
          solidFillColor: _kCyan,
          size: 200,
          // 目标完成后点亮全彩插画，未完成只有轮廓
          fullArt: progress.isComplete,
        ),
        const SizedBox(height: 8),
        Text(
          '${progress.totalEffectiveMl}ml',
          style: const TextStyle(
            color: _kCyan,
            fontSize: 32,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '进水量 · ${(progress.progress * 100).round()}% 的目标',
          style: const TextStyle(color: _kHintGray, fontSize: 14),
        ),
      ],
    );
  }

  // ---------------- 筛选入口 + 记录列表 ----------------

  Widget _buildFilterTrigger() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: () => _showFilterSheet(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _beverageFilter,
                  style: const TextStyle(color: Color(0xFF6B6B70), fontSize: 13),
                ),
                const Icon(Icons.keyboard_arrow_down,
                    size: 16, color: Color(0xFF6B6B70)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEntryList(List<DrinkEntry> entries) {
    final filtered = entries
        .where((e) =>
            _beverageFilter == '全部' || e.beverageName == _beverageFilter)
        .toList()
      ..sort((a, b) => b.drankAt.compareTo(a.drankAt));

    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          entries.isEmpty ? '当天还没有饮水记录' : '该饮品暂无记录',
          style: TextStyle(color: _kHintGray.withValues(alpha: 0.7), fontSize: 13),
        ),
      );
    }

    return Column(
      children: [for (final e in filtered) _buildEntryRow(e)],
    );
  }

  /// 单条记录行：青色杯形图标 + 名称 + 容量 + 右侧时间
  Widget _buildEntryRow(DrinkEntry e) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        children: [
          const Icon(Icons.local_drink, color: _kCyan, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.beverageName,
                  style: const TextStyle(
                    color: _kCyan,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${e.volumeMl}ml',
                  style: const TextStyle(
                    color: _kTextDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Text(
            DateFormat('HH:mm').format(e.drankAt),
            style: const TextStyle(color: _kHintGray, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ---------------- 统计卡 ----------------

  Widget _buildStatsCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 天/周/月 三段切换（选中黑底白字胶囊，未选中浅灰底）
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                      child: GestureDetector(
                        onTap: () => setState(() => _tab = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 7),
                          decoration: BoxDecoration(
                            color: _tab == i
                                ? const Color(0xFF1C1C1E)
                                : const Color(0xFFECECEE),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            ['天', '周', '月'][i],
                            style: TextStyle(
                              color: _tab == i ? Colors.white : _kHintGray,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // 右侧彩虹徽章
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _kRainbow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildChart(),
        ],
      ),
    );
  }

  Widget _buildChart() {
    if (_tab == 0) {
      // 天：过去 7 天
      final last7 = ref.watch(last7DaysProvider);
      return last7.when(
        loading: () => const SizedBox(height: 140),
        error: (_, __) => const SizedBox(height: 140),
        data: (days) => _BarChart(
          title: '过去 7 天',
          barWidth: 26,
          bars: [
            for (final d in days)
              _BarData(
                label: const ['日', '一', '二', '三', '四', '五', '六'][d.day.weekday % 7],
                value: d.effectiveMl,
                valueLabel:
                    d.effectiveMl > 0 && _isToday(d.day) ? _fmtMl(d.effectiveMl) : null,
                highlighted: _isToday(d.day),
              ),
          ],
        ),
      );
    }
    // 周 / 月：近一年每日聚合后本地计算
    final year = ref.watch(yearDailyProvider);
    return year.when(
      loading: () => const SizedBox(height: 140),
      error: (_, __) => const SizedBox(height: 140),
      data: (data) => _tab == 1
          ? _BarChart(
              title: '每日平均\n过去 4 周',
              barWidth: 40,
              bars: _weekBars(data),
            )
          : _BarChart(
              title: '每日平均\n过去 12 个月',
              barWidth: 16,
              bars: _monthBars(data),
            ),
    );
  }

  /// 周 Tab：过去 4 周（周日起始，本周截至今天）每日平均
  List<_BarData> _weekBars(Map<DateTime, DayTotal> year) {
    final today = _today();
    final thisSunday = today.subtract(Duration(days: today.weekday % 7));
    final bars = <_BarData>[];
    for (var i = 3; i >= 0; i--) {
      final start = thisSunday.subtract(Duration(days: 7 * i));
      final isCurrent = i == 0;
      final end = isCurrent
          ? today.add(const Duration(days: 1))
          : start.add(const Duration(days: 7));
      var sum = 0;
      var daysWith = 0;
      for (var day = start; day.isBefore(end); day = day.add(const Duration(days: 1))) {
        final dt = year[DateTime(day.year, day.month, day.day)];
        if (dt != null && dt.effectiveMl > 0) {
          sum += dt.effectiveMl;
          daysWith++;
        }
      }
      final avg = daysWith == 0 ? 0 : sum ~/ daysWith;
      bars.add(_BarData(
        label: _weekLabel(start, isCurrent),
        value: avg,
        valueLabel: isCurrent && avg > 0 ? '${(avg / 1000).toStringAsFixed(1)}升' : null,
        highlighted: isCurrent,
      ));
    }
    return bars;
  }

  /// 月 Tab：过去 12 个月每日平均
  List<_BarData> _monthBars(Map<DateTime, DayTotal> year) {
    final today = _today();
    final bars = <_BarData>[];
    for (var k = 11; k >= 0; k--) {
      final m = DateTime(today.year, today.month - k, 1);
      final next = DateTime(m.year, m.month + 1, 1);
      final end = next.isAfter(today.add(const Duration(days: 1)))
          ? today.add(const Duration(days: 1))
          : next;
      var sum = 0;
      var daysWith = 0;
      for (var day = m; day.isBefore(end); day = day.add(const Duration(days: 1))) {
        final dt = year[DateTime(day.year, day.month, day.day)];
        if (dt != null && dt.effectiveMl > 0) {
          sum += dt.effectiveMl;
          daysWith++;
        }
      }
      final avg = daysWith == 0 ? 0 : sum ~/ daysWith;
      final isCurrent = k == 0;
      // 去年月份显示纯数字，今年显示 N 月，当前月纯数字
      final label = isCurrent || m.year < today.year ? '${m.month}' : '${m.month}月';
      bars.add(_BarData(
        label: label,
        value: avg,
        valueLabel: isCurrent && avg > 0 ? (avg / 1000).toStringAsFixed(1) : null,
        highlighted: isCurrent,
      ));
    }
    return bars;
  }

  String _weekLabel(DateTime start, bool isCurrent) {
    final end = isCurrent ? DateTime.now() : start.add(const Duration(days: 6));
    return start.month == end.month
        ? '${start.month}.${start.day}-${end.day}'
        : '${start.month}.${start.day}-${end.month}.${end.day}';
  }

  String _fmtMl(int ml) =>
      ml >= 1000 ? '${(ml / 1000).toStringAsFixed(1)}升' : '$ml ml';

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool _isToday(DateTime d) {
    final t = _today();
    return d.year == t.year && d.month == t.month && d.day == t.day;
  }

  // ---------------- 筛选弹层（原版样式：全屏底部弹层 + 彩色饮品图标行） ----------------

  void _showFilterSheet() {
    final now = DateTime.now();
    final todayKey = DateTime(now.year, now.month, now.day);
    final entries = ref.read(dayEntriesForProvider(todayKey)).valueOrNull ?? const [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FilterSheet(
        current: _beverageFilter,
        entries: entries,
        onSelect: (v) => setState(() => _beverageFilter = v),
      ),
    );
  }

  void _showTip(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

// ==================== 顶部大徽章 ====================

/// 青色进度环大徽章：内容每 2 秒交替（%/今天的饮水量 ↔ N/天 连续达到）
class _TopBadge extends StatefulWidget {
  const _TopBadge({required this.percent, required this.streakDays});
  final double percent;
  final int streakDays;

  @override
  State<_TopBadge> createState() => _TopBadgeState();
}

class _TopBadgeState extends State<_TopBadge> {
  bool _showStreak = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() => _showStreak = !_showStreak);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _showStreak ? '${widget.streakDays}/天' : '${(widget.percent * 100).round()}%';
    final label = _showStreak ? '连续达到' : '今天的饮水量';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: SizedBox(
        key: ValueKey(_showStreak),
        width: 140,
        height: 140,
        child: CustomPaint(
          painter: _BadgePainter(widget.percent),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 进度环：浅青轨道 + 青色进度弧 + 内部青色实心圆
class _BadgePainter extends CustomPainter {
  const _BadgePainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 3;

    // 轨道
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = const Color(0xFFE3F2F7),
    );
    // 进度弧
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = _kCyan,
    );
    // 内部实心圆
    canvas.drawCircle(c, r - 11, Paint()..color = _kCyan);
  }

  @override
  bool shouldRepaint(_BadgePainter old) => old.progress != progress;
}

// ==================== 月历 ====================

/// 当月月历：今天黑圆白字；过去有记录带圆点（达标青点）；未来灰数字
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({required this.data, required this.today});
  final Map<int, DayTotal> data;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(today.year, today.month, 1);
    // 周日起始：周日偏移 0
    final leading = first.weekday % 7;
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
    final rowCount = (leading + daysInMonth + 6) ~/ 7;

    return Column(
      children: [
        Text(
          DateFormat('yyyy年M月d日').format(today),
          style: const TextStyle(
            color: _kTextDark,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        // 表头：日一二三四五六（青色）
        Row(
          children: [
            for (final w in const ['日', '一', '二', '三', '四', '五', '六'])
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: const TextStyle(
                      color: _kCyan,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < rowCount; row++)
          SizedBox(
            height: 44,
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(child: _cell(row * 7 + col - leading + 1, daysInMonth)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(int day, int daysInMonth) {
    if (day < 1 || day > daysInMonth) return const SizedBox.shrink();

    final isFuture = DateTime(today.year, today.month, day).isAfter(today);
    final isToday = day == today.day;
    // monthDataProvider 以月内 0 基索引为 key
    final dt = data[day - 1];
    final hasRecord = dt != null && dt.effectiveMl > 0;

    final Widget number = isToday
        ? Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$day',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        : Text(
            '$day',
            style: TextStyle(
              color: isFuture ? _kFutureGray : _kTextDark,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        number,
        const SizedBox(height: 3),
        // 有记录的过去日期：达标青点，否则灰点
        if (!isToday && !isFuture && hasRecord)
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: (dt.complete) ? _kCyan : _kFutureGray,
              shape: BoxShape.circle,
            ),
          )
        else
          const SizedBox(height: 5),
      ],
    );
  }
}

// ==================== 筛选弹层 ====================

/// 饮品筛选弹层：白底圆角顶部 + 右上 X + 浅灰圆角行（彩色饮品图标 + 名称）
class _FilterSheet extends StatelessWidget {
  const _FilterSheet({
    required this.current,
    required this.entries,
    required this.onSelect,
  });

  final String current;
  final List<DrinkEntry> entries;
  final ValueChanged<String> onSelect;

  /// (名称, 图标色, 图标)
  List<(String, Color, IconData)> _options() {
    final out = <(String, Color, IconData)>[];
    void add(String name, Color c, IconData i) {
      if (!out.any((o) => o.$1 == name)) out.add((name, c, i));
    }

    add('全部', Colors.transparent, Icons.water_drop);
    for (final b in Beverage.presets) {
      add(b.name, b.category.color, b.category.icon);
    }
    for (final e in entries) {
      add(e.beverageName, e.beverageCategory.color, e.beverageCategory.icon);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final opts = _options();

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // 右上角 X
            Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE9E9EB),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close,
                      color: Color(0xFF8E8E93), size: 20),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: opts.length,
                itemBuilder: (ctx, i) {
                  final o = opts[i];
                  final isAll = o.$1 == '全部';
                  final selected = current == o.$1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          onSelect(o.$1);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              // 彩色饮品图标（「全部」行 = 彩虹杯）
                              Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: isAll
                                    ? const BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: _kRainbow,
                                      )
                                    : BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: o.$2.withValues(alpha: 0.18),
                                      ),
                                child: Icon(
                                  o.$3,
                                  size: 16,
                                  color: isAll ? Colors.white : o.$2,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  o.$1,
                                  style: const TextStyle(
                                    color: Color(0xFF1C1C1E),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              // 选中：青色实心圆 ✓
                              if (selected)
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: const BoxDecoration(
                                    color: _kCyan,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check,
                                      size: 14, color: Colors.white),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 通用小组件 ====================

/// 灰色圆形关闭按钮
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Color(0xFFE9E9EB),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, color: Color(0xFF8E8E93), size: 24),
      ),
    );
  }
}

/// 带锁功能胶囊按钮（浅青背景）
class _LockedPill extends StatelessWidget {
  const _LockedPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE0F4F8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 14, color: Color(0xFF6B6B70)),
            const SizedBox(width: 6),
            Icon(icon, size: 15, color: const Color(0xFF6B6B70)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B6B70),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 柱状图数据（valueLabel 仅当前柱显示在柱顶）
class _BarData {
  const _BarData({
    required this.label,
    required this.value,
    this.valueLabel,
    this.highlighted = false,
  });
  final String label;
  final int value;
  final String? valueLabel;
  final bool highlighted;
}

/// 简易柱状图：全圆角柱体（青色），值为 0 不画柱（只保留轴标签）
class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.title,
    required this.bars,
    required this.barWidth,
  });
  final String title;
  final List<_BarData> bars;
  final double barWidth;

  @override
  Widget build(BuildContext context) {
    final maxVal = bars.fold<int>(0, (a, b) => a > b.value ? a : b.value);

    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _kTextDark,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          // 值标签(4+15) + 柱体92 + 间距6 + 轴标签13 ≈ 130
          height: 130,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final b in bars)
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // 柱顶值标签（仅当前柱）
                    if (b.valueLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          b.valueLabel!,
                          style: const TextStyle(
                            color: _kCyan,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    // 柱体：值为 0 不画（只保留轴标签，对标原版）
                    Container(
                      width: barWidth,
                      height: b.value > 0
                          ? (b.value / maxVal * 92).clamp(6.0, 92.0)
                          : 0.0,
                      decoration: BoxDecoration(
                        color: _kCyan,
                        borderRadius:
                            BorderRadius.circular(math.min(8.0, barWidth / 2)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      b.label,
                      style: TextStyle(
                        color: b.highlighted ? _kCyan : _kHintGray,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
