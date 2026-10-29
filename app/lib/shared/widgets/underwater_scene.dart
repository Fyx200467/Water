import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/user_profile.dart';

/// 水下场景公用组件：气泡/冰晶背景、水面波纹、性别选项、目标温度。
///
/// 初始化信息录入页（onboarding 第 1 步）与设置页「我的饮水目标」复用
/// 同一套视觉，避免两份重复实现。

// ---- 设计规范色板（取自原版效果图，供水下背景共用） ----
const Color waterTop = Color(0xFF4FBFDC);
const Color waterBottom = Color(0xFF37A3C6);

// ============================================================
// 性别选项（初始化页与常见目标页共用，怀孕/母乳喂养按女性修正计算）
// ============================================================

/// 性别选项：展示标签与计算用 Gender 枚举分离（怀孕/母乳喂养 → female）
class GenderOption {
  const GenderOption(this.label, this.gender, this.icon);
  final String label;
  final Gender gender;
  final IconData icon;
}

/// 两页共用的 5 个性别选项
const List<GenderOption> kGenderOptions = <GenderOption>[
  GenderOption('男性', Gender.male, Icons.male),
  GenderOption('女性', Gender.female, Icons.female),
  GenderOption('怀孕', Gender.female, Icons.pregnant_woman),
  GenderOption('母乳喂养', Gender.female, Icons.child_care),
  GenderOption('不愿透露', Gender.other, Icons.no_accounts),
];

/// 无持久化标签时按 Gender 枚举回退的展示标签
String defaultGenderLabel(Gender g) => switch (g) {
      Gender.male => '男性',
      Gender.female => '女性',
      Gender.other => '不愿透露',
    };

// ============================================================
// 目标温度（气温修正：寒冷 -150 / 温和 0 / 炎热 +300）
// ============================================================

enum GoalTemperature {
  cold('寒冷', -150, '天冷出汗少，目标相应降低'),
  mild('温和', 0, '常温天气，无需修正'),
  hot('炎热', 300, '天热出汗多，需要补充更多水分');

  const GoalTemperature(this.label, this.deltaMl, this.description);
  final String label;
  final int deltaMl;
  final String description;
}

// ============================================================
// 可复用水下背景（渐变水体 + 冰晶 + 气泡）
// ============================================================

/// 自带循环动画的水下背景层：青色渐变 + 两侧缓旋冰晶 + 升起气泡
class UnderwaterBackground extends StatefulWidget {
  const UnderwaterBackground({
    super.key,
    this.gradientColors,
    this.decorTint = Colors.white,
  });

  /// 自定义背景渐变（上→下）；为空时使用默认水体配色
  final List<Color>? gradientColors;

  /// 气泡/冰晶的着色；深色底用白色，浅色底需换成淡青灰
  final Color decorTint;

  @override
  State<UnderwaterBackground> createState() => _UnderwaterBackgroundState();
}

class _UnderwaterBackgroundState extends State<UnderwaterBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final t = _anim.value;
        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: widget.gradientColors ?? [waterTop, waterBottom],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                    painter: IceCubesPainter(t: t, tint: widget.decorTint)),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                    painter: BubblesPainter(t: t, tint: widget.decorTint)),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================
// 动画组件
// ============================================================

/// 左右轻微颤动包裹器（性别/体重选项胶囊专用）
class PillSway extends StatelessWidget {
  const PillSway({
    super.key,
    required this.t,
    required this.phase,
    required this.child,
  });

  /// 循环进度 0~1
  final double t;
  final double phase;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dx = math.sin(2 * math.pi * t + phase) * 2.4;
    return Transform.translate(offset: Offset(dx, 0), child: child);
  }
}

/// 气泡层：随机分布的气泡自然升起、放大、淡出消失
class BubblesPainter extends CustomPainter {
  BubblesPainter({required this.t, this.tint = Colors.white});

  final double t;
  final Color tint;

  static final List<_BubbleSpec> _specs = () {
    final rnd = math.Random(11);
    return List.generate(10, (i) {
      return _BubbleSpec(
        xFrac: 0.06 + rnd.nextDouble() * 0.88,
        size: 4 + rnd.nextDouble() * 9,
        phase: rnd.nextDouble(),
        speed: 0.6 + rnd.nextDouble() * 0.7,
        sway: 4 + rnd.nextDouble() * 8,
      );
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final yStart = h * 0.96;
    final yEnd = h * 0.24;
    for (final s in _specs) {
      // 每个气泡独立周期：local 0→1 = 升起全程
      final local = (t * s.speed + s.phase) % 1.0;
      final y = yStart + (yEnd - yStart) * local;
      final x = s.xFrac * size.width +
          math.sin(local * 3 * math.pi + s.phase * 7) * s.sway;
      final r = s.size * (0.7 + local * 0.5); // 上升过程缓慢放大
      // 自然出现又自然消失：透明度按正弦半波包络
      final opacity = math.sin(math.pi * local) * 0.55;
      final paint = Paint()
        ..color = tint.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawCircle(Offset(x, y), r, paint);
      // 高光小点
      canvas.drawCircle(
        Offset(x - r * 0.35, y - r * 0.35),
        r * 0.22,
        Paint()..color = tint.withOpacity(opacity),
      );
    }
  }

  @override
  bool shouldRepaint(BubblesPainter old) => old.t != t || old.tint != tint;
}

class _BubbleSpec {
  const _BubbleSpec({
    required this.xFrac,
    required this.size,
    required this.phase,
    required this.speed,
    required this.sway,
  });

  final double xFrac;
  final double size;
  final double phase;
  final double speed;
  final double sway;
}

/// 冰晶六边形层：屏幕两侧分布，缓慢旋转 + 上下轻微浮动
class IceCubesPainter extends CustomPainter {
  IceCubesPainter({required this.t, this.tint = Colors.white});

  final double t;
  final Color tint;

  static final List<_CubeSpec> _specs = () {
    final rnd = math.Random(7);
    return List.generate(9, (i) {
      final isLeft = i % 2 == 0;
      return _CubeSpec(
        isLeft: isLeft,
        yFrac: 0.18 + rnd.nextDouble() * 0.72,
        size: 30 + rnd.nextDouble() * 62,
        edgeFrac: 0.10 + rnd.nextDouble() * 0.16,
        rotSpeed: (i % 3 - 1).toDouble(), // -1 / 0 / 1 圈每循环（0=仅浮动）
        phase: rnd.nextDouble(),
        bright: rnd.nextBool(),
        opacity: 0.10 + rnd.nextDouble() * 0.10,
      );
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in _specs) {
      final cy = s.yFrac * size.height +
          math.sin(2 * math.pi * (t + s.phase)) * 9; // 上下轻微浮动
      final cx = s.isLeft
          ? -s.size * (0.5 - s.edgeFrac)
          : size.width + s.size * (0.5 - s.edgeFrac);
      final rotation = 2 * math.pi * (t * s.rotSpeed + s.phase);
      final paint = Paint()
        ..color = s.bright
            ? tint.withOpacity(s.opacity)
            : const Color(0xFF1B7A99).withOpacity(s.opacity * 0.9);
      _drawHexagon(canvas, Offset(cx, cy), s.size * 0.5, rotation, paint);
    }
  }

  void _drawHexagon(
      Canvas canvas, Offset center, double r, double rotation, Paint paint) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = rotation + math.pi / 6 + i * math.pi / 3;
      final p = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(IceCubesPainter old) => old.t != t;
}

class _CubeSpec {
  const _CubeSpec({
    required this.isLeft,
    required this.yFrac,
    required this.size,
    required this.edgeFrac,
    required this.rotSpeed,
    required this.phase,
    required this.bright,
    required this.opacity,
  });

  final bool isLeft;
  final double yFrac;
  final double size;

  /// 贴边嵌入比例（越大越多部分露出）
  final double edgeFrac;
  final double rotSpeed;
  final double phase;
  final bool bright;
  final double opacity;
}
