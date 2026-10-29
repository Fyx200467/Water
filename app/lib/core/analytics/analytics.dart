import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import '../sync/sync_api.dart';

/// 轻量行为埋点：只上报关键漏斗事件（会员转化 / 打卡），不接第三方 SDK。
///
/// 采用「内存队列 + 批量上报」：事件先入队，满 20 条或 3 秒后统一 POST，
/// 失败直接丢弃——埋点永远不能反过来影响业务主流程。
class Analytics {
  static const String _tokenKey = 'sync_token';
  static const String _anonKey = 'account_anon_id';
  static const int _maxBatch = 20;
  static const int _flushDelaySeconds = 3;

  static final List<Map<String, dynamic>> _queue = [];
  static Timer? _timer;
  static bool _flushing = false;

  /// 记录一个事件（白名单在服务端校验，客户端不做二次过滤）
  static void track(String event, {Map<String, dynamic>? props}) {
    _queue.add({
      'event': event,
      if (props != null && props.isNotEmpty) 'props': props,
    });
    if (_queue.length >= _maxBatch) {
      unawaited(flush());
      return;
    }
    _timer?.cancel();
    _timer = Timer(
      const Duration(seconds: _flushDelaySeconds),
      () => unawaited(flush()),
    );
  }

  /// 立即上报队列中的事件（冷启动 / 回前台时也可主动调用）
  static Future<void> flush() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    _timer?.cancel();
    try {
      while (_queue.isNotEmpty) {
        final batch = _queue.take(_maxBatch).toList();
        _queue.removeRange(0, batch.length);
        try {
          final prefs = await SharedPreferences.getInstance();
          await SyncApi.trackEvents(
            token: prefs.getString(_tokenKey),
            anonId: prefs.getString(_anonKey) ?? '',
            events: batch,
            appVersion: kAppVersion,
            platform: kIsWeb ? 'web' : Platform.operatingSystem,
          );
        } catch (_) {
          // 埋点失败直接丢弃，不重试、不打扰用户
        }
      }
    } finally {
      _flushing = false;
    }
  }
}
