import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sync_api.dart';

/// 会话实时监听：常驻一条 SSE 长连接（/v1/session/stream）。
///
/// 另一台设备登录时服务端会立即推送 `session_revoked`，
/// 本机无需等待下一轮同步轮询即可弹出「账号已在其他设备登录」。
class SessionWatch {
  SessionWatch._();

  static HttpClient? _client;
  static StreamSubscription<String>? _sub;
  static Timer? _retry;
  static String? _token;
  static bool _revoked = false;
  static bool _connecting = false;

  /// 收到服务端顶号事件 / 连接时发现令牌已失效时的回调
  static void Function()? onRevoked;

  static void start(String token) {
    if (token.isEmpty) {
      stop();
      return;
    }
    if (_token == token && (_connecting || _sub != null || _retry != null)) {
      return;
    }
    _teardown();
    _token = token;
    _revoked = false;
    unawaited(_connect());
  }

  static void stop() {
    _teardown();
    _token = null;
  }

  static void _teardown() {
    _sub?.cancel();
    _sub = null;
    _retry?.cancel();
    _retry = null;
    _client?.close(force: true);
    _client = null;
    _connecting = false;
  }

  static Future<void> _connect() async {
    final token = _token;
    if (token == null || _revoked || _connecting) return;
    _connecting = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    _client = client;
    try {
      final request = await client.getUrl(
        Uri.parse('${SyncApi.baseUrl}/v1/session/stream'),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      final response = await request.close();
      if (response.statusCode == 401) {
        _notifyRevoked();
        return;
      }
      if (response.statusCode != 200) {
        _scheduleRetry();
        return;
      }
      _connecting = false;
      _sub = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.contains('session_revoked')) _notifyRevoked();
        },
        onError: (_) => _scheduleRetry(),
        onDone: () {
          if (!_revoked) _scheduleRetry();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    } finally {
      if (_sub == null) _connecting = false;
    }
  }

  static void _scheduleRetry() {
    if (_revoked || _token == null || _retry != null) return;
    _teardown();
    _retry = Timer(const Duration(seconds: 5), () {
      _retry = null;
      unawaited(_connect());
    });
  }

  static void _notifyRevoked() {
    if (_revoked) return;
    _revoked = true;
    final callback = onRevoked;
    _teardown();
    _token = null;
    callback?.call();
  }
}
