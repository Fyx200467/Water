import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 顶部快速轮换的饮料杯（对标原版双手+水杯，改为单独水杯快速切换）
///
/// 每秒左右快速轮换：红酒杯→汽水→咖啡→果汁→水杯
/// 每种杯子形状+颜色都不同
class BeverageCup extends StatefulWidget {
  const BeverageCup({super.key, this.size = 56, this.frozen = false});

  final double size;
  /// true 时停止轮换，定格为单滴水形状
  final bool frozen;

  @override
  State<BeverageCup> createState() => _BeverageCupState();
}

class _BeverageCupState extends State<BeverageCup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  static const List<_BeverageSpec> _cups = [
    _BeverageSpec(type: _CupType.wine, liquidColor: Color(0xFF722F37), label: '红酒'),
    _BeverageSpec(type: _CupType.soda, liquidColor: Color(0xFFC9302C), label: '汽水'),
    _BeverageSpec(type: _CupType.coffee, liquidColor: Color(0xFF6F4E37), label: '咖啡'),
    _BeverageSpec(type: _CupType.juice, liquidColor: Color(0xFFFF8C42), label: '果汁'),
    _BeverageSpec(type: _CupType.water, liquidColor: Color(0xFF4DB8D8), label: '水'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    // 每秒切换一次，左右摆动
    _ctrl.repeat(min: 0, max: 1, reverse: true, period: const Duration(milliseconds: 800));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 定格模式：显示单滴水（不再轮换）
    if (widget.frozen) {
      return CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _WaterDropPainter(),
      );
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        // 用时间戳选杯子，让它快速轮换
        final t = DateTime.now().millisecondsSinceEpoch ~/ 800;
        final cup = _cups[t % _cups.length];
        // 左右摆动动画
        final sway = (math.sin(_ctrl.value * math.pi * 2) * 0.15);
        return Transform.rotate(
          angle: sway,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _CupPainter(spec: cup),
          ),
        );
      },
    );
  }
}

/// 单滴水形状（对标原版开屏顶部水滴图标）
class _WaterDropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFF6BC8E8), Color(0xFF4DB8D8)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    // 水滴路径：上尖下圆
    final path = Path()
      ..moveTo(cx, h * 0.05)
      ..cubicTo(cx - w * 0.18, h * 0.32, cx - w * 0.28, h * 0.55, cx - w * 0.20, h * 0.72)
      ..cubicTo(cx - w * 0.10, h * 0.92, cx + w * 0.10, h * 0.92, cx + w * 0.20, h * 0.72)
      ..cubicTo(cx + w * 0.28, h * 0.55, cx + w * 0.18, h * 0.32, cx, h * 0.05)
      ..close();
    canvas.drawPath(path, paint);
    // 高光
    final hi = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx - w * 0.06, h * 0.45), width: w * 0.10, height: h * 0.20),
      math.pi * 1.1, math.pi * 0.45, false, hi,
    );
  }

  @override
  bool shouldRepaint(covariant _WaterDropPainter old) => false;
}

enum _CupType { wine, soda, coffee, juice, water }

class _BeverageSpec {
  const _BeverageSpec({required this.type, required this.liquidColor, required this.label});
  final _CupType type;
  final Color liquidColor;
  final String label;
}

class _CupPainter extends CustomPainter {
  _CupPainter({required this.spec});
  final _BeverageSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    final glassPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFFCBD3DC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final liquidPaint = Paint()..color = spec.liquidColor;

    switch (spec.type) {
      case _CupType.wine:
        // 高脚杯：碗+茎+底座
        final bowlPath = Path()
          ..moveTo(cx - w * 0.32, h * 0.15)
          ..quadraticBezierTo(cx - w * 0.38, h * 0.5, cx - w * 0.12, h * 0.52)
          ..lineTo(cx + w * 0.12, h * 0.52)
          ..quadraticBezierTo(cx + w * 0.38, h * 0.5, cx + w * 0.32, h * 0.15)
          ..close();
        canvas.drawPath(bowlPath, glassPaint);
        canvas.drawPath(bowlPath, strokePaint);
        // 酒液（碗下半部）
        final liquidPath = Path()
          ..moveTo(cx - w * 0.28, h * 0.38)
          ..quadraticBezierTo(cx - w * 0.34, h * 0.5, cx - w * 0.12, h * 0.52)
          ..lineTo(cx + w * 0.12, h * 0.52)
          ..quadraticBezierTo(cx + w * 0.34, h * 0.5, cx + w * 0.28, h * 0.38)
          ..close();
        canvas.drawPath(liquidPath, liquidPaint);
        // 茎
        canvas.drawRect(
          Rect.fromCenter(center: Offset(cx, h * 0.68), width: w * 0.08, height: h * 0.22),
          glassPaint,
        );
        canvas.drawRect(
          Rect.fromCenter(center: Offset(cx, h * 0.68), width: w * 0.08, height: h * 0.22),
          strokePaint,
        );
        // 底座
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, h * 0.88), width: w * 0.4, height: h * 0.07),
          glassPaint,
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, h * 0.88), width: w * 0.4, height: h * 0.07),
          strokePaint,
        );
        break;

      case _CupType.soda:
        // 易拉罐：圆柱+拉环
        final canRect = Rect.fromCenter(
          center: Offset(cx, h * 0.5),
          width: w * 0.5,
          height: h * 0.7,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(canRect, const Radius.circular(4)),
          liquidPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(canRect, const Radius.circular(4)),
          strokePaint,
        );
        // 高光
        final hi = Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..style = PaintingStyle.fill;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              canRect.left + 4, canRect.top + 6,
              canRect.left + 10, canRect.bottom - 6,
            ),
            const Radius.circular(3),
          ),
          hi,
        );
        // 顶部
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, canRect.top + 3), width: w * 0.48, height: 6),
          Paint()..color = const Color(0xFFCBD3DC),
        );
        break;

      case _CupType.coffee:
        // 马克杯：杯身+把手
        final cupRect = Rect.fromCenter(
          center: Offset(cx, h * 0.55),
          width: w * 0.48,
          height: h * 0.55,
        );
        final rounded = RRect.fromRectAndCorners(
          cupRect,
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(6),
        );
        canvas.drawRRect(rounded, glassPaint);
        canvas.drawRRect(rounded, strokePaint);
        // 咖啡液
        final liqRect = Rect.fromCenter(
          center: Offset(cx, cupRect.top + 8),
          width: w * 0.46,
          height: h * 0.08,
        );
        canvas.drawOval(liqRect, liquidPaint);
        // 把手
        final handlePath = Path()
          ..moveTo(cupRect.right - 2, cupRect.top + h * 0.15)
          ..quadraticBezierTo(cx + w * 0.42, h * 0.5, cupRect.right - 2, cupRect.bottom - h * 0.15);
        canvas.drawPath(handlePath, strokePaint..strokeWidth = 3);
        // 蒸汽
        final steamPaint = Paint()
          ..color = Colors.grey.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawLine(Offset(cx - 4, h * 0.18), Offset(cx - 6, h * 0.05), steamPaint);
        canvas.drawLine(Offset(cx + 2, h * 0.18), Offset(cx + 4, h * 0.02), steamPaint);
        break;

      case _CupType.juice:
        // 果汁杯：直筒玻璃杯
        final jRect = Rect.fromCenter(
          center: Offset(cx, h * 0.55),
          width: w * 0.42,
          height: h * 0.6,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(jRect, const Radius.circular(6)),
          glassPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(jRect, const Radius.circular(6)),
          strokePaint,
        );
        // 果汁（占下半部 70%）
        final jLiqRect = Rect.fromLTRB(
          jRect.left + 2, jRect.top + h * 0.2,
          jRect.right - 2, jRect.bottom - 2,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(jLiqRect, const Radius.circular(4)),
          liquidPaint,
        );
        // 吸管
        canvas.save();
        canvas.translate(cx + w * 0.08, jRect.top);
        canvas.rotate(-0.2);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: w * 0.04, height: h * 0.35),
          Paint()..color = Colors.redAccent,
        );
        canvas.restore();
        break;

      case _CupType.water:
        // 水杯：梯形（上宽下窄）
        final wPath = Path()
          ..moveTo(cx - w * 0.28, h * 0.18)
          ..lineTo(cx + w * 0.28, h * 0.18)
          ..lineTo(cx + w * 0.22, h * 0.85)
          ..lineTo(cx - w * 0.22, h * 0.85)
          ..close();
        canvas.drawPath(wPath, glassPaint);
        canvas.drawPath(wPath, strokePaint);
        // 水面高光
        canvas.drawLine(
          Offset(cx - w * 0.24, h * 0.22),
          Offset(cx + w * 0.24, h * 0.22),
          Paint()..color = Colors.white.withValues(alpha: 0.6)..strokeWidth = 2,
        );
        // 水滴
        canvas.drawCircle(Offset(cx - w * 0.1, h * 0.08), 3, liquidPaint);
        canvas.drawCircle(Offset(cx + w * 0.1, h * 0.06), 2, liquidPaint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _CupPainter old) => old.spec != spec;
}
