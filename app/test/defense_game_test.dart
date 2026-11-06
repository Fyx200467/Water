import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:water_llama/features/games/defense/defense_game.dart';
import 'package:water_llama/features/games/defense/defense_levels.dart';
import 'package:water_llama/features/games/defense/defense_models.dart';
import 'package:water_llama/features/games/defense/defense_rules.dart';
import 'package:water_llama/features/points/points_provider.dart';

void main() {
  group('关卡配置', () {
    test('5 个内置关卡，路径轴对齐且炮位不与路径重叠', () {
      expect(defenseLevels.length, DefenseRules.levelCount);

      for (final level in defenseLevels) {
        expect(level.waves.isNotEmpty, true);

        // 折线必须横平竖直
        for (var i = 1; i < level.waypoints.length; i++) {
          final a = level.waypoints[i - 1];
          final b = level.waypoints[i];
          final horizontal = (a.y - b.y).abs() < 0.001;
          final vertical = (a.x - b.x).abs() < 0.001;
          expect(
            horizontal || vertical,
            true,
            reason: '第 ${level.index} 关第 $i 段路径不是横平竖直',
          );
        }

        // 路径经过的格子（只统计地图内）
        final pathCells = <String>{};
        for (var i = 1; i < level.waypoints.length; i++) {
          final a = level.waypoints[i - 1];
          final b = level.waypoints[i];
          final minX = a.x < b.x ? a.x : b.x;
          final maxX = a.x > b.x ? a.x : b.x;
          final minY = a.y < b.y ? a.y : b.y;
          final maxY = a.y > b.y ? a.y : b.y;
          for (var x = minX; x <= maxX; x++) {
            for (var y = minY; y <= maxY; y++) {
              if (x >= 0 && x < 9 && y >= 0 && y < 16) {
                pathCells.add('${x.toInt()},${y.toInt()}');
              }
            }
          }
        }

        for (final slot in level.slots) {
          expect(
            pathCells.contains('${slot.col},${slot.row}'),
            false,
            reason: '第 ${level.index} 关炮位 (${slot.col}, ${slot.row}) 压在路径上',
          );
          expect(
            slot.col >= 0 && slot.col < 9 && slot.row >= 0 && slot.row < 16,
            true,
            reason: '第 ${level.index} 关炮位越界',
          );
        }
      }
    });

    test('炮位自动生成：不重复、数量够用，且都在最短射程内', () {
      for (final level in defenseLevels) {
        final slots = level.slots;
        expect(slots.length, greaterThanOrEqualTo(8), reason: '第 ${level.index} 关炮位太少');
        expect(slots.toSet().length, slots.length, reason: '第 ${level.index} 关有重复炮位');

        // 最短射程（1 级水滴塔 2.2 格减去怪物半径）内必须能覆盖路径
        final minRange = DefenseRules.rangeOf(DefenseTowerType.droplet, 1);
        for (final slot in slots) {
          final d = _distanceToPath(slot.center, level.waypoints);
          expect(
            d,
            lessThanOrEqualTo(1.25),
            reason: '第 ${level.index} 关炮位 (${slot.col}, ${slot.row}) 距路径 $d 格，太远',
          );
          expect(
            d,
            lessThan(minRange),
            reason: '第 ${level.index} 关炮位 (${slot.col}, ${slot.row}) 超出射程',
          );
        }
      }
    });

    test('前 3 关 6~7 波、第 5 关 8 波，且都有 BOSS 波', () {
      for (final level in defenseLevels) {
        final expected = level.index == 1 ? 6 : (level.index == 5 ? 8 : 7);
        expect(level.waves.length, expected);
        final hasBoss = level.waves.any(
          (w) => w.spawns.any((s) => s.type == DefenseEnemyType.boss),
        );
        expect(hasBoss, true, reason: '第 ${level.index} 关缺少 BOSS');
      }
    });
  });

  group('数值规则', () {
    test('消消乐与守卫战的每日 500 分额度互不占用', () {
      final state = PointsState(
        history: [
          PointsRecord(source: 'match3', amount: 500, at: DateTime.now()),
        ],
      );
      expect(state.capReachedForSource('match3'), true);
      expect(state.earnedTodayForSource('match3'), 500);
      expect(state.earnedTodayForSource('defense'), 0);
      expect(state.capReachedForSource('defense'), false);
      expect(state.gameCapReached, true);
    });
    test('升级价格按「造价 ×1.2 × 当前等级」计算，满级不再升级', () {
      expect(DefenseRules.upgradeCost(DefenseTowerType.droplet, 1), 48);
      expect(DefenseRules.upgradeCost(DefenseTowerType.droplet, 2), 96);
      expect(DefenseRules.upgradeCost(DefenseTowerType.droplet, 3), 0);
      expect(DefenseRules.upgradeCost(DefenseTowerType.cannon, 1), 72);
    });

    test('出售返还 70% 投入', () {
      expect(DefenseRules.sellValue(184), 129);
      expect(DefenseRules.sellValue(40), 28);
    });

    test('通关积分：60 + 生命×4 + 关卡系数，重复通关 60%', () {
      expect(DefenseRules.scoreFor(levelIndex: 1, lives: 10, repeat: false), 100);
      expect(DefenseRules.scoreFor(levelIndex: 5, lives: 10, repeat: false), 132);
      expect(DefenseRules.scoreFor(levelIndex: 5, lives: 5, repeat: false), 112);
      expect(DefenseRules.scoreFor(levelIndex: 1, lives: 10, repeat: true), 60);
    });
  });

  group('建塔 / 升级 / 出售', () {
    test('只能建在固定炮位，重复建塔与金币不足会被拒绝', () {
      final game = DefenseGame(level: defenseLevelFor(1));
      final slot = game.level.slots.first;

      expect(
        game.placeTower(slot.col, slot.row, DefenseTowerType.droplet),
        DefensePlaceResult.ok,
      );
      expect(game.gold, 130 - DefenseTowerType.droplet.cost);
      expect(game.towers.length, 1);

      expect(
        game.placeTower(slot.col, slot.row, DefenseTowerType.droplet),
        DefensePlaceResult.occupied,
      );
      // 路径格与空白格都不能建塔
      expect(
        game.placeTower(1, 2, DefenseTowerType.droplet),
        DefensePlaceResult.notSlot,
      );

      game.gold = 0;
      final other = game.level.slots[1];
      expect(
        game.placeTower(other.col, other.row, DefenseTowerType.cannon),
        DefensePlaceResult.noGold,
      );
      expect(game.towers.length, 1);
    });

    test('升级消耗金币并提升等级，满级与金币不足有对应结果', () {
      final game = DefenseGame(level: defenseLevelFor(1));
      final slot = game.level.slots.first;
      game.placeTower(slot.col, slot.row, DefenseTowerType.droplet);
      final tower = game.towers.single;

      game.gold = 1000;
      expect(game.upgradeTower(tower), DefenseUpgradeResult.ok);
      expect(tower.level, 2);
      expect(game.gold, 1000 - 48);
      expect(game.upgradeTower(tower), DefenseUpgradeResult.ok);
      expect(tower.level, 3);
      expect(game.gold, 1000 - 48 - 96);
      expect(game.upgradeTower(tower), DefenseUpgradeResult.maxLevel);

      // 另一座新塔在 0 金币时无法升级
      final other = game.level.slots[1];
      game.gold = DefenseTowerType.ice.cost;
      expect(
        game.placeTower(other.col, other.row, DefenseTowerType.ice),
        DefensePlaceResult.ok,
      );
      final ice = game.towers.last;
      game.gold = 0;
      expect(game.upgradeTower(ice), DefenseUpgradeResult.noGold);
    });

    test('出售返还 70% 并移除塔', () {
      final game = DefenseGame(level: defenseLevelFor(1));
      final slot = game.level.slots.first;
      game.placeTower(slot.col, slot.row, DefenseTowerType.droplet);
      final tower = game.towers.single;
      game.gold = 1000;
      game.upgradeTower(tower);
      game.upgradeTower(tower);
      // 投入 40 + 48 + 96 = 184，返还 129
      expect(game.sellTower(tower), 129);
      expect(game.towers, isEmpty);
      expect(game.gold, 1000 - 48 - 96 + 129);
    });
  });

  group('对局推进', () {
    test('布阵阶段不出怪，点开始后才进入第一波', () {
      final game = DefenseGame(level: defenseLevelFor(1));
      expect(game.started, false);

      // 不点开始：等再久也不会出怪
      for (var i = 0; i < 10 * 60; i++) {
        game.update(1 / 60);
      }
      expect(game.currentWave, 0);
      expect(game.enemies, isEmpty);
      expect(game.remainingEnemies, 0);

      game.startWaves();
      expect(game.started, true);
      game.update(1 / 60);
      expect(game.currentWave, 1);
      expect(game.remainingEnemies, greaterThan(0));
    });

    test('漏怪会扣生命，无塔时无法坚持到最后', () {
      final game = DefenseGame(level: defenseLevelFor(1));
      game.startWaves();
      for (var i = 0; i < 90 * 60; i++) {
        game.update(1 / 60);
      }
      expect(game.currentWave, greaterThan(0));
      expect(game.lives, lessThan(10));
    });

    test('有塔时能击杀怪物并获得金币', () {
      final game = DefenseGame(level: defenseLevelFor(1));
      game.gold = 10000;
      for (final slot in game.level.slots.take(6)) {
        game.placeTower(slot.col, slot.row, DefenseTowerType.droplet);
      }
      game.startWaves();
      for (var i = 0; i < 120 * 60; i++) {
        game.update(1 / 60);
        if (game.phase != DefensePhase.playing) break;
      }
      expect(game.kills, greaterThan(0));
    });

    test('怪物沿路径前进且不超过终点', () {
      final game = DefenseGame(level: defenseLevelFor(1));
      // 点击开始后，等待首只怪入场
      game.startWaves();
      for (var i = 0; i < 8 * 60; i++) {
        game.update(1 / 60);
      }
      expect(game.enemies.isNotEmpty, true);
      final enemy = game.enemies.first;
      final startDist = enemy.dist;
      game.update(1);
      expect(enemy.dist, greaterThan(startDist));
      expect(enemy.dist, lessThanOrEqualTo(game.pathLength));
    });

    test('茶杯炮为真正的范围伤害：一发同时炸到多只怪', () {
      expect(DefenseTowerType.cannon.isAoe, true);
      expect(DefenseTowerType.cannon.splashRadius, greaterThan(1));

      final level = DefenseLevel(
        index: 1,
        name: '测试水道',
        waypoints: const [DefenseVec(-1, 3), DefenseVec(9, 3)],
        slots: const [DefenseCell(3, 4)],
        waves: const [
          DefenseWave([
            // 间隔极小 → 三只怪叠在一起，验证溅射范围
            DefenseSpawn(DefenseEnemyType.normal, 3, gap: 0.05),
          ]),
        ],
        startGold: 500,
        lives: 10,
        hpScale: 1,
      );
      final game = DefenseGame(level: level);
      expect(
        game.placeTower(3, 4, DefenseTowerType.cannon),
        DefensePlaceResult.ok,
      );
      final tower = game.towers.single;
      game.startWaves();

      // 等到第一发炮弹出膛
      for (var i = 0; i < 30 * 60 && game.projectiles.isEmpty; i++) {
        game.update(1 / 60);
      }
      expect(game.projectiles, isNotEmpty);
      // 开火瞬间：杯口闪光、后坐、朝向对准目标
      expect(tower.flash, greaterThan(0));
      expect(tower.recoil, greaterThan(0.5));
      expect(tower.aimAngle, isNot(closeTo(-math.pi / 2, 0.01)));

      // 落地后聚在一起的怪都被炸到（不是只打单体）
      for (var i = 0; i < 5 * 60 && game.projectiles.isNotEmpty; i++) {
        game.update(1 / 60);
      }
      final damaged = game.enemies.where((e) => e.hp < e.maxHp).length;
      expect(damaged, greaterThanOrEqualTo(2));
    });

    test('水滴塔冷却期间也持续转向，视觉朝向平滑逼近目标', () {
      final level = DefenseLevel(
        index: 1,
        name: '转向测试',
        waypoints: const [DefenseVec(-1, 3), DefenseVec(9, 3)],
        slots: const [DefenseCell(3, 4)],
        waves: const [
          DefenseWave([
            DefenseSpawn(DefenseEnemyType.normal, 1, gap: 1, delay: 30),
          ]),
        ],
        startGold: 500,
        lives: 10,
        hpScale: 1,
      );
      final game = DefenseGame(level: level);
      expect(
        game.placeTower(3, 4, DefenseTowerType.droplet),
        DefensePlaceResult.ok,
      );
      final tower = game.towers.single;

      // 放一只已经走到射程内的怪
      final enemy = DefenseEnemy(
        id: 99,
        type: DefenseEnemyType.normal,
        maxHp: 1000,
      );
      enemy.dist = 2.2;
      enemy.pos = game.positionAt(2.2);
      game.enemies.add(enemy);

      game.update(1 / 60);
      // 第一帧只转一小步，不会瞬间“掰头”
      expect(tower.aimAngle, isNot(closeTo(-math.pi / 2, 0.02)));
      expect((tower.visualAngle - tower.aimAngle).abs(), greaterThan(0.05));
      final firstAim = tower.aimAngle;

      // 冷却期间也会继续跟踪怪物，角度持续变化
      for (var i = 0; i < 10; i++) {
        game.update(1 / 60);
      }
      expect(tower.cooldown, greaterThan(0));
      expect((tower.aimAngle - firstAim).abs(), greaterThan(0.01));

      // 若干帧后视觉朝向追上目标朝向
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }
      expect((tower.visualAngle - tower.aimAngle).abs(), lessThan(0.02));
    });

    test('单体弹在目标死亡后仍能命中落点附近的敌人', () {
      final level = DefenseLevel(
        index: 1,
        name: '空放测试',
        waypoints: const [DefenseVec(-1, 3), DefenseVec(9, 3)],
        slots: const [DefenseCell(3, 4)],
        waves: const [
          DefenseWave([DefenseSpawn(DefenseEnemyType.normal, 1, gap: 1)]),
        ],
        startGold: 0,
        lives: 10,
        hpScale: 1,
      );
      final game = DefenseGame(level: level);
      final doomed = DefenseEnemy(
        id: 1,
        type: DefenseEnemyType.normal,
        maxHp: 100,
      );
      doomed.dist = 2.3;
      doomed.pos = game.positionAt(2.3);
      final bystander = DefenseEnemy(
        id: 2,
        type: DefenseEnemyType.normal,
        maxHp: 100,
      );
      bystander.dist = 2.6;
      bystander.pos = game.positionAt(2.6);
      game.enemies.addAll([doomed, bystander]);

      final shot = DefenseProjectile(
        id: 1,
        type: DefenseTowerType.droplet,
        pos: const DefenseVec(1.5, 3.5),
        target: doomed,
        damage: 30,
      );
      game.projectiles.add(shot);
      doomed.hp = 0; // 飞行途中目标死亡

      for (var i = 0; i < 5 && game.projectiles.isNotEmpty; i++) {
        game.update(1 / 60);
      }
      expect(game.projectiles, isEmpty);
      expect(bystander.hp, lessThan(bystander.maxHp));
    });

    test('怪物有行走相位，血条会滞后追平掉血', () {
      final game = DefenseGame(level: defenseLevelFor(1));
      game.startWaves();
      for (var i = 0; i < 8 * 60; i++) {
        game.update(1 / 60);
      }
      expect(game.enemies, isNotEmpty);
      final enemy = game.enemies.first;
      final phase = enemy.walkPhase;
      game.update(0.5);
      expect(enemy.walkPhase, greaterThan(phase));
      expect(enemy.barRatio, inInclusiveRange(0, 1));
    });
  });
}

/// 点到折线（路径按格子中心连线）的最短距离，单位：格
double _distanceToPath(DefenseVec p, List<DefenseVec> waypoints) {
  double best = double.infinity;
  for (var i = 1; i < waypoints.length; i++) {
    final a = DefenseVec(waypoints[i - 1].x + 0.5, waypoints[i - 1].y + 0.5);
    final b = DefenseVec(waypoints[i].x + 0.5, waypoints[i].y + 0.5);
    final ab = b - a;
    final len2 = ab.x * ab.x + ab.y * ab.y;
    var t = len2 <= 0 ? 0.0 : ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / len2;
    t = t.clamp(0.0, 1.0).toDouble();
    final closest = DefenseVec(a.x + ab.x * t, a.y + ab.y * t);
    final d = p.distanceTo(closest);
    if (d < best) best = d;
  }
  return best;
}
