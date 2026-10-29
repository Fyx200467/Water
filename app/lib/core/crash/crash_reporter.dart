import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import '../sync/sync_api.dart';

/// 客户端异常上报（内测自建，不引入第三方崩溃 SDK）
///
/// 仅 release/profile 包上报；同一错误在一次启动内只上报一次，
/// 且单次启动最多 10 条，避免异常风暴把服务端日志表撑爆。
class CrashReporter {
  static const int _maxReportsPerLaunch = 10;
  static const String _tokenKey = 'sync_token';

  static final Set<int> _reported = <int>{};
  static int _sent = 0;

  /// 在 runApp 前调用，接管框架与异步未捕获异常
  static void init() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(report(details.exception, details.stack));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(report(error, stack));
      return true;
    };
  }

  /// 手动上报（业务侧捕获后可选调用）
  static Future<void> report(Object error, StackTrace? stack) async {
    if (kDebugMode || _sent >= _maxReportsPerLaunch) return;
    final message = error.toString();
    final trace = stack?.toString() ?? '';
    final key = Object.hash(message, trace.hashCode);
    if (!_reported.add(key)) return;
    _sent++;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      if (token == null || token.isEmpty) return;
      await SyncApi.reportClientError(
        token,
        message: message.length > 1000 ? message.substring(0, 1000) : message,
        stack: trace.length > 8000 ? trace.substring(0, 8000) : trace,
        appVersion: kAppVersion,
        platform: Platform.operatingSystem,
        device: Platform.operatingSystemVersion,
      );
    } catch (_) {
      // 上报本身失败不能影响主流程
    }
  }
}
