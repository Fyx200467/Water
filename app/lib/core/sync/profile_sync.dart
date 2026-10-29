import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../shared/models/user_profile.dart';
import '../storage/local_storage.dart';
import 'sync_api.dart';

/// 账号档案跨设备同步：性别/体重/身高/年龄/活动量/饮水目标 + 头像。
///
/// 同步策略：
/// - 登录（或本机尚未与服务端对齐）时，以服务端档案为准覆盖本机；
///   服务端还没有档案（新注册 / 旧账号）时，把本机档案补传上去。
/// - 已对齐后本机修改立即上行；定时拉取其他设备的修改并覆盖本机。
/// - 头像：以服务端为准。云端有而本机没有 → 下载；本机有而云端没有 → 上传；
///   其他设备恢复默认头像 → 本机同步清除。
class ProfileSync {
  ProfileSync._();

  static DateTime? _lastRemoteCheck;

  /// 串行执行：避免登录强同步与定时同步并发，把本机默认目标抢先写进账号
  static Future<void> _queue = Future<void>.value();

  /// 头像路径发生变化后的回调（app 层用来刷新「账号与云备份」界面）
  static void Function()? onAvatarSynced;

  /// 账号档案被服务端覆盖 / 恢复游客档案后的回调
  static void Function()? onProfileSynced;

  static Future<void> _enqueue(Future<void> Function() action) {
    final task = _queue.then((_) => action());
    _queue = task.catchError((_) {});
    return task;
  }

  /// 同步资料；[force] 用于登录完成等强一致场景，忽略节流并强制以服务端为准
  static Future<void> sync(LocalStorage storage, {bool force = false}) {
    return _enqueue(() => _sync(storage, force: force));
  }

  static Future<void> _sync(
    LocalStorage storage, {
    required bool force,
  }) async {
    if (!storage.hasAccountSession) return;
    try {
      final token = storage.syncToken!;
      final local = storage.loadProfile();
      final pushed = storage.lastPushedProfileSignature;
      final localSignature = local == null ? null : _signature(local);
      // 该账号在本机还没有成功对齐过：服务端是唯一事实来源
      final hydrate = force || pushed == null;

      // 已对齐的账号：本机改过档案就先上行（离线改动重启后也不丢）
      if (!hydrate && local != null && localSignature != pushed) {
        await _pushProfile(storage, local);
      }

      final now = DateTime.now();
      final remoteDue = hydrate ||
          _lastRemoteCheck == null ||
          now.difference(_lastRemoteCheck!) >= const Duration(seconds: 20);
      if (!remoteDue) return;
      _lastRemoteCheck = now;

      final me = await SyncApi.me(token);
      await _applyServerProfile(storage, me, storage.loadProfile());
      await _syncAvatar(storage, token, me);
    } catch (_) {
      // 离线或服务端不可达时静默跳过，不阻塞业务
    }
  }

  /// 服务端档案 → 本机档案；服务端还没有档案时把本机档案补传上去
  static Future<void> _applyServerProfile(
    LocalStorage storage,
    Map<String, dynamic> me,
    UserProfile? local,
  ) async {
    final remote = _fromServer(me, local);
    if (remote == null) {
      if (local != null) await _pushProfile(storage, local);
      return;
    }
    final remoteSignature = _signature(remote);
    if (local == null || remoteSignature != _signature(local)) {
      await storage.saveProfile(remote);
      onProfileSynced?.call();
    }
    if (storage.lastPushedProfileSignature != remoteSignature) {
      await storage.setLastPushedProfileSignature(remoteSignature);
    }
    // 旧账号可能只同步过饮水目标：补齐身高/体重/年龄/活动量，
    // 之后换任何设备登录都能恢复同一份身体数据
    final raw = me['profile'];
    final data = raw is Map ? raw : const {};
    final complete = const ['gender', 'weightKg', 'heightCm', 'age', 'activityLevel']
        .every((key) => data[key] != null);
    if (!complete) await _pushProfile(storage, remote);
  }

  /// 本机修改档案后立即调用（也由 [sync] 兜底）
  static Future<void> pushProfile(LocalStorage storage) {
    return _enqueue(() async {
      if (!storage.hasAccountSession) return;
      final profile = storage.loadProfile();
      if (profile == null) return;
      if (storage.lastPushedProfileSignature == _signature(profile)) return;
      await _pushProfile(storage, profile);
    });
  }

  static Future<void> _pushProfile(
    LocalStorage storage,
    UserProfile profile,
  ) async {
    final token = storage.syncToken;
    if (token == null || token.isEmpty) return;
    try {
      await SyncApi.updateProfile(token, _toServerProfile(profile));
      await storage.setLastPushedProfileSignature(_signature(profile));
    } catch (_) {
      // 网络失败下轮再试
    }
  }

  /// 退出登录 / 被挤下线后恢复登录前的游客档案
  static Future<void> restoreGuestProfile(LocalStorage storage) async {
    final snapshot = storage.guestProfileSnapshot;
    if (snapshot == null) return;
    await storage.saveProfile(snapshot);
    await storage.clearGuestProfileSnapshot();
    onProfileSynced?.call();
  }

  /// 把本机头像上传到服务端（用户主动换头像后立即调用，不等下一轮同步）
  static Future<bool> uploadLocal(
    LocalStorage storage,
    String token,
    String path,
  ) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final ext = p.extension(path).toLowerCase();
      final contentType = ext == '.png'
          ? 'image/png'
          : ext == '.webp'
            ? 'image/webp'
            : 'image/jpeg';
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return false;
      final res = await SyncApi.uploadAvatar(token, bytes, contentType);
      final url = (res['avatarUrl'] as String?) ?? '';
      await storage.setAccountAvatarRemoteUrl(url.isEmpty ? null : url);
      return url.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _syncAvatar(
    LocalStorage storage,
    String token,
    Map<String, dynamic> me,
  ) async {
    final remote = (me['avatarUrl'] as String?) ?? '';
    final known = storage.accountAvatarRemoteUrl;
    final localPath = storage.accountAvatarPath;

    if (remote.isEmpty) {
      if (known != null && known.isNotEmpty) {
        // 另一台设备恢复了默认头像
        await storage.setAccountAvatarPath(null);
        await storage.setAccountAvatarRemoteUrl(null);
        onAvatarSynced?.call();
      } else if (localPath != null) {
        // 本机先有头像：补传一次，让新设备能拿到
        final file = File(localPath);
        if (await file.exists()) {
          await uploadLocal(storage, token, localPath);
        }
      }
    } else if (remote != known) {
      final bytes = await _download(remote);
      if (bytes != null) {
        final saved = await _saveLocal(storage, bytes, remote);
        if (saved != null) {
          await storage.setAccountAvatarPath(saved);
          onAvatarSynced?.call();
        }
      }
      await storage.setAccountAvatarRemoteUrl(remote);
    }
  }

  static Map<String, dynamic> _toServerProfile(UserProfile profile) => {
        'gender': profile.gender.name,
        'weightKg': profile.weightKg,
        'heightCm': profile.heightCm,
        'age': profile.age,
        'activityLevel': profile.activityLevel.name,
        'dailyGoalMl': profile.dailyGoalMl,
      };

  static String _signature(UserProfile profile) =>
      jsonEncode(_toServerProfile(profile));

  /// 解析服务端档案；服务端没有 dailyGoalMl 视为尚未建立账号档案
  static UserProfile? _fromServer(
    Map<String, dynamic> me,
    UserProfile? local,
  ) {
    final raw = me['profile'];
    final data = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final goal = (data['dailyGoalMl'] as num?)?.toInt() ??
        (me['dailyGoalMl'] as num?)?.toInt();
    if (goal == null) return null;

    var gender = local?.gender ?? Gender.male;
    final genderName = data['gender']?.toString();
    if (genderName != null && genderName.isNotEmpty) {
      gender = Gender.values.firstWhere(
        (g) => g.name == genderName,
        orElse: () => gender,
      );
    }
    var activity = local?.activityLevel ?? ActivityLevel.low;
    final activityName = data['activityLevel']?.toString();
    if (activityName != null && activityName.isNotEmpty) {
      activity = ActivityLevel.values.firstWhere(
        (a) => a.name == activityName,
        orElse: () => activity,
      );
    }
    double numOr(num? value, double fallback) =>
        value == null ? fallback : value.toDouble();

    return UserProfile(
      id: local?.id ?? 1,
      gender: gender,
      weightKg: numOr(data['weightKg'] as num?, local?.weightKg ?? 60),
      heightCm: numOr(data['heightCm'] as num?, local?.heightCm ?? 170),
      age: (data['age'] as num?)?.toInt() ?? local?.age ?? 25,
      activityLevel: activity,
      dailyGoalMl: goal,
      createdAt: local?.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  static Future<List<int>?> _download(String remote) async {
    final url = remote.startsWith('http')
        ? remote
        : '${SyncApi.baseUrl}$remote';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200) return null;
      final chunks = <int>[];
      await for (final chunk in response) {
        chunks.addAll(chunk);
      }
      return chunks.isEmpty ? null : chunks;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String?> _saveLocal(
    LocalStorage storage,
    List<int> bytes,
    String remote,
  ) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final avatarDir = Directory(p.join(appDir.path, 'avatars'));
      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }
      final ext = p.extension(remote).isEmpty ? '.jpg' : p.extension(remote);
      final dest = File(
        p.join(
          avatarDir.path,
          'avatar_${DateTime.now().millisecondsSinceEpoch}$ext',
        ),
      );
      await dest.writeAsBytes(bytes, flush: true);
      final old = storage.accountAvatarPath;
      if (old != null && old != dest.path) {
        try {
          final f = File(old);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      return dest.path;
    } catch (_) {
      return null;
    }
  }
}
