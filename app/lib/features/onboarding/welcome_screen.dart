import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../home/providers/home_providers.dart';
import 'unit_selection_sheet.dart';

/// PRD 对标 §开屏体验：欢迎页（水滴开场）
///
/// 单次播放时间线（毫秒，结束后静态停留）：
/// 1. 0~800     一滴水从屏幕上方加速坠落到画面上方图标位置
/// 2. 700~1150  水花散开的同时，应用图标先弹出（缩放 + 淡入）
/// 3. 1150~2158 "Drink some water！" 逐字母上浮（LetterPullup）
/// 4. 2250~2630 底部「开始使用」与语言标识最后上浮出现
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  static const _accent = Color(0xFF4DB8D8);
  static const _ink = Color(0xFF2C3E50);

  static const _totalMs = 4000.0;
  static const _fallEndMs = 800.0; // 水滴落地
  static const _splashEndMs = 1560.0; // 水花散开结束
  static const _iconStartMs = 760.0; // 图标出现（水花刚开始散）
  static const _iconDurMs = 620.0;
  static const _textStartMs = 2380.0; // 图标动画结束后 1s 文字才出现
  static const _letterDelayMs = 42.0; // 逐字母间隔
  static const _letterDurMs = 420.0;
  static const _bottomStartMs = 3560.0; // 底部按钮最后出现
  static const _bottomDurMs = 380.0;

  /// 与 painter 共用的归一化节点
  static const _fallEnd = _fallEndMs / _totalMs;
  static const _splashEnd = _splashEndMs / _totalMs;

  /// 水滴落点相对屏幕中心的偏移（对齐图标中心）
  static const _impactDy = -90.0;

  static const _titleStyle = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w500,
    color: _ink,
    letterSpacing: 0.2,
  );

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 水滴下落 + 水花散开（落点对齐中央图标）
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DropSplashPainter(
                  animation: _c,
                  accent: _accent,
                  fallEnd: _fallEnd,
                  splashEnd: _splashEnd,
                  impactDy: _impactDy,
                ),
              ),
            ),
          ),

          // 中央：应用图标 → Drink some water！（整体略高于页面中心）
          Center(
            child: Transform.translate(
              offset: const Offset(0, -60),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) => _buildStage(_c.value * _totalMs),
                ),
              ),
            ),
          ),

          // 底部：全部动画结束后才出现
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => _buildBottom(_c.value * _totalMs),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 图标 + 文字主体
  Widget _buildStage(double ms) {
    // 图标像从水花里"弹"出来：先淡入，再带回弹地放大，同时轻微上浮
    final iconP = ((ms - _iconStartMs) / _iconDurMs).clamp(0.0, 1.0);
    final iconScale = 0.45 + 0.55 * Curves.easeOutBack.transform(iconP);
    final iconDy = (1 - Curves.easeOutCubic.transform(iconP)) * 18;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: (iconP / 0.35).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, iconDy),
            child: Transform.scale(
              scale: iconScale,
              child: const _AppIconTile(size: 88),
            ),
          ),
        ),
        const SizedBox(height: 26),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _buildPullUpLetters(ms),
          ),
        ),
      ],
    );
  }

  /// 底部按钮区：动画整体结束后淡入上浮
  Widget _buildBottom(double ms) {
    final p = ((ms - _bottomStartMs) / _bottomDurMs).clamp(0.0, 1.0);
    final e = Curves.easeOutCubic.transform(p);
    return IgnorePointer(
      ignoring: p < 1,
      child: Opacity(
        opacity: p,
        child: Transform.translate(
          offset: Offset(0, (1 - e) * 20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 96),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 54,
                  width: 190,
                  child: _RainbowButton(
                    label: '开始使用',
                    onPressed: () => _onStart(context, ref),
                  ),
                ),
                const SizedBox(height: 16),
                const _LangChip(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 单个字母的动画进度：按 delay 顺序起跑，各自独立上浮
  double _letterProgress(double ms, int index) =>
      ((ms - _textStartMs - index * _letterDelayMs) / _letterDurMs)
          .clamp(0.0, 1.0);

  /// LetterPullup：逐字母从下方 28px 处上浮 + 淡入，带轻微回弹
  List<Widget> _buildPullUpLetters(double ms) {
    const text = 'Drink some water';
    return [
      for (var i = 0; i < text.length; i++)
        () {
          final p = _letterProgress(ms, i);
          final e = Curves.easeOutBack.transform(p);
          return Opacity(
            opacity: (p * 1.6).clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, (1 - e) * 28),
              child: Text(text[i], style: _titleStyle),
            ),
          );
        }(),
    ];
  }

  Future<void> _onStart(BuildContext context, WidgetRef ref) async {
    final unit = await UnitSelectionSheet.show(context);
    if (unit != null && context.mounted) {
      await ref.read(preferredUnitProvider.notifier).select(unit);
      if (context.mounted) context.go('/onboarding');
    }
  }
}

/// 画：下落的水滴（带渐变）、落地压扁、环形波纹、四散的水花
class _DropSplashPainter extends CustomPainter {
  _DropSplashPainter({
    required this.animation,
    required this.accent,
    required this.fallEnd,
    required this.splashEnd,
    required this.impactDy,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color accent;
  final double fallEnd;
  final double splashEnd;
  final double impactDy;

  /// 12 个飞溅方向（-20°~-160°，即向上扇形散开）与随机系数
  static final List<({double angle, double k})> _drops = List.generate(12, (i) {
    final t = i / 11;
    return (angle: -math.pi * (0.12 + 0.76 * t), k: 0.65 + 0.7 * _rnd(i));
  });

  static double _rnd(int i) {
    // 固定伪随机，保证每次播放同样的水花形态
    final x = math.sin(i * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + impactDy);
    final p = animation.value;

    if (p < fallEnd) {
      // ── 下落：加速坠向落点，落地前轻微压扁
      final q = p / fallEnd;
      final eased = Curves.easeInCubic.transform(q);
      final startY = size.height * 0.12;
      final y = startY + (center.dy - startY) * eased;
      final fadeIn = (q / 0.12).clamp(0.0, 1.0);
      final squash = q > 0.88 ? (q - 0.88) / 0.12 : 0.0;
      final sy = 1 - 0.30 * squash;
      final sx = 1 + 0.26 * squash;
      final r = 15.0;

      canvas.save();
      canvas.translate(center.dx, y);
      canvas.scale(sx, sy);
      // 渐变填充按 alpha 作用到整层（Paint.color 的 alpha 不会影响 shader）
      canvas.saveLayer(
        Rect.fromCircle(center: Offset.zero, radius: r * 2.4),
        Paint()..color = Colors.white.withValues(alpha: fadeIn),
      );
      final shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0.0, 0.55, 1.0],
        colors: [Color(0xFFB6E6F5), Color(0xFF6CC7E4), Color(0xFF3FA9CE)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 1.6));
      canvas.drawPath(
        _tearDrop(Size(r * 2, r * 3.05)).shift(Offset(-r, -r * 1.525)),
        Paint()
          ..shader = shader
          ..isAntiAlias = true,
      );
      // 高光
      canvas.drawCircle(
        Offset(-r * 0.28, -r * 0.25),
        r * 0.22,
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
      canvas.restore();
      canvas.restore();
      return;
    }

    // ── 散开
    final s = ((p - fallEnd) / (splashEnd - fallEnd)).clamp(0.0, 1.0);
    final out = Curves.easeOutCubic.transform(s);

    // 环形波纹（两层，错开时间）
    for (var i = 0; i < 2; i++) {
      final ss = ((s - i * 0.18) / (1 - i * 0.18)).clamp(0.0, 1.0);
      if (ss <= 0) continue;
      final rr = 16 + (58 + i * 26) * Curves.easeOut.transform(ss);
      canvas.drawCircle(
        center,
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4 * (1 - ss) + 0.4
          ..color = accent.withValues(alpha: 0.38 * (1 - ss)),
      );
    }

    // 四散的小水珠：抛物线飞出 + 逐渐透明、缩小
    for (final d in _drops) {
      final dir = Offset(math.cos(d.angle), math.sin(d.angle));
      final dist = (6 + 54 * out) * d.k;
      final pos = center + dir * dist + Offset(0, 74 * s * s);
      final r = (2.8 + 2.4 * d.k) * (1 - s * 0.85);
      if (r <= 0.2) continue;
      canvas.drawCircle(
        pos,
        r,
        Paint()..color = accent.withValues(alpha: 0.85 * (1 - s)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DropSplashPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.impactDy != impactDy;
}

/// 水滴轮廓：顶点在上、底部圆润，铺满给定矩形
Path _tearDrop(Size s) {
  final w = s.width;
  final h = s.height;
  final cx = w / 2;
  final p = Path();
  p.moveTo(cx, 0);
  p.cubicTo(cx + w * 0.30, h * 0.28, cx + w * 0.50, h * 0.60, cx + w * 0.30, h * 0.86);
  p.quadraticBezierTo(cx, h, cx - w * 0.30, h * 0.86);
  p.cubicTo(cx - w * 0.50, h * 0.60, cx - w * 0.30, h * 0.28, cx, 0);
  p.close();
  return p;
}

/// 应用图标：浅灰圆角方块 + 青色水滴
class _AppIconTile extends StatelessWidget {
  const _AppIconTile({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F7),
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: size * 0.34,
        height: size * 0.42,
        child: CustomPaint(painter: _TileDropPainter()),
      ),
    );
  }
}

class _TileDropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = _tearDrop(size);
    canvas.drawPath(path, Paint()..color = const Color(0xFF71E3F0));
    // 左侧高光弧
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.34, size.height * 0.66),
        width: size.width * 0.34,
        height: size.height * 0.36,
      ),
      math.pi * 0.72,
      math.pi * 0.52,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.10
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 开始按钮：白色胶囊 + 底部静态彩虹光晕
class _RainbowButton extends StatefulWidget {
  const _RainbowButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_RainbowButton> createState() => _RainbowButtonState();
}

class _RainbowButtonState extends State<_RainbowButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _down ? 0.985 : 1,
        duration: const Duration(milliseconds: 120),
        child: CustomPaint(
          painter: _RainbowGlowPainter(),
          child: Center(
            child: Text(
              widget.label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2C3E50),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RainbowGlowPainter extends CustomPainter {
  static const _colors = [
    Color(0xFFFF5A5F), // 红
    Color(0xFFFF9F43), // 橙
    Color(0xFFFFD93D), // 黄
    Color(0xFF4CD07D), // 绿
    Color(0xFF34C6C6), // 青
    Color(0xFF4D9BF5), // 蓝
    Color(0xFFA66BFF), // 紫
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = size.height / 2;
    final shader = const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: _colors,
    ).createShader(rect);

    // 底部彩虹光晕（柔光扩散到按钮下方）
    canvas.saveLayer(
      rect.inflate(32),
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
    canvas.translate(0, size.height * 0.30);
    canvas.scale(1, 0.55);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()
        ..shader = shader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
    );
    canvas.restore();

    // 白色胶囊（极浅投影保证在纯白背景上仍有轮廓）
    final body = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius - 0.5),
    );
    canvas.drawRRect(
      body.shift(const Offset(0, 3)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.05)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(body, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LangChip extends StatelessWidget {
  const _LangChip();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '简体中文',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }
}
