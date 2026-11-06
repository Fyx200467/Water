// 吨吨守卫战：纯数据模型与数值配置（不依赖 Flutter，便于单测）
//
// 坐标系：以格子为单位，(0,0) 为地图左上角格；格子中心为 (col + 0.5, row + 0.5)。
// 路径、怪物、弹道均使用「格坐标」，渲染时再乘以格子像素大小。

import 'dart:math' as math;

/// 地图尺寸（格）
const int defenseCols = 9;
const int defenseRows = 16;

/// 二维坐标（单位：格）
class DefenseVec {
  const DefenseVec(this.x, this.y);

  final double x;
  final double y;

  static const DefenseVec zero = DefenseVec(0, 0);

  DefenseVec operator +(DefenseVec o) => DefenseVec(x + o.x, y + o.y);

  DefenseVec operator -(DefenseVec o) => DefenseVec(x - o.x, y - o.y);

  DefenseVec operator *(double s) => DefenseVec(x * s, y * s);

  double get length => math.sqrt(x * x + y * y);

  double distanceTo(DefenseVec o) => (this - o).length;

  /// 单位向量；零向量返回 (0,0)
  DefenseVec get normalized {
    final len = length;
    return len <= 0.0001 ? zero : DefenseVec(x / len, y / len);
  }

  @override
  String toString() => 'DefenseVec($x, $y)';
}

/// 地图格子
class DefenseCell {
  const DefenseCell(this.col, this.row);

  final int col;
  final int row;

  DefenseVec get center => DefenseVec(col + 0.5, row + 0.5);

  @override
  bool operator ==(Object other) =>
      other is DefenseCell && other.col == col && other.row == row;

  @override
  int get hashCode => Object.hash(col, row);
}

/// 防御塔类型（基础数值为 1 级）
enum DefenseTowerType {
  droplet(
    label: '水滴塔',
    desc: '单体高频，稳定输出',
    cost: 40,
    range: 2.2,
    cooldown: 0.5,
    damage: 12,
    projectileSpeed: 9,
    color: 0xFF4DB8D8,
  ),
  cannon(
    label: '茶杯炮',
    desc: '范围爆炸，成片清怪',
    cost: 60,
    range: 1.9,
    cooldown: 1.25,
    damage: 20,
    splashRadius: 1.3,
    splashRatio: 0.9,
    projectileSpeed: 5.0,
    color: 0xFFE8A94A,
  ),
  ice(
    label: '冰饮塔',
    desc: '减速控场，拖住快怪',
    cost: 50,
    range: 2.0,
    cooldown: 0.9,
    damage: 8,
    slowFactor: 0.4,
    slowSeconds: 1.5,
    projectileSpeed: 8,
    color: 0xFF7FD6E8,
  );

  const DefenseTowerType({
    required this.label,
    required this.desc,
    required this.cost,
    required this.range,
    required this.cooldown,
    required this.damage,
    required this.projectileSpeed,
    required this.color,
    this.splashRadius = 0,
    this.splashRatio = 0,
    this.slowFactor = 0,
    this.slowSeconds = 0,
  });

  final String label;
  final String desc;

  /// 建造价格
  final int cost;

  /// 射程（格）
  final double range;

  /// 射击间隔（秒）
  final double cooldown;

  /// 单发伤害
  final double damage;

  /// 溅射半径（格）；0 表示无溅射
  final double splashRadius;

  /// 溅射伤害比例（0~1）
  final double splashRatio;

  /// 减速比例（0~1，0 表示无减速）
  final double slowFactor;

  /// 减速持续时间（秒）
  final double slowSeconds;

  /// 弹道飞行速度（格/秒）
  final double projectileSpeed;

  /// 主题色（0xAARRGGBB）
  final int color;

  /// 是否为范围伤害（溅射半径 > 0）
  bool get isAoe => splashRadius > 0;
}

/// 怪物类型
enum DefenseEnemyType {
  normal(
    label: '脱水怪',
    hp: 60,
    speed: 1.1,
    reward: 8,
    radius: 0.30,
    color: 0xFF6BCB77,
  ),
  fast(
    label: '干燥怪',
    hp: 40,
    speed: 1.9,
    reward: 9,
    radius: 0.26,
    color: 0xFFF08C4A,
  ),
  armored(
    label: '奶茶怪',
    hp: 120,
    speed: 0.9,
    reward: 14,
    armor: 0.3,
    radius: 0.33,
    color: 0xFFC99A62,
  ),
  boss(
    label: '焦渴魔王',
    hp: 800,
    speed: 0.8,
    reward: 20,
    radius: 0.50,
    color: 0xFF9B7BE8,
  );

  const DefenseEnemyType({
    required this.label,
    required this.hp,
    required this.speed,
    required this.reward,
    required this.radius,
    required this.color,
    this.armor = 0,
  });

  final String label;

  /// 1 级地图下的基础血量
  final double hp;

  /// 移动速度（格/秒）
  final double speed;

  /// 击杀获得的金币
  final int reward;

  /// 减伤比例（0~1）
  final double armor;

  /// 绘制半径（格）
  final double radius;

  /// 主题色
  final int color;
}

/// 一只怪物
class DefenseEnemy {
  DefenseEnemy({
    required this.id,
    required this.type,
    required this.maxHp,
  }) : hp = maxHp;

  final int id;
  final DefenseEnemyType type;
  final double maxHp;

  double hp;

  /// 沿路径已行进的距离（格）
  double dist = 0;

  /// 当前位置（格坐标）
  DefenseVec pos = DefenseVec.zero;

  /// 减速截止时刻（游戏时钟）
  double slowUntil = 0;

  /// 当前减速比例（0~1）
  double slowFactor = 0;

  /// 受击闪白剩余时间
  double hitFlash = 0;

  /// 行走相位（渲染时用于上下弹跳与左右摇摆）
  double walkPhase = 0;

  /// 血条的滞后显示比例（掉血时慢慢追下去，形成“掉血条”动效）
  double barRatio = 1;

  bool get alive => hp > 0;

  bool get slowed => slowFactor > 0 && slowUntil > 0;

  double get hpRatio => maxHp <= 0 ? 0 : (hp / maxHp).clamp(0.0, 1.0);
}

/// 一座已建造的防御塔
class DefenseTower {
  DefenseTower({
    required this.id,
    required this.type,
    required this.cell,
  }) : invested = type.cost;

  final int id;
  final DefenseTowerType type;
  final DefenseCell cell;

  int level = 1;

  /// 累计投入金币（出售时按比例返还）
  int invested;

  /// 射击冷却剩余时间
  double cooldown = 0;

  /// 目标朝向（弧度，指向当前锁定的目标；冷却期间也会持续更新）
  double aimAngle = -math.pi / 2;

  /// 视觉朝向（弧度）：每帧向 [aimAngle] 平滑靠拢，绘制时用它，
  /// 让矛头转动看起来自然，而不是开火瞬间“掰头”
  double visualAngle = -math.pi / 2;

  /// 后坐力（1 → 0 衰减，渲染时沿炮口反方向缩进）
  double recoil = 0;

  /// 炮口闪光剩余时间（秒）
  double flash = 0;

  /// 待机旋转相位（冰塔雪花旋转）
  double spin = 0;

  DefenseVec get center => cell.center;
}

/// 飞行中的弹道
class DefenseProjectile {
  DefenseProjectile({
    required this.id,
    required this.type,
    required this.pos,
    required this.target,
    required this.damage,
  }) : aim = target?.pos ?? pos;

  final int id;
  final DefenseTowerType type;

  DefenseVec pos;

  /// 追踪目标；目标死亡后按最后位置结算溅射
  DefenseEnemy? target;

  DefenseVec aim;

  final double damage;

  /// 出生时间（渲染用）
  double age = 0;

  /// 已命中，等待清理
  bool done = false;
}

/// 命中特效（溅射圈 / 减速雪花）
class DefenseBurst {
  DefenseBurst({
    required this.pos,
    required this.radius,
    required this.color,
    this.life = 0.32,
  });

  final DefenseVec pos;
  final double radius;
  final int color;
  final double life;
  double age = 0;

  double get progress => (age / life).clamp(0.0, 1.0);
}

/// 一波中某种怪物的生成配置
class DefenseSpawn {
  const DefenseSpawn(
    this.type,
    this.count, {
    this.gap = 1.0,
    this.delay = 0.0,
  });

  final DefenseEnemyType type;
  final int count;

  /// 同种怪之间的生成间隔（秒）
  final double gap;

  /// 相对本波开始的延迟（秒）
  final double delay;
}

/// 一波怪物
class DefenseWave {
  const DefenseWave(this.spawns);

  final List<DefenseSpawn> spawns;

  int get totalCount =>
      spawns.fold<int>(0, (sum, s) => sum + s.count);
}

/// 一关的地图与波次配置
class DefenseLevel {
  const DefenseLevel({
    required this.index,
    required this.name,
    required this.waypoints,
    required this.slots,
    required this.waves,
    required this.startGold,
    required this.lives,
    required this.hpScale,
  });

  /// 关卡序号（1 起）
  final int index;

  final String name;

  /// 路径折线拐点（格坐标，可越出地图边界表示入口/出口）
  final List<DefenseVec> waypoints;

  /// 固定炮位（不可自由建塔）
  final List<DefenseCell> slots;

  final List<DefenseWave> waves;

  final int startGold;

  final int lives;

  /// 本关怪物血量倍率
  final double hpScale;

  bool hasSlot(int col, int row) =>
      slots.any((s) => s.col == col && s.row == row);

  DefenseCell? slotAt(int col, int row) {
    for (final s in slots) {
      if (s.col == col && s.row == row) return s;
    }
    return null;
  }
}
