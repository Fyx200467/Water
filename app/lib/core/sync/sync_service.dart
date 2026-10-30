import 'package:flutter/foundation.dart';

import '../../shared/models/drink_entry.dart';
import '../settings/account_settings.dart';
import '../storage/local_storage.dart';
import 'points_sync.dart';
import 'profile_sync.dart';
import 'session_watch.dart';
import 'sync_api.dart';

class SyncResult {
  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.failed = false,
    this.message,
  });

  final int pushed;
  final int pulled;
  final bool failed;
  final String? message;
}

/// 云同步：登录账号 + 记录批量上行 + 增量下行
///
/// 离线优先：本地写入永远先落库，同步只是后台补充动作。
/// 未登录时只做本地存储，不与云端发生任何数据往来。
class SyncService {
  /// 正在进行的一轮同步。并发调用方复用同一轮结果，
  /// 不再返回一个空的「假成功」——否则登录流程会以为同步已完成、
  /// 在云端数据还没落库时就按旧缓存渲染（首页 0ml 的根因之一）
  static Future<SyncResult>? _inFlight;

  /// 会话被其他设备顶掉时的全局回调（App 根节点注册，用于弹窗提示）
  static void Function()? onSessionRevoked;

  /// 当前设备的数据归属账号发生变化（登录 / 退出 / 被顶下线）。
  /// App 根节点据此推进会话纪元，让按 owner 读取的数据统一重载。
  static void Function()? onSessionChanged;

  /// 云端账号级偏好（单位 / 角色 / 自定义饮品等）已应用到本机。
  /// App 根节点据此刷新全局单位与偏好 provider。
  static void Function()? onSettingsSynced;

  static Future<void> signIn(
    LocalStorage storage,
    String email,
    String password,
  ) async {
    // 游客数据合并全部在本机完成（bindGuestEntriesToAccount / adoptGuestPoints）
    final res = await SyncApi.login(email: email.trim(), password: password);
    await _applyAccount(storage, res);
  }

  static Future<void> signUp(
    LocalStorage storage,
    String email,
    String password, {
    String? nickname,
  }) async {
    final res = await SyncApi.register(
      email: email.trim(),
      password: password,
      // 没填昵称就用本机当前昵称，注册后两边一致
      nickname: nickname ?? storage.accountNickname,
    );
    await _applyAccount(storage, res);
  }

  static Future<void> signOut(LocalStorage storage) async {
    // 先让服务端吊销 token（失败不阻塞退出），本机再回到游客态
    final token = storage.syncToken;
    if (token != null && token.isNotEmpty) {
      try {
        await SyncApi.logout(token);
      } catch (_) {}
    }
    await _backToGuest(storage);
  }

  /// 账号被其他设备顶掉：恢复游客档案 + 清会话 + 断开实时通道
  static Future<void> handleSessionRevoked(LocalStorage storage) =>
      _backToGuest(storage);

  /// 注销账号：服务端删除云端账号与数据成功后，清掉本机该账号的数据
  static Future<void> deleteAccount(
    LocalStorage storage, {
    String? password,
  }) async {
    final token = storage.syncToken;
    final uid = storage.syncUserId;
    if (token == null || token.isEmpty) return;
    await SyncApi.deleteAccount(token, password: password);
    // 头像文件在切回游客态前删掉（路径按账号存放）
    await ProfileSync.deleteLocalAvatar(storage);
    await _backToGuest(storage);
    if (uid != null && uid.isNotEmpty) {
      await storage.purgeAccountData(uid);
    }
  }

  /// 回到游客态：恢复游客档案与昵称、清会话、断开实时通道
  static Future<void> _backToGuest(LocalStorage storage) async {
    await ProfileSync.restoreGuestProfile(storage);
    await storage.restoreGuestNickname();
    await storage.clearNicknameDirty();
    SessionWatch.stop();
    await storage.clearSyncSession();
    onSessionChanged?.call();
  }

  static Future<void> _applyAccount(
    LocalStorage storage,
    Map<String, dynamic> res,
  ) async {
    // 登录前先快照游客档案与昵称，退出账号时恢复
    if (!storage.hasAccountSession) {
      final guestProfile = storage.loadProfile();
      if (guestProfile != null) {
        await storage.saveGuestProfileSnapshot(guestProfile);
      }
      await storage.saveGuestNicknameSnapshot();
    }
    await storage.setSyncSession(
      res['userId'] as String,
      res['accessToken'] as String,
      email: res['email'] as String,
    );
    // 本机改过昵称（离线）时以本地为准，等同步再上行，避免被服务端旧值覆盖
    if (!storage.nicknameDirty) {
      final nickname = res['nickname'] as String?;
      if (nickname != null && nickname.isNotEmpty) {
        await storage.setAccountNickname(nickname);
      }
    }
    // 新登录的账号必须先从服务端拉档案，不能把本机默认目标抢先写进账号
    await storage.clearLastPushedProfileSignature();
    // 注意：本地游客记录、偏好、积分不在这里并入账号。
    // 「游客数据属于这台手机」：登录成功后由界面询问用户是否并入，
    // 默认只拉云端，避免共用设备/登录错账号时把游客数据送给下一个登录者
    // 归属账号已切换：通知界面按新 owner 重载本地数据
    onSessionChanged?.call();
    // 实时监听顶号；随后立刻拉一次完整档案与头像
    SessionWatch.start(res['accessToken'] as String);
    await ProfileSync.sync(storage, force: true);
  }

  /// 用户确认后把本机游客数据并入当前账号（记录 + 账号级偏好 + 历史遗留积分）
  /// 返回实际并入的记录条数（删除的墓碑不计数）
  static Future<int> mergeGuestData(LocalStorage storage) async {
    final userId = storage.syncUserId;
    if (userId == null || userId.isEmpty) return 0;
    final count = await storage.countGuestEntries();
    await storage.bindGuestEntriesToAccount(userId);
    await storage.adoptGuestAccountSettings(userId);
    // 老版本允许游客攒积分，这批遗留数据在用户确认并入时一起带上
    await storage.adoptGuestPoints(userId);
    return count;
  }

  /// 一轮同步结束（无论成功/失败）后回调：界面据此刷新「待同步 N 条」
  static void Function()? onSyncFinished;

  static Future<SyncResult> syncNow(LocalStorage storage) {
    if (!storage.hasAccountSession) {
      return Future<SyncResult>.value(const SyncResult(message: '未登录'));
    }
    final running = _inFlight;
    if (running != null) return running;
    final future = _runSync(storage);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
      onSyncFinished?.call();
    });
  }

  static Future<SyncResult> _runSync(LocalStorage storage) async {
    try {
      final token = storage.syncToken!;

      final pending = await storage.loadPendingSyncEntries();
      // 账号级偏好（单位 / 角色 / 自定义饮品）随账号上行，只带本地改动过的
      final settings = storage.settingsPushPayload();
      // 本轮刚上行的偏好版本：下行时跳过同版本回显，避免无意义的刷新
      final pushedSettingAt = {
        for (final s in settings)
          if (s['key'] != null) s['key'].toString(): s['updatedAt']?.toString(),
      };
      var pushed = 0;
      var settingsChanged = false;
      final conflicted = <String>{};

      if (pending.isNotEmpty || settings.isNotEmpty) {
        final res = await SyncApi.push(
          token,
          entries: pending.map(_looksLikeEntry).toList(),
          settings: settings,
        );
        final mergedCollect = <String>{};

        for (final raw in (res['conflicts'] as List?) ?? const []) {
          if (raw is! Map) continue;
          if (raw['type'] == 'entry') {
            final clientId = raw['clientId']?.toString();
            final data = raw['data'];
            if (clientId == null || data is! Map) continue;
            await storage.applyRemoteEntry(
              _entryFromRemote(
                Map<String, dynamic>.from(data),
                clientId: clientId,
                deletedAt: raw['deletedAt']?.toString(),
              ),
            );
            conflicted.add(clientId);
          } else if (raw['type'] == 'setting') {
            final key = raw['key']?.toString();
            final updatedAt = raw['updatedAt']?.toString();
            if (key == null || updatedAt == null || updatedAt.isEmpty) continue;
            await _applyRemoteSetting(storage, key, raw['value'], updatedAt);
            settingsChanged = true;
            // 收集记录取并集后本地更新，需再上行一次
            if (key == AccountSettingKeys.characterCollected) {
              mergedCollect.add(key);
            }
          }
        }

        // 上行成功的偏好记下时间戳，避免每轮同步重复推送
        final pushedSettingKeys = settings
            .map((s) => s['key']?.toString())
            .whereType<String>()
            .where((key) => !mergedCollect.contains(key))
            .toSet();
        await storage.markAccountSettingsPushed(pushedSettingKeys);

        // 「上行条数」= 本轮待推记录中被服务端接受（未判冲突）的条数。
        // 不用服务端返回的 accepted 反推：那是 entries + settings 的混合
        // 计数，口径一变（新增字段/跳过规则）就会算错
        pushed = pending.length - conflicted.length;

        await storage.markEntriesSynced(
          pending
              .map((e) => e.clientId)
              .where((id) => !conflicted.contains(id))
              .toList(),
        );
      }

      var cursor = storage.syncCursor;
      var pulled = 0;
      final pulledSettingKeys = <String>{};
      while (true) {
        final res = await SyncApi.pull(token, cursor: cursor);
        final items = (res['items'] as List?) ?? const [];
        for (final raw in items) {
          if (raw is! Map) continue;
          if (raw['type'] == 'entry') {
            final clientId = raw['clientId']?.toString();
            final data = raw['data'];
            if (clientId == null || data is! Map) continue;
            await storage.applyRemoteEntry(
              _entryFromRemote(
                Map<String, dynamic>.from(data),
                clientId: clientId,
                deletedAt: raw['deletedAt']?.toString(),
              ),
            );
            pulled += 1;
          } else if (raw['type'] == 'setting') {
            final key = raw['key']?.toString();
            final updatedAt = raw['updatedAt']?.toString();
            if (key == null || updatedAt == null || updatedAt.isEmpty) continue;
            // 本轮自己刚推上去的同一版本，本地已有，跳过回显
            if (pushedSettingAt[key] == updatedAt) continue;
            if (raw['deletedAt'] != null) {
              await storage.removeAccountSetting(key);
            } else if (await _applyRemoteSetting(
              storage,
              key,
              raw['value'],
              updatedAt,
            )) {
              settingsChanged = true;
              // 收集记录并集后本地更新，留给下一轮上行
              if (key != AccountSettingKeys.characterCollected) {
                pulledSettingKeys.add(key);
              }
            }
          }
        }
        cursor = (res['cursor'] as num?)?.toInt() ?? cursor;
        await storage.setSyncCursor(cursor);
        if (res['hasMore'] != true) break;
      }
      await storage.markAccountSettingsPushed(pulledSettingKeys);

      await storage.setSyncLastSyncAt(DateTime.now());
      // 本轮成功：清掉历史失败原因（云备份页的「上次同步失败」提示）
      await storage.setSyncLastError(null);
      // 记录同步完成后，顺带同步账号资料（头像 / 饮水目标）
      await ProfileSync.sync(storage);
      // 积分：补传离线累计的流水，并以服务端余额 / 明细为准
      await PointsSync.sync(storage);
      if (settingsChanged) onSettingsSynced?.call();
      return SyncResult(pushed: pushed, pulled: pulled);
    } catch (e) {
      // 账号已在其他设备登录：清掉本机会话并通知 UI 弹窗
      if (e is SyncApiException && e.isSessionRevoked) {
        await handleSessionRevoked(storage);
        debugPrint('[Sync] session revoked by another device');
        onSessionRevoked?.call();
        return SyncResult(failed: true, message: '账号已在其他设备登录');
      }
      debugPrint('[Sync] failed: $e');
      // 静默失败没有任何用户可见反馈：记下原因，云备份页据此展示
      try {
        final msg = '$e';
        await storage.setSyncLastError(
          msg.length > 120 ? '${msg.substring(0, 120)}…' : msg,
        );
      } catch (_) {
        // 记录失败原因不应影响同步结果返回
      }
      return SyncResult(failed: true, message: '$e');
    }
  }

  /// 无感同步：开关关闭或未登录时静默跳过（失败不打扰用户）
  static Future<SyncResult?> autoSync(LocalStorage storage) async {
    if (!storage.autoSyncEnabled || !storage.hasAccountSession) return null;
    return syncNow(storage);
  }

  /// 应用一条云端偏好：收集记录只增不减取并集，其余按更新时间取新
  static Future<bool> _applyRemoteSetting(
    LocalStorage storage,
    String key,
    Object? value,
    String updatedAt,
  ) async {
    if (key == AccountSettingKeys.characterCollected) {
      final ids = value is List
          ? value.map((e) => e.toString()).toList()
          : const <String>[];
      await storage.mergeListSetting(key, ids);
      return true;
    }
    return storage.applyRemoteAccountSetting(key, value, updatedAt);
  }

  static Map<String, dynamic> _looksLikeEntry(DrinkEntry e) {
    final updatedAt = e.effectiveUpdatedAt.toUtc().toIso8601String();
    return {
      'clientId': e.clientId,
      'updatedAt': updatedAt,
      'deletedAt': e.deleted ? updatedAt : null,
      'data': e.toMap(),
    };
  }

  static DrinkEntry _entryFromRemote(
    Map<String, dynamic> data, {
    required String clientId,
    String? deletedAt,
  }) {
    final parsed = DrinkEntry.fromMap(data);
    final updated =
        DateTime.tryParse(deletedAt ?? '') ??
        DateTime.tryParse(data['updated_at']?.toString() ?? '');
    return parsed.copyWith(
      synced: true,
      deleted: deletedAt != null,
      updatedAt: updated?.toUtc(),
    );
  }
}
