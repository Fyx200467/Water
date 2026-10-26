import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一条积分流水（收入为正、支出为负）
class PointsRecord {
  const PointsRecord({
    required this.source,
    required this.amount,
    required this.at,
  });

  final String source;
  final int amount;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'source': source,
        'amount': amount,
        'at': at.millisecondsSinceEpoch,
      };

  static PointsRecord fromJson(Map<String, dynamic> m) => PointsRecord(
        source: (m['source'] as String?) ?? '',
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        at: DateTime.fromMillisecondsSinceEpoch(
            (m['at'] as num?)?.toInt() ?? 0),
      );
}

class PointsState {
  const PointsState({
    this.balance = 0,
    this.todayEarned = 0,
    this.dayKey = '',
    this.history = const [],
  });

  final int balance;

  /// 今日已获得的积分（用于每日上限判定）
  final int todayEarned;

  /// todayEarned 所属日期（yyyy-MM-dd），跨天自动归零
  final String dayKey;

  final List<PointsRecord> history;

  PointsState copyWith({
    int? balance,
    int? todayEarned,
    String? dayKey,
    List<PointsRecord>? history,
  }) =>
      PointsState(
        balance: balance ?? this.balance,
        todayEarned: todayEarned ?? this.todayEarned,
        dayKey: dayKey ?? this.dayKey,
        history: history ?? this.history,
      );
}

/// 积分系统（本地持久化）
///
/// 后续接会员只改 [redeem]：把 itemId/cost 换成真实兑换（会员天数、券等），
/// 余额与流水逻辑不用动，也不影响消消乐的发分入口。
class PointsNotifier extends StateNotifier<PointsState> {
  PointsNotifier() : super(const PointsState()) {
    _load();
  }

  static const _kKey = 'points_state';
  static const _maxHistory = 60;

  /// 消消乐每日最多可得积分
  static const int matchGameDailyCap = 20;

  /// 每多少分折算 1 积分
  static const int scorePerPoint = 1000;

  String _todayKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final key = _todayKey();
      final savedKey = (m['dayKey'] as String?) ?? '';
      state = PointsState(
        balance: (m['balance'] as num?)?.toInt() ?? 0,
        // 跨天：今日累计归零，余额不受影响
        todayEarned: savedKey == key ? ((m['todayEarned'] as num?)?.toInt() ?? 0) : 0,
        dayKey: key,
        history: ((m['history'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => PointsRecord.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    } catch (_) {
      // 数据异常时保持默认空态
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kKey,
        jsonEncode({
          'balance': state.balance,
          'todayEarned': state.todayEarned,
          'dayKey': state.dayKey,
          'history': state.history.map((e) => e.toJson()).toList(),
        }),
      );
    } catch (_) {
      // 持久化失败不阻塞游戏流程
    }
  }

  /// 发放积分（按今日上限截断），返回实际到账数量
  Future<int> earn({
    required String source,
    required int amount,
    int dailyCap = matchGameDailyCap,
  }) async {
    if (amount <= 0) return 0;
    final key = _todayKey();
    final earnedToday = state.dayKey == key ? state.todayEarned : 0;
    final remain = (dailyCap - earnedToday).clamp(0, dailyCap);
    final granted = amount.clamp(0, remain);
    if (granted <= 0) {
      // 已达上限：仍刷新日期键，避免次日误判
      if (state.dayKey != key) {
        state = state.copyWith(dayKey: key, todayEarned: 0);
        await _persist();
      }
      return 0;
    }
    state = state.copyWith(
      balance: state.balance + granted,
      todayEarned: earnedToday + granted,
      dayKey: key,
      history: [
        PointsRecord(source: source, amount: granted, at: DateTime.now()),
        ...state.history,
      ].take(_maxHistory).toList(),
    );
    await _persist();
    return granted;
  }

  /// 消费积分（兑换会员 / 商品时调用），余额不足返回 false
  Future<bool> redeem({required String itemId, required int cost}) async {
    if (cost <= 0) return false;
    if (state.balance < cost) return false;
    state = state.copyWith(
      balance: state.balance - cost,
      history: [
        PointsRecord(source: 'redeem:$itemId', amount: -cost, at: DateTime.now()),
        ...state.history,
      ].take(_maxHistory).toList(),
    );
    await _persist();
    // TODO(membership): 这里接入会员权益开通（本地占位时可直接落一个到期时间）
    return true;
  }
}

final pointsProvider = StateNotifierProvider<PointsNotifier, PointsState>(
  (ref) => PointsNotifier(),
);
