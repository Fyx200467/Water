import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../time/logical_day.dart';
import 'dao_shared.dart';

/// 积分流水（账号级，离线累计、联网补传）
class PointsDao {
  PointsDao(this.prefs);

  final SharedPreferences prefs;

  String get owner => ownerOf(prefs);

  String get pointsStoreKey =>
      'points_state_${ownerSuffix(owner)}';

  String get pointsPendingKey =>
      'points_pending_${ownerSuffix(owner)}';

  /// 当前归属的积分快照（balance / todayEarned / dayKey / history）
  Map<String, dynamic>? loadPointsSnapshot() {
    final raw = prefs.getString(pointsStoreKey);
    if (raw == null || raw.isEmpty) return null;
    return decodeJsonMap(raw);
  }

  Future<void> savePointsSnapshot(Map<String, dynamic> snapshot) =>
      prefs.setString(pointsStoreKey, jsonEncode(snapshot));

  /// 待上行的积分流水（eventId 去重，服务端也按同一 id 去重）
  List<Map<String, dynamic>> loadPendingPointEvents() =>
      decodePendingList(prefs.getString(pointsPendingKey));

  Future<void> addPendingPointEvent(Map<String, dynamic> event) async {
    final id = event['eventId']?.toString();
    if (id == null || id.isEmpty) return;
    final all = <Map<String, dynamic>>[...loadPendingPointEvents()];
    if (all.any((e) => e['eventId']?.toString() == id)) return;
    all.add(event);
    await prefs.setString(pointsPendingKey, jsonEncode(all));
  }

  Future<void> removePendingPointEvents(Iterable<String> eventIds) async {
    final removeIds = eventIds.toSet();
    if (removeIds.isEmpty) return;
    final all = loadPendingPointEvents()
        .where((e) => !removeIds.contains(e['eventId']?.toString()))
        .toList();
    if (all.isEmpty) {
      await prefs.remove(pointsPendingKey);
    } else {
      await prefs.setString(pointsPendingKey, jsonEncode(all));
    }
  }

  /// 应用服务端下发的余额与流水（服务端为准），保留本机今日累计用于上限判定
  Future<void> applyPointsSummary(
    int balance,
    List<Map<String, dynamic>> history,
  ) async {
    final snapshot = loadPointsSnapshot() ?? <String, dynamic>{};
    snapshot['balance'] = balance;
    snapshot['history'] = history;
    // 今日收入按服务端流水重算：服务端未入账的本地记录不再显示，
    // 避免出现「今日 +6 但余额没涨」的假数据
    final today = LogicalDay.today();
    var todayEarned = 0;
    for (final e in history) {
      final amount = (e['amount'] as num?)?.toInt() ?? 0;
      final at = DateTime.fromMillisecondsSinceEpoch(
        (e['at'] as num?)?.toInt() ?? 0,
      );
      if (amount > 0 && LogicalDay.sameDay(at, today)) {
        todayEarned += amount;
      }
    }
    snapshot['todayEarned'] = todayEarned;
    final todayKey = LogicalDay.keyString(today);
    // 换日时必须同时清空领取标记，否则同步会把旧 dayKey 改写成今天，
    // 而 claimed 仍是昨天的来源，导致第二天签到/达标任务一直显示「已领取」
    if ((snapshot['dayKey']?.toString() ?? '') != todayKey) {
      snapshot['claimed'] = <String>[];
    }
    snapshot['dayKey'] = todayKey;
    await savePointsSnapshot(snapshot);
  }

  /// 登录后把游客积分并入账号桶（余额、流水、待上行流水一起迁移）
  Future<void> adoptGuestPoints(String userId) async {
    if (userId.isEmpty) return;
    const guestSuffix = 'guest';
    final guestRaw = prefs.getString('points_state_$guestSuffix');
    final guestPendingRaw = prefs.getString('points_pending_$guestSuffix');
    final hasGuestPoints = guestRaw != null && guestRaw.isNotEmpty;
    final hasGuestPending =
        guestPendingRaw != null && guestPendingRaw.isNotEmpty;
    if (!hasGuestPoints && !hasGuestPending) return;

    final userKey = 'points_state_$userId';
    final userPendingKey = 'points_pending_$userId';
    final user = decodeJsonMap(prefs.getString(userKey)) ?? {};
    final guest = decodeJsonMap(guestRaw) ?? {};

    user['balance'] =
        ((user['balance'] as num?)?.toInt() ?? 0) +
        ((guest['balance'] as num?)?.toInt() ?? 0);
    user['todayEarned'] =
        ((user['todayEarned'] as num?)?.toInt() ?? 0) +
        ((guest['todayEarned'] as num?)?.toInt() ?? 0);
    user['dayKey'] = user['dayKey'] ?? guest['dayKey'];
    final history = <Map<String, dynamic>>[
      ...((user['history'] as List?) ?? const []).whereType<Map>().map(
        (e) => Map<String, dynamic>.from(e),
      ),
      ...((guest['history'] as List?) ?? const []).whereType<Map>().map(
        (e) => Map<String, dynamic>.from(e),
      ),
    ];
    user['history'] = history.take(60).toList();
    await prefs.setString(userKey, jsonEncode(user));

    final pending = decodePendingList(prefs.getString(userPendingKey));
    final guestPending = decodePendingList(guestPendingRaw);
    for (final event in guestPending) {
      final id = event['eventId']?.toString();
      if (id == null || id.isEmpty) continue;
      if (pending.any((e) => e['eventId']?.toString() == id)) continue;
      pending.add(event);
    }
    if (pending.isNotEmpty) {
      await prefs.setString(userPendingKey, jsonEncode(pending));
    }

    await prefs.remove('points_state_$guestSuffix');
    await prefs.remove('points_pending_$guestSuffix');
  }
}
