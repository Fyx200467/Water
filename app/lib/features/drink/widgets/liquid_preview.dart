import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../settings/settings_flags.dart';
import 'svg_container.dart';

/// 动态液体预览（添加饮品页 / 图标 / 颜色 / 动画选择页共用）：
/// 灰底 SVG 容器剪影 + 液体层（波面晃动 + 按动画选项渲染粒子），
/// 液体经 SVG alpha 蒙版（BlendMode.dstIn）裁剪进容器形状。
/// 液面默认接近杯口但保留气隙（fillRatio 0.75），对标内置饮品的满杯观感。
class LiquidPreview extends StatefulWidget {
  const LiquidPreview({
    super.key,
    required this.containerId,
    required this.color,
    this.animation = 'bubbles',
    this.fillRatio = 0.75,
    this.width = 170,
    this.height = 225,
  });

  final String containerId;

  /// 液体颜色（实时渲染）
  final Color color;

  /// 动画 key：bubbles / micro / ice / rice / none
  final String animation;

  /// 液面比例 0~1（1 = 齐杯口）
  final double fillRatio;

  final double width;
  final double height;

  @override
  State<LiquidPreview> createState() => _LiquidPreviewState();
}

class _LiquidPreviewState extends State<LiquidPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  /// 连续时间时钟：驱动波形/气泡/米粒的相位（永不跳回）
  final Stopwatch _clock = Stopwatch()..start();

  // SVG 容器 alpha 蒙版 + 图形度量（异步加载）
  ui.Picture? _maskPicture;
  Size _maskViewBox = Size.zero;
  SvgArtMetrics? _metrics;
  String? _loadedMaskId;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadMask();
  }

  @override
  void didUpdateWidget(LiquidPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.containerId != widget.containerId) {
      _loadMask();
    }
  }

  /// 加载 SVG 容器的 alpha 蒙版与图形度量；同一容器只加载一次
  Future<void> _loadMask() async {
    if (_failed) return;
    final id = widget.containerId;
    if (!isSvgContainer(id)) return;
    if (_loadedMaskId == id && _maskPicture != null) return;
    final loadingId = id;
    try {
      final info = await vg.loadPicture(
        SvgAssetLoader(svgContainerAsset(loadingId)),
        context,
      );
      final metrics = await loadSvgArtMetrics(
        loadingId,
        info.picture,
        info.size,
      );
      if (mounted) {
        setState(() {
          _maskPicture = info.picture;
          _maskViewBox = info.size;
          _metrics = metrics;
          _loadedMaskId = loadingId;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return SizedBox(width: widget.width, height: widget.height);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => SizedBox(
        width: widget.width,
        height: widget.height,
        child: CustomPaint(
          painter: LiquidPainter(
            color: widget.color,
            animation: widget.animation,
            fillRatio: widget.fillRatio,
            // 连续时钟秒数（_ctrl 仅驱动重绘）：循环控制器 value 跳回 0
            // 会让波形/气泡相位瞬间倒流产生周期性抽搐，连续时钟则永不跳变
            t: _clock.elapsedMilliseconds / 1000,
            maskPicture: _maskPicture,
            maskViewBox: _maskViewBox,
            metrics: _metrics,
          ),
        ),
      ),
    );
  }
}

/// 液体自绘（SVG 蒙版模式）：
/// - 空容器剪影染浅灰，液体层（液面多重正弦晃动 + 粒子）经 SVG alpha 蒙版
///   （dstIn）裁剪进容器形状
/// - bubbles：气泡自底部升起，上升途中渐显、顶端渐散
/// - micro：微气泡（数量多、体积小、上升更快）
/// - ice：冰块悬浮于液面下方，带轻微上下浮动与旋转
/// - rice：米粒悬浮于液体中，轻微上下浮动（粥类）
class LiquidPainter extends CustomPainter {
  LiquidPainter({
    required this.color,
    required this.animation,
    required this.t,
    this.fillRatio = 0.75,
    this.maskPicture,
    this.maskViewBox = Size.zero,
    this.metrics,
  });

  final Color color;
  final String animation;
  final double t;
  final double fillRatio;

  /// SVG 容器 alpha 蒙版（非空时才绘制）
  final ui.Picture? maskPicture;
  final Size maskViewBox;

  /// 容器图形度量（包围盒 + 杯口沿），null 时回退画框估算
  final SvgArtMetrics? metrics;

  /// 将 viewBox 坐标系的 SVG Picture 非等比铺满目标 size
  void _drawMaskScaled(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / maskViewBox.width,
      size.height / maskViewBox.height,
    );
    canvas.drawPicture(maskPicture!);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (maskPicture == null || maskViewBox.isEmpty) return;

    // 1. 空容器剪影染浅灰（与图标选择页网格剪影同色）
    canvas.saveLayer(Offset.zero & size, Paint());
    _drawMaskScaled(canvas, size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = const Color(0xFFE2E2E7)
        ..blendMode = BlendMode.srcIn,
    );
    canvas.restore();

    // 2. 液体内容，随后按 SVG alpha 蒙版裁剪进容器形状
    canvas.saveLayer(Offset.zero & size, Paint());
    _paintLiquid(canvas, size);
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..blendMode = BlendMode.dstIn,
    );
    _drawMaskScaled(canvas, size);
    canvas.restore();
    canvas.restore();
  }

  void _paintLiquid(Canvas canvas, Size size) {
    // 液体范围按容器图形包围盒对齐（源文件留白各异，不能按画框估算）
    const inset = 9.0;
    final m = metrics;
    final Rect art = m == null
        ? Rect.fromLTRB(
            inset + 7, inset + 7, size.width - inset - 7, size.height - inset - 7)
        : Rect.fromLTRB(
            m.bounds.left / maskViewBox.width * size.width,
            m.bounds.top / maskViewBox.height * size.height,
            m.bounds.right / maskViewBox.width * size.width,
            m.bounds.bottom / maskViewBox.height * size.height,
          );
    final body = m == null
        ? art.top
        : m.bodyTop / maskViewBox.height * size.height;

    final left = art.left;
    final right = art.right;
    final bottom = art.bottom + 0.5;
    // 液面：相对杯身高度，接近杯口但保留气隙；不高于杯口沿
    final baseLevel = math.max(body, bottom - (bottom - body) * fillRatio);
    final step = math.max(2.0, (right - left) / 48);

    // 液面晃动：复用首页加水页水杯同款效果——空间正弦波沿杯宽流动
    // （满杯宽一个整波、振幅 3px，相位 1.6s 走满 2π 即一个整波周期，
    // 与水杯 phase=value·2π 完全同构同步），液面有波峰波谷
    double surfaceY(double x) => baseLevel +
        math.sin((x - left) / (right - left) * math.pi * 2 +
                t * math.pi * 2 / 1.6) *
        3;

    // 液体主体
    final liquid = Path()
      ..moveTo(left, bottom)
      ..lineTo(left, surfaceY(left));
    for (double x = left + step; x < right; x += step) {
      liquid.lineTo(x, surfaceY(x));
    }
    liquid
      ..lineTo(right, surfaceY(right))
      ..lineTo(right, bottom)
      ..close();
    canvas.drawPath(liquid, Paint()..color = color);

    // 液面高光
    final highlight = Path()..moveTo(left, surfaceY(left));
    for (double x = left + step; x < right; x += step) {
      highlight.lineTo(x, surfaceY(x));
    }
    highlight.lineTo(right, surfaceY(right));
    canvas.drawPath(
      highlight,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // 粒子层（按动画选项）
    final paint = Paint();
    switch (animation) {
      case 'bubbles':
        drawRisingBubbles(
          canvas,
          liquidColor: color,
          left: left,
          right: right,
          bottom: bottom,
          surface: baseLevel, // 与首页水杯一致：气泡消散判断用液面基准线
          refDepth: bottom - body,
          floorY: bottom, // 预览无 ml 语义：液底即可生成
          tSeconds: t,
          count: 5,
          seed: 5,
        );
      case 'micro':
        drawRisingBubbles(
          canvas,
          liquidColor: color,
          left: left,
          right: right,
          bottom: bottom,
          surface: baseLevel,
          refDepth: bottom - body,
          floorY: bottom,
          tSeconds: t,
          count: 8,
          sizeScale: 0.6,
          seed: 9,
        );
      case 'ice':
        // 「杯子里的动画」总开关关闭：冰块停画
        if (!SettingsFlags.instance.cupAnimations) break;
        final iceSize =
            (math.min(right - left, bottom - baseLevel) * 0.3)
                .clamp(12.0, 34.0);
        for (int i = 0; i < 2; i++) {
          final bob = math.sin(t * 1.2 + i * 2.1) * 4;
          final rot = math.sin(t * 0.8 + i * 1.4) * 0.10;
          final cx = left + (right - left) * (i == 0 ? 0.36 : 0.66);
          final cy = surfaceY(cx) + 20 + bob;
          canvas.save();
          canvas.translate(cx, cy);
          canvas.rotate(rot);
          final rect = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: iceSize, height: iceSize),
            Radius.circular(iceSize * 0.24),
          );
          paint.color = Colors.white.withValues(alpha: 0.62);
          canvas.drawRRect(rect, paint);
          paint
            ..color = Colors.white.withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
          canvas.drawRRect(rect, paint);
          paint.style = PaintingStyle.fill;
          canvas.restore();
        }
      case 'rice':
        // 「杯子里的动画」总开关关闭：米粒停画
        if (!SettingsFlags.instance.cupAnimations) break;
        // 米粒分布在满杯固定区间（8%~85% 液深），不随当前液面压缩；
        // 高于当前液面的米粒跳过（低液量时自然隐藏，与气泡同哲学）
        final fullDepth = bottom - body;
        for (int i = 0; i < 10; i++) {
          final gy = body + fullDepth * (0.08 + _rnd(i, 9) * 0.77);
          if (gy < baseLevel + 4) continue; // 液面之上（含浮动余量）不显示
          final cy = gy + math.sin(t * 1.1 + i * 1.3) * 3;
          final cx = left + _rnd(i, 5) * (right - left);
          canvas.save();
          canvas.translate(cx, cy);
          canvas.rotate(_rnd(i, 11) * math.pi);
          paint.color = Colors.white.withValues(alpha: 0.78);
          canvas.drawOval(
            Rect.fromCenter(
                center: Offset.zero, width: 7, height: 4.2),
            paint,
          );
          canvas.restore();
        }
      case 'leaves':
        // 茶叶：沉在容器底部（与首页绿茶同款 drawTeaLeaves）
        drawTeaLeaves(
          canvas,
          liquidColor: color,
          left: left,
          right: right,
          bottom: bottom,
          top: body,
          surface: baseLevel,
          tSeconds: t,
          seed: 13,
        );
      case 'none':
        break;
    }
  }

  /// 确定性伪随机（每帧稳定，无抖动）
  double _rnd(int i, int salt) {
    final v =
        math.sin((i + 1) * 12.9898 + salt * 78.233) * 43758.5453;
    return v - v.floor();
  }

  @override
  bool shouldRepaint(LiquidPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.animation != animation ||
      oldDelegate.t != t ||
      oldDelegate.fillRatio != fillRatio ||
      oldDelegate.maskPicture != maskPicture ||
      oldDelegate.maskViewBox != maskViewBox ||
      oldDelegate.metrics != metrics;
}
