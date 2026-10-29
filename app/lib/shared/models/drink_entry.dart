import 'package:flutter/foundation.dart';

import '../../core/time/logical_day.dart';
import 'beverage.dart';

/// PRD §2.3 单次饮水记录
/// 离线优先 + 同步队列（PRD §4.2）
@immutable
class DrinkEntry {
  const DrinkEntry({
    required this.clientId,
    required this.beverageId,
    required this.beverageCategory,
    required this.beverageName,
    required this.volumeMl,
    required this.effectiveMl,
    required this.drankAt,
    required this.synced,
    this.serverId,
    this.deleted = false,
    this.calories = -1,
    this.healthSampleId,
    this.healthState = healthNone,
    this.updatedAt,
  });

  /// 未与健康 App 交互
  static const int healthNone = 0;

  /// 本 App 写入健康 App 的记录（已导出）
  static const int healthExported = 1;

  /// 从健康 App 导入的记录（不再回写，避免重复）
  static const int healthImported = 2;

  /// 客户端 UUID，断网写入后联网去重
  final String clientId;
  final String? serverId;
  final String beverageId;
  final BeverageCategory beverageCategory;
  final String beverageName;
  final int volumeMl;
  final int effectiveMl;
  final DateTime drankAt;
  final bool synced;
  final bool deleted;

  /// 录入时快照的热量（kcal）；-1 = 历史旧记录未记录，展示时回退到饮品当前定义
  final int calories;

  /// 健康 App 里的样本 UUID（导入记录用来去重）
  final String? healthSampleId;

  /// 健康同步状态，见 [healthNone] / [healthExported] / [healthImported]
  final int healthState;

  /// 本记录最后一次修改时间（同步冲突按它做 LWW）；旧数据为空时按 [drankAt]
  final DateTime? updatedAt;

  DateTime get effectiveUpdatedAt => updatedAt ?? drankAt;

  DrinkEntry copyWith({
    String? serverId,
    bool? synced,
    bool? deleted,
    int? calories,
    String? healthSampleId,
    int? healthState,
    DateTime? updatedAt,
  }) {
    return DrinkEntry(
      clientId: clientId,
      beverageId: beverageId,
      beverageCategory: beverageCategory,
      beverageName: beverageName,
      volumeMl: volumeMl,
      effectiveMl: effectiveMl,
      drankAt: drankAt,
      synced: synced ?? this.synced,
      serverId: serverId ?? this.serverId,
      deleted: deleted ?? this.deleted,
      calories: calories ?? this.calories,
      healthSampleId: healthSampleId ?? this.healthSampleId,
      healthState: healthState ?? this.healthState,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 判断记录是否属于指定逻辑日（尊重「一天中的重置时间」设置）
  bool belongsToDay(DateTime day) => LogicalDay.sameDay(drankAt, day);

  Map<String, dynamic> toMap() {
    return {
      'client_id': clientId,
      'server_id': serverId,
      'beverage_id': beverageId,
      'beverage_category': beverageCategory.name,
      'beverage_name': beverageName,
      'volume_ml': volumeMl,
      'effective_ml': effectiveMl,
      'drank_at': drankAt.toIso8601String(),
      'synced': synced ? 1 : 0,
      'deleted': deleted ? 1 : 0,
      'calories': calories,
      'health_sample_id': healthSampleId,
      'health_state': healthState,
      'updated_at': effectiveUpdatedAt.toIso8601String(),
    };
  }

  factory DrinkEntry.fromMap(Map<String, dynamic> m) {
    int toInt(dynamic v, int d) {
      if (v == null || v == '') return d;
      if (v is bool) return v ? 1 : 0;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? d;
    }
    return DrinkEntry(
      clientId: m['client_id']?.toString() ?? '',
      serverId: m['server_id']?.toString(),
      beverageId: m['beverage_id']?.toString() ?? '',
      beverageCategory: BeverageCategory.values.firstWhere(
        (c) => c.name == m['beverage_category'],
        orElse: () => BeverageCategory.water,
      ),
      beverageName: m['beverage_name']?.toString() ?? '',
      volumeMl: toInt(m['volume_ml'], 0),
      // 云端 / 旧版数据可能没有 effective_ml：按容量兜底，避免出现
      // 「记录有 1800ml 但有效饮水 / 角色填充为 0」的数据残缺
      effectiveMl: m['effective_ml'] == null
          ? toInt(m['volume_ml'], 0)
          : toInt(m['effective_ml'], 0),
      drankAt: DateTime.parse(m['drank_at']?.toString() ?? DateTime.now().toIso8601String()),
      synced: toInt(m['synced'], 0) == 1,
      deleted: toInt(m['deleted'], 0) == 1,
      calories: toInt(m['calories'], -1),
      healthSampleId: m['health_sample_id']?.toString(),
      healthState: toInt(m['health_state'], healthNone),
      updatedAt: DateTime.tryParse(m['updated_at']?.toString() ?? ''),
    );
  }

  /// 工厂：从饮品选择快速生成
  factory DrinkEntry.create({
    required Beverage beverage,
    required int volumeMl,
    DateTime? drankAt,
  }) {
    final at = drankAt ?? DateTime.now();
    final perDefault = beverage.calories;
    final calories = (perDefault == null || perDefault <= 0 || beverage.defaultMl <= 0)
        ? 0
        : (perDefault * volumeMl / beverage.defaultMl).round();
    return DrinkEntry(
      clientId: _uuid(),
      beverageId: beverage.id,
      beverageCategory: beverage.category,
      beverageName: beverage.name,
      volumeMl: volumeMl,
      effectiveMl: beverage.effectiveMl(volumeMl),
      drankAt: at,
      synced: false,
      calories: calories,
      updatedAt: at,
    );
  }

  /// 简单 UUID v4 生成（不依赖 uuid 包，避免额外依赖）
  static String _uuid() {
    final r = DateTime.now().microsecondsSinceEpoch;
    final s = StringBuffer();
    for (var i = 0; i < 8; i++) {
      s.write((r >> (i * 4) & 0xF).toRadixString(16));
    }
    s.write('-');
    for (var i = 0; i < 4; i++) {
      s.write(DateTime.now().microsecondsSinceEpoch.toRadixString(16)[i]);
    }
    return s.toString();
  }
}
