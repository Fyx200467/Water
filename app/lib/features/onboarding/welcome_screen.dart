import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../characters/character_data.dart';
import '../home/providers/home_providers.dart';
import 'unit_selection_sheet.dart';
import 'widgets/animal_silhouette.dart';
import 'widgets/selling_points_carousel.dart';

/// PRD 对标 §开屏体验：欢迎页
///
/// 动画时间线（v7）：
/// 1. 阵容随机：每次冷启动从 6 个收集分类（每日/可爱/人/家/蔬果/植物）
///    各随机抽取 1 个角色，共 6 只登场
/// 2. 0~30s 依次轮换 + 慢速顺序填色（每只 5s）
/// 3. 30~42s 巨轮弧线轮播（对标 InspiraUI TestimonialSlider）：整体速度
///    由 easeInOutCubic 主导——慢起加速、临近结束自然减速，恰好停在
///    最后一只上（与礼炮定格帧一致，无跳变）
/// 4. 42s+ 触发持续全屏礼炮雨 + 角色定格
///          用户点击"开始使用"→ 弹出单位选择 → 进入 onboarding
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _master;
  bool _confettiStarted = false;

  static const _accent = Color(0xFF4DB8D8);

  /// 登场阵容：每个收集分类随机抽 1 个角色（实例创建时抽取一次，
  /// 本次会话内填色轮换与弧线轮播共用同一阵容）
  final List<String> _animals = _pickRandomCast();

  static List<String> _pickRandomCast() {
    final rnd = math.Random();
    return [
      for (final cat in characterCategories)
        cat.characterIds[rnd.nextInt(cat.characterIds.length)],
    ];
  }

  static const _tFillPerAnimal = 5.0; // 每只填色 5s
  static const _tCarouselPerAnimal = 2.0; // 轮播每只 2s

  double get _tInitialEnd => _animals.length * _tFillPerAnimal; // 初始轮换结束
  double get _tCarouselEnd =>
      _tInitialEnd + _animals.length * _tCarouselPerAnimal; // 轮播结束 → 礼炮

  @override
  void initState() {
    super.initState();
    // 总时长 = 轮换 + 轮播 + 4s 礼炮定格缓冲
    final totalSec = (_tCarouselEnd + 4).round();
    _master = AnimationController(
      vsync: this,
      duration: Duration(seconds: totalSec),
    )..forward();

    _master.addListener(_onMasterTick);
  }

  void _onMasterTick() {
    final t = _master.value * _master.duration!.inSeconds;
    if (t >= _tCarouselEnd && !_confettiStarted) {
      _confettiStarted = true;
      // ConfettiRain widget 内部自带 controller，只需 setState 让 active=true
      setState(() {});
    }
  }

  @override
  void dispose() {
    _master.removeListener(_onMasterTick);
    _master.dispose();
    super.dispose();
  }

  double _seg(double totalSec, double a, double b) =>
      ((totalSec - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
            child: Column(
              children: [
                // 顶部：卖点文案轮换（对标原版：无插画，彩色✓文案淡入淡出）
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    children: [
                      // 三饮品循环置换动画（对标用户截图：中顶杯左滑降底
                      // → 右底杯左滑升顶 → 左底杯右滑补位，循环往复）
                      const DrinksTrioCarousel(),
                      const SizedBox(height: 8),
                      const SellingPointsCarousel(width: 260),
                      const SizedBox(height: 8),
                      Text(
                        '跟踪你的饮水量',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF2C3E50),
                        ),
                      ),
                    ],
                  ),
                ),

                // 中央：动物轮播
                Expanded(child: Center(child: _buildAnimalLayer())),

                // 底部：按钮水平居中 + 语言标识
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 180,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _onStart,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2C3E50),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          child: const Text('开始使用'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const _LangChip(),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }

  /// 动物层：初始轮换 → 轮播滑动 → 礼炮定格
  Widget _buildAnimalLayer() {
    return AnimatedBuilder(
      animation: _master,
      builder: (ctx, _) {
        final t = _master.value * _master.duration!.inSeconds;

        if (_confettiStarted) {
          return AnimalSilhouette(
            animalId: _animals.last,
            fillRatio: 1.0,
            accentColor: _accent,
            size: 300,
          );
        }

        if (t >= _tInitialEnd) {
          return _buildCarousel(t);
        }

        return _buildInitialRotation(t);
      },
    );
  }

  /// 巨轮弧线轮播（对标 InspiraUI TestimonialSlider）：
  /// 动物骑在巨大圆盘边缘，如摩天轮转动——当前只在弧顶居中，下一只
  /// 沿弧线从右侧屏幕边缘升起，当前只向左侧屏幕边缘沉走淡出。
  /// 舞台为全屏宽，可见角窗按屏幕宽度反推：θ_edge = asin(半屏宽 / R)。
  ///
  /// 速度设计：轮盘进度由主时间轴驱动，全程套 easeInOutCubic——
  /// 起步慢（与静止的填色轮换无缝衔接）→ 中段加速 → 末段自然减速，
  /// 总进度恰好一整圈（N 格），最终停在最后一只（与礼炮定格帧一致）。
  /// 几何：弧顶为原点，槽位角 θ 处的坐标 x=R·sinθ, y=R·(1-cosθ)
  Widget _buildCarousel(double masterT) {
    const slotAngle = 36 * math.pi / 180; // 相邻槽位角间隔
    const radius = 520.0; // 轮盘半径

    // 可见角窗：动物越过屏幕边缘 60px 后才完全淡出，避免边缘处"半空消失"
    final screenW = MediaQuery.sizeOf(context).width;
    final maxAngle =
        math.asin(math.min(screenW / 2 + 60, radius - 1) / radius);

    // 轮播窗口内的时间进度 → 全程缓动 → 轮盘格进度
    // 起点 -1：轮换结束时最后一只正在弧顶，起转瞬间无跳变；
    // 终点 N-1：整整转过 N 格后恰好落在最后一只上，速度归零自然停住
    final tCar =
        (masterT - _tInitialEnd).clamp(0.0, _tCarouselEnd - _tInitialEnd);
    final f = Curves.easeInOutCubic
        .transform(tCar / (_tCarouselEnd - _tInitialEnd));
    final cp = -1.0 + f * _animals.length;

    return ClipRect(
      child: SizedBox(
        width: screenW,
        height: 300,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < _animals.length; i++)
              _arcAnimal(i, cp, slotAngle, radius, maxAngle),
          ],
        ),
      ),
    );
  }

  /// 第 i 只动物在轮盘上的姿态：rel 为相对轮盘进度的槽位偏移
  /// （活动位 0；负 = 已越过弧顶向左下沉，正 = 右侧待升顶）
  Widget _arcAnimal(
    int i,
    double cp,
    double slotAngle,
    double radius,
    double maxAngle,
  ) {
    final n = _animals.length;
    var rel = (i - cp) % n; // Dart 的 % 恒非负
    if (rel > n / 2) rel -= n; // 折算到 (-n/2, n/2]，保证跨循环连续
    final angle = rel * slotAngle;
    final d = angle.abs();
    if (d > maxAngle) return const SizedBox.shrink();
    // 淡入淡出只发生在屏幕边缘附近：弧顶半窗内全亮，越过之后线性淡出
    const fadeInZone = 0.55;
    final opacity = d <= maxAngle * fadeInZone
        ? 1.0
        : (1 - (d - maxAngle * fadeInZone) / (maxAngle * (1 - fadeInZone)))
            .clamp(0.0, 1.0);
    if (opacity <= 0.01) return const SizedBox.shrink();
    final x = radius * math.sin(angle);
    final y = radius * (1 - math.cos(angle));
    return Transform.translate(
      offset: Offset(x, y),
      child: Transform.scale(
        scale: 1.0 - 0.3 * (d / maxAngle), // 离弧顶越远越小
        child: Opacity(
          opacity: opacity,
          child: AnimalSilhouette(
            key: ValueKey('arc_$i'),
            animalId: _animals[i],
            fillRatio: 1.0,
            accentColor: _accent,
            size: 300,
          ),
        ),
      ),
    );
  }

  /// 初始轮换（N 只动物依次登场、慢速填色；除最后一只外依次退场）
  Widget _buildInitialRotation(double t) {
    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < _animals.length; i++) _slot(i, t),
        ],
      ),
    );
  }

  Widget _slot(int index, double t) {
    final animal = _animals[index];
    final isLast = index == _animals.length - 1;
    final startT = index * _tFillPerAnimal;
    final endT = (index + 1) * _tFillPerAnimal;
    const enterDur = 0.6;
    final fillStart = startT + enterDur;
    final fillEnd = endT - 0.6;
    final exitStart = endT;
    final exitEnd = endT + 0.8;

    final enter = _seg(t, startT, startT + enterDur);
    final fill = _seg(t, fillStart, fillEnd);
    // 最后一只不退场：填完色停留到轮播阶段接管
    final exit = isLast ? 0.0 : _seg(t, exitStart, exitEnd);

    double offset;
    double opacity;

    if (index == 0) {
      offset = exit * 280;
      opacity = 1 - exit;
    } else {
      offset = (1 - enter) * -280 + exit * 280;
      opacity = (t < startT) ? 0 : (1 - exit);
    }

    if (opacity <= 0.01) return const SizedBox.shrink();

    return Transform.translate(
      offset: Offset(offset, 0),
      child: Opacity(
        opacity: opacity,
        child: AnimalSilhouette(
          animalId: animal,
          fillRatio: fill,
          accentColor: _accent,
          size: 300,
        ),
      ),
    );
  }

  void _onStart() async {
    final unit = await UnitSelectionSheet.show(context);
    if (unit != null && mounted) {
      await ref.read(preferredUnitProvider.notifier).select(unit);
      if (mounted) context.go('/onboarding');
    }
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Color(0xFFFF8C42),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Text(
            '简',
            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '简体中文',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }
}
