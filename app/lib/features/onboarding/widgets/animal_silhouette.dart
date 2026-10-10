import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 动物剪影（实心剪影蒙版 + 分层饮料色液体填充）
///
/// 复现原版效果：
/// - 7 层粗色带，饮品色（粉/绿/灰蓝/蓝/红/酒红/黄）
/// - 每层顶部是起伏的水面线（波浪边界），像真实分层饮料
/// - 自上而下绘制：每层从自己的水面线填到形状底部，下层覆盖上层 → 无缺口
/// - 蒙版矩阵带对比度：只有接近纯黑的像素不透明，消除 JPEG 灰边
class AnimalSilhouette extends StatefulWidget {
  const AnimalSilhouette({
    super.key,
    required this.animalId,
    required this.fillRatio,
    required this.accentColor,
    this.size = 260,
  });

  final String animalId;
  final double fillRatio;
  final Color accentColor;
  final double size;

  @override
  State<AnimalSilhouette> createState() => _AnimalSilhouetteState();
}

class _AnimalSilhouetteState extends State<AnimalSilhouette>
    with SingleTickerProviderStateMixin {
  ui.Image? _image;

  /// 波动动画驱动器：水面持续晃动
  late final AnimationController _wave;

  /// 动物 ID → 实心剪影资源路径
  static const _assetPaths = <String, String>{
    'llama': 'assets/images/animal_llama_solid.jpg',
    'panda': 'assets/images/animal_panda_solid.jpg',
    'tiger': 'assets/images/animal_tiger_solid.jpg',
    'fox': 'assets/images/animal_llama_solid.jpg',
    'penguin': 'assets/images/animal_panda_solid.jpg',
  };

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _loadImage();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final path = _assetPaths[widget.animalId] ?? _assetPaths['llama']!;
    try {
      final data = await rootBundle.load(path);
      final bytes = data.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _image = frame.image);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: _image == null
          ? const SizedBox.shrink()
          : AnimatedBuilder(
              animation: _wave,
              builder: (ctx, _) => CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _ImageSilhouettePainter(
                  image: _image!,
                  fillRatio: widget.fillRatio,
                  phase: _wave.value * math.pi * 2,
                ),
              ),
            ),
    );
  }
}

class _ImageSilhouettePainter extends CustomPainter {
  _ImageSilhouettePainter({
    required this.image,
    required this.fillRatio,
    required this.phase,
  });

  final ui.Image image;
  final double fillRatio;
  final double phase;

  /// 7 色饮品色带（从下到上 = 第一杯饮料在底部）
  static const _colorBands = <Color>[
    Color(0xFFF28BAA), // 粉（草莓奶）
    Color(0xFF7CB342), // 绿（抹茶）
    Color(0xFFB0C4D4), // 灰蓝（椰水）
    Color(0xFF3D6FE0), // 蓝（纯水）
    Color(0xFFE05252), // 红（果汁）
    Color(0xFF8E3B4E), // 酒红（红酒）
    Color(0xFFF5C542), // 黄（橙汁）
  ];

  /// 高对比蒙版：只有接近纯黑的像素不透明（白色/灰色背景全透明）
  static const _whiteToTransparent = ColorFilter.matrix(<double>[
    0, 0, 0, 0, 0, //
    0, 0, 0, 0, 0, //
    0, 0, 0, 0, 0, //
    -2, -2, -2, 0, 510, //
  ]);

  @override
  void paint(Canvas canvas, Size size) {
    final srcW = image.width.toDouble();
    final srcH = image.height.toDouble();
    // 裁掉图片外圈留白，让动物占满绘制区
    const crop = 0.82;
    final srcRect = Rect.fromCenter(
      center: Offset(srcW / 2, srcH / 2),
      width: srcW * crop,
      height: srcH * crop,
    );
    final dst = _fitContain(srcRect.width, srcRect.height, size.width, size.height);

    // 色带画进离屏层，再用剪影蒙版裁出动物形状
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawImageRect(
      image,
      srcRect,
      dst,
      Paint()..colorFilter = _whiteToTransparent,
    );
    _drawLiquidLayers(canvas, dst, BlendMode.srcIn);
    canvas.restore();
  }

  /// 分层液体：自上而下画，每层从水面线填到底部，下层覆盖上层
  void _drawLiquidLayers(Canvas canvas, Rect dst, BlendMode blend) {
    if (fillRatio <= 0) return;

    final bandCount = _colorBands.length;
    final bandHeight = dst.height / bandCount;
    final fillBottom = dst.bottom;
    final totalFill = dst.height * fillRatio;
    final fullLayers = (totalFill / bandHeight).floor().clamp(0, bandCount);
    final partial = (totalFill / bandHeight) - fullLayers;

    // 表面 y 坐标（从高到低）。partial > 0 时最高表面是当前水面
    final surfaces = <double>[];
    if (partial > 0 && fullLayers < bandCount) {
      surfaces.add(fillBottom - totalFill);
    }
    for (var i = fullLayers - 1; i >= 0; i--) {
      surfaces.add(fillBottom - (i + 1) * bandHeight);
    }

    for (var s = 0; s < surfaces.length; s++) {
      final colorIndex =
          partial > 0 ? fullLayers - s : fullLayers - 1 - s;
      if (colorIndex < 0 || colorIndex >= bandCount) continue;
      _drawLiquidBody(
        canvas, dst, surfaces[s], _colorBands[colorIndex], blend,
      );
    }
  }

  /// 从波动水面线填充到形状底部
  void _drawLiquidBody(
    Canvas canvas,
    Rect dst,
    double surfaceY,
    Color color,
    BlendMode blend,
  ) {
    if (surfaceY >= dst.bottom) return;
    final top = surfaceY.clamp(dst.top - 8, dst.bottom);
    final path = Path()
      ..moveTo(dst.left, dst.bottom)
      ..lineTo(dst.left, top);
    const samples = 24;
    for (var i = 1; i <= samples; i++) {
      final t = i / samples;
      final x = dst.left + dst.width * t;
      // 波浪：2.5 个周期，振幅 5px，每层相位不同
      final wave =
          math.sin(t * math.pi * 2.5 + phase + surfaceY * 0.05) * 5;
      path.lineTo(x, top + wave);
    }
    path
      ..lineTo(dst.right, dst.bottom)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..blendMode = blend,
    );
  }

  /// contain 模式适配
  Rect _fitContain(double srcW, double srcH, double dstW, double dstH) {
    final scale = math.min(dstW / srcW, dstH / srcH);
    final w = srcW * scale;
    final h = srcH * scale;
    return Rect.fromCenter(
      center: Offset(dstW / 2, dstH / 2),
      width: w,
      height: h,
    );
  }

  @override
  bool shouldRepaint(covariant _ImageSilhouettePainter old) {
    return old.fillRatio != fillRatio ||
        old.image != image ||
        old.phase != phase;
  }
}
