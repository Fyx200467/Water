import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 动物液体填充（对标原版 WaterLlama 欢迎页效果）
///
/// 复现要点：
/// - 全彩卡通插画（透明背景 PNG）
/// - 空杯态：纯浅灰实心剪影（另一种白），轮廓边界完整清晰
/// - 填充：饮料色带自上而下堆叠（每层从自己的波浪水面线填到底部，下层覆盖上层）
/// - 色带用图片 alpha 做 dstIn 蒙版 → 只显示在动物轮廓内
class AnimalSilhouette extends StatefulWidget {
  const AnimalSilhouette({
    super.key,
    required this.animalId,
    required this.fillRatio,
    required this.accentColor,
    this.size = 260,
    this.solidFillColor,
    this.fullArt = false,
  });

  final String animalId;
  final double fillRatio;
  final Color accentColor;
  final double size;
  /// 非空时用纯色填充（从底部按 fillRatio 高度填充），不画多色色带
  final Color? solidFillColor;
  /// true 时叠加全彩插画（五官可见）；false 时只有轮廓剪影（对标原版：目标未完成不显示今日角色插画）
  final bool fullArt;

  @override
  State<AnimalSilhouette> createState() => _AnimalSilhouetteState();
}

class _AnimalSilhouetteState extends State<AnimalSilhouette>
    with SingleTickerProviderStateMixin {
  ui.Image? _image;

  /// 波动动画驱动器：水面持续晃动
  late final AnimationController _wave;

  /// 随机色带：每次挂载生成 10 层柔和随机色，层间色相不重复
  late final List<Color> _bandColors = _generateRandomBands();

  /// 动物 ID → 全彩插画资源（透明背景 PNG）
  static const _assetPaths = <String, String>{
    'octopus': 'assets/images/animal_octopus_full.png',
    'llama': 'assets/images/animal_llama_full.png',
    'panda': 'assets/images/animal_panda_full.png',
    'tiger': 'assets/images/animal_octopus_full.png',
    'fox': 'assets/images/animal_octopus_full.png',
    'penguin': 'assets/images/animal_panda_full.png',
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

  /// 生成 10 层低饱和柔和随机色（色相两两不重复，间隔 ≥ 28°）
  List<Color> _generateRandomBands() {
    final rnd = math.Random();
    double hueDist(double a, double b) {
      final d = (a - b).abs() % 360;
      return d > 180 ? 360 - d : d;
    }

    final hues = <double>[];
    var guard = 0;
    while (hues.length < 10 && guard++ < 400) {
      final h = rnd.nextDouble() * 360;
      if (hues.every((e) => hueDist(e, h) >= 28)) hues.add(h);
    }
    // 兜底：随机挑不够 10 个时按 36° 均匀补齐
    while (hues.length < 10) {
      hues.add(hues.length * 36.0);
    }
    hues.shuffle(rnd);
    return [
      for (final h in hues)
        HSLColor.fromAHSL(
          1,
          h,
          0.65 + rnd.nextDouble() * 0.20, // 高饱和，颜色鲜艳
          0.55 + rnd.nextDouble() * 0.12, // 中等亮度，避免粉彩暗淡
        ).toColor(),
    ];
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
                painter: _AnimalFillPainter(
                  image: _image!,
                  fillRatio: widget.fillRatio,
                  phase: _wave.value * math.pi * 2,
                  bandColors: _bandColors,
                  solidFillColor: widget.solidFillColor,
                  fullArt: widget.fullArt,
                ),
              ),
            ),
    );
  }
}

class _AnimalFillPainter extends CustomPainter {
  _AnimalFillPainter({
    required this.image,
    required this.fillRatio,
    required this.phase,
    required this.bandColors,
    this.solidFillColor,
    this.fullArt = false,
  });

  final ui.Image image;
  final double fillRatio;
  final double phase;
  final Color? solidFillColor;
  final bool fullArt;

  /// 随机柔和色带（10 层，层间色相不重复），由外层生成保证逐帧稳定
  final List<Color> bandColors;

  /// 空杯态剪影色：比页面纯白稍深的「另一种白」，保证轮廓边界完整清晰
  static const _silhouetteGray = Color(0xFFEBEBEB);

  @override
  void paint(Canvas canvas, Size size) {
    final srcW = image.width.toDouble();
    final srcH = image.height.toDouble();
    const crop = 0.82; // 裁掉四周留白，动物占满绘制区
    final srcRect = Rect.fromCenter(
      center: Offset(srcW / 2, srcH / 2),
      width: srcW * crop,
      height: srcH * crop,
    );
    final dst =
        _fitContain(srcRect.width, srcRect.height, size.width, size.height);

    // 目标已完成 → 直接显示全彩插画
    if (fullArt) {
      canvas.drawImageRect(image, srcRect, dst, Paint());
      return;
    }

    // 1. 底层：纯浅灰实心剪影（灰块经图片 alpha 蒙版裁形），
    //    未填充时也有完整清晰的轮廓边界，对标原版空杯效果
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(dst, Paint()..color = _silhouetteGray);
    canvas.drawImageRect(
      image,
      srcRect,
      dst,
      Paint()..blendMode = BlendMode.dstIn,
    );
    canvas.restore();

    if (fillRatio <= 0) return;

    // 2. 色带画进离屏层，再用图片 alpha 做 dstIn 蒙版裁出动物形状
    canvas.saveLayer(Offset.zero & size, Paint());
    if (solidFillColor != null) {
      _drawSolidLiquid(canvas, dst, solidFillColor!);
    } else {
      _drawLiquidLayers(canvas, dst);
    }
    canvas.drawImageRect(
      image,
      srcRect,
      dst,
      Paint()..blendMode = BlendMode.dstIn,
    );
    canvas.restore();
  }

  /// 纯色液体：从底部按 fillRatio 高度填充，顶部波浪面晃动
  void _drawSolidLiquid(Canvas canvas, Rect dst, Color color) {
    final surfaceY = dst.bottom - dst.height * fillRatio;
    _drawLiquidBody(canvas, dst, surfaceY, color);
  }

  /// 分层液体：自上而下画，每层从水面线填到底部，下层覆盖上层
  void _drawLiquidLayers(Canvas canvas, Rect dst) {
    final bandCount = bandColors.length;
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
      final colorIndex = partial > 0 ? fullLayers - s : fullLayers - 1 - s;
      if (colorIndex < 0 || colorIndex >= bandCount) continue;
      _drawLiquidBody(canvas, dst, surfaces[s], bandColors[colorIndex]);
    }
  }

  /// 从波动水面线填充到形状底部
  void _drawLiquidBody(Canvas canvas, Rect dst, double surfaceY, Color color) {
    if (surfaceY >= dst.bottom) return;
    final top = surfaceY.clamp(dst.top - 8, dst.bottom);
    final path = Path()
      ..moveTo(dst.left, dst.bottom)
      ..lineTo(dst.left, top);
    const samples = 24;
    for (var i = 1; i <= samples; i++) {
      final t = i / samples;
      final x = dst.left + dst.width * t;
      // 波浪：2 个周期，振幅 2.5px（幅度调小更自然），每层相位不同
      final wave = math.sin(t * math.pi * 2.0 + phase + surfaceY * 0.05) * 2.5;
      path.lineTo(x, top + wave);
    }
    path
      ..lineTo(dst.right, dst.bottom)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
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
  bool shouldRepaint(covariant _AnimalFillPainter old) {
    return old.fillRatio != fillRatio ||
        old.image != image ||
        old.phase != phase ||
        old.bandColors != bandColors ||
        old.solidFillColor != solidFillColor ||
        old.fullArt != fullArt;
  }
}
