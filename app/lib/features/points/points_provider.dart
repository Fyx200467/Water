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
    this.claimedToday = const {},
  });

  final int balance;

  /// 今日已获得的积分（用于积分页展示今日收入）
  final int todayEarned;

  /// todayEarned 所属日期（yyyy-MM-dd），跨天自动归零
  final String dayKey;

  final List<PointsRecord> history;

  /// 今天已领取过的每日任务来源。
  /// 独立于流水保存：服务端同步会整体替换 history，
  /// 若只依赖流水判断，领取后退出再进入会再次领取。
  final Set<String> claimedToday;

  /// 今天是否已领取过某个来源的奖励（按本机时区判断）
  bool hasEarnedToday(String source) {
    if (claimedToday.contains(source)) return true;
    final now = DateTime.now();
    return history.any(
      (r) =>
          r.source == source &&
          r.amount > 0 &&
          r.at.year == now.year &&
          r.at.month == now.month &&
          r.at.day == now.day,
    );
  }

  PointsState copyWith({
    int? balance,
    int? todayEarned,
    String? dayKey,
    List<PointsRecord>? history,
    Set<String>? claimedToday,
  }) => PointsState(
    balance: balance ?? this.balance,
    todayEarned: todayEarned ?? this.todayEarned,
    dayKey: dayKey ?? this.dayKey,
    history: history ?? this.history,
    claimedToday: claimedToday ?? this.claimedToday,
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
    // 云端合并有新流水时原地重载，不重建 notifier，
    // 避免积分页瞬间回落到空态（余额 0 / 空明细）造成的闪烁
    ref.listen<int>(pointsRevisionProvider, (_, __) {
      unawaited(_load());
    });
  }

  final Ref ref;

  /// 磁盘加载完成信号，避免首个发分请求覆盖已加载的余额
  late final Future<void> loaded;

  static const int _maxHistory = 300;

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
      if (!mounted) return;
      final snapshot = storage.loadPointsSnapshot();
      final key = _todayKey();
      if (snapshot == null) {
        state = PointsState(dayKey: key);
        return;
      }
      final savedKey = snapshot['dayKey']?.toString() ?? '';
      final history = ((snapshot['history'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => PointsRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      // 今日收入以流水为准：服务端同步后本地可能残留旧数字，重算以保证一致
      final now = DateTime.now();
      final todaySum = history
          .where(
            (r) =>
                r.amount > 0 &&
                r.at.year == now.year &&
                r.at.month == now.month &&
                r.at.day == now.day,
          )
          .fold<int>(0, (sum, r) => sum + r.amount);
      final claimed = savedKey == key
          ? ((snapshot['claimed'] as List?) ?? const [])
                .map((e) => e.toString())
                .toSet()
          : <String>{};
      state = PointsState(
        balance: (snapshot['balance'] as num?)?.toInt() ?? 0,
        todayEarned: todaySum,
        dayKey: key,
        history: history,
        claimedToday: claimed,
      );
    } catch (_) {
      // 数据异常时保持默认空态
    }
  }

  /// 外部触发刷新（跨零点 / 跨设备）：保留旧状态直到新快照读完，避免闪空
  Future<void> reload() => _load();

  Future<void> _persist() async {
    try {
      final storage = await ref.read(localStorageProvider.future);
      await storage.savePointsSnapshot({
        'balance': state.balance,
        'todayEarned': state.todayEarned,
        'dayKey': state.dayKey,
        'history': state.history.map((e) => e.toJson()).toList(),
        'claimed': state.claimedToday.toList(),
      });
    } catch (_) {
      // 持久化失败不阻塞游戏流程
    }
  }

  /// 发放积分（不限每日上限），返回实际到账数量
  ///
  /// [eventId] 用于每日任务（如签到）：同一天用同一个 eventId，
  /// 服务端按 eventId 去重，避免多设备重复领取。
  Future<int> earn({
    required String source,
    required int amount,
    String? eventId,
  }) async {
    await loaded;
    final storage = await ref.read(localStorageProvider.future);
    // 积分是账号权益：游客不计分（否则本机可反复刷分，登录后余额来源也无法校验）
    if (!storage.hasAccountSession) return 0;
    if (amount <= 0) return 0;
    final key = _todayKey();
    final earnedToday = state.dayKey == key ? state.todayEarned : 0;
    final claimedToday = state.dayKey == key ? state.claimedToday : const <String>{};
    state = state.copyWith(
      balance: state.balance + amount,
      todayEarned: earnedToday + amount,
      dayKey: key,
      claimedToday: claimedToday,
      history: [
        PointsRecord(source: source, amount: amount, at: DateTime.now()),
        ...state.history,
      ].take(_maxHistory).toList(),
    );
    await _persist();

    // 记一条待上行流水：离线累计，联网后按 eventId 去重补传
    await storage.addPendingPointEvent({
      'eventId': eventId ?? _newEventId(),
      'source': source,
      'amount': amount,
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
    });
    unawaited(SyncService.autoSync(storage));
    return amount;
  }

  /// 每日任务领取：今天已领过则返回 0；否则按「来源-日期」确定性 eventId 入账
  Future<int> claimDaily({
    required String source,
    required int amount,
  }) async {
    await loaded;
    if (state.hasEarnedToday(source)) return 0;
    final granted = await earn(
      source: source,
      amount: amount,
      eventId: '$source-${_todayKey()}',
    );
    if (granted > 0) {
      // 领取标记单独持久化：退出页面/同步替换流水后仍然保持「已领取」
      state = state.copyWith(
        claimedToday: {...state.claimedToday, source},
      );
      await _persist();
    }
    return granted;
  }
}

/// 云端积分（余额 / 流水）已合并到本机后 +1，积分页据此重新加载
final pointsRevisionProvider = StateProvider<int>((ref) => 0);

final pointsProvider = StateNotifierProvider<PointsNotifier, PointsState>((
  ref,
) {
  // 会话切换后按新归属账号重建；云端流水合并由 notifier 内部原地重载
  ref.watch(sessionEpochProvider);
  return PointsNotifier(ref);
});
