import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../shared/models/beverage.dart';
import '../../shared/models/drink_entry.dart';
import '../characters/current_character_provider.dart';
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

  /// 当前选中的日历日期（默认今天；点选日历任意日期后动态切换）
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(dailyProgressProvider);
    final streak = ref.watch(streakProvider);
    final currentChar = ref.watch(currentCharacterProvider);
    final profile = ref.watch(profileProvider);
    final now = DateTime.now();
    final todayKey = DateTime(now.year, now.month, now.day);
    final isToday = _selectedDate.year == todayKey.year &&
        _selectedDate.month == todayKey.month &&
        _selectedDate.day == todayKey.day;
    final topInset = MediaQuery.of(context).padding.top;
    final dayEntries = ref.watch(dayEntriesForProvider(_selectedDate));

    final goalMl = profile?.dailyGoalMl ?? 2000;

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
                    // 1. 顶部大徽章（始终显示今天的数据：% 与 连续天数 每 2 秒交替）
                    _TopBadge(
                      percent: progress.progress,
                      streakDays: streak.valueOrNull?.current ?? 0,
                    ),
                    const SizedBox(height: 20),
                    // 2. 月历（标题动态渲染选中日期，日期可点选）
                    _buildCalendar(todayKey),
                    const SizedBox(height: 16),
                    // 3. 选中日期的内容区：有条目→角色+总量+按钮+列表；无条目→无条目+补上遗漏
                    dayEntries.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: CircularProgressIndicator(),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (entries) => _buildDaySection(
                        entries: entries,
                        goalMl: goalMl,
                        currentChar: currentChar,
                        isToday: isToday,
                        todayProgress: progress,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 4. 统计卡（随内容滚动；右侧彩虹圆按钮=饮品筛选入口）
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
        data: (data) => _MonthCalendar(
          data: data,
          today: todayKey,
          selectedDate: _selectedDate,
          onSelect: (d) => setState(() => _selectedDate = d),
        ),
      ),
    );
  }

  // ---------------- 选中日期内容区 ----------------

  /// 选中日期的内容区：
  /// - 有条目：角色（与首页角色统一）+ 当日总量 + 编辑记录/补上遗漏按钮 + 记录列表
  /// - 无条目：显示「无条目」+「补上遗漏」按钮（会员带锁）
  Widget _buildDaySection({
    required List<DrinkEntry> entries,
    required int goalMl,
    required String currentChar,
    required bool isToday,
    required DailyProgress todayProgress,
  }) {
    final hasEntries = entries.isNotEmpty;
    // 选中日总量与完成率
    final totalMl = entries.fold<int>(0, (s, e) => s + e.effectiveMl);
    final ratio = goalMl > 0 ? totalMl / goalMl : 0.0;
    final complete = totalMl >= goalMl;
    // 今天用首页 dailyProgress（与首页角色点亮态实时统一）
    final fillRatio = isToday
        ? todayProgress.progress.clamp(0.0, 1.0)
        : ratio.clamp(0.0, 1.0);
    final fullArt = isToday ? todayProgress.isComplete : complete;
    final displayMl = isToday ? todayProgress.totalEffectiveMl : totalMl;
    final displayPct = isToday ? todayProgress.progress : ratio;

    if (!hasEntries) {
      // 无条目：显示「无条目」+「补上遗漏」按钮（会员带锁，对标原版第六张图）
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const Text(
              '无条目',
              style: TextStyle(
                color: _kHintGray,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _LockedPill(
              icon: Icons.add_circle_outline,
              label: '补上遗漏',
              onTap: () => _showTip('补上遗漏是会员功能'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 角色 + 当日总量（角色与首页 currentCharacterProvider 实时统一，缩小3倍）
        AnimalSilhouette(
          animalId: currentChar,
          fillRatio: fillRatio,
          accentColor: _kCyan,
          solidFillColor: _kCyan,
          size: 66,
          // 选中日达标→全彩插画，否则剪影+液体填充
          fullArt: fullArt,
        ),
        const SizedBox(height: 8),
        Text(
          '${displayMl}ml',
          style: const TextStyle(
            color: _kCyan,
            fontSize: 32,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '进水量 · ${(displayPct * 100).round()}% 的目标',
          style: const TextStyle(color: _kHintGray, fontSize: 14),
        ),
        const SizedBox(height: 16),
        // 编辑记录 / 补上遗漏
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
        // 记录列表（按筛选过滤）
        _buildEntryList(entries),
      ],
    );
  }

  // ---------------- 记录列表 ----------------

  Widget _buildEntryList(List<DrinkEntry> entries) {
    // 彩色按钮筛选只作用于柱形图，不筛选当日记录列表（对标原版）
    final sorted = [...entries]..sort((a, b) => b.drankAt.compareTo(a.drankAt));

    if (sorted.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          '当天还没有饮水记录',
          style: TextStyle(color: _kHintGray.withValues(alpha: 0.7), fontSize: 13),
        ),
      );
    }

    return Column(
      children: [for (final e in sorted) _buildEntryRow(e)],
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
              // 右侧彩色按钮 = 饮品筛选入口
              // 选中「全部」→彩虹渐变圆；选中具体饮品→该饮品分类色+图标（一一对应）
              _buildFilterButton(),
            ],
          ),
          const SizedBox(height: 16),
          _buildChart(),
        ],
      ),
    );
  }

  /// 彩色筛选按钮：选中「全部」→彩虹渐变圆；选中具体饮品→该饮品分类色+图标
  Widget _buildFilterButton() {
    if (_beverageFilter == '全部') {
      return GestureDetector(
        onTap: () => _showFilterSheet(),
        child: Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: _kRainbow,
          ),
        ),
      );
    }
    // 查找选中饮品的分类色与图标（与筛选弹层一一对应）
    final preset = Beverage.presets.firstWhere(
      (b) => b.name == _beverageFilter,
      orElse: () => Beverage.presets.first,
    );
    return GestureDetector(
      onTap: () => _showFilterSheet(),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: preset.color,
        ),
        child: Icon(preset.category.icon, size: 16, color: Colors.white),
      ),
    );
  }

  Widget _buildChart() {
    if (_tab == 0) {
      // 天：过去 7 天（按彩色按钮筛选的饮品过滤柱形图数据）
      final last7 = ref.watch(filteredLast7DaysProvider(_beverageFilter));
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
    // 周 / 月：近一年每日聚合后本地计算（按彩色按钮筛选的饮品过滤）
    final year = ref.watch(filteredYearDailyProvider(_beverageFilter));
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
    final entries =
        ref.read(dayEntriesForProvider(_selectedDate)).valueOrNull ?? const [];

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
    // 进度态显示真实百分比（可超 100%：110%、130%）；连续态显示天数
    final value =
        _showStreak ? '${widget.streakDays}' : '${(widget.percent * 100).round()}%';
    final label = _showStreak ? '天连续签到' : '今天的饮水量';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: SizedBox(
        key: ValueKey(_showStreak),
        width: 140,
        height: 140,
        child: CustomPaint(
          // 进度环按 clamp 后的值绘制（不超过一圈）
          painter: _BadgePainter(widget.percent.clamp(0.0, 1.0)),
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

/// 当月月历：
/// - 标题动态渲染选中日期（xxxx年xx月xx日）
/// - 今天=黑圆白字；选中日（非今天）=青色描边圆；过去有记录带圆点（达标青点）；未来灰数字
/// - 点击任意日期 → onSelect 回调（驱动选中日期内容区动态切换）
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.data,
    required this.today,
    required this.selectedDate,
    required this.onSelect,
  });
  final Map<int, DayTotal> data;
  final DateTime today;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(today.year, today.month, 1);
    // 周日起始：周日偏移 0
    final leading = first.weekday % 7;
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
    final rowCount = (leading + daysInMonth + 6) ~/ 7;

    return Column(
      children: [
        // 标题：动态渲染选中日期（用户点选任意日期后实时切换）
        Text(
          DateFormat('yyyy年M月d日').format(selectedDate),
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

    final cellDate = DateTime(today.year, today.month, day);
    final isFuture = cellDate.isAfter(today);
    final isToday = day == today.day;
    final isSelected = !isToday &&
        selectedDate.year == today.year &&
        selectedDate.month == today.month &&
        selectedDate.day == day;
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
        : isSelected
            ? Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _kCyan, width: 2),
                ),
                child: Text(
                  '$day',
                  style: const TextStyle(
                    color: _kTextDark,
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(cellDate),
      child: Column(
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
      ),
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
          // 值标签(4+14) + 柱体88 + 间距6 + 轴标签12 + 余量 ≈ 144
          // 原 130 高度导致 "BOTTOM OVERFLOWED BY 3.0 PIXELS"，加高到 144 修复
          height: 144,
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
                          ? (b.value / maxVal * 88).clamp(6.0, 88.0)
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
