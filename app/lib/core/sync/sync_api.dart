import 'dart:convert';
import 'dart:io';

/// 本地/局域网服务端调用（开发期）
class SyncApiException implements Exception {
  SyncApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SyncApi {
  /// 默认指向本机开发服务；真机验证时用
  /// `--dart-define=API_BASE_URL=http://192.168.1.83:3000` 覆盖
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );

  static Future<Map<String, dynamic>> guest(String anonId) {
    return _request('POST', '/v1/auth/guest', body: {'anonId': anonId});
  }

  static Future<Map<String, dynamic>> push(
    String token, {
    required List<Map<String, dynamic>> entries,
    List<Map<String, dynamic>> settings = const [],
  }) {
    return _request(
      'POST',
      '/v1/sync/push',
      token: token,
      body: {'entries': entries, 'settings': settings},
    );
  }

  static Future<Map<String, dynamic>> pull(
    String token, {
    required int cursor,
    int limit = 500,
  }) {
    return _request(
      'GET',
      '/v1/sync/pull?cursor=$cursor&limit=$limit',
      token: token,
    );
  }

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? token,
    Object? body,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.openUrl(method, Uri.parse('$baseUrl$path'));
      request.headers.contentType = ContentType.json;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) request.write(jsonEncode(body));

      final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty
          ? <String, dynamic>{}
          : (jsonDecode(text) as Map).cast<String, dynamic>();

      if (response.statusCode != 200) {
        final error = decoded['error'];
        final message = (error is Map ? error['message'] : null)?.toString();
        throw SyncApiException(message ?? 'HTTP ${response.statusCode}');
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}
