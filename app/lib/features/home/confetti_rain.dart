import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 达标礼炮：**一次性**庆祝雨
///
/// 与旧版的区别：粒子不再无限循环，而是从顶部一次性撒出——顶部先露出一部分，
/// 随后自然下落，落到屏幕底部就消失，整段动画约 3.2 秒后自动结束不再重播。
/// 达标后常驻的喜庆感交给文字上的星光（SparklesText），礼炮只做开场。
///
/// - 45 个粒子（数量适中）
/// - 每个粒子有自己的起落延迟（phase），错峰出现，形成「先撒一把」的观感
/// - 缓慢下落 + sin 横向漂移 + 自转
/// - 首尾各淡入/淡出，避免突兀闪现
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
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..addStatusListener(_onStatus);
    if (widget.active) _play();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _finished = true);
    }
  }

  void _play() {
    _finished = false;
    _ctrl.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant ConfettiRain old) {
    super.didUpdateWidget(old);
    // 达标那一刻（false → true）撒一次；之后不再重复
    if (widget.active && !old.active) {
      _play();
    } else if (!widget.active && old.active) {
      _ctrl.stop();
      _finished = false;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || _finished) return const SizedBox.shrink();
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

/// 礼炮雨画师：45 个粒子一次性下落
class ConfettiRainPainter extends CustomPainter {
  ConfettiRainPainter({required this.t, required this.active});

  final double t;
  final bool active;

  static final _rng = math.Random(42);
  static final _particles = List.generate(45, (_) => RainParticle(_rng));

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
      // 起落延迟：phase 越大出现越晚，整段 0.65 个时间窗内落完
      final local = (t - p.phase * 0.35) / 0.65;
      if (local <= 0 || local >= 1) continue;

      final y = local * (h + 60) - 20;
      final drift =
          math.sin(local * math.pi * 3 + p.driftPhase) * p.driftAmp;
      final x = (p.baseX * w) + drift;
      final rot = p.spin * (local * math.pi * 2 + p.spinOffset);
      final color = _colors[p.colorIdx];
      // 前 8% 淡入，末尾 15% 淡出（落到下方时自然消失）
      final alpha = local < 0.08
          ? local / 0.08
          : (local > 0.85 ? (1 - local) / 0.15 : 1.0);

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

/// 礼炮粒子参数（每帧固定，由 t 驱动一次性动画）
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

  final double phase;      // 出现顺序（错峰撒出）
  final double baseX;      // 横向基准位置 [0,1]
  final double driftAmp;   // 横向 sin 漂移幅度
  final double driftPhase; // 漂移相位
  final double spin;       // 自转速度
  final double spinOffset; // 自转相位
  final double size;       // 矩形宽
  final int colorIdx;      // 8 色索引
}
