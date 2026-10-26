import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../drink/widgets/svg_container.dart';

/// 动物液体填充（对标原版 WaterLlama 首页效果）
///
/// 机制（v3 — 归一化渲染，修复不同角色大小比例不一致）：
/// 1. 光栅扫描 SVG 图形拿到真实 bounds（轮廓外留白不再干扰）
/// 2. 把 bounds 作为"有效图形单元"，**所有角色统一映射到盒子的 85%**
///    （等比缩放 + 居中），轮廓视觉占比完全一致
/// 3. 裁剪线从图形的 bottom 往上 fillRatio×图形高度（相对于归一化后的 bounds）
/// 4. 底层：染灰 SVG 剪影（始终显示，0% 进度态）
/// 5. 顶层：彩色 SVG，按 fillRatio 从图形底部裁剪 + 正弦波面
/// 6. fullArt=true（目标完成）：同样归一化缩放显示彩色 SVG
/// 7. PNG 遗留资源（onboarding 用）跳过 bounds 扫描，仍按 BoxFit.contain
class AnimalSilhouette extends StatefulWidget {
  const AnimalSilhouette({
    super.key,
    required this.animalId,
    required this.fillRatio,
    required this.accentColor,
    this.size = 260,
    this.solidFillColor,
    this.fullArt = false,
    this.phase,
  });

  final String animalId;
  final double fillRatio;
  final Color accentColor;
  final double size;
  final Color? solidFillColor;
  final bool fullArt;
  final double? phase;

  @override
  State<AnimalSilhouette> createState() => _AnimalSilhouetteState();
}

class _AnimalSilhouetteState extends State<AnimalSilhouette>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave;

  /// 光栅扫描得到的 bounds（viewBox 坐标系），缓存后复用
  SvgArtMetrics? _metrics;

  /// viewBox 尺寸（光栅化时同倍数缩放）
  Size _viewBox = Size.zero;

  /// 资源是否 PNG（PNG 跳过 bounds 扫描）
  bool get _isPng => _legacyPngPaths.containsKey(widget.animalId);

  /// 目标归一化占比：所有角色图形 bounds 映射到盒子的 85%
  static const _kTargetFraction = 0.85;

  /// 归一化后的渲染参数：把 bounds 缩放到盒子 85% 并居中
  /// 返回：渲染宽高（盒子坐标系）、图形 bounds 在盒子坐标系中的 top/bottom
  ({
    double renderW,
    double renderH,
    double dx,
    double dy,
    double renderTop,
    double renderBottom,
  }) _effectiveLayout() {
    if (_isPng || _metrics == null || _viewBox.isEmpty) {
      // PNG 或 bounds 还没算出来：fallback 按盒子高度撑满
      return (
        renderW: widget.size,
        renderH: widget.size,
        dx: 0.0,
        dy: 0.0,
        renderTop: 0.0,
        renderBottom: widget.size,
      );
    }
    final vb = _viewBox;
    final b = _metrics!.bounds;
    final bodyW = b.width;
    final bodyH = b.height;
    if (bodyW <= 0 || bodyH <= 0) {
      return (
        renderW: widget.size,
        renderH: widget.size,
        dx: 0.0,
        dy: 0.0,
        renderTop: 0.0,
        renderBottom: widget.size,
      );
    }

    // 目标区 = 盒子 × 目标占比，按图形原始高宽比等比缩放
    final target = widget.size * _kTargetFraction;
    final normScale = math.min(target / bodyW, target / bodyH);

    // SVG 在盒子里的渲染尺寸（viewBox 整体缩放）
    final renderW = vb.width * normScale;
    final renderH = vb.height * normScale;

    // 以图形真实 bounds 居中定位（而不是整张 viewBox 居中）：
    // 图形在画布里偏上/偏下时，老写法会把图形底部推出盒子，
    // 低进度（如 12%）的液面直接落到盒子外 → 有水量却看不到液体
    final dx = (widget.size - bodyW * normScale) / 2 - b.left * normScale;
    final dy = (widget.size - bodyH * normScale) / 2 - b.top * normScale;

    // 图形 bounds 在盒子坐标系中的位置（必定落在盒内）
    final bodyTop = dy + b.top * normScale;
    final bodyBottom = dy + b.bottom * normScale;

    return (
      renderW: renderW,
      renderH: renderH,
      dx: dx,
      dy: dy,
      renderTop: bodyTop,
      renderBottom: bodyBottom,
    );
  }

  static const _legacyPngPaths = <String, String>{
    'llama': 'assets/images/animal_llama_full.png',
    'panda': 'assets/images/animal_panda_full.png',
    'octopus': 'assets/images/animal_octopus_full.png',
  };

  static const _silhouetteGray = Color(0xFFEBEBEB);

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadMetrics();
  }

  @override
  void didUpdateWidget(covariant AnimalSilhouette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animalId != widget.animalId) _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    if (_isPng) return;
    final svgPath = 'assets/images/characters/${widget.animalId}.svg';
    final info = await vg.loadPicture(SvgAssetLoader(svgPath), null);
    if (!mounted) return;
    final vb = Size(info.size.width, info.size.height);
    _viewBox = vb;
    final metrics = await loadSvgArtMetrics(svgPath, info.picture, vb);
    if (!mounted) return;
    setState(() {
      _metrics = metrics;
    });
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  ({String path, bool isPng}) get _asset {
    final png = _legacyPngPaths[widget.animalId];
    if (png != null) return (path: png, isPng: true);
    return (
      path: 'assets/images/characters/${widget.animalId}.svg',
      isPng: false,
    );
  }

  Widget _buildArt({required bool grayscale}) {
    final a = _asset;
    Widget img;
    if (a.isPng) {
      img = Image.asset(
        a.path,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
      );
    } else {
      // 归一化后的 SVG 尺寸（宽高各自独立，保留 viewBox 比例）
      // 按 bounds 实际位置摆放，保证图形整体落在盒内
      final layout = _effectiveLayout();
      img = SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          children: [
            Positioned(
              left: layout.dx,
              top: layout.dy,
              width: layout.renderW,
              height: layout.renderH,
              child: SvgPicture.asset(a.path, fit: BoxFit.fill),
            ),
          ],
        ),
      );
    }
    if (!grayscale) return img;
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(_silhouetteGray, BlendMode.srcIn),
      child: img,
    );
  }

  Widget _buildLiquid(double wavePhase) {
    final layout = _effectiveLayout();
    final liquidChild = widget.solidFillColor != null
        ? _SolidLiquid(
            size: widget.size,
            color: widget.solidFillColor!,
            art: _buildArt(grayscale: false),
          )
        : _buildArt(grayscale: false);
    return ClipPath(
      clipper: _LiquidSurfaceClipper(
        fillRatio: widget.fillRatio,
        phase: wavePhase,
        artTop: layout.renderTop,
        artBottom: layout.renderBottom,
      ),
      child: liquidChild,
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;

    if (w.fullArt) {
      return SizedBox(
        width: w.size,
        height: w.size,
        child: _buildArt(grayscale: false),
      );
    }

    return SizedBox(
      width: w.size,
      height: w.size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildArt(grayscale: true),
          if (w.fillRatio > 0)
            if (w.phase != null)
              _buildLiquid(w.phase! * math.pi * 2)
            else
              AnimatedBuilder(
                animation: _wave,
                builder: (ctx, _) => _buildLiquid(_wave.value * math.pi * 2),
              ),
        ],
      ),
    );
  }
}

/// 液体表面波浪裁剪器：裁剪线相对于图形真实 bounds（归一化后的值）
class _LiquidSurfaceClipper extends CustomClipper<Path> {
  _LiquidSurfaceClipper({
    required this.fillRatio,
    required this.phase,
    required this.artTop,
    required this.artBottom,
  });

  final double fillRatio;
  final double phase;
  final double artTop;
  final double artBottom;

  @override
  Path getClip(Size size) {
    final bodyH = artBottom - artTop;
    if (bodyH <= 0) {
      final surfaceY = size.height * (1 - fillRatio.clamp(0.0, 1.0));
      return _wavePath(size.width, size.height, surfaceY);
    }
    final clamped = fillRatio.clamp(0.0, 1.0);
    final surfaceY = artBottom - clamped * bodyH;
    return _wavePath(size.width, size.height, surfaceY);
  }

  Path _wavePath(double w, double h, double surfaceY) {
    final path = Path()
      ..moveTo(0, h)
      ..lineTo(0, surfaceY);
    const samples = 24;
    for (var i = 1; i <= samples; i++) {
      final t = i / samples;
      final x = w * t;
      final wave = math.sin(t * math.pi * 2.0 + phase) * 2.5;
      path.lineTo(x, surfaceY + wave);
    }
    path
      ..lineTo(w, h)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _LiquidSurfaceClipper old) =>
      old.fillRatio != fillRatio ||
      old.phase != phase ||
      old.artTop != artTop ||
      old.artBottom != artBottom;
}

class _SolidLiquid extends StatelessWidget {
  const _SolidLiquid({
    required this.size,
    required this.color,
    required this.art,
  });

  final double size;
  final Color color;
  final Widget art;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          art,
          ColorFiltered(
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            child: art,
          ),
        ],
      ),
    );
  }
}
