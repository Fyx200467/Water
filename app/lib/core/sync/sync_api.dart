import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地/局域网服务端调用（开发期）
class SyncApiException implements Exception {
  SyncApiException(this.message, {this.code, this.status});

  final String message;

  /// 服务端返回的业务码，如 session_revoked（账号已在其他设备登录）
  final String? code;
  final int? status;

  bool get isSessionRevoked => code == 'session_revoked';

  @override
  String toString() => message;
}

class SyncApi {
  /// 默认指向本机开发服务；可用
  /// `--dart-define=API_BASE_URL=...` 覆盖，也可在设置页长按版本号运行时修改
  static const String _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );

  static String _baseUrl = _defaultBaseUrl;

  static String get baseUrl => _baseUrl;

  /// 运行时可配接口地址在 SharedPreferences 中的键
  static const String prefsKey = 'api_base_url';

  /// 启动时加载已保存的接口地址（内网穿透域名变化时无需重新打包）
  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final normalized = normalize(prefs.getString(prefsKey));
      if (normalized != null) _baseUrl = normalized;
    } catch (_) {
      // 读取失败时保持默认地址
    }
  }

  static void configure(String normalized) => _baseUrl = normalized;

  /// 归一化为 `scheme://host:port`：自动补协议、去掉尾部斜杠与路径，
  /// 方便直接粘贴后台的 `.../api/v1` 地址
  static String? normalize(String? raw) {
    var value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? nickname,
  }) {
    return _request(
      'POST',
      '/v1/auth/register',
      body: {
        'email': email,
        'password': password,
        if (nickname != null && nickname.isNotEmpty) 'nickname': nickname,
      },
    );
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) {
    return _request(
      'POST',
      '/v1/auth/login',
      body: {'email': email, 'password': password},
    );
  }

  /// 退出登录：服务端吊销当前 token（清掉本机会话之外也真正断开）
  static Future<void> logout(String token) async {
    await _request('POST', '/v1/auth/logout', token: token);
  }

  /// 绑定登录方式（目前仅邮箱）：成功后服务端返回 providers 列表
  static Future<Map<String, dynamic>> bindEmail(
    String token, {
    required String email,
    required String password,
  }) {
    return _request(
      'POST',
      '/v1/auth/bind',
      token: token,
      body: {'provider': 'email', 'email': email, 'password': password},
    );
  }

  /// 解绑登录方式；仅剩一种方式时服务端返回 last_credential
  static Future<Map<String, dynamic>> unbindProvider(
    String token,
    String provider,
  ) {
    return _request(
      'POST',
      '/v1/auth/unbind',
      token: token,
      body: {'provider': provider},
    );
  }

  /// 注销账号：服务端校验密码后删除云端账号与全部数据
  static Future<Map<String, dynamic>> deleteAccount(
    String token, {
    String? password,
  }) {
    return _request(
      'POST',
      '/v1/auth/delete',
      token: token,
      body: {
        'confirm': true,
        if (password != null && password.isNotEmpty) 'password': password,
      },
    );
  }

  static Future<Map<String, dynamic>> updateNickname(
    String token,
    String nickname,
  ) {
    return _request(
      'PATCH',
      '/v1/me',
      token: token,
      body: {'nickname': nickname},
    );
  }

  /// 当前账号资料（头像地址、云端口径的饮水目标等）
  static Future<Map<String, dynamic>> me(String token) {
    return _request('GET', '/v1/me', token: token);
  }

  /// 上行完整账号档案：换设备登录后体重/身高/年龄/活动量/目标跟着账号走
  static Future<Map<String, dynamic>> updateProfile(
    String token,
    Map<String, dynamic> profile,
  ) {
    return _request(
      'PATCH',
      '/v1/me',
      token: token,
      body: {'profile': profile},
    );
  }

  /// 上传头像原图，返回服务端相对地址（/static/avatars/...）
  static Future<Map<String, dynamic>> uploadAvatar(
    String token,
    List<int> bytes,
    String contentType,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.openUrl(
        'POST',
        Uri.parse('$baseUrl/v1/me/avatar'),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.contentType = ContentType.parse(contentType);
      request.add(bytes);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty
          ? <String, dynamic>{}
          : (jsonDecode(text) as Map).cast<String, dynamic>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'];
        throw SyncApiException(
          (error is Map ? error['message'] : null)?.toString() ??
              'HTTP ${response.statusCode}',
          code: (error is Map ? error['code'] : null)?.toString(),
          status: response.statusCode,
        );
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  /// 清除服务端头像（恢复默认头像时调用）
  static Future<void> deleteAvatar(String token) async {
    await _request('DELETE', '/v1/me/avatar', token: token);
  }

  /// 最新一笔开通申请（含 pending / paid / rejected / cancelled）
  static Future<Map<String, dynamic>?> latestMembershipOrder(
    String token,
  ) async {
    final res = await _request(
      'GET',
      '/v1/membership/orders/latest',
      token: token,
    );
    final order = res['order'];
    return order is Map ? Map<String, dynamic>.from(order) : null;
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

  /// 会员套餐列表（后端返回数组，与 _request 的 Map 约定不同，单独实现）
  static Future<List<Map<String, dynamic>>> membershipPlans() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(
        'GET',
        Uri.parse('$baseUrl/v1/membership/plans'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw SyncApiException('HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return const [];
    } finally {
      client.close(force: true);
    }
  }

  /// 创建会员订单：开通必须联网，服务端返回待支付订单
  static Future<Map<String, dynamic>> createMembershipOrder(
    String token,
    String planCode,
  ) {
    return _request(
      'POST',
      '/v1/membership/orders',
      token: token,
      body: {'planCode': planCode},
    );
  }

  /// 查询订单状态；支付确认后会带 expireAt / permanent
  static Future<Map<String, dynamic>> membershipOrder(
    String token,
    String orderId,
  ) {
    return _request('GET', '/v1/membership/orders/$orderId', token: token);
  }

  /// 服务端会员状态（恢复购买用）
  static Future<Map<String, dynamic>> membershipStatus(String token) {
    return _request('GET', '/v1/membership/status', token: token);
  }

  /// 上行积分流水：离线累计后补传，服务端按 eventId 去重合并
  static Future<Map<String, dynamic>> pushPointEvents(
    String token,
    List<Map<String, dynamic>> events,
  ) {
    return _request(
      'POST',
      '/v1/points/events',
      token: token,
      body: {'events': events},
    );
  }

  /// 服务端积分余额 + 最近 60 条流水
  static Future<Map<String, dynamic>> pointsSummary(String token) {
    return _request('GET', '/v1/points', token: token);
  }

  /// 积分兑换会员天数：扣分与开通都在服务端完成
  static Future<Map<String, dynamic>> redeemMembershipDay(
    String token, {
    int days = 1,
  }) {
    return _request(
      'POST',
      '/v1/membership/redeem',
      token: token,
      body: {'days': days},
    );
  }

  /// 当前账号最新的待确认开通申请；没有则返回 null
  static Future<Map<String, dynamic>?> pendingMembershipOrder(
    String token,
  ) async {
    final res = await _request('GET', '/v1/membership/pending', token: token);
    return res.isEmpty ? null : res;
  }

  /// 撤回自己的待确认申请
  static Future<Map<String, dynamic>> cancelMembershipOrder(
    String token,
    String orderId,
  ) {
    return _request(
      'POST',
      '/v1/membership/orders/$orderId/cancel',
      token: token,
    );
  }

  /// 提交问题反馈（内测收集用）
  static Future<Map<String, dynamic>> submitFeedback(
    String token, {
    required String content,
    String? contact,
    String? appVersion,
    String? platform,
    String? device,
  }) {
    return _request(
      'POST',
      '/v1/feedback',
      token: token,
      body: {
        'content': content,
        if (contact != null && contact.isNotEmpty) 'contact': contact,
        if (appVersion != null) 'appVersion': appVersion,
        if (platform != null) 'platform': platform,
        if (device != null) 'device': device,
      },
    );
  }

  /// 最新版本信息（免鉴权），versionCode 为 0 表示未发布
  static Future<Map<String, dynamic>> appVersion(String platform) {
    return _request('GET', '/v1/app/version?platform=$platform');
  }

  /// 上报客户端未捕获异常（内测自建收集，非第三方 SDK）
  static Future<void> reportClientError(
    String token, {
    required String message,
    required String stack,
    String? appVersion,
    String? platform,
    String? device,
  }) async {
    await _request(
      'POST',
      '/v1/client-errors',
      token: token,
      body: {
        'message': message,
        'stack': stack,
        if (appVersion != null) 'appVersion': appVersion,
        if (platform != null) 'platform': platform,
        if (device != null) 'device': device,
      },
    );
  }

  /// 批量上报行为埋点（免鉴权，登录后带 token 归因到账号）
  static Future<void> trackEvents({
    String? token,
    required String anonId,
    required List<Map<String, dynamic>> events,
    String? appVersion,
    String? platform,
  }) async {
    await _request(
      'POST',
      '/v1/events',
      token: token,
      body: {
        'events': events,
        if (anonId.isNotEmpty) 'anonId': anonId,
        if (appVersion != null) 'appVersion': appVersion,
        if (platform != null) 'platform': platform,
      },
    );
  }

  /// 后台发布的云端饮品目录（含容器图标地址，免鉴权）
  static Future<List<Map<String, dynamic>>> beverageCatalog() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(
        'GET',
        Uri.parse('$baseUrl/v1/catalog/beverages'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw SyncApiException('HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return const [];
    } finally {
      client.close(force: true);
    }
  }

  /// 云端容器图标列表（免鉴权）：App 联网时据此补齐/清理本地图标缓存
  static Future<List<Map<String, dynamic>>> containerCatalog() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.openUrl(
        'GET',
        Uri.parse('$baseUrl/v1/catalog/containers'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw SyncApiException('HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(text);
      final items = decoded is Map ? decoded['items'] : decoded;
      if (items is List) {
        return items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return const [];
    } finally {
      client.close(force: true);
    }
  }

  /// 云端角色目录（免鉴权）：分类 + 已发布角色，App 联网时据此同步
  static Future<Map<String, dynamic>> characterCatalog() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.openUrl(
        'GET',
        Uri.parse('$baseUrl/v1/catalog/characters'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw SyncApiException('HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return const {};
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? token,
    Object? body,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
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

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'];
        final message = (error is Map ? error['message'] : null)?.toString();
        final code = (error is Map ? error['code'] : null)?.toString();
        throw SyncApiException(
          message ?? 'HTTP ${response.statusCode}',
          code: code,
          status: response.statusCode,
        );
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}
