import 'package:flutter/foundation.dart';

/// 性别
enum Gender {
  male('男'),
  female('女'),
  other('其他');

  const Gender(this.label);
  final String label;
}

/// 日常活动量
enum ActivityLevel {
  low('低', 0, '久坐 / 办公室工作'),
  medium('中', 350, '每周 1-3 次轻运动'),
  high('高', 700, '每周 3+ 次高强度运动');

  const ActivityLevel(this.label, this.extraMl, this.description);
  final String label;
  final int extraMl;
  final String description;
}

/// PRD §2.1 用户档案 + 目标计算入参
@immutable
class UserProfile {
  const UserProfile({
    required this.id,
    required this.gender,
    required this.weightKg,
    required this.heightCm,
    required this.age,
    required this.activityLevel,
    required this.dailyGoalMl,
    this.createdAt,
    this.updatedAt,
  });

  factory UserProfile.create({
    required Gender gender,
    required double weightKg,
    required double heightCm,
    required int age,
    required ActivityLevel activityLevel,
    int? customGoalMl,
  }) {
    final now = DateTime.now();
    final goal = customGoalMl ?? _calculateGoal(
      gender: gender,
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      activity: activityLevel,
    );
    return UserProfile(
      id: 1,
      gender: gender,
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      activityLevel: activityLevel,
      dailyGoalMl: goal,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 单实例 App，本地存储固定 id=1
  final int id;
  final Gender gender;
  final double weightKg;
  final double heightCm;
  final int age;
  final ActivityLevel activityLevel;
  final int dailyGoalMl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserProfile copyWith({
    Gender? gender,
    double? weightKg,
    double? heightCm,
    int? age,
    ActivityLevel? activityLevel,
    int? dailyGoalMl,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id,
      gender: gender ?? this.gender,
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm ?? this.heightCm,
      age: age ?? this.age,
      activityLevel: activityLevel ?? this.activityLevel,
      dailyGoalMl: dailyGoalMl ?? this.dailyGoalMl,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// PRD §2.1 智能饮水量目标算法
  /// 基础目标 = 体重(kg) × 35ml
  /// 活动量加成：低 +0、中 +350、高 +700
  /// 性别修正：男 × 1.0、女 × 0.9
  /// 身高修正：身高>175 +200
  /// 夹紧 [1500, 4000]
  static int _calculateGoal({
    required Gender gender,
    required double weightKg,
    required double heightCm,
    required int age,
    required ActivityLevel activity,
  }) {
    double base = weightKg * 35.0;
    base += activity.extraMl;
    if (gender == Gender.female) base *= 0.9;
    if (heightCm > 175) base += 200;
    // 老人代谢慢、青少年需要更多 — 简化处理
    if (age >= 65) base -= 200;
    final rounded = (base / 50).round() * 50;
    return rounded.clamp(1500, 4000);
  }

  factory UserProfile.fromMap(Map<String, dynamic> m) {
    int toInt(dynamic v, int d) {
      if (v == null || v == '') return d;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? d;
    }
    double toDouble(dynamic v, double d) {
      if (v == null || v == '') return d;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? d;
    }
    String? toStr(dynamic v) {
      if (v == null || v == '') return null;
      return v.toString();
    }
    return UserProfile(
      id: toInt(m['id'], 1),
      gender: Gender.values.firstWhere(
        (g) => g.name == m['gender'],
        orElse: () => Gender.male,
      ),
      weightKg: toDouble(m['weight_kg'], 60),
      heightCm: toDouble(m['height_cm'], 170),
      age: toInt(m['age'], 25),
      activityLevel: ActivityLevel.values.firstWhere(
        (a) => a.name == m['activity_level'],
        orElse: () => ActivityLevel.low,
      ),
      dailyGoalMl: toInt(m['daily_goal_ml'], 2000),
      createdAt: toStr(m['created_at']) != null ? DateTime.tryParse(toStr(m['created_at'])!) : null,
      updatedAt: toStr(m['updated_at']) != null ? DateTime.tryParse(toStr(m['updated_at'])!) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'gender': gender.name,
      'weight_kg': weightKg,
      'height_cm': heightCm,
      'age': age,
      'activity_level': activityLevel.name,
      'daily_goal_ml': dailyGoalMl,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
