import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../home/providers/home_providers.dart';

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
    at: DateTime.fromMillisecondsSinceEpoch((m['at'] as num?)?.toInt() ?? 0),
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
  }) => PointsState(
    balance: balance ?? this.balance,
    todayEarned: todayEarned ?? this.todayEarned,
    dayKey: dayKey ?? this.dayKey,
    history: history ?? this.history,
  );
}

/// 积分系统（账号级，离线优先）
///
/// - 未登录（游客）：不计分、不产生流水，积分页只展示历史遗留余额；
/// - 已登录：每笔收入/支出都会记一条带 eventId 的待上行流水，联网后补传，
///   服务端按 eventId 去重、以流水求和得到余额，再回写本机（多设备合并）。
class PointsNotifier extends StateNotifier<PointsState> {
  PointsNotifier(this.ref) : super(const PointsState()) {
    loaded = _load();
  }

  final Ref ref;

  /// 磁盘加载完成信号，避免首个发分请求覆盖已加载的余额
  late final Future<void> loaded;

  static const int _maxHistory = 60;

  /// 消消乐每日最多可得积分
  static const int matchGameDailyCap = 20;

  /// 每多少分折算 1 积分
  static const int scorePerPoint = 1000;

  static final math.Random _random = math.Random();

  String _todayKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  String _newEventId() {
    final rand = _random.nextInt(1 << 24).toRadixString(16);
    return '${DateTime.now().microsecondsSinceEpoch}-$rand';
  }

  Future<void> _load() async {
    try {
      final storage = await ref.read(localStorageProvider.future);
      final snapshot = storage.loadPointsSnapshot();
      final key = _todayKey();
      if (snapshot == null) {
        state = PointsState(dayKey: key);
        return;
      }
      final savedKey = snapshot['dayKey']?.toString() ?? '';
      state = PointsState(
        balance: (snapshot['balance'] as num?)?.toInt() ?? 0,
        // 跨天：今日累计归零，余额不受影响
        todayEarned: savedKey == key
            ? ((snapshot['todayEarned'] as num?)?.toInt() ?? 0)
            : 0,
        dayKey: key,
        history: ((snapshot['history'] as List?) ?? const [])
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
      final storage = await ref.read(localStorageProvider.future);
      await storage.savePointsSnapshot({
        'balance': state.balance,
        'todayEarned': state.todayEarned,
        'dayKey': state.dayKey,
        'history': state.history.map((e) => e.toJson()).toList(),
      });
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
    await loaded;
    final storage = await ref.read(localStorageProvider.future);
    // 积分是账号权益：游客不计分（否则本机可反复刷分，登录后余额来源也无法校验）
    if (!storage.hasAccountSession) return 0;
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

    // 记一条待上行流水：离线累计，联网后按 eventId 去重补传
    await storage.addPendingPointEvent({
      'eventId': _newEventId(),
      'source': source,
      'amount': granted,
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
    });
    unawaited(SyncService.autoSync(storage));
    return granted;
  }
}

/// 云端积分（余额 / 流水）已合并到本机后 +1，积分页据此重新加载
final pointsRevisionProvider = StateProvider<int>((ref) => 0);

final pointsProvider = StateNotifierProvider<PointsNotifier, PointsState>((
  ref,
) {
  // 会话切换 / 云端积分合并后，按新归属账号重新加载
  ref.watch(sessionEpochProvider);
  ref.watch(pointsRevisionProvider);
  return PointsNotifier(ref);
});
