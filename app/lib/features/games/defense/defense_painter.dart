// 吨吨守卫战：Canvas 渲染层
//
// 所有素材均为程序化绘制（圆角路径、水滴、茶杯、雪花），
// 不引入额外图片资源，与消消乐的轻量风格保持一致。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'defense_game.dart';
import 'defense_models.dart';
import 'defense_rules.dart';

class DefensePainter extends CustomPainter {
  DefensePainter({
    required this.game,
    required this.selectedTower,
    super.repaint,
  });

  final DefenseGame game;
  final DefenseTower? selectedTower;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / defenseCols;
    canvas.clipRect(Offset.zero & size);

    _paintBackground(canvas, size, cell);
    _paintPath(canvas, cell);
    _paintStartGate(canvas, cell);
    _paintExitCup(canvas, cell);
    _paintSlots(canvas, cell);
    _paintTowers(canvas, cell);
    _paintEnemies(canvas, cell);
    _paintProjectiles(canvas, cell);
    _paintBursts(canvas, cell);
  }

  Offset _px(DefenseVec v, double cell) => Offset(v.x * cell, v.y * cell);

  // ==================== 底图 ====================

  void _paintBackground(Canvas canvas, Size size, double cell) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEAF8FC), Color(0xFFF9FDFF)],
        ).createShader(rect),
    );

    // 极淡的网格线，帮助判断炮位与路径
    final grid = Paint()
      ..color = const Color(0xFFE1F1F7)
      ..strokeWidth = 0.8;
    for (var c = 1; c < defenseCols; c++) {
      canvas.drawLine(
        Offset(c * cell, 0),
        Offset(c * cell, size.height),
        grid,
      );
    }
    for (var r = 1; r < defenseRows; r++) {
      canvas.drawLine(
        Offset(0, r * cell),
        Offset(size.width, r * cell),
        grid,
      );
    }
  }

  /// 路径画成传送带：带面 + 移动的横向挡条 + 方向箭头，让怪“被传送着”往前走
  void _paintPath(Canvas canvas, double cell) {
    final points = game.pathPoints;
    if (points.length < 2) return;
    final path = Path()
      ..moveTo(_px(points.first, cell).dx, _px(points.first, cell).dy);
    for (final p in points.skip(1)) {
      final o = _px(p, cell);
      path.lineTo(o.dx, o.dy);
    }

    final casing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.96
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFD8C4A0);
    final belt = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFF6E9CF);

    canvas.drawPath(path, casing);
    canvas.drawPath(path, belt);

    final slatPaint = Paint()..color = const Color(0x22C39E63);
    final arrowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.045
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x8CB08A4C);

    // 带速：在传送带上流动的速度感
    final travel = game.clock * cell * 0.8;
    for (final metric in path.computeMetrics()) {
      // 横向挡条
      final slatGap = cell * 0.62;
      var d = travel % slatGap;
      while (d < metric.length) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent != null) {
          final angle = math.atan2(tangent.vector.dy, tangent.vector.dx);
          canvas.save();
          canvas.translate(tangent.position.dx, tangent.position.dy);
          canvas.rotate(angle);
          canvas.drawLine(
            Offset(0, -cell * 0.34),
            Offset(0, cell * 0.34),
            slatPaint,
          );
          canvas.restore();
        }
        d += slatGap;
      }

      // 方向箭头
      final arrowGap = cell * 2.2;
      var a = (travel * 1.4) % arrowGap;
      while (a < metric.length) {
        final tangent = metric.getTangentForOffset(a);
        if (tangent != null) {
          final angle = math.atan2(tangent.vector.dy, tangent.vector.dx);
          canvas.save();
          canvas.translate(tangent.position.dx, tangent.position.dy);
          canvas.rotate(angle);
          final s = cell * 0.13;
          canvas.drawLine(Offset(-s, -s * 0.9), Offset(0, 0), arrowPaint);
          canvas.drawLine(Offset(-s, s * 0.9), Offset(0, 0), arrowPaint);
          canvas.restore();
        }
        a += arrowGap;
      }
    }
  }

  /// 布阵阶段：怪物出口处的呼吸光圈 + 开始箭头（点击后才开始出怪）
  void _paintStartGate(Canvas canvas, double cell) {
    if (game.started || game.phase != DefensePhase.playing) return;
    final points = game.pathPoints;
    if (points.isEmpty) return;
    final start = points.first;
    final c = _px(
      DefenseVec(
        start.x.clamp(0.5, defenseCols - 0.5),
        start.y.clamp(0.5, defenseRows - 0.5),
      ),
      cell,
    );
    final pulse = 0.5 + 0.5 * math.sin(game.clock * 3.2);

    canvas.drawCircle(
      c,
      cell * (0.4 + 0.08 * pulse),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.035
        ..color = const Color(
          0xFF4DB8D8,
        ).withValues(alpha: 0.3 + 0.35 * pulse),
    );
    canvas.drawCircle(
      c,
      cell * 0.31,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );

    // 箭头顺着第一段路径，暗示“从这里出发”
    final d = points.length > 1
        ? DefenseVec(points[1].x - start.x, points[1].y - start.y)
        : DefenseVec(1, 0);
    final angle = math.atan2(d.y, d.x);
    final s = cell * 0.13;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final tri = Path()
      ..moveTo(-s * 0.55, -s)
      ..lineTo(s * 0.95, 0)
      ..lineTo(-s * 0.55, s)
      ..close();
    canvas.drawPath(tri, Paint()..color = const Color(0xFF3FA9CB));
    canvas.restore();
  }

  /// 终点水杯：杯里的水位就是剩余生命，怪物抵达会让水位下降
  void _paintExitCup(Canvas canvas, double cell) {
    final points = game.pathPoints;
    if (points.isEmpty) return;
    final end = points.last;
    final cx = end.x.clamp(0.65, defenseCols - 0.65) * cell;
    final cy = end.y.clamp(0.65, defenseRows - 0.65) * cell;

    final cupW = cell * 0.78;
    final cupH = cell * 0.9;
    final top = cy - cupH * 0.52;
    final bottom = top + cupH;

    // 杯身（上宽下窄）
    final body = Path()
      ..moveTo(cx - cupW / 2, top)
      ..lineTo(cx + cupW / 2, top)
      ..lineTo(cx + cupW * 0.35, bottom)
      ..lineTo(cx - cupW * 0.35, bottom)
      ..close();
    canvas.drawPath(
      body,
      Paint()..color = Colors.white.withValues(alpha: 0.96),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.045
        ..color = const Color(0xFFBFE3EF),
    );

    // 剩余水量
    final ratio = game.level.lives <= 0
        ? 0.0
        : (game.lives / game.level.lives).clamp(0.0, 1.0);
    if (ratio > 0) {
      final waterHeight = cupH * 0.74 * ratio;
      final waterTop = bottom - waterHeight;
      // 按杯身在该高度的宽度插值，避免水位超出杯沿
      final t = ((waterTop - top) / cupH).clamp(0.0, 1.0);
      final halfWidth = cupW / 2 - (cupW * 0.15) * t;
      final water = Path()
        ..moveTo(cx - halfWidth, waterTop)
        ..lineTo(cx + halfWidth, waterTop)
        ..lineTo(cx + cupW * 0.35, bottom)
        ..lineTo(cx - cupW * 0.35, bottom)
        ..close();
      canvas.drawPath(
        water,
        Paint()..color = const Color(0x9954C3DE),
      );
    }

    // 吸管
    canvas.drawLine(
      Offset(cx + cupW * 0.16, top - cupH * 0.2),
      Offset(cx + cupW * 0.03, top + cupH * 0.22),
      Paint()
        ..color = const Color(0xFF7FD6E8)
        ..strokeWidth = cell * 0.05
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintSlots(Canvas canvas, double cell) {
    for (final slot in game.level.slots) {
      final tower = game.towerAt(slot.col, slot.row);
      if (tower != null) continue;
      final center = _px(slot.center, cell);
      // 轻微呼吸的虚线圆，提示“这里可以点”
      final pulse = 0.5 + 0.5 * math.sin(game.clock * 2.4 + slot.col + slot.row);
      final base = const Color(0xFFB9D7E2);

      canvas.drawCircle(
        center,
        cell * 0.31,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
      _dashedCircle(
        canvas,
        center,
        cell * (0.34 + pulse * 0.025),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.04
          ..color = base.withValues(alpha: 0.55 + pulse * 0.35),
        dash: cell * 0.1,
        gap: cell * 0.08,
      );

      // 「+」提示
      final plus = Paint()
        ..color = const Color(0xFF7FB2C4).withValues(alpha: 0.7 + pulse * 0.3)
        ..strokeWidth = cell * 0.035
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        center - Offset(cell * 0.09, 0),
        center + Offset(cell * 0.09, 0),
        plus,
      );
      canvas.drawLine(
        center - Offset(0, cell * 0.09),
        center + Offset(0, cell * 0.09),
        plus,
      );
    }
  }

  // ==================== 防御塔 ====================

  void _paintTowers(Canvas canvas, double cell) {
    // 选中塔的射程先画，避免遮挡塔与敌
    final sel = selectedTower;
    if (sel != null && game.towers.contains(sel)) {
      final range = DefenseRules.rangeOf(sel.type, sel.level) * cell;
      final center = _px(sel.center, cell);
      final color = Color(sel.type.color);
      canvas.drawCircle(
        center,
        range,
        Paint()..color = color.withValues(alpha: 0.10),
      );
      canvas.drawCircle(
        center,
        range,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.035
          ..color = color.withValues(alpha: 0.55),
      );
    }

    for (final tower in game.towers) {
      final center = _px(tower.center, cell);
      final color = Color(tower.type.color);
      final flashTotal =
          tower.type == DefenseTowerType.cannon ? 0.24 : 0.15;
      final flashRatio = tower.flash <= 0
          ? 0.0
          : (tower.flash / flashTotal).clamp(0.0, 1.0);

      // 底座
      canvas.drawCircle(
        center + Offset(0, cell * 0.06),
        cell * 0.32,
        Paint()..color = const Color(0x22000000),
      );
      canvas.drawCircle(center, cell * 0.32, Paint()..color = Colors.white);
      canvas.drawCircle(
        center,
        cell * 0.32,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.045
          ..color = color.withValues(alpha: 0.85),
      );

      // 开火瞬间的地面光晕
      if (flashRatio > 0) {
        canvas.drawCircle(
          center,
          cell * (0.36 + 0.2 * (1 - flashRatio)),
          Paint()..color = color.withValues(alpha: 0.16 * flashRatio),
        );
      }

      switch (tower.type) {
        case DefenseTowerType.droplet:
          _paintDroplet(canvas, center, cell, color, tower);
          break;
        case DefenseTowerType.cannon:
          _paintCannon(canvas, center, cell, color, tower);
          break;
        case DefenseTowerType.ice:
          _paintIce(canvas, center, cell, color, tower);
          break;
      }

      // 出膛闪光：水滴塔在矛尖、茶杯炮在杯口、冰塔在中心
      if (flashRatio > 0) {
        final muzzle = _muzzlePoint(tower, center, cell);
        canvas.drawCircle(
          muzzle,
          cell * 0.14 * (0.5 + 0.7 * (1 - flashRatio)),
          Paint()..color = color.withValues(alpha: 0.35 * flashRatio),
        );
        canvas.drawCircle(
          muzzle,
          cell * 0.07 * flashRatio + cell * 0.02,
          Paint()..color = Colors.white.withValues(alpha: 0.9 * flashRatio),
        );
      }

      // 等级：底部金色小点
      for (var i = 0; i < tower.level; i++) {
        final dx = (i - (tower.level - 1) / 2) * cell * 0.12;
        canvas.drawCircle(
          center + Offset(dx, cell * 0.28),
          cell * 0.035,
          Paint()..color = const Color(0xFFE8B44A),
        );
      }

      // 选中标记
      if (identical(tower, selectedTower)) {
        _dashedCircle(
          canvas,
          center,
          cell * 0.4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.05
            ..color = color,
          dash: cell * 0.12,
          gap: cell * 0.06,
        );
      }
    }
  }

  /// 出膛闪光的中心位置（水滴塔在矛尖，茶杯炮在杯口）
  Offset _muzzlePoint(DefenseTower tower, Offset center, double cell) {
    switch (tower.type) {
      case DefenseTowerType.droplet:
        final dir = Offset(
          math.cos(tower.visualAngle),
          math.sin(tower.visualAngle),
        );
        return center + dir * cell * 0.27;
      case DefenseTowerType.cannon:
        return center + Offset(0, -cell * 0.02);
      case DefenseTowerType.ice:
        return center;
    }
  }

  /// 水滴塔：整颗水滴绕中心平滑旋转，尖头始终指着目标；
  /// 射击时沿反方向后坐，并沿着射出方向轻微压扁
  void _paintDroplet(
    Canvas canvas,
    Offset center,
    double cell,
    Color color,
    DefenseTower tower,
  ) {
    final angle = tower.visualAngle;
    final dir = Offset(math.cos(angle), math.sin(angle));
    final c = center - dir * (cell * 0.06 * tower.recoil);
    final squash = 1 - 0.12 * tower.recoil;
    // 水滴默认尖头朝上（-π/2），旋转到视觉朝向后正好指向目标
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle + math.pi / 2);
    canvas.scale(1 + (1 - squash) * 0.5, squash);

    final bodyR = cell * 0.17;
    canvas.drawCircle(
      Offset(0, cell * 0.04),
      bodyR,
      Paint()..color = color,
    );
    final tip = Path()
      ..moveTo(0, -cell * 0.27)
      ..lineTo(-bodyR * 0.78, cell * 0.03)
      ..lineTo(bodyR * 0.78, cell * 0.03)
      ..close();
    canvas.drawPath(tip, Paint()..color = color);
    canvas.drawCircle(
      Offset(-bodyR * 0.35, cell * 0.04 - bodyR * 0.12),
      bodyR * 0.3,
      Paint()..color = Colors.white.withValues(alpha: 0.8),
    );
    canvas.restore();
  }

  /// 茶杯炮：没有炮管，炮弹直接从杯口抛出去；
  /// 开火时杯身下沉压缩一下，杯口泛起闪光
  void _paintCannon(
    Canvas canvas,
    Offset center,
    double cell,
    Color color,
    DefenseTower tower,
  ) {
    final recoil = tower.recoil;
    final squash = 1 - 0.10 * recoil;
    final bodyCenter = center + Offset(0, cell * (0.08 + 0.02 * recoil));

    canvas.save();
    canvas.translate(bodyCenter.dx, bodyCenter.dy);
    canvas.scale(1 + (1 - squash) * 0.4, squash);

    // 杯身
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: cell * 0.42,
        height: cell * 0.30,
      ),
      Radius.circular(cell * 0.1),
    );
    canvas.drawRRect(body, Paint()..color = color);
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.028
        ..color = const Color(0xFFB9832F).withValues(alpha: 0.6),
    );

    // 杯口（奶茶面）
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, -cell * 0.05),
        width: cell * 0.34,
        height: cell * 0.13,
      ),
      Paint()..color = const Color(0xFF7B5320),
    );
    // 液面高光
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-cell * 0.03, -cell * 0.058),
        width: cell * 0.13,
        height: cell * 0.045,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );

    // 珍珠
    for (final dx in [-0.1, 0.0, 0.1]) {
      canvas.drawCircle(
        Offset(cell * dx, cell * 0.05),
        cell * 0.022,
        Paint()..color = const Color(0xFF3E2A16),
      );
    }
    // 杯身高光
    canvas.drawCircle(
      Offset(-cell * 0.11, -cell * 0.02),
      cell * 0.028,
      Paint()..color = Colors.white.withValues(alpha: 0.75),
    );
    canvas.restore();
  }

  /// 冰饮塔：雪花缓慢旋转，开火时向外扩一圈冰环
  void _paintIce(
    Canvas canvas,
    Offset center,
    double cell,
    Color color,
    DefenseTower tower,
  ) {
    canvas.drawCircle(
      center,
      cell * 0.19,
      Paint()..color = color.withValues(alpha: 0.28),
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tower.spin);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.045
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (var i = 0; i < 3; i++) {
      final angle = math.pi / 3 * i;
      final dx = math.cos(angle) * cell * 0.22;
      final dy = math.sin(angle) * cell * 0.22;
      canvas.drawLine(Offset(-dx, -dy), Offset(dx, dy), stroke);
      // 两端小枝
      for (final sign in [-1.0, 1.0]) {
        final tipX = dx * sign;
        final tipY = dy * sign;
        final bx = math.cos(angle + math.pi / 2) * cell * 0.07;
        final by = math.sin(angle + math.pi / 2) * cell * 0.07;
        canvas.drawLine(
          Offset(tipX, tipY),
          Offset(tipX - dx * 0.35 + bx * sign, tipY - dy * 0.35 + by * sign),
          stroke,
        );
        canvas.drawLine(
          Offset(tipX, tipY),
          Offset(tipX - dx * 0.35 - bx * sign, tipY - dy * 0.35 - by * sign),
          stroke,
        );
      }
    }
    canvas.restore();

    if (tower.flash > 0) {
      final t = (tower.flash / 0.15).clamp(0.0, 1.0);
      canvas.drawCircle(
        center,
        cell * (0.2 + 0.16 * (1 - t)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.04
          ..color = color.withValues(alpha: 0.7 * t),
      );
    }
  }

  // ==================== 怪物 ====================

  void _paintEnemies(Canvas canvas, double cell) {
    for (final e in game.enemies) {
      if (!e.alive) continue;
      final ground = _px(e.pos, cell);
      final r = e.type.radius * cell;
      final color = Color(e.type.color);

      // 行走动效：上下弹跳 + 左右摇摆；受击时额外抖动
      final bob = math.sin(e.walkPhase) * cell * 0.05;
      final sway = math.sin(e.walkPhase * 0.5) * 0.10;
      final hit = e.hitFlash > 0;
      final shake = hit ? math.sin(game.clock * 70) * cell * 0.035 : 0.0;
      final center = ground + Offset(shake, bob);

      // 影子始终贴在地面
      canvas.drawOval(
        Rect.fromCenter(
          center: ground + Offset(0, r * 0.6),
          width: r * 1.7,
          height: r * 0.5,
        ),
        Paint()..color = const Color(0x22000000),
      );

      // 交替迈步的小脚
      final step = math.sin(e.walkPhase) * r * 0.28;
      final foot = Paint()..color = color.withValues(alpha: 0.9);
      canvas.drawOval(
        Rect.fromCenter(
          center: center + Offset(-r * 0.33, r * 0.78 - step),
          width: r * 0.34,
          height: r * 0.22,
        ),
        foot,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: center + Offset(r * 0.33, r * 0.78 + step),
          width: r * 0.34,
          height: r * 0.22,
        ),
        foot,
      );

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(sway);

      final bodyR = r * (hit ? 1.06 : 1.0);
      canvas.drawCircle(Offset.zero, bodyR, Paint()..color = color);
      canvas.drawCircle(
        Offset.zero,
        bodyR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.03
          ..color = const Color(0x33000000),
      );

      // 奶茶怪的珍珠护甲
      if (e.type == DefenseEnemyType.armored) {
        final pearl = Paint()..color = const Color(0xFF6B4A2B);
        for (var i = -1; i <= 1; i++) {
          canvas.drawCircle(
            Offset(i * bodyR * 0.42, bodyR * 0.55),
            bodyR * 0.13,
            pearl,
          );
        }
      }

      // 受击闪白
      if (hit) {
        canvas.drawCircle(
          Offset.zero,
          bodyR,
          Paint()..color = Colors.white.withValues(alpha: 0.85),
        );
      }

      // 眼睛
      final eye = Paint()..color = Colors.white;
      final pupil = Paint()..color = const Color(0xFF2E3440);
      canvas.drawCircle(Offset(-bodyR * 0.32, -bodyR * 0.12), bodyR * 0.18, eye);
      canvas.drawCircle(Offset(bodyR * 0.32, -bodyR * 0.12), bodyR * 0.18, eye);
      canvas.drawCircle(
        Offset(-bodyR * 0.30, -bodyR * 0.10),
        bodyR * 0.08,
        pupil,
      );
      canvas.drawCircle(
        Offset(bodyR * 0.34, -bodyR * 0.10),
        bodyR * 0.08,
        pupil,
      );

      // BOSS 小皇冠
      if (e.type == DefenseEnemyType.boss) {
        final crown = Path()
          ..moveTo(-bodyR * 0.55, -bodyR * 0.9)
          ..lineTo(-bodyR * 0.25, -bodyR * 1.25)
          ..lineTo(0, -bodyR * 0.95)
          ..lineTo(bodyR * 0.25, -bodyR * 1.25)
          ..lineTo(bodyR * 0.55, -bodyR * 0.9)
          ..close();
        canvas.drawPath(crown, Paint()..color = const Color(0xFFE8B44A));
      }
      canvas.restore();

      // 减速光环
      if (game.clock < e.slowUntil) {
        canvas.drawCircle(
          center,
          r * 1.18,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.04
            ..color = const Color(0xAA7FD6E8),
        );
      }

      // 血条：受击时往上弹一下，掉血条缓慢追平
      final barW = r * 2.0;
      final barH = cell * 0.06 + (hit ? cell * 0.012 : 0);
      final barRect = Rect.fromCenter(
        center: center + Offset(0, -r * 1.25 - barH - (hit ? cell * 0.04 : 0)),
        width: barW,
        height: barH,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, Radius.circular(barH)),
        Paint()..color = const Color(0x33000000),
      );
      final trail = e.barRatio.clamp(0.0, 1.0);
      if (trail > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(barRect.left, barRect.top, barW * trail, barH),
            Radius.circular(barH),
          ),
          Paint()..color = const Color(0x66FFFFFF),
        );
      }
      final ratio = e.hpRatio;
      if (ratio > 0) {
        final hpColor = Color.lerp(
          const Color(0xFFEF6B6B),
          const Color(0xFF6BCB77),
          ratio,
        )!;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(barRect.left, barRect.top, barW * ratio, barH),
            Radius.circular(barH),
          ),
          Paint()..color = hpColor,
        );
      }
    }
  }

  // ==================== 弹道与特效 ====================

  void _paintProjectiles(Canvas canvas, double cell) {
    for (final p in game.projectiles) {
      if (p.done) continue;
      final groundPos = _px(p.pos, cell);
      final color = Color(p.type.color);
      switch (p.type) {
        case DefenseTowerType.droplet:
          canvas.drawCircle(
            groundPos,
            cell * 0.10,
            Paint()..color = color.withValues(alpha: 0.35),
          );
          canvas.drawCircle(groundPos, cell * 0.065, Paint()..color = color);
          break;
        case DefenseTowerType.cannon:
          // 抛射：弹丸有抛物线弧线，落点在地面留阴影
          final height =
              math.sin(math.min(1.0, p.age / 0.55) * math.pi) * cell * 0.5;
          final center = groundPos - Offset(0, height);
          canvas.drawCircle(
            groundPos,
            cell * 0.09,
            Paint()..color = const Color(0x22000000),
          );
          canvas.drawCircle(
            center,
            cell * 0.12,
            Paint()..color = color.withValues(alpha: 0.3),
          );
          canvas.drawCircle(
            center,
            cell * 0.085,
            Paint()..color = const Color(0xFF7B5320),
          );
          canvas.drawCircle(
            center + Offset(-cell * 0.025, -cell * 0.03),
            cell * 0.03,
            Paint()..color = Colors.white.withValues(alpha: 0.7),
          );
          break;
        case DefenseTowerType.ice:
          final r = cell * 0.09;
          canvas.save();
          canvas.translate(groundPos.dx, groundPos.dy);
          canvas.rotate(p.age * 8);
          final diamond = Path()
            ..moveTo(0, -r)
            ..lineTo(r, 0)
            ..lineTo(0, r)
            ..lineTo(-r, 0)
            ..close();
          canvas.drawPath(diamond, Paint()..color = color);
          canvas.restore();
          break;
      }
    }
  }

  void _paintBursts(Canvas canvas, double cell) {
    for (final b in game.bursts) {
      final center = _px(b.pos, cell);
      final t = b.progress;
      final color = Color(b.color);
      final radius = b.radius * cell * (0.4 + t * 0.8);
      // 中心亮斑 + 扩散圈，爆炸看起来更有冲击力
      canvas.drawCircle(
        center,
        radius * 0.7,
        Paint()..color = color.withValues(alpha: (1 - t) * 0.35),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.05
          ..color = color.withValues(alpha: 1 - t),
      );
      canvas.drawCircle(
        center,
        radius * 0.45,
        Paint()..color = Colors.white.withValues(alpha: (1 - t) * 0.5),
      );
    }
  }

  // ==================== 工具 ====================

  void _dashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    final path = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DefensePainter oldDelegate) {
    return oldDelegate.game != game ||
        oldDelegate.selectedTower != selectedTower;
  }
}
