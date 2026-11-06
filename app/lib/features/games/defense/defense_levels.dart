// 吨吨守卫战：5 个内置关卡（地图 + 波次）
//
// 炮位不再手写，而是沿路径自动生成：
// 每个炮位都与路径相距 1 格，保证任何炮塔（最短射程 1.8 格）都能打到怪；
// 同时避开路径格、互相保持间距，避免出现“建了却打不到”的死角。

import 'dart:math' as math;

import 'defense_models.dart';
import 'defense_rules.dart';

/// 全部关卡（序号 1~5，随进度解锁）
final List<DefenseLevel> defenseLevels = List<DefenseLevel>.unmodifiable([
  _level(
    index: 1,
    name: '清凉小径',
    waypoints: const [
      DefenseVec(-1, 2),
      DefenseVec(7, 2),
      DefenseVec(7, 6),
      DefenseVec(2, 6),
      DefenseVec(2, 10),
      DefenseVec(7, 10),
      DefenseVec(7, 14),
      DefenseVec(4, 14),
      DefenseVec(4, 16),
    ],
  ),
  _level(
    index: 2,
    name: '茶杯回廊',
    waypoints: const [
      DefenseVec(-1, 1),
      DefenseVec(3, 1),
      DefenseVec(3, 5),
      DefenseVec(7, 5),
      DefenseVec(7, 9),
      DefenseVec(3, 9),
      DefenseVec(3, 13),
      DefenseVec(7, 13),
      DefenseVec(7, 16),
    ],
  ),
  _level(
    index: 3,
    name: '冰镇迷宫',
    waypoints: const [
      DefenseVec(-1, 3),
      DefenseVec(6, 3),
      DefenseVec(6, 7),
      DefenseVec(1, 7),
      DefenseVec(1, 11),
      DefenseVec(7, 11),
      DefenseVec(7, 15),
      DefenseVec(2, 15),
      DefenseVec(2, 16),
    ],
  ),
  _level(
    index: 4,
    name: '双层水道',
    waypoints: const [
      DefenseVec(-1, 1),
      DefenseVec(7, 1),
      DefenseVec(7, 4),
      DefenseVec(1, 4),
      DefenseVec(1, 7),
      DefenseVec(7, 7),
      DefenseVec(7, 10),
      DefenseVec(1, 10),
      DefenseVec(1, 13),
      DefenseVec(7, 13),
      DefenseVec(7, 16),
    ],
  ),
  _level(
    index: 5,
    name: '终局激流',
    waypoints: const [
      DefenseVec(-1, 2),
      DefenseVec(6, 2),
      DefenseVec(6, 5),
      DefenseVec(1, 5),
      DefenseVec(1, 8),
      DefenseVec(7, 8),
      DefenseVec(7, 11),
      DefenseVec(1, 11),
      DefenseVec(1, 14),
      DefenseVec(6, 14),
      DefenseVec(6, 16),
    ],
  ),
]);

DefenseLevel _level({
  required int index,
  required String name,
  required List<DefenseVec> waypoints,
}) {
  return DefenseLevel(
    index: index,
    name: name,
    waypoints: waypoints,
    slots: _slotsAlong(waypoints),
    waves: _wavesFor(index),
    startGold: 130 + (index - 1) * 30,
    lives: 10,
    // 单波基数：前 3 关平缓递增；第 4/5 关路线更长、炮位更多，
    // 基数压低一些，压力主要交给游戏内的“波次越靠后血量越高”
    hpScale: switch (index) {
      3 => 1.7,
      4 => 2.0,
      5 => 2.3,
      _ => 1 + 0.45 * (index - 1),
    },
  );
}

/// 沿路径自动生成固定炮位
List<DefenseCell> _slotsAlong(List<DefenseVec> waypoints) {
  final points = [
    for (final w in waypoints) DefenseVec(w.x + 0.5, w.y + 0.5),
  ];
  final cumulative = <double>[0];
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += points[i - 1].distanceTo(points[i]);
    cumulative.add(total);
  }

  // 路径经过的所有格子，炮位不能压在上面
  final pathCells = <String>{};
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final steps = math.max(1, (a.distanceTo(b) * 4).ceil());
    for (var s = 0; s <= steps; s++) {
      final t = s / steps;
      final x = a.x + (b.x - a.x) * t;
      final y = a.y + (b.y - a.y) * t;
      pathCells.add('${x.floor()},${y.floor()}');
    }
  }

  DefenseVec pointAt(double d) {
    if (d <= 0) return points.first;
    if (d >= total) return points.last;
    var seg = 1;
    while (seg < points.length - 1 && d > cumulative[seg]) {
      seg++;
    }
    final a = points[seg - 1];
    final b = points[seg];
    final segLen = cumulative[seg] - cumulative[seg - 1];
    final t = segLen <= 0 ? 0.0 : (d - cumulative[seg - 1]) / segLen;
    return DefenseVec(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
    );
  }

  DefenseVec tangentAt(double d) {
    var seg = 1;
    while (seg < points.length - 1 && d > cumulative[seg]) {
      seg++;
    }
    return (points[seg] - points[seg - 1]).normalized;
  }

  final slots = <DefenseCell>[];
  var side = 1;
  for (var d = 2.2; d <= total - 1.6; d += 2.6) {
    final pos = pointAt(d);
    final tangent = tangentAt(d);
    final normal = DefenseVec(-tangent.y, tangent.x);
    // 依次尝试左右两侧，跳过压路径或超出地图的格子
    for (final sign in [side, -side]) {
      final c = DefenseCell(
        (pos.x + normal.x * sign).floor(),
        (pos.y + normal.y * sign).floor(),
      );
      if (c.col < 0 || c.col >= defenseCols || c.row < 0 || c.row >= defenseRows) {
        continue;
      }
      if (pathCells.contains('${c.col},${c.row}')) continue;
      if (slots.any((s) => s.center.distanceTo(c.center) < 1.5)) continue;
      slots.add(c);
      break;
    }
    side = -side;
  }
  return slots;
}

/// 按关卡序号生成波次：6~8 波，第 5（或第 8）波出魔王
List<DefenseWave> _wavesFor(int level) {
  final waveCount = level == 1 ? 6 : (level == 5 ? 8 : 7);
  final bossWave = waveCount >= 8 ? 8 : 5;
  final waves = <DefenseWave>[];

  for (var i = 1; i <= waveCount; i++) {
    final spawns = <DefenseSpawn>[];
    if (i == bossWave) {
      spawns.add(
        DefenseSpawn(
          DefenseEnemyType.boss,
          level >= 4 ? 2 : 1,
          gap: 5,
          delay: 1,
        ),
      );
      spawns.add(DefenseSpawn(DefenseEnemyType.normal, 4 + level, gap: 1));
    } else {
      // 脱水怪为每波主体，数量随波次与关卡序号递增
      spawns.add(
        DefenseSpawn(
          DefenseEnemyType.normal,
          3 + i + level * 2,
          gap: math.max(0.42, 1.0 - i * 0.06),
        ),
      );
      if (i >= 2) {
        spawns.add(
          DefenseSpawn(DefenseEnemyType.fast, 1 + i + level, gap: 0.75, delay: 1.2),
        );
      }
      if (i >= 3) {
        spawns.add(
          DefenseSpawn(
            DefenseEnemyType.armored,
            i - 1 + level ~/ 2,
            gap: 1.2,
            delay: 2.2,
          ),
        );
      }
    }
    waves.add(DefenseWave(spawns));
  }
  return waves;
}

/// 取指定关卡（越界时收敛到 1~5）
DefenseLevel defenseLevelFor(int index) {
  final i = index.clamp(1, DefenseRules.levelCount);
  return defenseLevels[i - 1];
}
