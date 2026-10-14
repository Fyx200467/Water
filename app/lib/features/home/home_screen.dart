import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/beverage.dart';
import '../../shared/widgets/drink_illustration.dart';
import '../characters/character_art.dart';
import '../characters/character_catalog.dart';
import '../characters/character_data.dart';
import '../characters/character_screen.dart';
import '../characters/current_character_provider.dart';
import '../drink/providers/custom_beverage_provider.dart';
import '../drink/widgets/svg_container.dart';
import '../drink/screens/add_drink_screen.dart';
import '../drink/screens/drink_manage_screen.dart';
import '../onboarding/widgets/animal_silhouette.dart';
import '../settings/settings_flags.dart';
import '../stats/history_screen.dart';
import '../stats/providers/stats_providers.dart';
import 'confetti_rain.dart';
import 'providers/home_providers.dart';

/// PRD §2.2 首页（对标原版 WaterLlama 主页）
///
/// 布局（自上而下）：
/// 1. 顶部：左上"1 天"青色圆形徽章 + 右上菜单按钮
/// 2. 核心数据：青色大字"{totalMl}" + 灰色"进水量·{percent}% 的目标"
/// 3. 中央：大羊驼剪影（空杯态浅灰 + 按进度纯青色填充 + 波浪水面晃动）
/// 4. 底部操作栏：水杯按钮(+) / "+98 种物品和功能"胶囊 / 羊驼头像(+)
/// 5. 最底部：浅青色圆角横幅"滴酒不沾的十月"挑战
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // 品牌色规范
  static const _brandCyan = Color(0xFF4DB8D8);
  static const _hintGray = Color(0xFF8E8E93);

  /// 角色是否处于"点亮态"：完成当日目标时自动触发，持续 2 秒后自动恢复
  /// 用户点击角色（已完成目标的前提下）可再次触发点亮 2 秒
  bool _isLit = false;
  Timer? _litTimer;

  @override
  void dispose() {
    _litTimer?.cancel();
    super.dispose();
  }

  /// 触发角色点亮：取消上一次计时器，进入点亮态，2 秒后自动恢复
  void _triggerLit() {
    _litTimer?.cancel();
    setState(() => _isLit = true);
    _litTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isLit = false);
    });
  }

  /// 根据当前时间返回"星期一"~"星期日"（用于完成态文案"完美星期X！"）
  String _weekdayName() {
    const names = [
      '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日',
    ];
    return names[DateTime.now().weekday - 1];
  }

  /// 底部水平滚动饮品快捷栏：水 / +98物品胶囊 / 当前角色 / 已开启饮品（可排序）/ 添加或编辑
  Widget _buildDrinkBar(String currentChar, String? currentFilePath) {
    final isMember = ref.watch(memberProvider).isValid;
    final customs = ref.watch(customBeveragesProvider);
    final homeDrinks = ref.watch(homeDrinksProvider);
    // 全量池（非水预设 + 自定义）→ 按持久化顺序取已开启饮品
    // （管理页从上到下 = 首页从左到右；水单独渲染在第一位）
    final pool = [
      ...Beverage.presets.where((b) => b.id != 'water_pure'),
      ...customs,
    ];
    final byId = {for (final b in pool) b.id: b};
    final drinks = [
      for (final id in orderedVisibleIds(homeDrinks, pool))
        if (id != 'water_pure' && byId[id] != null) byId[id]!,
    ];

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // 1. 水（青色玻璃杯大插画 + 底部 ⊕ 徽章）
        _DrinkItem(
          beverageId: 'water_pure',
          label: '水',
          color: _brandCyan,
          highlight: true,
          badgeIcon: Icons.add,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const AddDrinkScreen(beverageId: 'water_pure')),
          ),
        ),
        // 2. "+98 种物品和功能"胶囊
        const _ItemsChip(),
        // 3. 当前选中角色头像（点击打开角色页）
        _DrinkItem(
          icon: CharacterArt(
            animalId: currentChar,
            unlocked: true,
            size: 52,
            filePath: currentFilePath,
          ),
          label: characters[currentChar]?.displayName ?? '角色',
          color: const Color(0xFF8B6F47),
          bg: const Color(0xFFF5E6D3),
          badgeIcon: Icons.refresh,
          onTap: () => Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => CharacterScreen(),
              // 从底部滑入的转场动画（不可拖拽关闭，只能点 X 按钮返回）
              transitionsBuilder: (_, animation, __, child) {
                final offset = Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ));
                return SlideTransition(position: offset, child: child);
              },
              transitionDuration: const Duration(milliseconds: 350),
            ),
          ),
        ),
        // 4. 各类饮品（非会员锁定除水外全部饮品；点击仍可进入容器页，记录时引导会员）
        for (final b in drinks)
          _DrinkItem(
            beverageId: b.id.startsWith('custom_') ? null : b.id,
            icon: isSvgContainer(b.containerId)
                ? SvgContainerIcon(
                    containerId: b.containerId!,
                    color: b.color,
                  )
                : b.id.startsWith('custom_')
                    ? Icon(b.icon, size: 30, color: b.color)
                    : null,
            label: b.name,
            color: b.color,
            locked: !isMember && b.id != 'water_pure',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AddDrinkScreen(beverageId: b.id)),
            ),
          ),
        // 5. 添加或编辑（浅青圆底 + 青色加号，对标原版）
        _DrinkItem(
          icon: Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFFE0F4F8),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add, size: 26, color: Color(0xFF31A8C9)),
          ),
          label: '添加或编辑',
          color: _brandCyan,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DrinkManageScreen()),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(dailyProgressProvider);
    final checkin = ref.watch(checkinDaysProvider);
    final currentChar = ref.watch(currentCharacterProvider);
    // 角色目录（上传素材路径；内置素材为 null，watch 以保证切换角色后按钮刷新）
    final catalogAsync = ref.watch(characterCatalogProvider);

    // 监听 dailyProgress：从未完成→完成时自动触发点亮 + 礼炮
    ref.listen(dailyProgressProvider, (prev, next) {
      if (prev?.isComplete == false && next.isComplete) {
        _triggerLit();
      }
    });

    // 仅当已完成目标且处于点亮态时显示彩色插画
    final isLit = _isLit && progress.isComplete;
    final percent = (progress.progress * 100).round();
    final done = progress.isComplete;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        // Stack 结构：顶部按钮悬浮于内容之上，内容可滚动（后续功能卡片）
        child: Stack(
          children: [
            // 底层：可滚动内容（IntrinsicHeight 让羊驼区弹性撑开、挑战横幅贴底；
            // 内容超过一屏后可下滑——为后续功能卡片预留）
            Positioned.fill(
              child: LayoutBuilder(
                builder: (ctx, cons) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: cons.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          // 给悬浮按钮留出空间
                          const SizedBox(height: 64),
                          // 1. 核心数据：完成时显示"完美星期X！"+ml·%目标；未完成时显示原数字
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              children: [
                                if (done) ...[
                                  // 完成态：庆祝文案（星期X 取自系统时间）
                                  Text(
                                    '完美${_weekdayName()}！',
                                    style: const TextStyle(
                                      color: _brandCyan,
                                      fontSize: 40,
                                      fontWeight: FontWeight.w800,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${progress.totalEffectiveMl}ml 进水量 · $percent% 的目标',
                                    style: const TextStyle(
                                        color: _hintGray, fontSize: 14),
                                  ),
                                ] else ...[
                                  // 未完成态：原版数据文案
                                  Text(
                                    '${progress.totalEffectiveMl}ml',
                                    style: const TextStyle(
                                      color: _brandCyan,
                                      fontSize: 56,
                                      fontWeight: FontWeight.w800,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '进水量 · $percent% 的目标',
                                    style: const TextStyle(
                                        color: _hintGray, fontSize: 14),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 2. 中央：大羊驼剪影（弹性区域撑开）
                          // 已完成目标时可点击重新点亮 2 秒
                          Expanded(
                            child: Center(
                              child: GestureDetector(
                                onTap: done ? _triggerLit : null,
                                child: AnimalSilhouette(
                                  animalId: currentChar,
                                  fillRatio: progress.progress.clamp(0.0, 1.0),
                                  accentColor: _brandCyan,
                                  solidFillColor: _brandCyan,
                                  size: 280,
                                  // 点亮态显示全彩插画，否则剪影+液体填充
                                  fullArt: isLit,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 2.5 完成态轮播：第1页「庆祝我的一天！」按钮 + 第2页鼓励横幅
                          //（可横滑，圆点指示；celebrateDay 开关控制第1页显隐）
                          if (done)
                            _CelebrationCarousel(
                              animalId: currentChar,
                              onCelebrate: _triggerLit,
                            ),
                          const SizedBox(height: 8),
                          // 3. 底部操作栏：水平滚动的饮品快捷栏（对标原版）
                          SizedBox(
                            height: 96,
                            child: _buildDrinkBar(
                              currentChar,
                              catalogAsync.value?.uploadedFilePaths[currentChar],
                            ),
                          ),
                          // 4. 挑战横幅（贴底）
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                            child: _ChallengeBanner(
                              title: '滴酒不沾的十月',
                              onTap: () => context.push('/stats'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 顶层：悬浮按钮（不随内容滚动）
            Positioned(
              top: 8,
              left: 20,
              right: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 左上角：天数徽章（外圈进度环 + 启动展开动画）→ 打开历史记录页
                  // 签到天数 = 当天打开过 App 即记录一天
                  // 完成态时在「天数」和「✓」之间循环切换（持续，不是只点亮时）
                  checkin.maybeWhen(
                    data: (days) => _DayBadge(
                      days: days,
                      progress: progress.progress,
                      showCycle: done,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const HistoryScreen()),
                      ),
                    ),
                    orElse: () => _DayBadge(
                      days: 0,
                      progress: progress.progress,
                      onTap: null,
                    ),
                  ),
                  // 右上角：菜单按钮（三根波浪线，尺寸与左上角徽章按钮一致）
                  IconButton(
                    onPressed: () => context.push('/settings'),
                    constraints: const BoxConstraints.tightFor(
                      width: 42,
                      height: 42,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const CustomPaint(
                      size: Size(32, 24),
                      painter: _MenuWavesPainter(),
                    ),
                  ),
                ],
              ),
            ),
            // 礼炮彩带层：完成态时持续从屏幕上方飘落（不阻挡点击）
            Positioned.fill(
              child: IgnorePointer(
                child: ConfettiRain(active: done),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 徽章按钮本体高度（圆形直径 / 胶囊高度），按钮与进度环共用
const double _kBadgeH = 34;

/// 左上角青色天数徽章（点击打开历史记录页）
/// - 外圈进度环：实时显示当日饮水量进度，0ml 时顶部只显示一个小圆点（对标原版）
/// - 启动动画：先横向展开为胶囊显示完整「N 天」，1.5 秒后收回圆形只显示「N」
/// - showCycle=true（完成当日目标）时在「天数」和「✓」之间循环切换（每 2 秒）
class _DayBadge extends StatefulWidget {
  const _DayBadge({
    required this.days,
    required this.progress,
    this.showCycle = false,
    this.onTap,
  });
  final int days;

  /// 当日饮水进度（0.0~1.0），驱动外圈进度环
  final double progress;
  final bool showCycle;
  final VoidCallback? onTap;

  @override
  State<_DayBadge> createState() => _DayBadgeState();
}

class _DayBadgeState extends State<_DayBadge> {
  bool _showCheck = false;
  bool _expanded = false; // 进入首页先显示圆形，1 秒后再展开
  Timer? _toggleTimer;
  Timer? _expandTimer;
  Timer? _collapseTimer;

  @override
  void initState() {
    super.initState();
    // 启动动画时序：进入首页 1 秒后展开为胶囊「N 天」，保持 1.5 秒后收回圆形
    _expandTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _expanded = true);
      _collapseTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _expanded = false);
      });
    });
    if (widget.showCycle) _startToggle();
  }

  @override
  void didUpdateWidget(covariant _DayBadge old) {
    super.didUpdateWidget(old);
    if (widget.showCycle && !old.showCycle) {
      _startToggle();
    } else if (!widget.showCycle && old.showCycle) {
      _stopToggle();
      if (_showCheck) setState(() => _showCheck = false);
    }
  }

  void _startToggle() {
    _toggleTimer?.cancel();
    _toggleTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        if (!mounted) return;
        setState(() => _showCheck = !_showCheck);
      },
    );
  }

  void _stopToggle() {
    _toggleTimer?.cancel();
    _toggleTimer = null;
  }

  @override
  void dispose() {
    _stopToggle();
    _expandTimer?.cancel();
    _collapseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showCheck = widget.showCycle && _showCheck;
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 88.0 + _extraWidth,
        height: 42,
        // 宽度动画驱动：每帧重建按钮 + 进度环，环随形状逐帧变形（圆↔胶囊）
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: _shapeWidth),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          builder: (ctx, w, _) => Stack(
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.none,
            children: [
              // 外圈进度环：沿当前形状（圆/胶囊）的外轮廓描边
              // 扫过长度 = 当日饮水量进度，0ml 时顶部一个小圆点
              Positioned.fill(
                child: CustomPaint(
                  painter: _BadgeRingPainter(
                    progress: widget.progress.clamp(0.0, 1.0),
                    shapeWidth: w,
                  ),
                ),
              ),
              // 按钮本体：34（圆形）↔ 76（展开胶囊）
              Container(
                width: w,
                height: _kBadgeH,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF4DB8D8),
                  borderRadius: BorderRadius.circular(_kBadgeH / 2),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: showCheck
                      ? const Text(
                          '✓',
                          key: ValueKey('check'),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : _showExpandedContent(w)
                          ? Padding(
                              key: const ValueKey('full'),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 18),
                              // 数字居左、「天」居右，对标原版展开态的宽松间距；
                              // 内容宽度固定为目标胶囊宽（不绑定当前帧宽 w）：
                              // 收回时出场子组件会被 AnimatedSwitcher 冻结，
                              // 若绑定 w 会被收缩中的容器钳制产生文字骤缩跳变；
                              // 固定宽度 + FittedBox 保证任意帧宽下连续缩放、绝不溢出
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: SizedBox(
                                  width: _shapeWidth - 36.0,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${widget.days}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const Text(
                                        '天',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : Text(
                              '${widget.days}',
                              key: const ValueKey('num'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 天数每多一位数字，展开胶囊加宽 9（三位数「100 天」也不会挤压变形）
  int get _extraWidth => math.max(0, '${widget.days}'.length - 1) * 9;

  /// 按钮当前目标宽度（34=圆形，76+N*9=展开胶囊）
  double get _shapeWidth => _expanded ? 76.0 + _extraWidth : _kBadgeH;

  /// 展开内容仅在动画接近完成时切换：早期帧就显示会让文字缩得过小、观感差
  /// （溢出已由「固定内容宽度 + FittedBox」从根本上排除，此处阈值纯为观感）
  bool _showExpandedContent(double w) =>
      _expanded && w >= _shapeWidth - 20;
}

/// 徽章外圈进度环：沿按钮当前形状（圆形/胶囊）外轮廓描边
/// - 外轮廓 = 按钮矩形外扩 0.2px 间隙 + 半描边的 stadium 轮廓（跟随展开动画逐帧变形）
/// - 起点固定在顶部 12 点方向，顺时针扫过（进度 × 周长）
/// - 解析几何逐段绘制（直线 + 四分之一圆弧），不依赖 PathMetrics：
///   其闭合轮廓起点在 Impeller 下会偏移，产生起点越过 12 点、端点凸起等伪影
/// - 0ml 时也画一小段（配合终点圆头呈现为顶部小圆点，对标原版）
class _BadgeRingPainter extends CustomPainter {
  _BadgeRingPainter({required this.progress, required this.shapeWidth});
  final double progress;

  /// 按钮当前宽度（含动画中间帧）
  final double shapeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    const double stroke = 3.5;
    const double gap = 0.8; // 环内沿与按钮边缘的间距（贴近浑然一体）

    final m = gap + stroke / 2; // 按钮边缘到环中心线的距离
    final center = Offset(shapeWidth / 2, size.height / 2);
    final halfW = shapeWidth / 2 + m;
    final r = _kBadgeH / 2 + m; // 圆角半径（stadium 形：= 半高 + 外扩）
    final straight = halfW - r; // 顶/底边单侧直线长（圆形态为 0）

    // 进度环用比按钮更深一档的蓝色，拉开层次（按钮 0xFF4DB8D8 浅水色）
    final ringColor = const Color(0xFF2E93B8);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..color = ringColor;
    final capPaint = Paint()..color = ringColor;

    // 周长 = 4 段直线 + 4 段四分之一圆弧
    final q = math.pi / 2 * r;
    final total = 4 * straight + 4 * q;
    // 0 进度也画总长的 2%（配合终点圆头呈现为顶部正中小圆点，对标原版 0ml 态）
    var remain = math.max(progress.clamp(0.0, 1.0) * total, total * 0.02);

    // 当前绘制端点：从 12 点整出发，随各段推进
    var cap = Offset(center.dx, center.dy - r);

    // 直线段：dirX=±1（水平），长度 len
    void lineSeg(double dirX, double len) {
      if (remain <= 0) return;
      final d = math.min(remain, len);
      if (d <= 0) return;
      final to = cap + Offset(dirX * d, 0);
      canvas.drawLine(cap, to, paint);
      cap = to;
      remain -= d;
    }

    // 圆弧段：半圆圆心 x = circleCx（y 与按钮中心同高），起始角 startAngle，弧长 len
    void arcSeg(double circleCx, double startAngle, double len) {
      if (remain <= 0) return;
      final d = math.min(remain, len);
      if (d <= 0) return;
      final c = Offset(circleCx, center.dy);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        startAngle,
        d / r,
        false,
        paint,
      );
      final a = startAngle + d / r;
      cap = c + Offset(r * math.cos(a), r * math.sin(a));
      remain -= d;
    }

    // 顺时针从 12 点整逐段推进（各段切线连续，端点精确衔接）
    final rightCx = center.dx + straight; // 右半圆圆心
    final leftCx = center.dx - straight; // 左半圆圆心
    lineSeg(1, straight); // 上半右直线 →
    arcSeg(rightCx, -math.pi / 2, q); // 右上四分之一弧 ↘
    arcSeg(rightCx, 0, q); // 右下四分之一弧 ↙
    lineSeg(-1, 2 * straight); // 下边直线（右→左）
    arcSeg(leftCx, math.pi / 2, q); // 左下四分之一弧 ↖
    arcSeg(leftCx, math.pi, q); // 左上四分之一弧 ↗
    lineSeg(1, straight); // 上半左直线（回到 12 点整）

    // 终点补圆头：0 进度时呈现为顶部小圆点，满进度时在 12 点整圆润收口
    canvas.drawCircle(cap, stroke / 2, capPaint);
  }

  @override
  bool shouldRepaint(covariant _BadgeRingPainter old) =>
      old.progress != progress || old.shapeWidth != shapeWidth;
}

/// 单根波浪线参数
class _Wave {
  const _Wave({
    required this.y,
    required this.amp,
    required this.cycles,
    required this.phase,
  });
  final double y; // 垂直基线位置（占高度比例）
  final double amp; // 振幅（px）
  final double cycles; // 波峰周期数
  final double phase; // 相位偏移（rad）
}

/// 右上角菜单按钮图标：三根波浪线（替代三横线，水波意象呼应喝水主题）
///
/// 对标原版：三根等长同形、左右对齐的密集波浪线，深灰粗线无背景
class _MenuWavesPainter extends CustomPainter {
  const _MenuWavesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF636E78);

    // 三根线同形同相、等长对齐，密集波峰如「≈」，叠出整齐的水波层次
    const waves = [
      _Wave(y: 0.16, amp: 1.9, cycles: 1.75, phase: 0.0),
      _Wave(y: 0.50, amp: 1.9, cycles: 1.75, phase: 0.0),
      _Wave(y: 0.84, amp: 1.9, cycles: 1.75, phase: 0.0),
    ];
    for (final w in waves) {
      final baseY = size.height * w.y;
      final path = Path()..moveTo(0, baseY);
      const steps = 48;
      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        path.lineTo(
          size.width * t,
          baseY + w.amp * math.sin(2 * math.pi * w.cycles * t + w.phase),
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MenuWavesPainter oldDelegate) => false;
}

/// 饮品快捷项：圆底图标 + 标签（锁定项右下角小锁徽章）
class _DrinkItem extends StatelessWidget {
  const _DrinkItem({
    required this.label,
    required this.color,
    required this.onTap,
    this.beverageId,
    this.icon,
    this.bg,
    this.locked = false,
    this.highlight = false,
    this.badgeIcon,
  });

  /// 饮品插画 id（icon 为空时使用）
  final String? beverageId;

  /// 自定义插画 widget（角色项用 CharacterArt）；为空时按 beverageId 渲染饮品插画
  final Widget? icon;
  final String label;
  final Color color;
  final Color? bg;
  final VoidCallback onTap;
  final bool locked;
  final bool highlight;

  /// 底部中央徽章图标（如水的 ⊕、羊驼的 ↻）；锁定项自动显示锁
  final IconData? badgeIcon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 对标原版：无圆底，饮品插画独立大图直接立在白色背景上
            SizedBox(
              width: 52,
              height: 56,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  icon ??
                      DrinkIllustration(
                        beverageId: beverageId ?? '',
                        color: color,
                        size: 52,
                        highlight: highlight,
                      ),
                  // 底部中央徽章：锁定项灰底白锁，水的 ⊕ 用品牌色
                  if (locked)
                    Positioned(
                      bottom: -2,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: const Color(0xFF9E9E9E).withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(Icons.lock,
                            size: 11, color: Colors.white),
                      ),
                    )
                  else if (badgeIcon != null)
                    Positioned(
                      bottom: -2,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Icon(badgeIcon,
                            size: 12, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: highlight ? color : const Color(0xFF8E8E93),
                fontSize: 12,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "+98 种物品和功能"白色虚线胶囊按钮
class _ItemsChip extends StatelessWidget {
  const _ItemsChip();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Center(
        child: Container(
          width: 120,
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: const Color(0xFFD8D8DC),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xFFF2F2F5),
                  shape: BoxShape.circle,
                ),
                child: const DrinkIllustration(
                    beverageId: 'llama',
                    color: Color(0xFF6B6B70),
                    size: 22,
                  ),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '+98 种物品和功能',
                  style: TextStyle(
                    color: Color(0xFF6B6B70),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 完成态轮播条（对标原版：角色卡与饮品栏之间，可横滑两页）
/// - 第1页：黑色胶囊「庆祝我的一天！」按钮（白方块内青色角色剪影）
///   —— 受设置页 celebrateDay 开关控制，关闭时不渲染此页
/// - 第2页：白色横幅 + 角色头像 + 鼓励文案
/// - 底部圆点指示当前页（单页时隐藏）
class _CelebrationCarousel extends StatefulWidget {
  const _CelebrationCarousel({
    required this.animalId,
    required this.onCelebrate,
  });

  final String animalId;
  final VoidCallback onCelebrate;

  @override
  State<_CelebrationCarousel> createState() => _CelebrationCarouselState();
}

class _CelebrationCarouselState extends State<_CelebrationCarousel> {
  final _pageCtrl = PageController(viewportFraction: 0.88);
  int _page = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  /// 青色角色剪影（第1页白色方块内）
  Widget _cyanSilhouette(double size) => ColorFiltered(
        colorFilter: const ColorFilter.mode(
            Color(0xFF4DB8D8), BlendMode.srcIn),
        child: CharacterArt(
          animalId: widget.animalId,
          unlocked: false,
          size: size,
        ),
      );

  /// 第1页：黑色胶囊庆祝按钮（点击触发角色点亮 2 秒）
  Widget _celebrateButton() => Center(
        child: GestureDetector(
          onTap: widget.onCelebrate,
          child: Container(
            height: 56,
            padding: const EdgeInsets.fromLTRB(8, 8, 24, 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C22),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(child: _cyanSilhouette(30)),
                ),
                const SizedBox(width: 14),
                const Text(
                  '庆祝我的一天！',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  /// 第2页：白色鼓励横幅（角色头像 + 文案）
  Widget _tipBanner() => Center(
        child: Container(
          height: 56,
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F4F8),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                  child: CharacterArt(
                    animalId: widget.animalId,
                    unlocked: true,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '今天选择喝水再完美不过了，继续享受！',
                  style: TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsFlags.instance,
      builder: (ctx, _) {
        // celebrateDay 开关控制第1页显隐（设置页实时生效）
        final showCelebrate = SettingsFlags.instance.celebrateDay;
        final pageCount = showCelebrate ? 2 : 1;
        if (_page > pageCount - 1) _page = pageCount - 1;

        return Column(
          children: [
            SizedBox(
              height: 56,
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  if (showCelebrate) _celebrateButton(),
                  _tipBanner(),
                ],
              ),
            ),
            // 翻页圆点（单页时隐藏）
            if (pageCount > 1) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pageCount; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page
                            ? const Color(0xFF1C1C22)
                            : const Color(0xFFD9D9DE),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 底部挑战横幅（浅青色圆角矩形 + 两侧图标 + 标题）
class _ChallengeBanner extends StatelessWidget {
  const _ChallengeBanner({required this.title, required this.onTap});
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFE0F4F8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // 左侧羽毛/月亮图标
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.nightlight,
                color: Color(0xFF4DB8D8),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            // 标题
            const Expanded(
              child: Text(
                '滴酒不沾的十月',
                style: TextStyle(
                  color: Color(0xFF1C1C1E),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // 右侧饮品图标（带禁止斜线）
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.no_drinks,
                color: Color(0xFFE05252),
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
