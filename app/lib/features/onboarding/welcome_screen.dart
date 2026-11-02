import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../home/providers/home_providers.dart';
import '../settings/app_icon_screen.dart';
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
    fontWeight: FontWeight.w400,
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
      // ── 下落：加速坠落；速度越快竖向拉伸越明显（横向收窄，体积近似守恒）
      final q = p / fallEnd;
      final eased = Curves.easeInCubic.transform(q);
      final startY = size.height * 0.12;
      final y = startY + (center.dy - startY) * eased;
      final fadeIn = (q / 0.12).clamp(0.0, 1.0);
      final squash = q > 0.88 ? (q - 0.88) / 0.12 : 0.0;
      final stretch = 1 + 0.16 * eased;
      final sy = stretch * (1 - 0.30 * squash);
      final sx = (1 / stretch) * (1 + 0.26 * squash);
      final r = 15.0;
      // 真实水滴受气流影响不会绝对垂直下落，加一点极轻微的横向摆动
      final sway = math.sin(q * math.pi * 1.4) * 1.8;

      final dropPath = _tearDrop(Size(r * 2, r * 2.9))
          .shift(Offset(-r + sway, -r * 1.45));

      canvas.save();
      canvas.translate(center.dx, y);
      canvas.scale(sx, sy);
      _paintGlossyDrop(canvas, dropPath, dropPath.getBounds(), r, fadeIn);
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
      final opacity = 0.85 * (1 - s);
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.30, -0.38),
            radius: 1.0,
            stops: const [0.0, 0.55, 1.0],
            colors: [
              Colors.white.withValues(alpha: opacity),
              accent.withValues(alpha: opacity),
              accent.withValues(alpha: opacity * 0.7),
            ],
          ).createShader(Rect.fromCircle(center: pos, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DropSplashPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.impactDy != impactDy;
}

/// 水滴轮廓：尖端较短、底部圆润饱满，接近参考图里的真实水珠
Path _tearDrop(Size s) {
  final w = s.width;
  final h = s.height;
  final cx = w / 2;
  final p = Path();
  p.moveTo(cx, 0);
  p.cubicTo(cx + w * 0.14, h * 0.18, cx + w * 0.50, h * 0.40,
      cx + w * 0.50, h * 0.68);
  p.cubicTo(cx + w * 0.50, h * 0.90, cx + w * 0.28, h, cx, h);
  p.cubicTo(cx - w * 0.28, h, cx - w * 0.50, h * 0.90,
      cx - w * 0.50, h * 0.68);
  p.cubicTo(cx - w * 0.50, h * 0.40, cx - w * 0.14, h * 0.18, cx, 0);
  p.close();
  return p;
}

/// 玻璃质感水珠：中心通透、边缘淡青、白色轮廓光 + 两处镜面高光
void _paintGlossyDrop(
  Canvas canvas,
  Path path,
  Rect bounds,
  double r,
  double alpha,
) {
  canvas.saveLayer(
    bounds.inflate(r * 0.4),
    Paint()..color = Colors.white.withValues(alpha: alpha),
  );
  canvas.clipPath(path);

  // 主体：中间近乎无色，越靠边缘越青，像真实水体的折射
  canvas.drawPath(
    path,
    Paint()
      ..isAntiAlias = true
      ..shader = const RadialGradient(
        center: Alignment(0.02, 0.18),
        radius: 0.95,
        stops: [0.0, 0.32, 0.68, 1.0],
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFF3FDFF),
          Color(0xFFD6F1F8),
          Color(0xFFA8DEEE),
        ],
      ).createShader(bounds),
  );

  // 尖端偏青、底部边缘回青，避免整颗水珠发白
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0.0, 0.38, 0.78, 1.0],
        colors: [
          Color(0x668FD6E6),
          Color(0x008FD6E6),
          Color(0x008FD6E6),
          Color(0x4D8FD6E6),
        ],
      ).createShader(bounds),
  );

  // 底部透光核心：大而柔的白色反光
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(r * 0.05, r * 0.62),
      width: r * 0.92,
      height: r * 1.15,
    ),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.78)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.20),
  );
  // 左上镜面高光
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(-r * 0.33, -r * 0.30),
      width: r * 0.40,
      height: r * 0.95,
    ),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.62)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.10),
  );
  // 右下小亮点
  canvas.drawCircle(
    Offset(r * 0.40, r * 0.50),
    r * 0.07,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.015),
  );

  // 白色轮廓光：参考图最明显的特征，左/下/右一圈，尖端自然淡出
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.16
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        stops: [0.0, 0.42, 0.8, 1.0],
        colors: [
          Color(0xFFFFFFFF),
          Color(0xE6FFFFFF),
          Color(0x66FFFFFF),
          Color(0x00FFFFFF),
        ],
      ).createShader(bounds)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.025),
  );

  canvas.restore();
}

/// 应用图标：直接复用图标库的默认图标（与桌面、设置页预览保持同一枚）
class _AppIconTile extends StatelessWidget {
  const _AppIconTile({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: AppIconPreview(size: size, id: kDefaultAppIconId),
    );
  }
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
