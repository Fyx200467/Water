// 吨吨守卫战：单局逻辑引擎（纯 Dart，可脱离 UI 运行）
//
// 职责：路径推进、波次生成、索敌开火、弹道命中/溅射/减速、
// 建塔升级出售，以及胜负结算。屏幕层只负责渲染与交互。

import 'dart:math' as math;

import 'defense_models.dart';
import 'defense_rules.dart';

/// 对局状态
enum DefensePhase { playing, won, lost }

/// 建塔结果
enum DefensePlaceResult { ok, notPlaying, notSlot, occupied, noGold }

/// 升级结果
enum DefenseUpgradeResult { ok, notPlaying, missing, maxLevel, noGold }

/// 正在生成的怪物队列
class _Spawner {
  _Spawner(this.spawn, this.timer);

  final DefenseSpawn spawn;
  double timer;
  int spawned = 0;

  bool get done => spawned >= spawn.count;
}

/// 单局塔防
class DefenseGame {
  DefenseGame({required this.level})
    : gold = level.startGold,
      lives = level.lives {
    _buildPath();
  }

  final DefenseLevel level;

  int gold;
  int lives;

  /// 游戏时钟（秒）
  double clock = 0;

  DefensePhase phase = DefensePhase.playing;

  /// 已击杀数量
  int kills = 0;

  /// 已开始的波次（1 起）
  int currentWave = 0;

  /// 是否已经点过出口的开始标记（布阵阶段不出怪）
  bool _started = false;
  bool get started => _started;

  /// 已生成完毕的波次
  int wavesCleared = 0;

  /// 距离下一波开始的秒数
  double _nextWaveIn = 0;

  final List<DefenseTower> towers = [];
  final List<DefenseEnemy> enemies = [];
  final List<DefenseProjectile> projectiles = [];
  final List<DefenseBurst> bursts = [];

  final List<_Spawner> _spawners = [];

  final List<DefenseVec> _points = [];
  final List<double> _cumulative = [];
  double pathLength = 0;

  int _nextTowerId = 1;
  int _nextEnemyId = 1;
  int _nextProjectileId = 1;

  bool get isPlaying => phase == DefensePhase.playing;

  int get waveCount => level.waves.length;

  /// 下一波倒计时（>0 时显示「下一波」；已全部开始时为 0）
  double get nextWaveIn =>
      _nextWaveIn.isFinite ? math.max(0, _nextWaveIn) : 0;

  /// 本关路径折线（已换算为格子中心坐标）
  List<DefenseVec> get pathPoints => List<DefenseVec>.unmodifiable(_points);

  /// 剩余敌人数（含尚未生成的）
  int get remainingEnemies =>
      enemies.length + _spawners.fold<int>(0, (sum, s) => sum + (s.spawn.count - s.spawned));

  // ==================== 路径 ====================

  void _buildPath() {
    for (final p in level.waypoints) {
      _points.add(DefenseVec(p.x + 0.5, p.y + 0.5));
    }
    _cumulative.add(0);
    var total = 0.0;
    for (var i = 1; i < _points.length; i++) {
      total += _points[i - 1].distanceTo(_points[i]);
      _cumulative.add(total);
    }
    pathLength = total;
  }

  /// 沿路径行进 [dist] 格后的位置
  DefenseVec positionAt(double dist) {
    if (_points.isEmpty) return DefenseVec.zero;
    if (dist <= 0) return _points.first;
    if (dist >= pathLength) return _points.last;
    for (var i = 1; i < _points.length; i++) {
      if (dist <= _cumulative[i]) {
        final segLen = _cumulative[i] - _cumulative[i - 1];
        final t = segLen <= 0 ? 0.0 : (dist - _cumulative[i - 1]) / segLen;
        final a = _points[i - 1];
        final b = _points[i];
        return DefenseVec(
          a.x + (b.x - a.x) * t,
          a.y + (b.y - a.y) * t,
        );
      }
    }
    return _points.last;
  }

  // ==================== 建造 ====================

  DefenseTower? towerAt(int col, int row) {
    for (final t in towers) {
      if (t.cell.col == col && t.cell.row == row) return t;
    }
    return null;
  }

  DefensePlaceResult placeTower(
    int col,
    int row,
    DefenseTowerType type,
  ) {
    if (!isPlaying) return DefensePlaceResult.notPlaying;
    final slot = level.slotAt(col, row);
    if (slot == null) return DefensePlaceResult.notSlot;
    if (towerAt(col, row) != null) return DefensePlaceResult.occupied;
    if (gold < type.cost) return DefensePlaceResult.noGold;
    gold -= type.cost;
    towers.add(
      DefenseTower(id: _nextTowerId++, type: type, cell: slot),
    );
    return DefensePlaceResult.ok;
  }

  DefenseUpgradeResult upgradeTower(DefenseTower tower) {
    if (!isPlaying) return DefenseUpgradeResult.notPlaying;
    if (!towers.contains(tower)) return DefenseUpgradeResult.missing;
    if (tower.level >= DefenseRules.maxTowerLevel) {
      return DefenseUpgradeResult.maxLevel;
    }
    final cost = DefenseRules.upgradeCost(tower.type, tower.level);
    if (gold < cost) return DefenseUpgradeResult.noGold;
    gold -= cost;
    tower.invested += cost;
    tower.level += 1;
    return DefenseUpgradeResult.ok;
  }

  /// 出售防御塔，返回返还金币；不在本局则返回 0
  int sellTower(DefenseTower tower) {
    if (!isPlaying || !towers.remove(tower)) return 0;
    final refund = DefenseRules.sellValue(tower.invested);
    gold += refund;
    return refund;
  }

  // ==================== 主循环 ====================

  /// 布阵结束，开始出怪（点击出口的开始标记时调用）
  void startWaves() {
    if (!isPlaying || _started) return;
    _started = true;
    _nextWaveIn = 0;
  }

  void update(double dt) {
    if (phase != DefensePhase.playing || dt <= 0) return;
    // 掉帧时限制单步时长，避免怪物瞬移跳过炮塔判定
    final step = math.min(dt, 0.1);
    clock += step;
    _updateWaves(step);
    _updateEnemies(step);
    _updateTowers(step);
    _updateProjectiles(step);
    _updateBursts(step);
    enemies.removeWhere((e) => !e.alive);
    _checkEnd();
  }

  void _updateWaves(double dt) {
    // 布阵阶段：不出怪，也不走倒计时
    if (!_started) return;
    if (_spawners.isNotEmpty) {
      for (final s in _spawners) {
        s.timer -= dt;
        while (s.timer <= 0 && s.spawned < s.spawn.count) {
          _spawnEnemy(s.spawn.type);
          s.spawned += 1;
          s.timer += s.spawn.gap;
        }
      }
      if (_spawners.every((s) => s.done)) {
        _spawners.clear();
        wavesCleared += 1;
        gold += DefenseRules.waveGold;
        _nextWaveIn = currentWave >= waveCount
            ? double.infinity
            : DefenseRules.waveInterval;
      }
      return;
    }

    if (currentWave >= waveCount) return;
    _nextWaveIn -= dt;
    if (_nextWaveIn <= 0) {
      _startWave(currentWave);
      _nextWaveIn = double.infinity; // 生成期间不计时
    }
  }

  void _startWave(int index) {
    final wave = level.waves[index];
    for (final spawn in wave.spawns) {
      if (spawn.count <= 0) continue;
      _spawners.add(_Spawner(spawn, spawn.delay));
    }
    if (_spawners.isEmpty) {
      // 空波直接算过
      currentWave += 1;
      wavesCleared += 1;
      _nextWaveIn = DefenseRules.waveInterval;
      return;
    }
    currentWave += 1;
  }

  void _spawnEnemy(DefenseEnemyType type) {
    // 同一关内越往后的波次血量越高，前松后紧，避免后期挂机
    final waveFactor = 1 + 0.08 * math.max(0, currentWave - 1);
    final hp = type.hp * level.hpScale * waveFactor;
    final enemy = DefenseEnemy(
      id: _nextEnemyId++,
      type: type,
      maxHp: hp,
    );
    enemy.pos = positionAt(0);
    enemies.add(enemy);
  }

  void _updateEnemies(double dt) {
    for (final e in enemies) {
      if (!e.alive) continue;
      if (e.hitFlash > 0) e.hitFlash -= dt;
      // 血条缓慢追平实际血量，掉血时有下滑动效
      e.barRatio += (e.hpRatio - e.barRatio) * math.min(1.0, dt * 9);
      // 行走相位：速度越快的怪倒腾得越勤
      e.walkPhase += dt * (4.5 + e.type.speed * 2.4);
      final slow = clock < e.slowUntil ? 1 - e.slowFactor : 1.0;
      e.dist += e.type.speed * slow * dt;
      if (e.dist >= pathLength) {
        e.pos = positionAt(pathLength);
        // 漏怪：BOSS 扣 3 点生命，其余扣 1 点；生命不会掉到负数
        final lost = e.type == DefenseEnemyType.boss ? 3 : 1;
        lives = math.max(0, lives - lost);
        e.hp = 0;
        continue;
      }
      e.pos = positionAt(e.dist);
    }
  }

  void _updateTowers(double dt) {
    for (final t in towers) {
      // 动效状态：后坐力回弹、炮口闪光衰减、冰塔雪花旋转
      if (t.recoil > 0) t.recoil = math.max(0, t.recoil - dt * 5.0);
      if (t.flash > 0) t.flash = math.max(0, t.flash - dt);
      t.spin += dt * (t.type == DefenseTowerType.ice ? 2.4 : 1.1);

      // 索敌与转向每帧都做：冷却中、暂未开火时也持续把矛头转向目标，
      // 避免“站桩不动，开火瞬间才瞬间转向”的突兀动画
      final target = _targetFor(t);
      if (target != null) {
        t.aimAngle = math.atan2(
          target.pos.y - t.center.y,
          target.pos.x - t.center.x,
        );
      }
      final turnSpeed = t.type == DefenseTowerType.droplet ? 12.0 : 9.0;
      final diff = _angleDelta(t.aimAngle - t.visualAngle);
      final maxTurn = turnSpeed * dt;
      t.visualAngle = diff.abs() <= maxTurn
          ? t.aimAngle
          : t.visualAngle + diff.sign * maxTurn;

      if (t.cooldown > 0) {
        t.cooldown -= dt;
        if (t.cooldown > 0) continue;
      }
      if (target == null) continue;
      t.cooldown = DefenseRules.cooldownOf(t.type, t.level);
      t.recoil = 1;
      t.flash = t.type == DefenseTowerType.cannon ? 0.24 : 0.15;
      projectiles.add(
        DefenseProjectile(
          id: _nextProjectileId++,
          type: t.type,
          pos: _muzzlePos(t),
          target: target,
          damage: DefenseRules.damageOf(t.type, t.level),
        ),
      );
    }
  }

  /// 炮弹出膛位置：水滴从矛尖射出，茶杯炮从杯口（杯中心上方）抛出
  DefenseVec _muzzlePos(DefenseTower t) {
    switch (t.type) {
      case DefenseTowerType.droplet:
        return t.center +
            DefenseVec(
                  math.cos(t.visualAngle),
                  math.sin(t.visualAngle),
                ) *
                0.18;
      case DefenseTowerType.cannon:
        return DefenseVec(t.center.x, t.center.y - 0.16);
      case DefenseTowerType.ice:
        return t.center;
    }
  }

  /// 归一化到 (-π, π]，用于取最短转向角差
  static double _angleDelta(double a) {
    var d = a;
    while (d > math.pi) {
      d -= math.pi * 2;
    }
    while (d <= -math.pi) {
      d += math.pi * 2;
    }
    return d;
  }

  /// 射程内沿路径走得最远的敌人
  DefenseEnemy? _targetFor(DefenseTower tower) {
    final range = DefenseRules.rangeOf(tower.type, tower.level);
    DefenseEnemy? best;
    for (final e in enemies) {
      if (!e.alive) continue;
      if (tower.center.distanceTo(e.pos) > range) continue;
      if (best == null || e.dist > best.dist) best = e;
    }
    return best;
  }

  void _updateProjectiles(double dt) {
    for (final p in projectiles) {
      if (p.done) continue;
      p.age += dt;
      final target = p.target;
      if (target != null && target.alive) p.aim = target.pos;
      final delta = p.aim - p.pos;
      final step = p.type.projectileSpeed * dt;
      if (delta.length <= step || delta.length < 0.06) {
        p.pos = p.aim;
        _impact(p);
      } else {
        p.pos = p.pos + delta.normalized * step;
      }
    }
    projectiles.removeWhere((p) => p.done);
  }

  void _impact(DefenseProjectile p) {
    p.done = true;
    switch (p.type) {
      case DefenseTowerType.droplet:
        // 目标可能在飞行途中死亡或被减速：改为命中落点附近的敌人，
        // 避免单体弹“空放”浪费一发
        final hit = _nearestEnemy(p.pos, 0.8);
        if (hit != null) _damage(hit, p.damage);
        break;
      case DefenseTowerType.cannon:
        // 主目标死亡时，把落点最近的敌人当作主目标吃满伤害
        final primary = (p.target != null && p.target!.alive)
            ? p.target
            : _nearestEnemy(p.pos, 0.6);
        for (final e in enemies) {
          if (!e.alive) continue;
          if (e.pos.distanceTo(p.pos) > p.type.splashRadius) continue;
          final dmg = identical(e, primary)
              ? p.damage
              : p.damage * p.type.splashRatio;
          _damage(e, dmg);
        }
        bursts.add(
          DefenseBurst(
            pos: p.pos,
            radius: p.type.splashRadius,
            color: p.type.color,
          ),
        );
        break;
      case DefenseTowerType.ice:
        final hit = _nearestEnemy(p.pos, 0.8);
        if (hit != null) {
          _damage(hit, p.damage);
          hit.slowFactor = p.type.slowFactor;
          hit.slowUntil = clock + p.type.slowSeconds;
          bursts.add(
            DefenseBurst(pos: hit.pos, radius: 0.45, color: p.type.color),
          );
        }
    }
  }

  /// 落点附近最近的存活敌人
  DefenseEnemy? _nearestEnemy(DefenseVec pos, double radius) {
    DefenseEnemy? best;
    var bestDist = radius;
    for (final e in enemies) {
      if (!e.alive) continue;
      final d = e.pos.distanceTo(pos);
      if (d <= bestDist) {
        bestDist = d;
        best = e;
      }
    }
    return best;
  }

  void _damage(DefenseEnemy e, double raw) {
    if (!e.alive || raw <= 0) return;
    e.hp -= raw * (1 - e.type.armor);
    e.hitFlash = 0.16;
    if (!e.alive) {
      kills += 1;
      gold += e.type.reward;
      // 死亡时给一个小爆点（复用溅射特效）
      bursts.add(
        DefenseBurst(pos: e.pos, radius: e.type.radius * 1.2, color: e.type.color),
      );
    }
  }

  void _updateBursts(double dt) {
    for (final b in bursts) {
      b.age += dt;
    }
    bursts.removeWhere((b) => b.age >= b.life);
  }

  void _checkEnd() {
    if (lives <= 0) {
      lives = 0;
      phase = DefensePhase.lost;
      return;
    }
    if (currentWave >= waveCount &&
        _spawners.isEmpty &&
        enemies.isEmpty) {
      phase = DefensePhase.won;
    }
  }

  /// 供 UI 预览：未开始的波次总数
  int get unstartedWaves => math.max(0, waveCount - currentWave);
}
