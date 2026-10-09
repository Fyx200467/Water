import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/models/animal_character.dart';

/// PRD §2.2 流体从下至上填充动画
/// PRD §4.1 60fps 满帧
/// PRD §4.5 真实流体物理效果，禁止生硬跳变
///
/// 复合 CustomPainter：
/// - 容器（圆/瓶）
/// - 流体（双正弦波叠加 + 着色渐变 + 高光波纹）
/// - 动物形象（按水位遮罩 / 表情变化）
class FluidPainter extends CustomPainter {
  FluidPainter({
    required this.progress,         // 0..1 当前显示进度
    required this.animal,
    required this.wavePhase,        // 动画相位 0..2π
    required this.bounce,            // 提交时弹动余震 0..1
  });

  final double progress;
  final AnimalCharacter animal;
  final double wavePhase;
  final double bounce;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;

    // ---- 1. 容器外框（玻璃质感）----
    final glassPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, glassPaint);

    // 高光弧
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 4),
      math.pi * 1.15,
      math.pi * 0.35,
      false,
      highlightPaint,
    );

    // ---- 2. 裁剪到圆形内部，画流体 ----
    canvas.save();
    final clipPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius - 2));
    canvas.clipPath(clipPath);

    // 背景（动物居住区）
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          animal.bodyColor.withValues(alpha: 0.05),
          animal.bodyColor.withValues(alpha: 0.18),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bgPaint);

    // 水位高度（底部至上）
    // bounce：提交瞬间水位上涌，逐渐回稳
    final bounceBoost = math.sin(bounce * math.pi) * 0.05;
    final waterLevelRatio = (progress + bounceBoost).clamp(0.0, 1.0);
    final waterTop = center.dy + radius - (2 * radius * waterLevelRatio);

    // 双正弦波叠加
    final wavePath = Path();
    wavePath.moveTo(center.dx - radius, waterTop);
    const samples = 60;
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final x = center.dx - radius + 2 * radius * t;
      final w1 = math.sin(t * math.pi * 2 + wavePhase) * 4;
      final w2 = math.sin(t * math.pi * 4 + wavePhase * 1.6) * 2;
      final y = waterTop + w1 + w2;
      wavePath.lineTo(x, y);
    }
    wavePath.lineTo(center.dx + radius, center.dy + radius);
    wavePath.lineTo(center.dx - radius, center.dy + radius);
    wavePath.close();

    // 流体填充渐变 — 零高度时降级为纯色，避免 Web CanvasKit shader 崩溃
    final waterRect = Rect.fromLTRB(
      center.dx - radius, waterTop,
      center.dx + radius, center.dy + radius,
    );
    final waterPaint = Paint();
    if (waterRect.height > 1) {
      waterPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.fluidHighlight,
          AppTheme.fluidColor,
          AppTheme.fluidDark,
        ],
      ).createShader(waterRect);
    } else {
      waterPaint.color = AppTheme.fluidColor;
    }
    canvas.drawPath(wavePath, waterPaint);

    // 高光波纹（薄薄一条）
    final surfacePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final surfacePath = Path();
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final x = center.dx - radius + 2 * radius * t;
      final w1 = math.sin(t * math.pi * 2 + wavePhase) * 4;
      final w2 = math.sin(t * math.pi * 4 + wavePhase * 1.6) * 2;
      final y = waterTop + w1 + w2;
      if (i == 0) {
        surfacePath.moveTo(x, y);
      } else {
        surfacePath.lineTo(x, y);
      }
    }
    canvas.drawPath(surfacePath, surfacePaint);

    // ---- 3. 动物形象（身体） ----
    // 简易风格：圆形身体 + 椭圆头 + 椭圆耳朵 + 黑点眼 + 嘴
    _drawAnimal(canvas, center, radius * 0.55, waterTop);

    canvas.restore();
  }

  void _drawAnimal(Canvas canvas, Offset center, double bodyR, double waterTop) {
    // 被水淹没的表情：水位 > 头部位置 -> 惊讶（眼瞪大）
    final headDy = center.dy - bodyR * 0.55;
    final headInWater = headDy > waterTop;

    // 身体
    final bodyPaint = Paint()
      ..color = animal.bodyColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, bodyR, bodyPaint);

    // 黑色描边
    final strokePaint = Paint()
      ..color = animal.primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, bodyR, strokePaint);

    // 头
    final headCenter = Offset(center.dx, headDy);
    canvas.drawCircle(headCenter, bodyR * 0.55, bodyPaint);
    canvas.drawCircle(headCenter, bodyR * 0.55, strokePaint);

    // 耳朵（小椭圆，两侧）
    final earPaint = Paint()
      ..color = animal.bodyColor
      ..style = PaintingStyle.fill;
    final earStroke = Paint()
      ..color = animal.primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final sign in [-1, 1]) {
      canvas.save();
      canvas.translate(headCenter.dx + sign * bodyR * 0.35, headCenter.dy - bodyR * 0.3);
      canvas.rotate(sign * 0.5);
      final earR = Rect.fromCenter(center: Offset.zero, width: bodyR * 0.25, height: bodyR * 0.45);
      canvas.drawOval(earR, earPaint);
      canvas.drawOval(earR, earStroke);
      canvas.restore();
    }

    // 眼睛
    final eyePaint = Paint()
      ..color = animal.primaryColor == Colors.white ? Colors.black : animal.primaryColor
      ..style = PaintingStyle.fill;
    final eyeRadius = headInWater ? bodyR * 0.10 : bodyR * 0.07;
    for (final sign in [-1, 1]) {
      canvas.drawCircle(
        Offset(headCenter.dx + sign * bodyR * 0.15, headCenter.dy - bodyR * 0.04),
        eyeRadius,
        eyePaint,
      );
    }

    // 嘴
    final mouthPaint = Paint()
      ..color = animal.primaryColor == Colors.white ? Colors.black : animal.primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (headInWater) {
      // 惊讶：小圆 O
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(headCenter.dx, headCenter.dy + bodyR * 0.18),
          width: bodyR * 0.12,
          height: bodyR * 0.15,
        ),
        mouthPaint,
      );
    } else {
      // 微笑弧
      final mouthRect = Rect.fromCenter(
        center: Offset(headCenter.dx, headCenter.dy + bodyR * 0.12),
        width: bodyR * 0.3,
        height: bodyR * 0.2,
      );
      canvas.drawArc(mouthRect, 0.1 * math.pi, 0.8 * math.pi, false, mouthPaint);
    }

    // 脸颊红晕
    final blushPaint = Paint()..color = const Color(0xFFFF8FA3).withValues(alpha: 0.5);
    for (final sign in [-1, 1]) {
      canvas.drawCircle(
        Offset(headCenter.dx + sign * bodyR * 0.28, headCenter.dy + bodyR * 0.08),
        bodyR * 0.07,
        blushPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FluidPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.wavePhase != wavePhase ||
        oldDelegate.bounce != bounce ||
        oldDelegate.animal.id != animal.id;
  }
}
