import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/storage/providers.dart';
import '../challenges/challenge_art.dart';
import '../challenges/challenge_catalog.dart';
import '../challenges/challenge_service.dart';
import '../drink/widgets/svg_container.dart';
import '../settings/cloud_backup_screen.dart';
import '../../shared/services/share_image.dart';

/// 习惯挑战详情页（对标原版录屏：点击习惯卡后底部滑入）
///
/// 结构与挑战详情页同构：
/// - 彩色头部：•••/× 悬浮圆钮 +「10 天挑战」标签 + 大标题 + 副标题
///   +「告诉朋友」胶囊 + 右侧角色插画压边裁剪
/// - 白色正文：介绍段落 → [挑战进度]（开始后出现）→「好处」→
///   emoji 好处段落 →「要做的事情」
/// - 底部悬浮胶囊：未开始「立即开始」，开始后「进行中 · x/10 天」，
///   完成后变绿「挑战完成」
///
/// 挑战完成（10 天）自动发放 1000 积分并展示到账提示。
class HabitDetailScreen extends ConsumerStatefulWidget {
  const HabitDetailScreen({super.key, required this.habit});

  final HabitData habit;

  @override
  ConsumerState<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends ConsumerState<HabitDetailScreen> {
  HabitData get habit => widget.habit;

  /// 奖励结算中标记：避免 build 期间重复触发
  bool _settling = false;

  /// 长截图分享：滚动控制器 + 包住整个滚动视图的截图边界
  final ScrollController _scroll = ScrollController();
  final GlobalKey _captureKey = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 「告诉Ta」= 当前页面整屏长截图（滚动拼接后调起系统分享）
  Future<void> _shareLongScreenshot() async {
    final title = habit.title.replaceAll('\n', '');
    try {
      await ShareImage.shareScrollable(
        context: context,
        controller: _scroll,
        viewportKey: _captureKey,
        fileName:
            'dun_dun_challenge_'
            '${DateTime.now().millisecondsSinceEpoch}.png',
        text: '我在「吨吨」参加${habit.days}天挑战：$title，一起来喝水打卡吧！',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('分享失败，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final progress = ref
        .watch(challengeOverviewProvider)
        .valueOrNull?[habit.id];
    // 挑战完成即自动发放积分（每人每个挑战一次）
    if (progress != null && progress.completed && !progress.claimed) {
      _settleReward(progress);
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 滚动正文（含彩色头部）；外层 RepaintBoundary 供长截图分享
          Positioned.fill(
            child: RepaintBoundary(
              key: _captureKey,
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(
                      habit: habit,
                      topPad: topPad,
                      onShare: _shareLongScreenshot,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 140),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            habit.intro,
                            style: const TextStyle(
                              color: Color(0xFF1C1C1E),
                              fontSize: 16,
                              height: 1.65,
                            ),
                          ),
                          // 开始挑战后，在「好处」上方展示进度信息
                          if (progress != null && progress.joined) ...[
                            const SizedBox(height: 24),
                            _ProgressCard(progress: progress),
                          ],
                          const SizedBox(height: 36),
                          Text(
                            '好处',
                            style: TextStyle(
                              color: habit.bg,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 16),
                          for (final (emoji, text) in habit.benefits) ...[
                            Text.rich(
                              TextSpan(
                                text: '$emoji ',
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.65,
                                ),
                                children: [
                                  TextSpan(
                                    text: text,
                                    style: const TextStyle(
                                      color: Color(0xFF1C1C1E),
                                      fontSize: 16,
                                      height: 1.65,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          const SizedBox(height: 22),
                          Text(
                            '要做的事情',
                            style: TextStyle(
                              color: habit.bg,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            habit.todo,
                            style: const TextStyle(
                              color: Color(0xFF1C1C1E),
                              fontSize: 16,
                              height: 1.65,
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
          // 顶部悬浮关闭圆钮（左上角三个点入口已移除）
          Positioned(
            top: topPad + 8,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _roundBtn(
                    Icons.close,
                    () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          ),
          // 底部悬浮胶囊
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 20,
            child: Center(child: _buildAction(progress)),
          ),
        ],
      ),
    );
  }

  /// 完成挑战后自动发放积分并提示（_settling 防重复触发）
  Future<void> _settleReward(ChallengeProgress progress) async {
    if (_settling) return;
    _settling = true;
    final granted = await ensureChallengeReward(ref, progress);
    if (!mounted) return;
    if (granted > 0) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('挑战完成，+$granted 积分已到账'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildAction(ChallengeProgress? progress) {
    // 「是否已开始」以本地持久化为准，进度数据仅用于展示天数
    final started = ref.watch(startedChallengesProvider).valueOrNull;
    final completed = progress?.completed ?? false;
    // 本地状态尚未加载完成：先禁用以避免闪烁成「立即开始」
    if (started == null && progress == null) {
      return _actionPill(
        color: const Color(0xFF1C1C22).withOpacity(0.4),
        text: '加载中…',
        onTap: null,
      );
    }
    final joined = started?.contains(habit.id) ?? (progress?.joined ?? false);
    if (completed) {
      return _actionPill(
        color: const Color(0xFF23A06A),
        text: '挑战完成',
        icon: Icons.check_rounded,
        // 已完成的挑战也支持结束，清除本机挑战记录
        onTap: _confirmEndChallenge,
      );
    }
    if (joined) {
      final done = progress?.doneDays ?? 0;
      return _actionPill(
        color: const Color(0xFF23A06A),
        text: '进行中 · $done/${habit.days} 天',
        icon: (progress?.todayDone ?? false) ? Icons.check_rounded : null,
        // 再次点击「进行中」→ 询问是否结束挑战
        onTap: _confirmEndChallenge,
      );
    }
    return _actionPill(
      color: const Color(0xFF1C1C22),
      text: '立即开始',
      onTap: _startWithSingleGuard,
    );
  }

  /// 同一时间只允许一个进行中的挑战：已有未完成挑战时先提示；
  /// 游客不允许开启挑战（挑战进度与积分属于账号权益）
  Future<void> _startWithSingleGuard() async {
    final storage = await ref.read(localStorageProvider.future);
    if (!mounted) return;
    if (!storage.hasAccountSession) {
      final goLogin = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('登录后才能开启挑战'),
          content: const Text(
            '挑战进度与积分属于账号权益，登录后开始挑战，'
            '进度与奖励跟随账号保存。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('知道了'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去登录'),
            ),
          ],
        ),
      );
      if (goLogin == true && mounted) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CloudBackupScreen()));
      }
      return;
    }
    final overview = ref.read(challengeOverviewProvider).valueOrNull;
    final active = _activeOther(overview);
    if (active != null) {
      final endCurrent = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('暂时不能开启新挑战'),
          content: Text(
            '你已开启「${active.plan.title.replaceAll('\n', '')}」挑战。'
            '需完成或结束该挑战后，才能开启新的挑战。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('知道了'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('结束当前挑战并开始'),
            ),
          ],
        ),
      );
      if (endCurrent != true) return;
      await endChallenge(active.plan.id);
      if (!mounted) return;
      ref.read(challengeRevisionProvider.notifier).state += 1;
    }
    await startChallenge(habit.id);
    if (!mounted) return;
    ref.read(challengeRevisionProvider.notifier).state += 1;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('挑战开始！坚持 ${habit.days} 天可得 ${habit.rewardPoints} 积分'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 其他正在进行（未完成）的挑战
  ChallengeProgress? _activeOther(Map<String, ChallengeProgress>? map) {
    if (map == null) return null;
    for (final p in map.values) {
      if (p.joined && !p.completed && p.plan.id != habit.id) return p;
    }
    return null;
  }

  /// 结束挑战二次确认
  Future<void> _confirmEndChallenge() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('结束挑战？'),
        content: Text(
          '结束后「${habit.title.replaceAll('\n', '')}」的进度将清零，'
          '且无法获得完成奖励。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '结束挑战',
              style: TextStyle(color: Color(0xFFD8354A)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await endChallenge(habit.id);
    if (!mounted) return;
    ref.read(challengeRevisionProvider.notifier).state += 1;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('已结束挑战'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _actionPill({
    required Color color,
    required String text,
    IconData? icon,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 30),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(29),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 小角色头像
            Container(
              width: 34,
              height: 34,
              margin: const EdgeInsets.only(right: 10),
              decoration: const BoxDecoration(
                color: Colors.white24,
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: ChallengeArt(
                asset: habit.asset,
                width: 26,
                height: 26,
                fit: BoxFit.contain,
              ),
            ),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 6),
              Icon(icon, color: Colors.white, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.22),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

/// 挑战进度卡：今日饮水进度环 + 10 天迷你柱状图 + 规则与积分说明
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final ChallengeProgress progress;

  static const Color _waterBlue = Color(0xFF4DB8D8);
  static const Color _red = Color(0xFFD8354A);
  static const Color _green = Color(0xFF23A06A);
  static const Color _ink = Color(0xFF1C1C1E);

  @override
  Widget build(BuildContext context) {
    final plan = progress.plan;
    final reached = progress.todayMl >= progress.goalMl;
    // 喝了挑战禁止的饮品：进度环变红
    final ringColor = progress.todayForbidden ? _red : _waterBlue;
    return Container(
      width: double.infinity,
      // 去掉卡片底色，仅保留少量内边距
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '今日饮水',
                style: TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '已坚持${progress.doneDays}/${plan.days}天',
                style: const TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // 今日饮水实时进度环（默认水蓝，喝到禁止饮品变红）
              _TodayRing(
                ratio: progress.goalMl <= 0
                    ? 0
                    : (progress.todayMl / progress.goalMl).clamp(0.0, 1.0),
                color: ringColor,
                // 达标且无禁止饮品 → 绿√；达标但有禁止饮品 → 红×
                showCheck: progress.todayDone,
                showCross: reached && progress.todayForbidden,
                size: 76,
              ),
              const SizedBox(width: 22),
              // 迷你图表：Y 轴最大值 = 饮水目标，X 轴 = 挑战 10 天
              Expanded(
                child: SizedBox(
                  height: 92,
                  child: CustomPaint(
                    painter: _MiniChartPainter(
                      dailyMl: progress.dailyMl,
                      dailyForbidden: progress.dailyForbidden,
                      goalMl: progress.goalMl,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // 注：挑战禁忌由该挑战「要做的事情」决定（不能喝哪些饮品）
          Text(
            progress.plan.forbiddenLabels.isEmpty
                ? '注：每日饮水达标才算完成'
                : '注：每日饮水达标且挑战期间不能饮用'
                      '${progress.plan.forbiddenLabels.join('、')}等饮品才算完成',
            style: const TextStyle(
              color: Color(0xFFA6ADB1),
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // 「获得积分」小图标
              SvgPicture.asset(
                'assets/images/icons/points_gained.svg',
                width: 18,
                height: 18,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  progress.claimed
                      ? '已完成${plan.days}天挑战，+${plan.rewardPoints}积分已到账'
                      : '完成${plan.days}天挑战可获得${plan.rewardPoints}积分',
                  style: TextStyle(
                    color: progress.claimed ? _green : _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 今日饮水进度环：圆角描边，内部为首页水杯图标 / 绿√ / 红×
class _TodayRing extends StatelessWidget {
  const _TodayRing({
    required this.ratio,
    required this.color,
    required this.showCheck,
    required this.showCross,
    required this.size,
  });

  final double ratio;
  final Color color;
  final bool showCheck;
  final bool showCross;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RingPainter(ratio: ratio, color: color),
            ),
          ),
          if (showCheck)
            Icon(
              Icons.check_rounded,
              color: const Color(0xFF23A06A),
              size: size * 0.42,
            )
          else if (showCross)
            Icon(
              Icons.close_rounded,
              color: const Color(0xFFD8354A),
              size: size * 0.42,
            )
          else
            // 首页同款水容器图标（纯净水杯，按进度环颜色填充）
            SvgContainerIcon(
              containerId: 'svg:water_pure_user',
              color: color,
              size: size * 0.46,
              fillRatio: 0.88,
            ),
        ],
      ),
    );
  }
}

/// 圆角进度环：从 12 点方向顺时针扫过，端点圆头
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.ratio, required this.color});

  final double ratio;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 不要未填满的轨道，只画已完成部分；描边加粗
    const double stroke = 6.5;
    final center = size.center(Offset.zero);
    final r = (size.shortestSide - stroke) / 2;
    final sweep = ratio.clamp(0.0, 1.0) * 2 * math.pi;
    if (sweep <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.ratio != ratio || old.color != color;
}

/// 10 天迷你柱状图：Y 轴最大值 = 饮水目标，X 轴 = 挑战第 1..10 天
///
/// 柱状图更适合：10 个离散日值、需要与目标横向对比，缺失/为 0 的
/// 天数在柱状图里一目了然（折线图容易被理解为连续趋势且 0 值难读）。
class _MiniChartPainter extends CustomPainter {
  const _MiniChartPainter({
    required this.dailyMl,
    required this.dailyForbidden,
    required this.goalMl,
  });

  final List<int> dailyMl;
  final List<bool> dailyForbidden;
  final int goalMl;

  static const Color _waterBlue = Color(0xFF4DB8D8);
  static const Color _red = Color(0xFFE05B6D);

  @override
  void paint(Canvas canvas, Size size) {
    const double labelGap = 12; // 留给底部日期数字
    // 不画 X/Y 轴线，只保留柱体与目标虚线
    final plot = Rect.fromLTRB(2, 3, size.width - 2, size.height - labelGap);

    final n = dailyMl.length;
    if (n == 0 || goalMl <= 0) return;

    // 目标参考虚线（Y 轴最大值 = 饮水目标）
    final dashPaint = Paint()
      ..color = const Color(0xFFC9D2CC)
      ..strokeWidth = 1;
    var dashX = plot.left + 3;
    final dashY = plot.top + 1;
    while (dashX < plot.right) {
      canvas.drawLine(
        Offset(dashX, dashY),
        Offset(math.min(dashX + 4, plot.right), dashY),
        dashPaint,
      );
      dashX += 8;
    }

    // 每天一根柱：水量/目标 折算高度，禁止饮品的天用红色
    const double gap = 3;
    final slotW = (plot.width - gap * (n - 1)) / n;
    final barW = math.max(3.0, slotW * 0.62);
    for (var i = 0; i < n; i++) {
      final ml = dailyMl[i];
      if (ml <= 0) continue;
      final h = (ml / goalMl).clamp(0.0, 1.0) * plot.height;
      final left = plot.left + i * (slotW + gap) + (slotW - barW) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(left, plot.bottom - h, left + barW, plot.bottom),
        const Radius.circular(2),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = dailyForbidden[i] ? _red : _waterBlue,
      );
    }

    // X 轴日期数字：挑战第 1..10 天
    for (var i = 0; i < n; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(color: Color(0xFFB0B7BB), fontSize: 7.5),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final cx = plot.left + i * (slotW + gap) + slotW / 2;
      tp.paint(canvas, Offset(cx - tp.width / 2, size.height - tp.height));
    }
  }

  @override
  bool shouldRepaint(covariant _MiniChartPainter old) =>
      old.goalMl != goalMl ||
      old.dailyMl.length != dailyMl.length ||
      (dailyMl.isNotEmpty &&
          List.generate(
            dailyMl.length,
            (i) =>
                old.dailyMl.length > i &&
                (old.dailyMl[i] != dailyMl[i] ||
                    old.dailyForbidden[i] != dailyForbidden[i]),
          ).any((e) => e));
}

/// 彩色头部：标签 + 大标题 + 副标题 + 告诉朋友 + 右侧角色压边
class _Header extends StatelessWidget {
  const _Header({
    required this.habit,
    required this.topPad,
    required this.onShare,
  });

  final HabitData habit;
  final double topPad;

  /// 点击「告诉Ta」：当前页面整屏长截图分享
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 350,
      // 角色超出头部范围的部分直接裁剪
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: habit.bg),
      child: Stack(
        children: [
          // 角色插画：右下角压边裁剪
          Positioned(
            right: -80,
            bottom: -46,
            child: SizedBox(
              width: 280,
              height: 280,
              child: ChallengeArt(asset: habit.asset, fit: BoxFit.contain),
            ),
          ),
          // 文案层
          Padding(
            padding: EdgeInsets.fromLTRB(24, topPad + 78, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${habit.days} 天挑战',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  habit.title.replaceAll('\n', ''),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  habit.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                // 告诉Ta（当前页面整屏长截图分享）
                GestureDetector(
                  onTap: onShare,
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(23),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          'assets/images/icons/tell_friend.svg',
                          width: 20,
                          height: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '告诉Ta',
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
