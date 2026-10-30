import 'package:flutter/foundation.dart';

import '../storage/local_storage.dart';
import 'sync_api.dart';

/// 积分 / 会员日兑换的服务端同步
///
/// 策略：允许离线累计，联网后把待上行流水补传；服务端按 `eventId` 去重、
/// 以流水求和得到余额，客户端再以服务端余额与明细为准（多设备合并）。
class PointsSync {
  static bool _running = false;

  /// 云端余额 / 流水已合并到本机后回调（App 根节点推进积分版本号）
  static void Function()? onSynced;

  static Future<bool> sync(LocalStorage storage) async {
    if (!storage.hasAccountSession || _running) return false;
    _running = true;
    try {
      final token = storage.syncToken!;
      await _pushPending(storage, token);
      await _pullSummary(storage, token);
      onSynced?.call();
      return true;
    } catch (e) {
      debugPrint('[Points] sync failed: $e');
      return false;
    } finally {
      _running = false;
    }
  }

  /// 积分兑换会员天数：先补传线下积分，再由服务端扣分并开通
  ///
  /// 兑换必须联网：服务端才是余额与会员有效期的权威。
  static Future<DateTime> redeemMemberDay(
    LocalStorage storage, {
    int days = 1,
  }) async {
    if (!storage.hasAccountSession) {
      throw SyncApiException('请先登录账号后再兑换');
    }
    final token = storage.syncToken!;

    // 先把待上行流水补传，服务端才能看到最新余额
    await _pushPending(storage, token);
    final res = await SyncApi.redeemMembershipDay(token, days: days);
    final expireAt = DateTime.tryParse(res['expireAt']?.toString() ?? '');
    if (expireAt == null) {
      throw SyncApiException('兑换结果异常，请稍后重试');
    }
    // 兑换流水已在服务端落库，拉一次权威余额与明细；失败不影响开通结果
    try {
      await _pullSummary(storage, token);
      onSynced?.call();
    } catch (e) {
      debugPrint('[Points] redeem refresh failed: $e');
    }
    return expireAt;
  }

  static Future<void> _pushPending(LocalStorage storage, String token) async {
    // 服务端单次最多 200 条：离线久了要分批补传
    const batchSize = 200;
    while (true) {
      final pending = storage.loadPendingPointEvents();
      if (pending.isEmpty) return;
      final batch = pending.take(batchSize).toList();
      await SyncApi.pushPointEvents(token, batch);
      // 服务端已接收（重复 eventId 也只会入库一次），移除本地待上行
      await storage.removePendingPointEvents(
        batch.map((e) => e['eventId']?.toString() ?? ''),
      );
      if (pending.length <= batchSize) return;
    }
  }

  static Future<void> _pullSummary(LocalStorage storage, String token) async {
    final summary = await SyncApi.pointsSummary(token);
    final history = ((summary['history'] as List?) ?? const [])
        .whereType<Map>()
        .map(_recordFromServer)
        .toList();
    await storage.applyPointsSummary(
      (summary['balance'] as num?)?.toInt() ?? 0,
      history,
    );
  }

  /// 服务端流水时间用 ISO 串，本机历史统一存毫秒时间戳
  static Map<String, dynamic> _recordFromServer(Map raw) {
    final at = DateTime.tryParse(raw['at']?.toString() ?? '');
    return {
      'source': raw['source']?.toString() ?? '',
      'amount': (raw['amount'] as num?)?.toInt() ?? 0,
      'at': (at ?? DateTime.now()).millisecondsSinceEpoch,
    };
  }
}
