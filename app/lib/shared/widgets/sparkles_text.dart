import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 闪耀文字（对标 Inspira UI 的 SparklesText）
///
/// 在文字四周叠加一组四角星闪光：
/// - `animate: true`：每颗星按各自的相位错开，按「由小到大再缩回」的节奏
///   闪烁，透明度固定不变（首页饮水达标后常驻）
/// - `animate: false`：定格效果，星星固定位置与亮度不再变化（海报用）
///
/// 星星位置每 1.6 秒随机换一批（换位发生在星星缩到 0 的瞬间，不会瞬移）。
class SparklesText extends StatefulWidget {
  const SparklesText({
    super.key,
    required this.child,
    this.count = 10,
    this.colors = const [Color(0xFF9E7AFF), Color(0xFFFE8BBB)],
    this.animate = true,
    this.seed = 7,
  });

  /// 被装饰的文字（或任意组件）
  final Widget child;

  /// 星星数量
  final int count;

  /// 星星颜色池（随机取用）
  final List<Color> colors;

  /// true 循环闪烁；false 定格
  final bool animate;

  /// 位置随机种子
  final int seed;

  @override
  State<SparklesText> createState() => _SparklesTextState();
}

class _SparklesTextState extends State<SparklesText>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  /// 闪烁代数：控制器每跑完一轮 +1，星星随之换到新的随机位置
  int _cycle = 0;
  double _lastValue = 0;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant SparklesText old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate || old.count != widget.count) {
      _syncController();
    }
  }

  void _syncController() {
    if (widget.animate) {
      _ctrl ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )
        ..addListener(_onTick)
        ..repeat();
    } else {
      _ctrl?.removeListener(_onTick);
      _ctrl?.dispose();
      _ctrl = null;
    }
  }

  /// 检测一轮循环结束（value 回到起点）：换一代随机布局
  void _onTick() {
    final v = _ctrl!.value;
    if (v < _lastValue) {
      _cycle++;
      _lastValue = 0;
    } else {
      _lastValue = v;
    }
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    super.dispose();
  }

  Widget _painter(double t) => CustomPaint(
    painter: _SparklesPainter(
      t: t,
      cycle: _cycle,
      animate: widget.animate,
      count: widget.count,
      colors: widget.colors,
      seed: widget.seed,
    ),
    child: const SizedBox.expand(),
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        widget.child,
        // 星光画布比文字四周各外扩一圈，星星才不会被文字边界裁掉
        Positioned(
          left: -18,
          right: -18,
          top: -14,
          bottom: -14,
          child: IgnorePointer(
            child: _ctrl == null
                ? _painter(0)
                : AnimatedBuilder(
                    animation: _ctrl!,
                    builder: (_, _) => _painter(_ctrl!.value),
                  ),
          ),
        ),
      ],
    );
  }
}

/// 四角星闪光画师
class _SparklesPainter extends CustomPainter {
  _SparklesPainter({
    required this.t,
    required this.cycle,
    required this.animate,
    required this.count,
    required this.colors,
    required this.seed,
  });

  final double t;

  /// 闪烁代数：每一代重新随机一次星星位置（避免位置固定死）
  final int cycle;
  final bool animate;
  final int count;
  final List<Color> colors;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || colors.isEmpty) return;
    final base = size.height * 0.16;
    final paint = Paint();

    for (var i = 0; i < count; i++) {
      // 节奏相位按序号固定（每颗星闪的时间点不同）。
      // 位置/大小/颜色按「序号 + 代次」重新随机：每代都换一批新位置，
      // 换位正好发生在该星亮度为 0 的时刻（v=0），所以看不到瞬移。
      final phase = math.Random(seed + i * 37).nextDouble();
      final v = (t + phase) % 1.0;
      final gen = cycle + (t + phase).floor();
      final rnd = math.Random(seed + i * 977 + gen * 131);

      final px = rnd.nextDouble();
      final py = rnd.nextDouble();
      final sizeRatio = 0.45 + rnd.nextDouble() * 0.55;
      final colorIdx = rnd.nextInt(colors.length);
      final rot = rnd.nextDouble() * math.pi;

      var scale = 1.0;
      if (animate) {
        // 一次出现→消失：只做「由小到大再到小」的缩放，亮度固定不变
        // （透明度不参与周期变化；换位发生在 scale≈0 的时刻，看不到瞬移）
        scale = math.sin(v * math.pi);
      }

      final center = Offset(px * size.width, py * size.height);
      final r = base * sizeRatio * scale;
      if (r <= 0.5) continue;

      // 固定透明度：星星始终是这个亮度，不随生命周期明暗变化
      const alpha = 0.95;
      final color = colors[colorIdx];

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rot);
      // 一点点同色辉光（很淡，只让边缘柔和发亮）
      paint.shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.22),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 1.6));
      canvas.drawCircle(Offset.zero, r * 1.6, paint);
      paint.shader = null;
      // 星体
      paint.color = color.withValues(alpha: alpha);
      canvas.drawPath(_fourPointStar(r), paint);
      canvas.restore();
    }
  }

  /// 四角星：外 4 个尖点 + 内 4 个凹点（半径约 0.38 外半径）
  Path _fourPointStar(double r) {
    const inner = 0.38;
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final radius = i.isEven ? r : r * inner;
      final angle = -math.pi / 2 + i * math.pi / 4;
      final p = Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _SparklesPainter old) =>
      old.t != t ||
      old.cycle != cycle ||
      old.count != count ||
      old.seed != seed ||
      old.animate != animate;
}
