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
import '../../shared/services/share_image.dart';
import '../../shared/widgets/app_back_button.dart';
import '../../shared/widgets/drink_illustration.dart';
import '../characters/current_character_provider.dart';
import '../drink/providers/beverage_catalog_provider.dart';

import '../drink/widgets/svg_container.dart';
import '../home/providers/home_providers.dart';
import '../onboarding/widgets/animal_silhouette.dart';
import '../settings/settings_flags.dart';
import '../settings/widget_settings_screen.dart';
import 'providers/stats_providers.dart';

part 'history_models.dart';
part 'history_widgets.dart';
part 'history_charts.dart';

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
  if (hasContainerIcon(b.containerId)) {
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
  return DrinkIllustration(
    beverageId: Beverage.presets.any((p) => p.id == b.id)
        ? b.id
        : Beverage.fallbackIllustration(b.category),
    color: b.color,
    size: size,
  );
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

  // 底部 tab 栏固定尺寸：三个标签都是两字，等宽排布保持视觉平衡
  // （84 = 图标 18 + 间距 6 + 两字 30 + 内边距 28）
  static const double _kTabItemW = 84;

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

  /// 分享长图用：三个视图各自的滚动控制器与截图边界
  final ScrollController _calendarCtrl = ScrollController();
  final ScrollController _trendCtrl = ScrollController();
  final ScrollController _listCtrl = ScrollController();
  final GlobalKey _calendarCaptureKey = GlobalKey();
  final GlobalKey _trendCaptureKey = GlobalKey();
  final GlobalKey _listCaptureKey = GlobalKey();

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
    _calendarCtrl.dispose();
    _trendCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(preferredUnitProvider);
    final progress = ref.watch(dailyProgressProvider);
    final checkin = ref.watch(checkinDaysProvider);
    final currentChar = ref.watch(effectiveCurrentCharacterProvider);
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
                  RepaintBoundary(
                    key: _calendarCaptureKey,
                    child: SingleChildScrollView(
                      controller: _calendarCtrl,
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
                  ),
                  // 1. 趋势视图：天/周/月柱形图统计卡（含饮品筛选）
                  RepaintBoundary(
                    key: _trendCaptureKey,
                    child: SingleChildScrollView(
                      controller: _trendCtrl,
                      padding:
                          EdgeInsets.only(top: topInset + 60, bottom: 120),
                      child: _buildStatsCard(),
                    ),
                  ),
                  // 2. 列表视图
                  RepaintBoundary(
                    key: _listCaptureKey,
                    child: _buildListView(),
                  ),
                ],
              ),
            ),
            // 顶层：左上角返回按钮悬浮固定，不随滚动（与提醒页/设置页同款）
            Positioned(
              top: topInset + 8,
              left: 16,
              child: const AppBackButton(),
            ),
            // 顶层：右上角分享按钮悬浮固定（与左上返回按钮同为无底色 36×36）
            Positioned(
              top: topInset + 8,
              right: 16,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _shareStats,
                child: SizedBox(
                  width: 36,
                  height: 36,
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

  // ---------------- 分享长图（当前视图整页） ----------------

  /// 当前视图对应的滚动控制器 / 截图边界
  ScrollController get _shareController => switch (_viewTab) {
        0 => _calendarCtrl,
        1 => _trendCtrl,
        _ => _listCtrl,
      };

  GlobalKey get _shareCaptureKey => switch (_viewTab) {
        0 => _calendarCaptureKey,
        1 => _trendCaptureKey,
        _ => _listCaptureKey,
      };

  /// 把当前视图从头滚到尾逐屏截图并拼成一张长图，再调起分享面板
  Future<void> _shareStats() async {
    final ctrl = _shareController;
    final key = _shareCaptureKey;
    if (!ctrl.hasClients || key.currentContext == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('页面还在加载，请稍后再试')),
      );
      return;
    }
    try {
      await ShareImage.shareScrollable(
        context: context,
        controller: ctrl,
        viewportKey: key,
        fileName: 'dun_dun_history_'
            '${DateTime.now().millisecondsSinceEpoch}.png',
        text: '吨吨 · 我的饮水记录',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分享失败，请稍后重试')),
      );
    }
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
        child: Row(
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
          // 滑动到相邻页（与左右滑动共用同一动画）
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
            controller: _listCtrl,
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
          controller: _listCtrl,
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
  List<Beverage> _drinkPool() => ref.read(beverageLibraryProvider);

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
