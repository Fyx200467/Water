import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show TextDirection;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../core/storage/providers.dart';
import '../../core/time/logical_day.dart';
import '../../shared/models/beverage.dart';
import '../../shared/models/drink_entry.dart';
import '../../shared/models/preferred_unit.dart';
import '../../shared/widgets/drink_illustration.dart';
import '../characters/current_character_provider.dart';
import '../drink/providers/custom_beverage_provider.dart';
import '../drink/widgets/svg_container.dart';
import '../home/providers/home_providers.dart';
import '../onboarding/widgets/animal_silhouette.dart';
import '../settings/settings_flags.dart';
import '../settings/widget_settings_screen.dart';
import 'providers/stats_providers.dart';

// 品牌色规范
const Color _kCyan = Color(0xFF4DB8D8);
const Color _kTextDark = Color(0xFF1C1C1E);
const Color _kHintGray = Color(0xFF8E8E93);
const Color _kFutureGray = Color(0xFFC7C7CC);

/// 刻度尺下方容量标签（每 100ml 一条）统一样式
const TextStyle _kRulerLabelStyle = TextStyle(
  color: Color(0xFF3A4250),
  fontSize: 12,
  fontWeight: FontWeight.w700,
);

/// 滑动刻度尺的横向密度：每 100ml 对应的像素宽度（越大拖动越细腻）
const double _kSlidePxPer100 = 62.0;

/// 与首页/管理页一致的饮品图标（预设=插画 / SVG 容器=液体风格 70% 液面 / 自定义=Icon）
Widget _beverageIcon(Beverage b, double size) {
  if (isSvgContainer(b.containerId)) {
    return SvgContainerIcon(
      containerId: b.containerId!,
      color: b.color,
      fillRatio: 0.9, // 液体风格：全局统一液面 90%，顶部留少量气隙
      size: size,
    );
  }
  if (b.id.startsWith('custom_')) {
    return Icon(b.icon, size: size - 4, color: b.color);
  }
  return DrinkIllustration(beverageId: b.id, color: b.color, size: size);
}

/// 对标原版 WaterLlama 历史记录页
///
/// 整页是单个可滚动列表（统计卡作为内容末尾随滚动，非固定底部）：
/// 1. 顶部居中大徽章：进度环 + 「%/今天的饮水量」↔「N/天 连续达到」每 2 秒交替
/// 2. 月历：有喝水记录的日期被达标度加粗小进度环包围（蓝/橙/红）
/// 3. 羊驼区：达标显示全彩插画 + 当日总量大字 + 目标百分比
/// 4. 编辑记录 / 补上遗漏（功能胶囊）
/// 5. 饮水记录列表（右上小按钮触发挥品筛选弹层）
/// 6. 统计卡：天/周/月三段切换 + 真实数据柱状图（位于底部 tab「趋势」视图）
/// 右上角灰色 X 悬浮固定，不随滚动
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  /// 当前统计 Tab：0=天 1=周 2=月
  int _tab = 0;

  /// 底部悬浮视图切换：0=日期 1=趋势 2=列表
  int _viewTab = 0;

  // 底部 tab 栏固定尺寸：三个标签都是两字，等宽排布才能让下划线
  // 按 PageView 页码连续滑动（84 = 图标 18 + 间距 6 + 两字 30 + 内边距 28）
  static const double _kTabItemW = 84;
  static const double _kTabSepW = 9; // 1px 竖线 + 左右各 4 间距
  static const double _kTabUnderlineW = 40;

  /// 三页横向滑动控制器（与底部 tab 双向联动）
  late final PageController _viewPageController =
      PageController(initialPage: _viewTab);

  /// 趋势图形态：false=柱形图，true=折线图（天/周/月共用切换）
  bool _chartLine = false;

  /// 「各饮品摄入量」面板指标：0=总摄入量 1=水份 2=热量
  int _intakeMetric = 0;

  /// 饮品筛选（'全部' 或具体饮品名）
  String _beverageFilter = '全部';

  /// 当前选中的日历日期（默认今天；点选日历任意日期后动态切换）
  late DateTime _selectedDate;

  /// 日历当前展示的月份（每月 1 日；列表里点选其它月份的日期时同步切换）
  late DateTime _calMonth;

  /// 列表视图本地已删除的日期（删除后先即时移除，等 provider 重算完成再摘掉占位）
  final Set<String> _pendingDeletedDays = <String>{};

  /// 列表页删除模式：开启后每天右上角出现红色「−」，点击行弹出删除确认卡
  bool _listDeleteMode = false;

  /// 补录写入中（防重复点击导致同一条记录入库多次）
  bool _backfilling = false;

  @override
  void initState() {
    super.initState();
    final today = LogicalDay.today();
    _selectedDate = today;
    _calMonth = DateTime(today.year, today.month, 1);
  }

  @override
  void dispose() {
    _viewPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(preferredUnitProvider);
    final progress = ref.watch(dailyProgressProvider);
    final checkin = ref.watch(checkinDaysProvider);
    final currentChar = ref.watch(currentCharacterProvider);
    final profile = ref.watch(profileProvider);
    final todayKey = LogicalDay.today();
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
            // 底层：「日历」视图 = 整页可滚动内容；趋势/列表各自独立视图
            Positioned.fill(
              child: PageView(
                controller: _viewPageController,
                onPageChanged: (i) {
                  if (i != _viewTab) setState(() => _viewTab = i);
                },
                children: [
                  // 0. 日期视图
                  SingleChildScrollView(
                    padding:
                        EdgeInsets.only(top: topInset + 60, bottom: 120),
                    child: Column(
                      children: [
                        // 1. 顶部大徽章（始终显示今天的数据：% 与 签到天数 每 2 秒交替）
                        _TopBadge(
                          percent: progress.progress,
                          streakDays: checkin.valueOrNull ?? 0,
                        ),
                        const SizedBox(height: 14),
                        // 徽章底注：使用 App 以来的最长连续签到天数（补录/删除实时重算）
                        Text(
                          '历史记录最长连续签到'
                          ' ${ref.watch(bestCheckinDaysProvider).valueOrNull ?? 0} 天',
                          style: const TextStyle(
                            color: _kHintGray,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 36),
                        // 2. 月历（标题动态渲染选中日期，日期可点选）
                        _buildCalendar(todayKey),
                        const SizedBox(height: 16),
                        // 3. 选中日期的内容区：有条目→角色+总量+按钮+列表；无条目→无条目+补上遗漏
                        dayEntries.when(
                          skipLoadingOnReload: true,
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
                      ],
                    ),
                  ),
                  // 1. 趋势视图：天/周/月柱形图统计卡（含饮品筛选）
                  SingleChildScrollView(
                    padding:
                        EdgeInsets.only(top: topInset + 60, bottom: 120),
                    child: _buildStatsCard(),
                  ),
                  // 2. 列表视图
                  _buildListView(),
                ],
              ),
            ),
            // 顶层：左上角返回按钮悬浮固定，不随滚动（与提醒页/设置页同款）
            Positioned(
              top: topInset + 8,
              left: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE5E5EA),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    size: 15,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
              ),
            ),
            // 顶层：右上角分享按钮悬浮固定（与左上返回按钮同规格 36 圆底）
            Positioned(
              top: topInset + 8,
              right: 16,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  // 分享功能暂未接入，先占位
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE5E5EA),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/icons/menu/share.svg',
                      width: 17,
                      height: 17,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF1C1C1E),
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 底部悬浮视图切换（日历/趋势/列表），固定离屏幕底部 20px
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 20,
              child: _buildViewTabBar(),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 底部悬浮视图切换 ----------------

  /// 悬浮胶囊 tab 栏：日期 / 趋势 / 列表，白色圆角容器 + 竖线分隔，
  /// 选中项深色 + 珊瑚色下划线，图标用用户自绘 SVG（统一染色适配选中态）
  Widget _buildViewTabBar() {
    const items = [
      ('assets/icons/menu/tab_date.svg', '日期'),
      ('assets/icons/menu/tab_trend.svg', '趋势'),
      ('assets/icons/menu/tab_list.svg', '列表'),
    ];
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        // 高度交给 Row 自身撑开（中文行高会略高于图标 18），
        // 不写死高度，避免字体行高变化时底部溢出
        child: Stack(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    Container(
                      width: 1,
                      height: 18,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: const Color(0xFFE7E7EA),
                    ),
                  _viewTabItem(items[i].$1, items[i].$2, i),
                ],
              ],
            ),
            // 珊瑚色下划线：跟随 PageView 的翻页进度连续移动
            // （点按走 animateToPage、左右滑动走拖拽，都是同一个 page）
            // 而不是每个 tab 各自淡入淡出——那样切换时会跳变
            AnimatedBuilder(
              animation: _viewPageController,
              builder: (context, child) {
                var page = _viewTab.toDouble();
                if (_viewPageController.hasClients &&
                    _viewPageController.position.haveDimensions) {
                  page = _viewPageController.page ?? page;
                }
                return Positioned(
                  left: page * (_kTabItemW + _kTabSepW) +
                      (_kTabItemW - _kTabUnderlineW) / 2,
                  bottom: 0,
                  width: _kTabUnderlineW,
                  height: 3,
                  child: child!,
                );
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF2695C),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewTabItem(String assetPath, String label, int index) {
    final selected = _viewTab == index;
    final color = selected
        ? const Color(0xFF33383E)
        : const Color(0xFFB4B9C0);
    return SizedBox(
      width: _kTabItemW,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (selected) return;
          HapticFeedback.selectionClick();
          setState(() => _viewTab = index);
          // 滑动到相邻页（与左右滑动共用同一动画，下划线跟着 page 走）
          _viewPageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 用户自绘图标：单色 SVG 统一染色（选中深灰/未选中浅灰）
                  SvgPicture.asset(
                    assetPath,
                    width: 18,
                    height: 18,
                    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 下划线占位（真正的珊瑚色横线由 tab 栏的滑动指示器绘制）
              const SizedBox(height: 3),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- 列表视图 ----------------

  /// 列表视图：近 3 年有饮水记录的日期按天倒序、按月分组展示。
  /// 行内小进度环沿用日历口径（蓝≥100% / 橙≥70% / 红<70%）；
  /// 点击任意日期切回「日期」视图并定位到该月该日。
  Widget _buildListView() {
    final entriesAsync = ref.watch(yearEntriesProvider);
    final topInset = MediaQuery.of(context).padding.top;
    return entriesAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(
        child: Text(
          '记录加载失败',
          style: TextStyle(color: _kHintGray, fontSize: 14),
        ),
      ),
      data: (entries) {
        // 按逻辑日聚合（近 3 年，key 统一为逻辑日零点；
        // 重置时刻之前的记录计入前一天）
        final byDay = <DateTime, List<DrinkEntry>>{};
        for (final e in entries) {
          final d = LogicalDay.of(e.drankAt);
          byDay.putIfAbsent(d, () => []).add(e);
        }
        final days = byDay.keys
            .where((d) => !_pendingDeletedDays.contains(_dayKey(d)))
            .toList()
          ..sort((a, b) => b.compareTo(a));
        final goalMl = ref.watch(profileProvider)?.dailyGoalMl ?? 2000;
        final today = _today();

        if (days.isEmpty) {
          return ListView(
            padding: EdgeInsets.only(top: topInset + 60, bottom: 120),
            children: const [
              SizedBox(height: 140),
              Icon(Icons.water_drop_outlined,
                  size: 46, color: Color(0xFFD6D9DD)),
              SizedBox(height: 12),
              Text(
                '还没有饮水记录',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF9BA0A6),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        }

        // 按月分组（倒序：最新月份在前）
        final groups = <String, List<DateTime>>{};
        for (final d in days) {
          final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
          groups.putIfAbsent(key, () => []).add(d);
        }

        final children = <Widget>[];

        groups.forEach((_, list) {
          final month = DateTime(list.first.year, list.first.month, 1);
          final completeDays = list.where((d) {
            final ml = byDay[d]!.fold<int>(0, (s, e) => s + e.effectiveMl);
            return goalMl > 0 && ml >= goalMl;
          }).length;
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
              child: Row(
                children: [
                  Text(
                    '${month.year}年${month.month}月',
                    style: const TextStyle(
                      color: _kTextDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${list.length} 天 · 达标 $completeDays 天',
                    style: const TextStyle(
                      color: _kHintGray,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildListDeleteToggle(),
                ],
              ),
            ),
          );
          for (var i = 0; i < list.length; i++) {
            final day = list[i];
            final dayEntries = byDay[day]!;
            children.add(
              // 行内不再包 Dismissible：横向手势让给 PageView 做页面左右切换
              _buildListDayRow(
                day: day,
                entries: dayEntries,
                goalMl: goalMl,
                today: today,
                isLast: i == list.length - 1,
              ),
            );
          }
        });

        return ListView(
          padding: EdgeInsets.fromLTRB(36, topInset + 60, 36, 120),
          children: children,
        );
      },
    );
  }

  /// 列表单日行：日期进度环 + 日期/饮品图标 + 当日净摄入量与目标占比
  Widget _buildListDayRow({
    required DateTime day,
    required List<DrinkEntry> entries,
    required int goalMl,
    required DateTime today,
    required bool isLast,
  }) {
    const orange = Color(0xFFF5A623);
    const red = Color(0xFFE5484D);

    final totalMl = entries.fold<int>(0, (s, e) => s + e.effectiveMl);
    final ratio = goalMl > 0 ? totalMl / goalMl : 0.0;
    final complete = goalMl > 0 && totalMl >= goalMl;
    final ringColor =
        complete ? _kCyan : (ratio >= 0.7 ? orange : red);
    final isToday =
        day.year == today.year && day.month == today.month && day.day == today.day;

    // 当日出现过的饮品（按首次出现去重），最多展示 3 个图标
    final seen = <String>{};
    final shown = <DrinkEntry>[];
    for (final e in entries) {
      if (seen.add(e.beverageId)) shown.add(e);
    }

    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final diffDays = today.difference(day).inDays;
    // 今天由行尾的「今天」小标签标识，这里统一显示日期，避免同一行出现两次「今天」
    final label = diffDays == 1 ? '昨天' : '${day.month}月${day.day}日';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        if (_listDeleteMode) {
          // 删除模式：点行任意位置弹出删除确认卡
          _showDeleteConfirmCard(day, entries);
        } else {
          _showDayRecordsSheet(day, entries);
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(
                  color:
                      isLast ? Colors.transparent : const Color(0xFFF0F1F3),
                ),
              ),
            ),
            child: Row(
          children: [
            // 日期进度环：环比例 = 当日净摄入 / 目标
            SizedBox(
              width: 46,
              height: 46,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(46, 46),
                    painter: _DayRingPainter(
                      ratio.clamp(0.0, 1.0),
                      ringColor,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${day.day}',
                        style: const TextStyle(
                          color: _kTextDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '周${weekdays[day.weekday - 1]}',
                        style: const TextStyle(
                          color: _kHintGray,
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: _kTextDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (isToday) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F4F8),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            '今天',
                            style: TextStyle(
                              color: _kCyan,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      if (complete) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.check_circle,
                            size: 14, color: _kCyan),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final e in shown.take(3))
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: Center(
                              child: _beverageById(e.beverageId) != null
                                  ? _beverageIcon(
                                      _beverageById(e.beverageId)!, 16)
                                  : Icon(
                                      e.beverageCategory.icon,
                                      size: 14,
                                      color: e.beverageCategory.color,
                                    ),
                            ),
                          ),
                        ),
                      if (shown.length > 3)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            '+${shown.length - 3}',
                            style: const TextStyle(
                              color: _kHintGray,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          '${entries.length} 次记录',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _kHintGray,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${UnitFormat.number(totalMl)}',
                        style: const TextStyle(
                          color: _kTextDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(
                        text: ' ${UnitFormat.unit.symbol}',
                        style: const TextStyle(
                          color: _kHintGray,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${(ratio * 100).round().clamp(0, 100)}%',
                  style: TextStyle(
                    color: ringColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
          // 删除模式：右上角红色「−」悬浮，不占位、不挤动其它元素
          if (_listDeleteMode)
            Positioned(
              top: 4,
              right: -22,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Color(0xFFF0655C),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.remove,
                    size: 15, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// 列表页月度删除开关：未开启=灰底灰图标，开启=浅红底红图标（标红）
  Widget _buildListDeleteToggle() {
    final active = _listDeleteMode;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _listDeleteMode = !_listDeleteMode);
      },
      // 无背景色：选中时只有图标本身变红
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        child: Icon(
          Icons.delete_outline,
          size: 19,
          color: active ? const Color(0xFFE5484D) : _kHintGray,
        ),
      ),
    );
  }

  /// 删除确认卡（顶部浅蓝带 + 取消/确认底栏）
  Future<void> _showDeleteConfirmCard(
      DateTime day, List<DrinkEntry> entries) async {
    final width = MediaQuery.sizeOf(context).width - 72;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: width,
            height: 392,
            child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 顶部浅蓝带
                      Container(height: 56, color: const Color(0xFFEAF7FB)),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                          child: Column(
                            children: [
                              const Text(
                                '删除确认',
                                style: TextStyle(
                                  color: _kTextDark,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                '删除了就不能恢复了哟，确认要删除吗？',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _kHintGray,
                                  fontSize: 15,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 底栏：取消 | 确认（细线分隔）
                      Container(
                        height: 56,
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Color(0xFFE7E7EA)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => Navigator.pop(ctx, false),
                                child: const Center(
                                  child: Text(
                                    '取消',
                                    style: TextStyle(
                                      color: _kHintGray,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(width: 1, color: const Color(0xFFE7E7EA)),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => Navigator.pop(ctx, true),
                                child: const Center(
                                  child: Text(
                                    '确认',
                                    style: TextStyle(
                                      color: _kCyan,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ),
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() => _pendingDeletedDays.add(_dayKey(day)));
      await _deleteDayEntries(day, entries);
    }
  }


  /// 列表页点击某天：只读查看当天全部饮水记录
  /// （与「编辑记录」同款居中小窗口，去掉删除按钮，只能查看）
  Future<void> _showDayRecordsSheet(
      DateTime day, List<DrinkEntry> entries) async {
    final list = [...entries]..sort((a, b) => b.drankAt.compareTo(a.drankAt));
    final total = list.fold<int>(0, (s, e) => s + e.effectiveMl);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.sizeOf(ctx).width - 72,
            height: 440,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 26, bottom: 4),
                  child: Text(
                    '饮水记录 · ${DateFormat('M月d日').format(day)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _kTextDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '共 ${list.length} 次 · 合计 ${UnitFormat.volume(total)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _kHintGray,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    itemCount: list.length,
                    itemBuilder: (ctx, i) {
                      final e = list[i];
                      final cat = e.beverageCategory;
                      final b = _beverageById(e.beverageId);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: Center(
                                child: b != null
                                    ? _beverageIcon(b, 34)
                                    : Icon(cat.icon,
                                        color: cat.color, size: 24),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.beverageName,
                                    style: const TextStyle(
                                      color: _kTextDark,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${UnitFormat.volume(e.volumeMl, compact: true)} · '
                                    '${DateFormat('HH:mm').format(e.drankAt)}',
                                    style: const TextStyle(
                                        color: _kHintGray, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // 底部「完成」（与编辑记录窗口同款底栏）
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    height: 54,
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Color(0xFFE7E7EA)),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '完成',
                      style: TextStyle(
                        color: _kCyan,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 删除某天全部记录（软删 + 全链刷新 + 同步桌面小组件）
  Future<void> _deleteDayEntries(
      DateTime day, List<DrinkEntry> entries) async {
    final storage = await ref.read(localStorageProvider.future);
    for (final e in entries) {
      await storage.softDeleteEntry(e.clientId);
    }
    if (!mounted) return;
    // 全链刷新：列表/柱状图/日历/收集总量/连续签到/连续达标
    ref.invalidate(todayEntriesProvider);
    ref.invalidate(checkinDaysProvider);
    ref.invalidate(streakProvider);
    // 等列表数据重算完成后再摘掉本地占位，否则该日期会永久停留在隐藏集合里
    await ref.read(yearEntriesProvider.future);
    if (!mounted) return;
    setState(() => _pendingDeletedDays.remove(_dayKey(day)));
    // 同步桌面小组件：删除后从存储重算今日合计（按逻辑日取，避免重置时间前出错）
    final todayEntries = await storage.loadEntriesForDay(LogicalDay.today());
    if (!mounted) return;
    final streak = await ref.read(checkinDaysProvider.future);
    if (!mounted) return;
    await syncWidgetFromSettings(
      ref.read,
      todayMl: todayEntries.fold<int>(0, (s, e) => s + e.effectiveMl),
      goalMl: ref.read(profileProvider)?.dailyGoalMl ?? 2000,
      streakDays: streak,
    );
  }

  // ---------------- 月历 ----------------

  Widget _buildCalendar(DateTime todayKey) {
    final monthData = ref.watch(monthDataProvider(_calMonth));
    final goalMl = ref.watch(profileProvider)?.dailyGoalMl ?? 2000;
    return Padding(
      // 左右 22 + 日历内层 14 = 36，与趋势页图表对齐
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: monthData.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox(height: 240),
        error: (_, __) => const SizedBox(height: 240),
        data: (data) => _MonthCalendar(
          data: data,
          goalMl: goalMl,
          month: _calMonth,
          today: todayKey,
          onSelect: (d) => setState(() {
            _selectedDate = d;
            _calMonth = DateTime(d.year, d.month, 1);
          }),
          // 翻月：可以回看更早的月份；不允许翻到未来月份
          onPrevMonth: () => setState(() {
            _calMonth =
                DateTime(_calMonth.year, _calMonth.month - 1, 1);
          }),
          onNextMonth: _calMonth.year == todayKey.year &&
                  _calMonth.month == todayKey.month
              ? null
              : () => setState(() {
                    _calMonth =
                        DateTime(_calMonth.year, _calMonth.month + 1, 1);
                  }),
        ),
      ),
    );
  }

  // ---------------- 选中日期内容区 ----------------

  /// 选中日期的内容区：
  /// - 有条目：角色（与首页角色统一）+ 当日总量 + 编辑记录/补上遗漏按钮 + 记录列表
  /// - 无条目：显示「无条目」+「补上遗漏」按钮
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
      // 无条目：显示「无条目」+「补上遗漏」按钮（对标原版第六张图）
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
            _ActionPill(
              icon: Icons.add_circle_outline,
              label: '补上遗漏',
              onTap: _showBackfillSheet,
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
          UnitFormat.volume(displayMl, compact: true),
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
            _ActionPill(
              icon: Icons.edit,
              label: '编辑记录',
              onTap: _showEditSheet,
            ),
            const SizedBox(width: 12),
            _ActionPill(
              icon: Icons.add_circle_outline,
              label: '补上遗漏',
              onTap: _showBackfillSheet,
            ),
          ],
        ),
        const SizedBox(height: 24),
        // 记录列表（按筛选过滤）
        _buildEntryList(entries),
      ],
    );
  }

  // ---------------- 编辑记录 / 补上遗漏 ----------------

  /// 编辑记录弹层：列出选中日期全部条目，支持删除单条（软删 + 全链刷新）
  Future<void> _showEditSheet() async {
    final entries = ref
            .read(dayEntriesForProvider(_selectedDate))
            .valueOrNull ??
        const <DrinkEntry>[];
    if (entries.isEmpty) {
      _showTip('当天没有可编辑的记录');
      return;
    }
    final list = [...entries]..sort((a, b) => b.drankAt.compareTo(a.drankAt));
    // 居中小窗口（对标竞品弹窗样式）：固定大小、白色大圆角卡 +
    // 半透明遮罩，饮品记录在窗口内上下滚动，底部「完成」关闭
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            // 记录全部删完自动关窗
            if (list.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
              });
            }
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.sizeOf(ctx).width - 72,
                  height: 440,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 标题
                      Padding(
                        padding: const EdgeInsets.only(top: 26, bottom: 10),
                        child: Text(
                          '编辑记录 · ${DateFormat('M月d日').format(_selectedDate)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _kTextDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      // 饮品记录（窗口内滚动，行样式与底部弹层版一致）
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                          itemCount: list.length,
                          itemBuilder: (ctx, i) {
                            final e = list[i];
                            final cat = e.beverageCategory;
                            // 首页同款饮品图标（与记录列表统一）；饮品已删时回退分类图标
                            final b = _beverageById(e.beverageId);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: Center(
                                      child: b != null
                                          ? _beverageIcon(b, 34)
                                          : Icon(cat.icon,
                                              color: cat.color, size: 24),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.beverageName,
                                          style: const TextStyle(
                                            color: _kTextDark,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          '${UnitFormat.volume(e.volumeMl, compact: true)} · ${DateFormat('HH:mm').format(e.drankAt)}',
                                          style: const TextStyle(
                                              color: _kHintGray, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () async {
                                      final storage = await ref
                                          .read(localStorageProvider.future);
                                      await storage
                                          .softDeleteEntry(e.clientId);
                                      // 全链刷新：今日列表/柱状图/日历/收集总量/连续签到/连续达标
                                      ref.invalidate(todayEntriesProvider);
                                      ref.invalidate(checkinDaysProvider);
                                      ref.invalidate(streakProvider);
                                      // 同步桌面小组件：删除后从存储重算今日合计（
                                      // todayEntriesProvider 已失效重载，直读存储才准确）
                                      final todayEntries = await storage
                                          .loadEntriesForDay(LogicalDay.today());
                                      if (!ctx.mounted) return;
                                      final streak = await ref
                                          .read(checkinDaysProvider.future);
                                      if (!ctx.mounted) return;
                                      await syncWidgetFromSettings(
                                        ref.read,
                                        todayMl: todayEntries.fold<int>(
                                            0, (s, e) => s + e.effectiveMl),
                                        goalMl:
                                            ref.read(profileProvider)?.dailyGoalMl ??
                                                2000,
                                        streakDays: streak,
                                      );
                                      if (!ctx.mounted) return;
                                      setSheet(() => list.remove(e));
                                    },
                                    icon: const Icon(Icons.delete_outline,
                                        color: Color(0xFFE05252), size: 22),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      // 底部「完成」（细线分隔，仿竞品「我知道了」底栏）
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(ctx).pop(),
                        child: Container(
                          height: 54,
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Color(0xFFE7E7EA)),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '完成',
                            style: TextStyle(
                              color: _kCyan,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 写入补录记录并全链刷新（滑动模式的「补上」与数字模式的「确认」共用）
  Future<void> _confirmBackfill(
    BuildContext ctx,
    Beverage selected,
    int volume,
    DateTime drankAt,
  ) async {
    // 防抖：快速连点「补上」只入库一次
    if (_backfilling) return;
    if (volume <= 0) {
      _showTip('请先输入容量');
      return;
    }
    _backfilling = true;
    try {
      final v = volume.clamp(10, 2000);
      final entry = DrinkEntry.create(
        beverage: selected,
        volumeMl: v,
        drankAt: drankAt,
      );
      final storage = await ref.read(localStorageProvider.future);
      await storage.insertDrinkEntry(entry);
      // 补录日凭「有饮水记录」自动计入签到，无需另写活跃天——
      // 这样删除该日全部记录后签到会正确回退
      // 全链刷新：当日明细/柱形图/月历/首页进度/连续签到/连续达标
      ref.invalidate(todayEntriesProvider);
      ref.invalidate(checkinDaysProvider);
      ref.invalidate(streakProvider);
      // 同步桌面小组件：补录今天的数据时小组件要立刻反映新总量
      final todayEntries = await storage.loadEntriesForDay(LogicalDay.today());
      final streak = await ref.read(checkinDaysProvider.future);
      await syncWidgetFromSettings(
        ref.read,
        todayMl: todayEntries.fold<int>(0, (s, e) => s + e.effectiveMl),
        goalMl: ref.read(profileProvider)?.dailyGoalMl ?? 2000,
        streakDays: streak,
      );
      if (ctx.mounted) Navigator.pop(ctx);
    } finally {
      _backfilling = false;
    }
  }

  /// 补上遗漏弹层：选择饮品 + 输入量，写入选中日期并全链刷新
  Future<void> _showBackfillSheet() async {
    final day = _selectedDate;
    final now = DateTime.now();
    // 补录时刻默认取当前时分；但必须落在选中「逻辑日」的区间内，
    // 否则重置时间 > 0 时（例如 03:00 重置、当前 01:30）记录会落到前一天。
    var drankAt = DateTime(day.year, day.month, day.day, now.hour, now.minute);
    if (!LogicalDay.sameDay(drankAt, day)) {
      drankAt = LogicalDay.startOf(day);
    }
    // 饮品池与首页/管理页同源（预设 + 自定义），图标用 _beverageIcon 一一对应
    final pool = _drinkPool();
    var selected = pool.first;
    var volume = selected.defaultMl;
    // 容量输入方式：true=滑动选择，false=App 内嵌数字输入（不唤起系统键盘）
    var slideMode = true;

    // 居中小窗口：固定大小白卡 + 半透明遮罩
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.sizeOf(ctx).width - 72,
                height: 480,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 顶栏：左上角日期 + 右上角补录时刻
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            DateFormat('M月d日').format(day),
                            style: const TextStyle(
                              color: _kTextDark,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            DateFormat('HH:mm').format(drankAt),
                            style: const TextStyle(
                              color: _kHintGray,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 饮品横滑选择（预设+自定义，图标与饮品管理页一一对应）
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        height: 90,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          scrollDirection: Axis.horizontal,
                          itemCount: pool.length,
                          itemBuilder: (ctx, i) {
                            final b = pool[i];
                            final isSel = b.id == selected.id;
                            return GestureDetector(
                              onTap: () => setSheet(() {
                                selected = b;
                                volume = b.defaultMl;
                              }),
                              child: Container(
                                width: 66,
                                margin: const EdgeInsets.only(right: 8),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // 选中不描边：图标轻微放大 + 回弹
                                    AnimatedScale(
                                      scale: isSel ? 1.16 : 1.0,
                                      duration:
                                          const Duration(milliseconds: 180),
                                      curve: Curves.easeOutBack,
                                      child: _beverageIcon(b, 34),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      b.name,
                                      style: TextStyle(
                                        color:
                                            isSel ? _kTextDark : _kHintGray,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 容量输入区：输入方式切换图标是独立模块，固定在左下角，
                    // 不随「滑动输入 / 数字输入」的布局切换而移动
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 2),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: slideMode
                                  ? _BackfillSlideArea(
                                      volume: volume,
                                      onChanged: (v) => setSheet(() =>
                                          volume = ((v / 10).round() * 10)
                                              .clamp(10, 2000)),
                                    )
                                  : _backfillNumberArea(
                                      volume: volume,
                                      onKey: (k) => setSheet(() {
                                        if (k == 'AC') {
                                          volume = 0;
                                        } else if (k == '⌫') {
                                          volume = volume ~/ 10;
                                        } else {
                                          final next =
                                              int.tryParse('$volume$k') ?? 0;
                                          if (next <= 2000) volume = next;
                                        }
                                      }),
                                      onConfirm: () => _confirmBackfill(
                                          ctx, selected, volume, drankAt),
                                    ),
                            ),
                            Align(
                              alignment: Alignment.bottomLeft,
                              child: Padding(
                                // 与数字键盘第一列按键的左边缘、底边对齐
                                padding: const EdgeInsets.only(
                                    left: 10, bottom: 4),
                                child: Builder(
                                  builder: (iconCtx) => _backfillModeIcon(
                                    onTap: () => _showInputModeMenu(
                                      iconCtx,
                                      slideMode: slideMode,
                                      onSelect: (isSlide) =>
                                          setSheet(() => slideMode = isSlide),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 底部「补上」（细线分隔，与编辑记录窗口的「完成」同款）
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          _confirmBackfill(ctx, selected, volume, drankAt),
                      child: Container(
                        height: 54,
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Color(0xFFE7E7EA)),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '补上',
                          style: TextStyle(
                            color: _kCyan,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }

  // ---------------- 主操作按钮（日期页） ----------------

  /// 键盘小图标弹出的模式菜单：滑动输入 / 数字输入
  ///
  /// 以图标为锚点，向左上角方向展开（菜单出现在图标上方、向右延伸）
  Future<void> _showInputModeMenu(
    BuildContext anchorCtx, {
    required bool slideMode,
    required ValueChanged<bool> onSelect,
  }) async {
    final box = anchorCtx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final iconRect = box.localToGlobal(Offset.zero) & box.size;
    final screen = MediaQuery.sizeOf(anchorCtx);
    const menuWidth = 150.0;
    const menuHeight = 104.0;
    // 左边缘与图标左边缘对齐（略缩进），底部位于图标上方 8px
    final left = (iconRect.left - 4)
        .clamp(10.0, (screen.width - menuWidth - 10).clamp(10.0, 10000.0));
    final bottom =
        (screen.height - iconRect.top + 8).clamp(menuHeight + 10, screen.height);

    final completer = Completer<String?>();
    late OverlayEntry entry;
    var closed = false;
    void close(String? v) {
      if (closed) return;
      closed = true;
      entry.remove();
      completer.complete(v);
    }

    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // 点击空白处关闭
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => close(null),
            ),
          ),
          Positioned(
            left: left,
            bottom: bottom,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: menuWidth,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _modeMenuItem(
                      label: '滑动输入',
                      icon: Icons.linear_scale,
                      selected: slideMode,
                      onTap: () => close('slide'),
                    ),
                    _modeMenuItem(
                      label: '数字输入',
                      icon: Icons.dialpad_rounded,
                      selected: !slideMode,
                      onTap: () => close('number'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(anchorCtx, rootOverlay: true).insert(entry);
    final result = await completer.future;
    if (result != null && anchorCtx.mounted) onSelect(result == 'slide');
  }

  Widget _modeMenuItem({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: SizedBox(
        height: 46,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: selected ? _kCyan : _kHintGray),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: selected ? _kTextDark : _kHintGray,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (selected) const Icon(Icons.check, size: 16, color: _kCyan),
            ],
          ),
        ),
      ),
    );
  }

  /// 左下角键盘小图标（点开模式菜单）
  Widget _backfillModeIcon({required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 40,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // 与数字键盘按键同色，切换模式时无视觉跳变
          color: const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.apps_rounded,
          size: 20,
          color: Color(0xFF6B7A8C),
        ),
      ),
    );
  }

  /// 数字键盘单键（统一浅灰底）
  Widget _padCell({required Widget child, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      ),
    );
  }

  /// 补上遗漏：App 内嵌数字键盘（不唤起系统输入法）
  ///
  /// 布局对齐参考图：顶部浅灰显示条（右对齐容量）+ 4 列键盘
  /// 7 8 9 AC / 4 5 6 ⌫ / 1 2 3 确认(跨两行) / 空位 0 00
  Widget _backfillNumberArea({
    required int volume,
    required ValueChanged<String> onKey,
    required VoidCallback onConfirm,
  }) {
    // 单键：统一浅灰底圆角块
    Widget key(
      Widget child, {
      required VoidCallback onTap,
      int flex = 1,
      EdgeInsets margin = const EdgeInsets.all(4),
    }) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: margin,
          child: _padCell(child: child, onTap: onTap),
        ),
      );
    }

    Widget digit(String label, {int flex = 1}) {
      return key(
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF2F3542),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
        onTap: () => onKey(label),
        flex: flex,
      );
    }

    Widget column(List<Widget> children) {
      return Expanded(child: Column(children: children));
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 显示条：右对齐金额 + ml
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.centerRight,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F2F6),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$volume',
                style: const TextStyle(
                  color: _kCyan,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                ' ml',
                style: TextStyle(
                  color: _kTextDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SizedBox(
            height: 190,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 第一列：7 4 1（左下角空出，作为切换图标的固定位置）
                column([
                  digit('7'),
                  digit('4'),
                  digit('1'),
                  const Expanded(child: SizedBox()),
                ]),
                // 第二列：8 5 2 0
                column([digit('8'), digit('5'), digit('2'), digit('0')]),
                // 第三列：9 6 3 00
                column([digit('9'), digit('6'), digit('3'), digit('00')]),
                // 第四列：AC ⌫ 确认（跨两行）
                column([
                  key(
                    const Text(
                      'AC',
                      style: TextStyle(
                        color: Color(0xFF2F3542),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    onTap: () => onKey('AC'),
                  ),
                  key(
                    const Icon(Icons.backspace_outlined,
                        size: 18, color: Color(0xFF3A4250)),
                    onTap: () => onKey('⌫'),
                  ),
                  key(
                    const Text(
                      '确认',
                      style: TextStyle(
                        color: Color(0xFF2F3542),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    onTap: onConfirm,
                    flex: 2,
                    margin: const EdgeInsets.all(4),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- 记录列表 ----------------

  Widget _buildEntryList(List<DrinkEntry> entries) {
    // 彩色按钮筛选只作用于柱形图，不筛选当日记录列表（对标原版）
    final sorted = [...entries]..sort((a, b) => b.drankAt.compareTo(a.drankAt));

    if (sorted.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(36, 24, 36, 24),
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

  /// 单条记录行：饮品图标（与首页饮品选项一一对应）+ 名称 + 容量 + 右侧时间
  Widget _buildEntryRow(DrinkEntry e) {
    // 按记录的饮品 id 渲染首页同款图标；饮品已被删除时回退分类图标
    final b = _beverageById(e.beverageId);
    // 左右 36 = 与趋势页图表对齐（趋势卡 16 外边距 + 20 内边距）
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 0, 36, 20),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: b != null
                  ? _beverageIcon(b, 28)
                  : Icon(e.beverageCategory.icon,
                      color: e.beverageCategory.color, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.beverageName,
                  style: const TextStyle(
                    color: _kTextDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  UnitFormat.volume(e.volumeMl, compact: true),
                  style: const TextStyle(
                    color: _kTextDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          // 折算量 + 记录时间（同字号；折算为正显示水蓝 +xxxml，为负显示酒红 -xxxml）
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${e.effectiveMl >= 0 ? '+' : '-'}${UnitFormat.volume(e.effectiveMl.abs(), compact: true)}',
                style: TextStyle(
                  color: e.effectiveMl >= 0
                      ? _kCyan
                      : const Color(0xFFC9364F), // 酒红色
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat('HH:mm').format(e.drankAt),
                style: const TextStyle(color: _kHintGray, fontSize: 14),
              ),
            ],
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
      // 趋势页不再用卡片背景包裹，内容直接落在白底上
      child: Column(
        children: [
          Row(
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
              const Spacer(),
              // 柱形 ↔ 折线 切换按钮（图标显示点击后进入的形态）
              _chartTypeToggle(),
              const SizedBox(width: 10),
              // 右侧彩色按钮 = 饮品筛选入口
              // 选中「全部」→彩虹渐变圆；选中具体饮品→该饮品分类色+图标（一一对应）
              _buildFilterButton(),
            ],
          ),
          const SizedBox(height: 16),
          _buildChart(),
          // 图表与各饮品摄入量模块之间：加大间距 + 灰色细线分隔
          const SizedBox(height: 34),
          Container(height: 1, color: const Color(0xFFE7E7EA)),
          const SizedBox(height: 26),
          // 各饮品摄入量面板（随天/周/月周期切换聚合范围）
          _buildIntakePanel(),
        ],
      ),
    );
  }

  /// 柱形 ↔ 折线切换按钮：浅灰圆底，图标显示点击后切换到的形态
  Widget _chartTypeToggle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _chartLine = !_chartLine);
      },
      child: Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          color: Color(0xFFECECEE),
          shape: BoxShape.circle,
        ),
        child: Icon(
          _chartLine ? Icons.bar_chart_rounded : Icons.show_chart,
          size: 18,
          color: const Color(0xFF6B7280),
        ),
      ),
    );
  }

  /// 彩色筛选按钮：选中「全部」→彩虹渐变水滴；选中具体饮品→首页同款图标
  Widget _buildFilterButton() {
    if (_beverageFilter == '全部') {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showFilterSheet(),
        child: const CustomPaint(
          size: Size(32, 32),
          painter: _WaterDropPainter(),
        ),
      );
    }
    // 选中具体饮品：渲染与管理页/首页一致的图标（浅灰圆底承托）
    final b = _filterBeverage();
    return GestureDetector(
      onTap: () => _showFilterSheet(),
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFECECEE),
        ),
        child: Center(
          child: b != null
              ? _beverageIcon(b, 28)
              : const Icon(Icons.local_drink, color: _kCyan, size: 18),
        ),
      ),
    );
  }

  Widget _buildChart() {
    if (_tab == 0) {
      // 天：过去 7 天（按彩色按钮筛选的饮品过滤柱形图数据）
      final last7 = ref.watch(filteredLast7DaysProvider(_beverageFilter));
      return last7.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox(height: 140),
        error: (_, __) => const SizedBox(height: 140),
        data: (days) {
          // 筛选后该时段没有记录：给出空态，避免只显示一排空柱子
          if (_beverageFilter != '全部' &&
              days.every((d) => d.count == 0)) {
            return _chartEmptyHint();
          }
          return _BarChart(
            title: '过去 7 天',
            barWidth: 26,
            line: _chartLine,
            bars: [
              for (final d in days)
                _BarData(
                  label: const ['日', '一', '二', '三', '四', '五', '六'][d.day.weekday % 7],
                  value: d.effectiveMl,
                  // 非零都标注数值：负数日显示 -xxxml（红色柱）
                  valueLabel: d.effectiveMl != 0 ? _fmtMl(d.effectiveMl) : null,
                  highlighted: _isToday(d.day),
                ),
            ],
          );
        },
      );
    }
    // 周 / 月：近 3 年每日聚合后本地计算（按彩色按钮筛选的饮品过滤）
    final year = ref.watch(filteredYearDailyProvider(_beverageFilter));
    return year.when(
      skipLoadingOnReload: true,
      loading: () => const SizedBox(height: 140),
      error: (_, __) => const SizedBox(height: 140),
      data: (data) {
        if (_beverageFilter != '全部' && data.isEmpty) {
          return _chartEmptyHint();
        }
        return _tab == 1
            ? _BarChart(
                title: '每日平均\n过去 4 周',
                barWidth: 40,
                line: _chartLine,
                bars: _weekBars(data),
              )
            : _BarChart(
                title: '每日平均\n过去 12 个月',
                barWidth: 16,
                line: _chartLine,
                bars: _monthBars(data),
              );
      },
    );
  }

  /// 筛选后无数据时的图表空态（与图表等高，保持统计卡高度稳定）
  Widget _chartEmptyHint() {
    return const SizedBox(
      height: 144,
      child: Center(
        child: Text(
          '这段时间没有该饮品的记录',
          style: TextStyle(color: _kHintGray, fontSize: 13),
        ),
      ),
    );
  }

  // ---------------- 各饮品摄入量面板 ----------------

  /// 面板聚合窗口：天=今天，周=本周（按「一周开始时间」设置，与日历一致），
  /// 月=本月；均按「逻辑日」边界切窗（重置时刻之前的记录属于前一天）
  (DateTime, DateTime) _panelWindow() {
    final today = _today();
    switch (_tab) {
      case 0: // 天：当前逻辑日
        return (LogicalDay.startOf(today), LogicalDay.endOf(today));
      case 1: // 周：本周起始逻辑日 ~ 本周最后一天结束
        final weekStart = LogicalDay.weekStartOf(today);
        final weekEnd = weekStart.add(const Duration(days: 6));
        return (LogicalDay.startOf(weekStart), LogicalDay.endOf(weekEnd));
      default: // 月：本月 1 号 ~ 下月 1 号（逻辑日边界）
        final first = DateTime(today.year, today.month, 1);
        return (
          LogicalDay.startOf(first),
          LogicalDay.startOf(DateTime(today.year, today.month + 1, 1)),
        );
    }
  }

  /// 当前指标取值：0=总摄入量(实际容量) 1=水份(有效进水量) 2=热量(kcal)
  /// 卡路里关闭时强制回退到「总摄入量」，避免面板仍展示已被隐藏的热量
  int get _activeMetric =>
      (_intakeMetric == 2 && !SettingsFlags.instance.trackCalories)
          ? 0
          : _intakeMetric;

  int _metricValue(_BeverageTotal t) {
    switch (_activeMetric) {
      case 0:
        return t.volumeMl;
      case 1:
        return t.effectiveMl;
      default:
        return t.calories;
    }
  }

  String _metricValueText(_BeverageTotal t) {
    switch (_activeMetric) {
      case 0:
        return _fmtMl(t.volumeMl);
      case 1:
        return _fmtMl(t.effectiveMl);
      default:
        return '${t.calories} 千卡';
    }
  }

  /// 按当前周期聚合各饮品并按当前指标降序，返回 (聚合, 占总量百分比)
  List<(_BeverageTotal, int)> _panelRows(List<DrinkEntry> entries) {
    final (start, end) = _panelWindow();
    final map = <String, _BeverageTotal>{};
    for (final e in entries) {
      if (e.drankAt.isBefore(start) || !e.drankAt.isBefore(end)) continue;
      final t = map.putIfAbsent(
        e.beverageName,
        () => _BeverageTotal(name: e.beverageName, category: e.beverageCategory),
      );
      t.volumeMl += e.volumeMl;
      t.effectiveMl += e.effectiveMl;
      // 热量优先用录入时的快照（改饮品定义不会回写历史）；
      // 旧记录（-1）才回退到饮品当前定义折算
      if (e.calories >= 0) {
        t.calories += e.calories;
      } else {
        final b = _beverageById(e.beverageId) ?? _beverageByName(e.beverageName);
        if (b != null && (b.calories ?? 0) > 0 && b.defaultMl > 0) {
          t.calories += (b.calories! * e.volumeMl / b.defaultMl).round();
        }
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => _metricValue(b).compareTo(_metricValue(a)));
    // 占比按绝对值计算：纯酒日（水份为负）也能得到 100% 而不是全 0
    final grand = list.fold<int>(0, (s, t) => s + _metricValue(t).abs());
    return [
      for (final t in list)
        (
          t,
          grand > 0
              ? (_metricValue(t).abs() / grand * 100).round().clamp(0, 100)
              : 0,
        ),
    ];
  }

  Widget _buildIntakePanel() {
    // 不受图表右上角饮品筛选按钮影响：面板始终展示全部饮品的摄入量
    final entriesAsync = ref.watch(yearEntriesProvider);
    return entriesAsync.when(
      skipLoadingOnReload: true,
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (entries) => ListenableBuilder(
        listenable: SettingsFlags.instance,
        builder: (_, __) {
          final rows = _panelRows(entries);
          if (rows.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // 标题行：左标题（小号常规字重）+ 右侧三指标切换（竖线分隔，选中加粗深色）
            Row(
              children: [
                const Text(
                  '各饮品摄入量',
                  style: TextStyle(
                    color: _kTextDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const Spacer(),
                _metricTab('总摄入量', 0),
                _metricSeparator(),
                _metricTab('水份', 1),
                if (SettingsFlags.instance.trackCalories) ...[
                  _metricSeparator(),
                  _metricTab('热量', 2),
                ],
              ],
            ),
            const SizedBox(height: 14),
            // 每个饮品一张白色圆角卡
            for (final (t, percent) in rows) _panelCard(t, percent),
          ],
          );
        },
      ),
    );
  }

  Widget _metricSeparator() => Container(
        width: 1,
        height: 12,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: const Color(0xFFD9DDE2),
      );

  Widget _metricTab(String label, int index) {
    final selected = _activeMetric == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _intakeMetric = index);
      },
      child: Text(
        label,
        style: TextStyle(
          color: selected ? _kTextDark : const Color(0xFF9AA1A9),
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _panelCard(_BeverageTotal t, int percent) {
    final b = _beverageByName(t.name);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 饮品图标（与日期页单条记录的图标同尺寸；已删除的自定义饮品回退分类图标）
          SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: b != null
                  ? _beverageIcon(b, 28)
                  : Icon(t.category.icon, size: 24, color: t.category.color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      t.name,
                      style: const TextStyle(
                        color: _kTextDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const Spacer(),
                    // 数值 + [占比]（水份指标为负数时数值用酒红色，同记录列表）
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: _metricValueText(t),
                            style: TextStyle(
                              color: _metricValue(t) < 0
                                  ? const Color(0xFFC9364F)
                                  : _kTextDark,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          TextSpan(
                            text: '  [$percent%]',
                            style: const TextStyle(
                              color: Color(0xFF9AA1A9),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 横向进度条：浅蓝填充 + 浅灰轨道，填充比例 = 占比
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      children: [
                        Container(color: const Color(0xFFEEF0F3)),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (percent / 100).clamp(0.0, 1.0),
                          child: Container(color: const Color(0xFF8FD9F5)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 周 Tab：过去 4 周（按「一周开始时间」设置，与日历/面板一致，本周截至今天）每日平均
  List<_BarData> _weekBars(Map<DateTime, DayTotal> year) {
    final today = _today();
    final thisWeekStart = LogicalDay.weekStartOf(today);
    final bars = <_BarData>[];
    for (var i = 3; i >= 0; i--) {
      final start = thisWeekStart.subtract(Duration(days: 7 * i));
      final isCurrent = i == 0;
      final end = isCurrent
          ? today.add(const Duration(days: 1))
          : start.add(const Duration(days: 7));
      var sum = 0;
      // 分母 = 窗口内实际天数（本周只算到今天），没记录的日子按 0 计入日均
      var dayCount = 0;
      for (var day = start; day.isBefore(end); day = day.add(const Duration(days: 1))) {
        dayCount++;
        final dt = year[DateTime(day.year, day.month, day.day)];
        // 负数日同样计入（净量为负说明当天以酒类为主）
        if (dt != null) sum += dt.effectiveMl;
      }
      final avg = dayCount == 0 ? 0 : sum ~/ dayCount;
      bars.add(_BarData(
        label: _weekLabel(start, isCurrent),
        value: avg,
        valueLabel: isCurrent && avg != 0 ? '${(avg / 1000).toStringAsFixed(1)}升' : null,
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
      // 分母 = 窗口内实际天数（本月只算到今天），没记录的日子按 0 计入日均
      var dayCount = 0;
      for (var day = m; day.isBefore(end); day = day.add(const Duration(days: 1))) {
        dayCount++;
        final dt = year[DateTime(day.year, day.month, day.day)];
        // 负数日同样计入（净量为负说明当天以酒类为主）
        if (dt != null) sum += dt.effectiveMl;
      }
      final avg = dayCount == 0 ? 0 : sum ~/ dayCount;
      final isCurrent = k == 0;
      // 去年月份显示纯数字，今年显示 N 月，当前月纯数字
      final label = isCurrent || m.year < today.year ? '${m.month}' : '${m.month}月';
      bars.add(_BarData(
        label: label,
        value: avg,
        valueLabel: isCurrent && avg != 0 ? (avg / 1000).toStringAsFixed(1) : null,
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

  String _fmtMl(int ml) => UnitFormat.smart(ml);

  DateTime _today() => LogicalDay.today();

  bool _isToday(DateTime d) {
    final t = _today();
    return d.year == t.year && d.month == t.month && d.day == t.day;
  }

  // ---------------- 筛选弹层（原版样式：全屏底部弹层 + 彩色饮品图标行） ----------------

  void _showFilterSheet() {
    // 候选饮品来自近 3 年全部历史记录，而不是只来自当前选中日期，
    // 避免「前几天喝过但今天没喝」的饮品无法筛选
    final entries = ref.read(yearEntriesProvider).valueOrNull ?? const [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FilterSheet(
        current: _beverageFilter,
        entries: entries,
        pool: _drinkPool(),
        onSelect: (v) => setState(() => _beverageFilter = v),
      ),
    );
  }

  /// 首页/管理页同款饮品池（预设 + 自定义）
  List<Beverage> _drinkPool() =>
      [...Beverage.presets, ...ref.read(customBeveragesProvider)];

  /// 把筛选 token 还原成饮品对象（筛选按钮图标用）
  Beverage? _filterBeverage() {
    final f = _beverageFilter;
    if (f == '全部') return null;
    if (f.startsWith('id:')) return _beverageById(f.substring(3));
    if (f.startsWith('name:')) return _beverageByName(f.substring(5));
    return _beverageByName(f);
  }

  /// 按名称查找饮品（筛选按钮用）
  Beverage? _beverageByName(String name) {
    for (final b in _drinkPool()) {
      if (b.name == name) return b;
    }
    return null;
  }

  /// 按条目的饮品 id 查找饮品（记录列表用；已删除的自定义饮品返回 null）
  Beverage? _beverageById(String id) {
    for (final b in _drinkPool()) {
      if (b.id == id) return b;
    }
    return null;
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

// ==================== 多层饮品色水滴按钮 ====================

/// 多层饮品色水滴（统计卡「全部」筛选按钮）：底部圆弧 + 顶部汇聚尖点，
/// 形状不变，内部改为 4 层横向色带填充（自上而下：酒类粉/奶类橙黄/
/// 纯水青/茶类绿），层间为轻微波浪分界，呼应竞品的分层配色设计
class _WaterDropPainter extends CustomPainter {
  const _WaterDropPainter();

  /// 色带颜色（自上而下），全部取自饮品分类色
  static const List<Color> _layerColors = [
    Color(0xFFE57373), // 酒类粉（顶部尖点区，对应参考图的粉层）
    Color(0xFFFFC107), // 奶类橙黄
    Color(0xFF00BFDC), // 纯水青
    Color(0xFF8BC34A), // 茶类绿（底部基色）
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final r = size.width * 0.31;
    final cy = size.height * 0.58;
    final tipY = size.height * 0.08;
    final drop = Path()
      ..moveTo(cx, tipY)
      // 右侧流线：从尖点外凸弧线过渡到圆右侧
      ..cubicTo(cx + r * 0.72, cy - r * 0.88, cx + r, cy - r * 0.48,
          cx + r, cy)
      // 底部半圆
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        0,
        math.pi,
        false,
      )
      // 左侧流线（对称）回尖点
      ..cubicTo(cx - r, cy - r * 0.48, cx - r * 0.72, cy - r * 0.88,
          cx, tipY)
      ..close();

    canvas.save();
    canvas.clipPath(drop);

    // 波浪分界线：baseY 上下做小幅正弦起伏
    Offset wavePoint(double x, double baseY, double amp, double phase) =>
        Offset(x, baseY + amp * math.sin(x / size.width * 2 * math.pi + phase));

    // 自上而下逐层覆盖：先整滴填顶色，再依次画下层色带
    // （每条色带从其波浪分界线一直铺到底，层层覆盖出 4 段）
    final span = cy + r - tipY;
    final bands = 3; // 分界线数量 = 层数 - 1
    for (var i = 0; i <= bands; i++) {
      final Color color;
      final Path band;
      if (i == 0) {
        color = _layerColors.first;
        band = Path()..addRect(Offset.zero & size);
      } else {
        color = _layerColors[i];
        final baseY = tipY + span * i / bands;
        final amp = size.width * 0.045;
        final phase = i * 1.8; // 各层波浪错开，更自然
        band = Path();
        const segs = 24;
        band.moveTo(0, baseY + amp * math.sin(phase));
        for (var s = 1; s <= segs; s++) {
          band.lineTo(
              size.width * s / segs, wavePoint(size.width * s / segs, baseY, amp, phase).dy);
        }
        band
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
      }
      canvas.drawPath(band, Paint()..color = color);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==================== 顶部大徽章 ====================

/// 青色进度环大徽章（Y 轴翻转卡）：
/// - 进场：仅本次启动 App 后第一次进入本页时绕 Y 轴自转 3 圈（减速缓动）
///   定格在「%/今天的饮水量」正面；之后再次进入不再自动转
/// - 点击：绕 Y 轴翻 180° 露出背面「N/天连续签到」，再点翻回正面
///   （连续翻面角度累加，方向始终一致）
class _TopBadge extends StatefulWidget {
  const _TopBadge({required this.percent, required this.streakDays});
  final double percent;
  final int streakDays;

  @override
  State<_TopBadge> createState() => _TopBadgeState();
}

/// 本次 App 会话内是否已播放过徽章进场自转（会话级只转一次）
bool _badgeAutoSpunThisSession = false;

class _TopBadgeState extends State<_TopBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  /// 当前 Y 轴旋转角（弧度，连续累加）；进场自转时从 3 整圈减速转到 0（正面）
  double _angle = 0;
  double _from = 0;
  double _to = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    _ctrl.addListener(() {
      setState(() {
        _angle = _from +
            (_to - _from) * Curves.easeOutCubic.transform(_ctrl.value);
      });
    });
    // 只在本次会话第一次进入时自动转几下；后续进入直接定格正面
    if (!_badgeAutoSpunThisSession) {
      _badgeAutoSpunThisSession = true;
      _from = _angle = 3 * 2 * math.pi;
      _to = 0;
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 点击翻面：角度累加半圈（动画中忽略点击，避免角度跳变）
  void _flip() {
    if (_ctrl.isAnimating) return;
    HapticFeedback.selectionClick();
    _from = _angle;
    _to = _angle + math.pi;
    _ctrl.duration = const Duration(milliseconds: 650);
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    // cos(θ) > 0 → 正面朝向观察者（今日饮水量），否则背面（连续签到）；
    // 背面文字额外绕 Y 转 180° 抵消镜像，保证可读
    final showFront = math.cos(_angle) >= 0;
    final value = showFront
        ? '${(widget.percent * 100).round()}%'
        : '${widget.streakDays}';
    final label = showFront ? '今天的饮水量' : '天连续签到';

    return GestureDetector(
      onTap: _flip,
      child: SizedBox(
        width: 140,
        height: 140,
        child: CustomPaint(
          // 静态进度环：始终固定不转，翻面的只有环内蓝色圆
          painter: _BadgePainter(widget.percent.clamp(0.0, 1.0)),
          child: Center(
            child: SizedBox(
              width: 112,
              height: 112,
              child: Transform(
                alignment: Alignment.center,
                // 透视投影：让翻转有近大远小的 3D 纵深感
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0016)
                  ..rotateY(_angle),
                child: Container(
                  decoration: const BoxDecoration(
                    color: _kCyan,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: showFront
                      ? _texts(value, label)
                      : Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..rotateY(math.pi),
                          child: _texts(value, label),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 圆内文字（正面/背面共用）
  Widget _texts(String value, String label) {
    return Column(
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
    );
  }
}

/// 进度环（静态）：浅青轨道 + 青色进度弧；环内蓝色圆由上层绘制
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
  }

  @override
  bool shouldRepaint(_BadgePainter old) => old.progress != progress;
}

// ==================== 月历 ====================

/// 当月月历：
/// - 标题行（yyyy-MM 左对齐 + 日历小图标）+ 分隔线 + 周一起始表头
///   （对标竞品布局，无卡片背景）
/// - 有喝水记录的日期被达标度小进度环包围（蓝≥100%、橙≥70%、红<70%），
///   今天不做黑圆特殊渲染
/// - 右下角对勾小圆标仅出现在「喝过水」的日期：当天=绿色底，
///   已过日期=灰色底，未来/未喝水的日期不显示
/// - 点击任意日期 → onSelect 回调（驱动选中日期内容区动态切换）
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.data,
    required this.goalMl,
    required this.month,
    required this.today,
    required this.onSelect,
    this.onPrevMonth,
    this.onNextMonth,
  });
  final Map<int, DayTotal> data;

  /// 当日饮水目标（ml），用于计算进度环比例与颜色
  final int goalMl;

  /// 当前展示的月份（该月 1 日），列表点选其它月份日期时随之切换
  final DateTime month;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;

  /// 上/下一个月（null = 不可翻，例如已是当前月）
  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;

  /// 进度环颜色：蓝=达标 / 橙=≥70% / 红=<70%（统计结果说明口径）
  static const _kOrange = Color(0xFFF5A623);
  static const _kRed = Color(0xFFE5484D);

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    // 一周起始随「一周开始时间」设置（周日或周一）
    final leading = LogicalDay.leadingBlanksOf(first);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final rowCount = (leading + daysInMonth + 6) ~/ 7;

    // 内边距：让日历内容与屏幕边缘保持更远距离（叠加外层 22 边距）
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: Column(
      children: [
        // 标题行：yyyy-MM 左对齐加粗 + 右侧日历小图标（对标竞品）
        Row(
          children: [
            Text(
              '${month.year}-${month.month.toString().padLeft(2, '0')}',
              style: const TextStyle(
                color: _kTextDark,
                fontSize: 18,
                fontWeight: FontWeight.w400,
              ),
            ),
            const Spacer(),
            // 翻月箭头：左侧看更早月份，右侧回到更近月份（当前月禁用）
            _monthArrow(Icons.chevron_left, onPrevMonth),
            const SizedBox(width: 2),
            _monthArrow(Icons.chevron_right, onNextMonth),
            const SizedBox(width: 8),
            // 用户自绘日历图标（assets/icons/menu/calendar_header.svg）
            SvgPicture.asset(
              'assets/icons/menu/calendar_header.svg',
              width: 22,
              height: 22,
            ),
          ],
        ),
        const SizedBox(height: 14),
        // 表头：随「一周开始时间」轮转（周日或周一起始，灰蓝色）
        Row(
          children: [
            for (final w in LogicalDay.weekHeaderLabels)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: const TextStyle(
                      color: Color(0xFF8A97A8),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var row = 0; row < rowCount; row++)
          SizedBox(
            height: 54,
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(child: _cell(row * 7 + col - leading + 1, daysInMonth)),
              ],
            ),
          ),
      ],
      ),
    );
  }

  /// 翻月箭头（禁用态变浅灰）
  Widget _monthArrow(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onTap();
            }
          : null,
      child: SizedBox(
        width: 26,
        height: 26,
        child: Icon(
          icon,
          size: 20,
          color: enabled ? _kTextDark : const Color(0xFFC7CDD4),
        ),
      ),
    );
  }

  Widget _cell(int day, int daysInMonth) {
    if (day < 1 || day > daysInMonth) return const SizedBox.shrink();

    final cellDate = DateTime(month.year, month.month, day);
    final isFuture = cellDate.isAfter(today);
    final isToday = cellDate.year == today.year &&
        cellDate.month == today.month &&
        cellDate.day == today.day;
    // monthDataProvider 以月内 0 基索引为 key
    final dt = data[day - 1];
    // 有饮水条目即点亮（不看正负）：净量为负的日子（负容量记录）同样算有记录
    final hasRecord = dt != null && dt.count > 0;

    // 有喝水记录的日期（含今天）→ 进度环包围（替代原日期下方圆点）：
    // 环比例 = 当日净量 / 目标，环色按达标度（蓝/橙/红）
    final showRing = !isFuture && hasRecord;
    final ratio = goalMl > 0 && dt != null
        ? (dt.effectiveMl / goalMl).clamp(0.0, 1.0)
        : 0.0;
    final ringColor = ratio >= 1.0
        ? _kCyan
        : ratio >= 0.7
            ? _kOrange
            : _kRed;

    // 所有日期统一普通字重（选中不做任何视觉特殊化）
    final TextStyle numberStyle = TextStyle(
      color: isFuture ? _kFutureGray : _kTextDark,
      fontSize: 14,
      fontWeight: FontWeight.w400,
    );

    final Widget number = Text('$day', style: numberStyle);

    // 右下角对勾小圆标（对标竞品）：仅「喝过水」的日期显示——
    // 当天=绿色底，已过日期=灰色底；未来日期与未喝水的日期不显示
    final Widget cellContent = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (showRing)
          SizedBox(
            width: 30,
            height: 30,
            child: CustomPaint(
              painter: _DayRingPainter(ratio, ringColor),
              child: Center(child: number),
            ),
          )
        else
          number,
        if (!isFuture && hasRecord)
          Positioned(
            right: -3,
            bottom: -2,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isToday
                    ? const Color(0xFF17C3A3)
                    : const Color(0xFFC7CDD4),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 9,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 未来日期不可点击（还没到的日期无法选中/补录）
      onTap: isFuture ? null : () => onSelect(cellDate),
      child: SizedBox(
        height: 54,
        child: Center(child: cellContent),
      ),
    );
  }
}

/// 日历日期小进度环：浅灰轨道 + 达标度色弧（自 12 点方向顺时针），
/// 选中态加粗；弧不满一圈时缺口即当日剩余量
class _DayRingPainter extends CustomPainter {
  const _DayRingPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 2.2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..color = const Color(0xFFECECEE),
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_DayRingPainter old) =>
      old.progress != progress || old.color != color;
}

// ==================== 筛选弹层 ====================

/// 饮品筛选弹层：白底圆角顶部 + 右上 X + 浅灰圆角行（饮品图标与首页/管理页一致）
class _FilterSheet extends StatelessWidget {
  const _FilterSheet({
    required this.current,
    required this.entries,
    required this.pool,
    required this.onSelect,
  });

  final String current;
  final List<DrinkEntry> entries;

  /// 首页/管理页同款饮品池（预设 + 自定义）
  final List<Beverage> pool;
  final ValueChanged<String> onSelect;

  /// (筛选 token, 展示名, 饮品对象[池内命中], 回退图标[仅条目但饮品已删除])
  ///
  /// token 用 `id:<beverageId>` 定位饮品，饮品改名后历史记录仍能连续筛选；
  /// 已删除的饮品只能用 `name:<name>` 匹配它留下的历史记录。
  List<(String, String, Beverage?, IconData?, Color?)> _options() {
    final out = <(String, String, Beverage?, IconData?, Color?)>[];
    void add(String token, String label,
        [Beverage? b, IconData? icon, Color? color]) {
      if (!out.any((o) => o.$1 == token)) out.add((token, label, b, icon, color));
    }

    add('全部', '全部');
    for (final b in pool) {
      add('id:${b.id}', b.name, b);
    }
    // 仅出现在历史记录中、但饮品已被删除的条目：回退分类图标
    for (final e in entries) {
      if (!pool.any((b) => b.id == e.beverageId)) {
        add('name:${e.beverageName}', e.beverageName, null,
            e.beverageCategory.icon, e.beverageCategory.color);
      }
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
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              // 饮品图标（与管理页/首页一致）；「全部」= 分层饮品色水滴
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: Center(
                                  child: isAll
                                      ? const CustomPaint(
                                          size: Size(28, 28),
                                          painter: _WaterDropPainter(),
                                        )
                                      : o.$3 != null
                                          ? _beverageIcon(o.$3!, 28)
                                          : Icon(o.$4,
                                              size: 24, color: o.$5),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  o.$2,
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

/// 功能胶囊按钮（浅青背景）
class _ActionPill extends StatelessWidget {
  const _ActionPill({
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

/// 「各饮品摄入量」面板的单品聚合（周期内按饮品名累加）
class _BeverageTotal {
  _BeverageTotal({required this.name, required this.category});
  final String name;
  final BeverageCategory category;
  int volumeMl = 0; // 总摄入量（实际喝入容量）
  int effectiveMl = 0; // 水份（有效进水量）
  int calories = 0; // 热量（按饮品每份 kcal × 容量折算）
}

/// 简易柱状图：全圆角柱体（青色），值为 0 不画柱（只保留轴标签）。
/// line=true 时同数据渲染为折线图；标题区固定高度，保证天/周/月
/// 切换（单行/双行标题）时卡片总高度一致不上下跳
class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.title,
    required this.bars,
    required this.barWidth,
    required this.line,
  });
  final String title;
  final List<_BarData> bars;
  final double barWidth;
  final bool line;

  @override
  Widget build(BuildContext context) {
    // 取绝对值最大值：全是负数时也能正确归一（maxVal=0 会除零）
    final maxVal = bars.fold<int>(0, (a, b) => math.max(a, b.value.abs()));

    return Column(
      children: [
        // 标题区固定 38 高（容纳两行标题），单行/双行不改变卡片高度
        SizedBox(
          height: 38,
          child: Center(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _kTextDark,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        line
            ? _LineChartBody(bars: bars, maxVal: maxVal)
            : SizedBox(
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
                          // 柱顶值标签（负值红、今天青色加粗、其他天灰色）
                          if (b.valueLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                b.valueLabel!,
                                style: TextStyle(
                                  color: b.value < 0
                                      ? const Color(0xFFE8446A)
                                      : b.highlighted
                                          ? _kCyan
                                          : _kHintGray,
                                  fontSize: 11,
                                  fontWeight: b.highlighted
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          // 柱体：值为 0 不画（只保留轴标签，对标原版）；
                          // 负值（负容量记录/负日均）画红色柱，高度取绝对值
                          Container(
                            width: barWidth,
                            height: b.value != 0 && maxVal > 0
                                ? (b.value.abs() / maxVal * 88).clamp(6.0, 88.0)
                                : 0.0,
                            decoration: BoxDecoration(
                              color:
                                  b.value < 0 ? const Color(0xFFE8446A) : _kCyan,
                              borderRadius: BorderRadius.circular(
                                  math.min(8.0, barWidth / 2)),
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

/// 折线图（与柱状图同 144 高度预算）：整个绘图交给 _LinePainter，
/// 含 XY 轴、横向网格线与底部轴标签
class _LineChartBody extends StatelessWidget {
  const _LineChartBody({required this.bars, required this.maxVal});
  final List<_BarData> bars;
  final int maxVal;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 144,
      child: CustomPaint(
        size: Size.infinite,
        painter: _LinePainter(bars, maxVal),
      ),
    );
  }
}

/// 折线绘制（含坐标轴）：
/// - Y 轴：每格 600ml 横向网格线 + 左侧刻度文字（600ml/1200ml/…），
///   上限 = 数据最大值向上取整到 600 的整数倍（至少 600）
/// - X 轴：底部轴线 + 各数据点正下方的天/周/月标签
/// - 青色圆角折线 + 数据点圆点（今天高亮加大），非空 valueLabel 标在点上方
///   （负值红）；负值按 0 处理
class _LinePainter extends CustomPainter {
  const _LinePainter(this.bars, this.maxVal);
  final List<_BarData> bars;
  final int maxVal;

  static const double _padLeft = 42; // 左侧 Y 轴刻度文字区
  static const double _padRight = 12;
  static const double _plotTop = 18; // 顶部留给数据点值标签
  static const double _xLabelH = 15; // 底部 X 轴标签区

  @override
  void paint(Canvas canvas, Size size) {
    final n = bars.length;
    if (n == 0) return;

    // Y 轴刻度：每格 600ml，上限向上取整到 600 的整数倍
    const yStep = 600.0;
    final steps = maxVal <= 0 ? 1 : (maxVal / yStep).ceil();
    final topV = steps * yStep;

    final plotBottom = size.height - _xLabelH - 2;
    final plotH = plotBottom - _plotTop;
    final plotW = size.width - _padLeft - _padRight;

    double xOf(int i) =>
        n == 1 ? _padLeft + plotW / 2 : _padLeft + i * plotW / (n - 1);
    double yOf(double v) => plotBottom - (v / topV) * plotH;

    TextPainter tp(String text,
        {Color color = const Color(0xFF9AA1A9),
        double fontSize = 9,
        FontWeight weight = FontWeight.w400}) {
      final p = TextPainter(
        text: TextSpan(
          text: text,
          style:
              TextStyle(color: color, fontSize: fontSize, fontWeight: weight),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      return p;
    }

    final gridPaint = Paint()
      ..color = const Color(0xFFEEF0F3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = const Color(0xFFC9CED4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // 横向网格线 + Y 轴刻度（0 格为 X 轴线，颜色更深）
    for (var s = 0; s <= steps; s++) {
      final v = s * yStep;
      final y = yOf(v);
      canvas.drawLine(Offset(_padLeft, y), Offset(size.width - _padRight, y),
          s == 0 ? axisPaint : gridPaint);
      final label =
          v == 0 ? '0' : UnitFormat.volume(v, compact: true);
      final p = tp(label);
      p.paint(canvas, Offset(_padLeft - 5 - p.width, y - p.height / 2));
    }
    // Y 轴竖线
    canvas.drawLine(
        Offset(_padLeft, _plotTop - 6), Offset(_padLeft, plotBottom), axisPaint);

    // 折线（负值按 0 处理，与柱状图红色负柱语义区分）
    Offset pointAt(int i) =>
        Offset(xOf(i), yOf(bars[i].value.clamp(0, topV).toDouble()));

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < n; i++) {
      path.lineTo(pointAt(i).dx, pointAt(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _kCyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 数据点 + 值标签 + X 轴标签
    for (var i = 0; i < n; i++) {
      final b = bars[i];
      final p = pointAt(i);
      canvas.drawCircle(
        p,
        b.highlighted ? 4.5 : 3.0,
        Paint()
          ..color = _kCyan
          ..style = PaintingStyle.fill,
      );
      if (b.highlighted) {
        canvas.drawCircle(
          p,
          4.5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
      final label = b.valueLabel;
      if (label != null) {
        final vtp = tp(
          label,
          color: b.value < 0
              ? const Color(0xFFE8446A)
              : b.highlighted
                  ? _kCyan
                  : _kHintGray,
          fontSize: 10,
          weight: FontWeight.w600,
        );
        // 值标签中心对齐数据点，左右与顶部均不出画布
        final dx = (p.dx - vtp.width / 2).clamp(0.0, size.width - vtp.width);
        final dy = (p.dy - 8 - vtp.height).clamp(0.0, size.height);
        vtp.paint(canvas, Offset(dx, dy));
      }
      // X 轴标签：数据点正下方，左右不出画布
      final xtp = tp(b.label,
          color: b.highlighted ? _kCyan : _kHintGray, fontSize: 10);
      final xdx = (p.dx - xtp.width / 2).clamp(0.0, size.width - xtp.width);
      xtp.paint(canvas, Offset(xdx, size.height - xtp.height));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.maxVal != maxVal ||
      old.bars.length != bars.length ||
      old.bars != bars;
}

/// 补上遗漏：滑动输入的刻度尺（游标固定居中，刻度随数值平移）
///
/// 每 25ml 一格刻度，每 100ml 一根长刻度并标注数值；
/// 数值增大时刻度整体左移，游标始终停在正中央。
class _VolumeRulerPainter extends CustomPainter {
  _VolumeRulerPainter({required this.value, required this.color})
      : super(repaint: value);

  /// 连续容量值：拖动时由 ValueNotifier 直接驱动重绘，不走 setState，
  /// 保证刻度以亚像素级平滑移动
  final ValueListenable<double> value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final current = value.value;
    final cx = size.width / 2;
    // 刻度统一以同一条中线上下对称：长/中/短三档只改长度，不改粗细
    const tickCenterY = 48.0;
    const majorHalf = 17.0;
    const midHalf = 15.0;
    const shortHalf = 9.0;
    final tickBottom = tickCenterY + majorHalf;
    // 画布左右各能容纳多少 ml
    final spanMl = cx / _kSlidePxPer100 * 100;
    final minVisible = current - spanMl;
    final maxVisible = current + spanMl;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    // 25ml 一格：0(=100) 最长、50 略短、25/75 约一半
    for (var v = (minVisible / 25).floorToDouble() * 25;
        v <= maxVisible;
        v += 25) {
      if (v < 0 || v > 2000) continue;
      final x = cx + (v - current) * _kSlidePxPer100 / 100;
      if (x < -4 || x > size.width + 4) continue;
      final rem = v % 100;
      final half = rem == 0
          ? majorHalf
          : rem == 50
              ? midHalf
              : shortHalf;
      canvas.drawLine(
        Offset(x, tickCenterY - half),
        Offset(x, tickCenterY + half),
        paint,
      );
    }

    // 每 100ml 标注数值（贴近边缘时按参考图自然裁切）
    for (var v = (minVisible / 100).floorToDouble() * 100;
        v <= maxVisible + 100;
        v += 100) {
      if (v < 0 || v > 2000) continue;
      final x = cx + (v - current) * _kSlidePxPer100 / 100;
      // 只画完整落在画布内的数值，避免边缘出现半截数字
      final tp = TextPainter(
        text: TextSpan(text: '${v.toInt()}', style: _kRulerLabelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final left = x - tp.width / 2;
      if (left < 0 || left + tp.width > size.width) continue;
      tp.paint(canvas, Offset(left, tickBottom + 22));
    }

    // 固定居中的游标：向下实心倒三角（与刻度线之间留出间距）
    final cursor = Path()
      ..moveTo(cx - 6, 0)
      ..lineTo(cx + 6, 0)
      ..lineTo(cx, 9)
      ..close();
    canvas.drawPath(cursor, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_VolumeRulerPainter old) => old.color != color;
}

/// 滑动容量选择：游标固定居中、刻度尺随手指平移，松手后按速度惯性滑行
class _BackfillSlideArea extends StatefulWidget {
  const _BackfillSlideArea({required this.volume, required this.onChanged});

  final int volume;
  final ValueChanged<int> onChanged;

  @override
  State<_BackfillSlideArea> createState() => _BackfillSlideAreaState();
}

class _BackfillSlideAreaState extends State<_BackfillSlideArea>
    with SingleTickerProviderStateMixin {
  static const int _minV = 10;
  static const int _maxV = 2000;

  late final AnimationController _fling =
      AnimationController.unbounded(vsync: this);
  // 拖动过程中的连续值（避免依赖父级重建后的整数值）
  double _dragValue = 0;
  // 刻度尺的连续数值源：直接驱动 CustomPainter 重绘，不触发整棵子树重建
  late final ValueNotifier<double> _value =
      ValueNotifier<double>(_clamp(widget.volume));
  // 最近一次同步给父级的数值（父级按 10ml 量化，只有跨档时才通知）
  late int _lastSent = widget.volume;

  static double _clamp(num v) => v.clamp(_minV, _maxV).toDouble();

  @override
  void initState() {
    super.initState();
    _fling.addListener(_onFlingTick);
  }

  @override
  void didUpdateWidget(_BackfillSlideArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父级数值被外部改动（切换饮品、点外部按钮）时同步刻度
    if (widget.volume != oldWidget.volume && widget.volume != _lastSent) {
      _lastSent = widget.volume;
      if (!_fling.isAnimating) {
        _dragValue = _clamp(widget.volume);
        _value.value = _dragValue;
      }
    }
  }

  @override
  void dispose() {
    _value.dispose();
    _fling.dispose();
    super.dispose();
  }

  /// 连续值负责刻度平滑移动；父级只在跨过 10ml 时收到一次通知，
  /// 避免每个拖动事件都重建整个弹窗
  void _emit(double v) {
    final clamped = _clamp(v);
    _value.value = clamped;
    final quantized = (clamped / 10).round() * 10;
    if (quantized == _lastSent) return;
    _lastSent = quantized;
    widget.onChanged(quantized);
  }

  void _onFlingTick() {
    if (!mounted) return;
    _emit(_fling.value);
  }

  void _onDragStart(DragStartDetails _) {
    _fling.stop();
    _dragValue = _clamp(widget.volume);
    _value.value = _dragValue;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // 手指左滑 → 数值增大（刻度尺向左移动），每 1px ≈ 1.6ml
    _dragValue = _clamp(_dragValue - d.delta.dx * 100 / _kSlidePxPer100);
    _emit(_dragValue);
  }

  void _onDragEnd(DragEndDetails d) {
    final vPx = d.velocity.pixelsPerSecond.dx;
    if (vPx.abs() < 80) return;
    // 像素速度换算成 ml/s（左滑为负 → 容量增大）
    final vMl = -vPx * 100 / _kSlidePxPer100;
    // 惯性滑行距离 = 速度 / 衰减系数，再按速度决定时长
    final target = (_dragValue + vMl / 3.5).clamp(_minV.toDouble(), _maxV.toDouble());
    final dist = (target - _dragValue).abs();
    if (dist < 10) return;
    final ms = (dist / vMl.abs() * 2200).clamp(220.0, 900.0);
    _fling.stop();
    _fling.value = _dragValue;
    _fling.animateTo(
      target,
      duration: Duration(milliseconds: ms.round()),
      curve: Curves.easeOutCubic,
    );
  }

  /// 加减按钮：本地立即更新刻度，再同步父级
  void _step(int delta) {
    _fling.stop();
    _dragValue = _clamp(widget.volume + delta);
    _emit(_dragValue);
  }

  Widget _stepButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFF6C7885), width: 1.2),
        ),
        child: Icon(icon, size: 11, color: const Color(0xFF4E5A66)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clamped = widget.volume.clamp(_minV, _maxV);

    return Center(
      child: Padding(
        // 让整组（数值 + 刻度尺）在卡片内视觉居中
        padding: const EdgeInsets.only(bottom: 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // − 值 + ：按钮固定在数值两侧（不随数字位数左右跳动）
          LayoutBuilder(
            builder: (_, cons) => SizedBox(
              width: cons.maxWidth,
              height: 28,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$clamped',
                        style: const TextStyle(
                          color: _kTextDark,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        ' ml',
                        style: TextStyle(
                          color: _kHintGray,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Transform.translate(
                    offset: const Offset(-62, 0),
                    child: _stepButton(
                      icon: Icons.remove,
                      onTap: () => _step(-10),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(62, 0),
                    child: _stepButton(
                      icon: Icons.add,
                      onTap: () => _step(10),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (_, cons) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: ClipRect(
                child: CustomPaint(
                  size: Size(cons.maxWidth, 104),
                  painter: _VolumeRulerPainter(value: _value, color: _kCyan),
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
