// 吨吨守卫战：数值成长与结算规则（纯 Dart）

import 'dart:math' as math;

import 'defense_models.dart';

/// 塔防玩法规则常量与计算
class DefenseRules {
  const DefenseRules._();

  /// 内置关卡总数
  static const int levelCount = 5;

  /// 防御塔最高等级
  static const int maxTowerLevel = 3;

  /// 出售返还比例
  static const double sellRatio = 0.7;

  /// 升级价格 = 造价 × 该系数 × 当前等级
  static const double upgradeCostFactor = 1.2;

  /// 每升一级：伤害 ×1.35、射程 ×1.08、射击间隔 ×0.88
  static const double damageGrowth = 1.35;
  static const double rangeGrowth = 1.08;
  static const double cooldownGrowth = 0.88;

  /// 每清完一波的额外金币
  static const int waveGold = 20;

  /// 两波之间的间隔（秒）
  static const double waveInterval = 6;

  static double damageOf(DefenseTowerType type, int level) =>
      type.damage * math.pow(damageGrowth, level - 1).toDouble();

  static double rangeOf(DefenseTowerType type, int level) =>
      type.range * math.pow(rangeGrowth, level - 1).toDouble();

  static double cooldownOf(DefenseTowerType type, int level) =>
      type.cooldown * math.pow(cooldownGrowth, level - 1).toDouble();

  /// 从 [level] 升到下一级的价格；已满级返回 0
  static int upgradeCost(DefenseTowerType type, int level) {
    if (level >= maxTowerLevel) return 0;
    return (type.cost * upgradeCostFactor * level).round();
  }

  /// 出售返还金币
  static int sellValue(int invested) => (invested * sellRatio).round();

  /// 通关积分：60 + 剩余生命 × 4 + 关卡系数；重复通关按 60% 折算
  static int scoreFor({
    required int levelIndex,
    required int lives,
    required bool repeat,
  }) {
    final base = 60 + math.max(0, lives) * 4 + (levelIndex - 1) * 8;
    return repeat ? (base * 0.6).round() : base;
  }
}
