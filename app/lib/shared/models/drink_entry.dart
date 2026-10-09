import 'package:flutter/foundation.dart';

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
  });

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

  DrinkEntry copyWith({
    String? serverId,
    bool? synced,
    bool? deleted,
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
    );
  }

  /// 判断记录是否属于指定自然日（用户本地时区）
  bool belongsToDay(DateTime day) {
    return drankAt.year == day.year &&
        drankAt.month == day.month &&
        drankAt.day == day.day;
  }

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
      effectiveMl: toInt(m['effective_ml'], 0),
      drankAt: DateTime.parse(m['drank_at']?.toString() ?? DateTime.now().toIso8601String()),
      synced: toInt(m['synced'], 0) == 1,
      deleted: toInt(m['deleted'], 0) == 1,
    );
  }

  /// 工厂：从饮品选择快速生成
  factory DrinkEntry.create({
    required Beverage beverage,
    required int volumeMl,
    DateTime? drankAt,
  }) {
    final at = drankAt ?? DateTime.now();
    return DrinkEntry(
      clientId: _uuid(),
      beverageId: beverage.id,
      beverageCategory: beverage.category,
      beverageName: beverage.name,
      volumeMl: volumeMl,
      effectiveMl: beverage.effectiveMl(volumeMl),
      drankAt: at,
      synced: false,
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
