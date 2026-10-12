import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 持续礼炮雨：粒子从屏幕顶部缓慢下落，循环不断
///
/// 复用自欢迎页 _ConfettiRainPainter：每个粒子用 `localT = (t + phase) % 1.0`
/// 实现无限循环——t 不断增加（repeat），localT 在 [0,1) 循环 → 粒子从顶部到底部
/// 不断循环出现，不会"一瞬间消失"
///
/// - 55 个粒子（数量适中）
/// - 缓慢下落 + sin 横向漂移 + 自转
/// - 前 5% 淡入、后 5% 淡出（无突兀闪现）
/// - 8 色循环（粉/橙/黄/绿/蓝/紫/品红/青）
class ConfettiRain extends StatefulWidget {
  const ConfettiRain({super.key, required this.active});
  final bool active;

  @override
  State<ConfettiRain> createState() => _ConfettiRainState();
}

class _ConfettiRainState extends State<ConfettiRain>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant ConfettiRain old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _ctrl.repeat();
    } else if (!widget.active && old.active) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    final screen = MediaQuery.sizeOf(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) => CustomPaint(
          size: screen,
          painter: ConfettiRainPainter(t: _ctrl.value, active: widget.active),
        ),
      ),
    );
  }
}

/// 礼炮雨画师：55 个粒子循环下落
class ConfettiRainPainter extends CustomPainter {
  ConfettiRainPainter({required this.t, required this.active});

  final double t;
  final bool active;

  static final _rng = math.Random(42);
  static final _particles = List.generate(55, (_) => RainParticle(_rng));

  static const _colors = [
    Color(0xFFFF6B6B), // 粉红
    Color(0xFFFFA94D), // 橙
    Color(0xFFFFD93D), // 黄
    Color(0xFF6BCB77), // 绿
    Color(0xFF4D96FF), // 蓝
    Color(0xFF9B5DE5), // 紫
    Color(0xFFF15BB5), // 品红
    Color(0xFF00BBF9), // 青
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;

    final h = size.height;
    final w = size.width;

    for (final p in _particles) {
      // localT 在 [0,1) 循环 → 粒子从顶部下落到底部再从顶部出现，无限循环
      final localT = ((t + p.phase) % 1.0);
      final y = localT * (h + 60) - 20;
      final drift = math.sin(localT * math.pi * 3 + p.driftPhase) * p.driftAmp;
      final x = (p.baseX * w) + drift;
      final rot = p.spin * (localT * math.pi * 2 + p.spinOffset);
      final color = _colors[p.colorIdx];
      // 前 5% 淡入，后 5% 淡出（避免突兀闪现）
      final alpha = localT < 0.05
          ? localT / 0.05
          : (localT > 0.95 ? (1 - localT) / 0.05 : 1.0);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rot);
      final paint = Paint()
        ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0));
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: p.size,
        height: p.size * 0.5,
      );
      canvas.drawRect(rect, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant ConfettiRainPainter old) =>
      old.t != t || old.active != active;
}

/// 礼炮粒子参数（每帧固定，由 t 驱动循环动画）
class RainParticle {
  RainParticle(math.Random r)
      : phase = r.nextDouble(),
        baseX = r.nextDouble(),
        driftAmp = 8 + r.nextDouble() * 22,
        driftPhase = r.nextDouble() * math.pi * 2,
        spin = (r.nextDouble() - 0.5) * 3,
        spinOffset = r.nextDouble() * math.pi * 2,
        size = 6 + r.nextDouble() * 10,
        colorIdx = r.nextInt(8);

  final double phase;      // 循环相位偏移（让粒子不同步下落）
  final double baseX;      // 横向基准位置 [0,1]
  final double driftAmp;   // 横向 sin 漂移幅度
  final double driftPhase; // 漂移相位
  final double spin;       // 自转速度
  final double spinOffset; // 自转相位
  final double size;       // 矩形宽
  final int colorIdx;      // 8 色索引
}
