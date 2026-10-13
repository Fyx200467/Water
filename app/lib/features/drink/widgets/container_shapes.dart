import 'dart:ui';

import 'package:flutter/material.dart';

/// 容器形状库：对标原版图标选择页的容器剪影
///
/// 所有形状在 0..100 单位坐标系内定义（等比映射到目标 Rect），
/// 使用迷你 SVG path 解析器（M/L/C/Q/Z）以紧凑方式描述轮廓。
class ContainerShape {
  const ContainerShape(
    this.id,
    this.path, {
    this.handle,
    this.foam,
    this.bandTop = 10,
  });

  final String id;

  /// 容器主体轮廓（单位坐标 0..100）
  final Path path;

  /// 把手（描边绘制：马克杯/扎啤杯/凉水壶等）
  final Path? handle;

  /// 顶部奶油/泡沫（白色，绘制在轮廓上方）
  final Path? foam;

  /// 白色液面气隙带的起始 y（单位坐标）
  final double bandTop;
}

/// 迷你 SVG path 解析器（仅支持绝对指令 M/L/C/Q/Z）
Path _p(String d) {
  final path = Path();
  final tokens = RegExp(r'([MLCQZ])|(-?\d*\.?\d+)')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  var i = 0;
  while (i < tokens.length) {
    switch (tokens[i]) {
      case 'M':
        path.moveTo(double.parse(tokens[i + 1]), double.parse(tokens[i + 2]));
        i += 3;
      case 'L':
        path.lineTo(double.parse(tokens[i + 1]), double.parse(tokens[i + 2]));
        i += 3;
      case 'C':
        path.cubicTo(
          double.parse(tokens[i + 1]), double.parse(tokens[i + 2]),
          double.parse(tokens[i + 3]), double.parse(tokens[i + 4]),
          double.parse(tokens[i + 5]), double.parse(tokens[i + 6]),
        );
        i += 7;
      case 'Q':
        path.quadraticBezierTo(
          double.parse(tokens[i + 1]), double.parse(tokens[i + 2]),
          double.parse(tokens[i + 3]), double.parse(tokens[i + 4]),
        );
        i += 5;
      case 'Z':
        path.close();
        i += 1;
      default:
        i += 1;
    }
  }
  return path;
}

/// 网格灰底剪影色（对标原版）
const Color kContainerGray = Color(0xFFE2E2E7);

/// 容器形状目录（顺序即图标选择页网格顺序）
final List<ContainerShape> kContainerShapes = [
  // ---- 杯子 ----
  ContainerShape('cup_tumbler', _p('M18,8 L82,8 C83,40 81,72 78,90 Q77,96 70,96 L30,96 Q23,96 22,90 C19,72 17,40 18,8 Z'), bandTop: 8),
  ContainerShape('cup_tapered', _p('M10,8 L90,8 C86,42 78,76 70,92 Q68,97 61,97 L39,97 Q32,97 30,92 C22,76 14,42 10,8 Z'), bandTop: 8),
  ContainerShape('cup_tall', _p('M24,4 L76,4 C77,36 75,70 72,93 Q71,97 66,97 L34,97 Q29,97 28,93 C25,70 23,36 24,4 Z'), bandTop: 4),
  ContainerShape('cup_short', _p('M12,22 C12,12 24,8 50,8 C76,8 88,12 88,22 L84,78 Q83,94 66,94 L34,94 Q17,94 16,78 Z'), bandTop: 10),
  ContainerShape('cup_barrel', _p('M20,10 L80,10 C82,26 78,34 80,46 C82,62 78,84 72,92 Q70,96 62,96 L38,96 Q30,96 28,92 C22,84 18,62 20,46 C22,34 18,26 20,10 Z'), bandTop: 10),
  // ---- 马克杯 ----
  ContainerShape('mug_classic', _p('M18,12 L72,12 L72,88 Q72,95 65,95 L25,95 Q18,95 18,88 Z'), handle: _p('M72,32 C90,32 90,66 72,66'), bandTop: 12),
  ContainerShape('mug_beer', _p('M16,14 L68,14 L64,90 Q63,96 55,96 L29,96 Q21,96 20,90 Z'), handle: _p('M68,30 C88,30 88,64 68,64'), foam: _p('M20,14 C20,4 32,2 38,8 C44,0 56,0 60,7 C68,2 80,4 80,14 Z'), bandTop: 14),
  ContainerShape('mug_foam', _p('M20,18 L80,18 L76,90 Q75,96 68,96 L32,96 Q25,96 24,90 Z'), foam: _p('M22,18 C16,8 28,0 40,7 C48,-1 60,1 62,8 C72,2 84,10 78,18 Z'), bandTop: 18),
  ContainerShape('mug_tall', _p('M22,6 L78,6 C79,36 77,70 74,92 Q73,97 68,97 L32,97 Q27,97 26,92 C23,70 21,36 22,6 Z'), handle: _p('M78,28 C90,30 90,54 78,56'), bandTop: 6),
  ContainerShape('cup_espresso', _p('M28,42 L72,42 C72,62 66,72 54,74 L54,80 L66,84 L66,89 L34,89 L34,84 L46,80 L46,74 C34,72 28,62 28,42 Z'), bandTop: 42),
  // ---- 瓶子 ----
  ContainerShape('bottle_water', _p('M42,2 L58,2 L58,10 L42,10 Z M44,10 L56,10 C56,18 64,22 64,34 L64,88 Q64,96 55,96 L45,96 Q36,96 36,88 L36,34 C36,22 44,18 44,10 Z'), bandTop: 2),
  ContainerShape('bottle_soda', _p('M43,2 L57,2 L57,9 L43,9 Z M45,9 L55,9 L55,15 C61,20 63,26 63,33 L63,87 Q63,96 54,96 L46,96 Q37,96 37,87 L37,33 C37,26 39,20 45,15 Z'), bandTop: 2),
  ContainerShape('bottle_sports', _p('M49,0 L54,0 L56,14 L51,14 Z M38,12 L62,12 L62,22 L38,22 Z M36,22 L64,22 C68,32 66,42 64,50 C68,60 66,80 61,90 Q58,96 50,96 Q42,96 39,90 C34,80 32,60 36,50 C34,42 32,32 36,22 Z'), bandTop: 12),
  ContainerShape('bottle_flask', _p('M40,8 L60,8 L60,18 L40,18 Z M34,18 L66,18 C70,28 68,40 66,52 C68,68 66,84 61,92 Q57,97 50,97 Q43,97 39,92 C34,84 32,68 34,52 C32,40 30,28 34,18 Z'), handle: _p('M42,10 C42,-2 58,-2 58,10'), bandTop: 8),
  ContainerShape('bottle_straw', _p('M32,12 L68,12 L68,20 L32,20 Z M30,20 L70,20 C72,46 70,76 65,92 Q63,97 55,97 L45,97 Q37,97 35,92 C30,76 28,46 30,20 Z'), handle: _p('M52,0 L57,0 L60,16 L55,17 Z'), bandTop: 12),
  // ---- 壶/盒 ----
  ContainerShape('carton_milk', _p('M22,24 L38,8 L62,8 L78,24 L78,90 Q78,96 71,96 L29,96 Q22,96 22,90 Z'), bandTop: 8),
  ContainerShape('jug_milk', _p('M42,4 L58,4 L58,12 L42,12 Z M34,12 L66,12 C72,17 74,25 74,34 L74,86 Q74,96 63,96 L37,96 Q26,96 26,86 L26,34 C26,25 28,17 34,12 Z'), handle: _p('M74,36 C88,38 88,62 74,64'), bandTop: 4),
  ContainerShape('pitcher', _p('M28,24 L20,14 Q18,10 23,12 L34,18 C40,12 72,10 78,22 C80,40 75,70 70,88 Q68,96 58,96 L40,96 Q30,96 28,88 C24,70 24,40 28,24 Z'), handle: _p('M78,30 C92,34 90,58 76,62'), bandTop: 14),
  ContainerShape('bottle_juice', _p('M42,2 L58,2 L58,9 L42,9 Z M44,9 L56,9 C58,16 62,19 62,27 L62,88 Q62,96 53,96 L47,96 Q38,96 38,88 L38,27 C38,19 42,16 44,9 Z'), bandTop: 2),
  ContainerShape('iced_straw', _p('M30,12 L70,12 L70,19 L30,19 Z M26,19 L74,19 C73,48 69,78 65,92 Q63,97 55,97 L45,97 Q37,97 35,92 C31,78 27,48 26,19 Z'), handle: _p('M50,0 L55,0 L58,14 L53,15 Z'), bandTop: 12),
  // ---- 高脚杯 ----
  ContainerShape('glass_wine', _p('M28,6 L72,6 C72,36 64,52 54,56 L54,86 L70,91 L70,96 L30,96 L30,91 L46,86 L46,56 C36,52 28,36 28,6 Z'), bandTop: 6),
  ContainerShape('glass_martini', _p('M12,8 L88,8 L54,58 L54,86 L72,91 L72,96 L28,96 L28,91 L46,86 L46,58 Z'), bandTop: 8),
  ContainerShape('glass_margarita', _p('M8,10 L92,10 C88,34 72,50 56,55 L56,86 L72,91 L72,96 L28,96 L28,91 L44,86 L44,55 C28,50 12,34 8,10 Z'), bandTop: 10),
  ContainerShape('glass_goblet', _p('M30,8 C30,38 38,54 50,56 C62,54 70,38 70,8 Z M46,56 L54,56 L54,86 L68,91 L68,96 L32,96 L32,91 L46,86 Z'), bandTop: 8),
  ContainerShape('glass_beer', _p('M20,6 L80,6 C79,30 82,52 74,92 Q72,97 64,97 L36,97 Q28,97 26,92 C18,52 21,30 20,6 Z'), bandTop: 6),
  // ---- 茶杯/碗 ----
  ContainerShape('teacup', _p('M20,28 C20,22 80,22 80,28 C80,52 70,66 55,68 L55,73 L68,76 L68,80 L32,80 L32,76 L45,73 L45,68 C30,66 20,52 20,28 Z M12,84 Q50,92 88,84 L88,89 Q50,97 12,89 Z'), bandTop: 26),
  ContainerShape('coffee_cup', _p('M22,24 L78,24 C78,52 68,66 52,68 L52,74 L66,78 L66,83 L34,83 L34,78 L48,74 L48,68 C32,66 22,52 22,24 Z'), handle: _p('M78,32 C92,34 92,54 76,56'), bandTop: 24),
  ContainerShape('boba_cup', _p('M32,20 C32,8 68,8 68,20 Z M28,20 L72,20 C70,50 66,80 62,92 Q60,97 52,97 L48,97 Q40,97 38,92 C34,80 30,50 28,20 Z'), handle: _p('M48,0 L53,0 L57,20 L52,21 Z'), bandTop: 8),
  ContainerShape('bowl_soup', _p('M14,36 C14,30 86,30 86,36 C86,60 74,78 55,80 L55,85 L70,89 L70,94 L30,94 L30,89 L45,85 L45,80 C26,78 14,60 14,36 Z'), bandTop: 32),
  ContainerShape('bowl_cereal', _p('M12,34 Q12,26 50,26 Q88,26 88,34 C88,60 76,84 50,84 Q24,84 12,34 Z'), bandTop: 28),
];

/// 按 id 查找容器形状（未找到回退第一款）
ContainerShape containerShapeById(String? id) {
  for (final s in kContainerShapes) {
    if (s.id == id) return s;
  }
  return kContainerShapes.first;
}

/// 将单位形状路径映射到目标 Rect（非等比填充）
Path scaledContainerPath(ContainerShape shape, Rect rect) {
  final matrix = Matrix4.translationValues(rect.left, rect.top, 0)
      .multiplied(Matrix4.diagonal3Values(
          rect.width / 100, rect.height / 100, 1));
  return shape.path.transform(matrix.storage);
}

/// 容器剪影绘制：主体填充 + 把手描边 + 白色液面气隙带 + 顶部泡沫
class ContainerShapePainter extends CustomPainter {
  ContainerShapePainter({required this.id, required this.color});

  final String id;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = containerShapeById(id);
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);

    // 主体填充
    canvas.drawPath(shape.path, Paint()..color = color);

    // 把手（描边，宽度按短边自适应）
    if (shape.handle != null) {
      canvas.drawPath(
        shape.handle!,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // 白色液面气隙带（从液面线向下 ~14 单位）
    canvas.save();
    canvas.clipPath(shape.path);
    final band = Path()
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(0, shape.bandTop, 100, 14),
        bottomLeft: const Radius.circular(6),
        bottomRight: const Radius.circular(6),
      ));
    canvas.drawPath(band, Paint()..color = Colors.white);
    canvas.restore();

    // 顶部奶油/泡沫
    if (shape.foam != null) {
      canvas.drawPath(shape.foam!, Paint()..color = Colors.white);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(ContainerShapePainter oldDelegate) =>
      oldDelegate.id != id || oldDelegate.color != color;
}
