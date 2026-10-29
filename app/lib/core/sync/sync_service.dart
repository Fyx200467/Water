import 'package:flutter/foundation.dart';

import '../../shared/models/drink_entry.dart';
import '../storage/local_storage.dart';
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
  static bool _running = false;

  /// 会话被其他设备顶掉时的全局回调（App 根节点注册，用于弹窗提示）
  static void Function()? onSessionRevoked;

  /// 当前设备的数据归属账号发生变化（登录 / 退出 / 被顶下线）。
  /// App 根节点据此推进会话纪元，让按 owner 读取的数据统一重载。
  static void Function()? onSessionChanged;

  static Future<void> signIn(
    LocalStorage storage,
    String email,
    String password,
  ) async {
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
      nickname: nickname,
    );
    await _applyAccount(storage, res);
  }

  static Future<void> signOut(LocalStorage storage) async {
    // 退出后回到登录前的游客档案，账号的身体数据不会残留在游客视图
    await ProfileSync.restoreGuestProfile(storage);
    SessionWatch.stop();
    await storage.clearSyncSession();
    onSessionChanged?.call();
  }

  /// 账号被其他设备顶掉：恢复游客档案 + 清会话 + 断开实时通道
  static Future<void> handleSessionRevoked(LocalStorage storage) async {
    await ProfileSync.restoreGuestProfile(storage);
    SessionWatch.stop();
    await storage.clearSyncSession();
    onSessionChanged?.call();
  }

  static Future<void> _applyAccount(
    LocalStorage storage,
    Map<String, dynamic> res,
  ) async {
    // 登录前先快照游客档案，退出账号时恢复
    if (!storage.hasAccountSession) {
      final guestProfile = storage.loadProfile();
      if (guestProfile != null) {
        await storage.saveGuestProfileSnapshot(guestProfile);
      }
    }
    await storage.setSyncSession(
      res['userId'] as String,
      res['accessToken'] as String,
      email: res['email'] as String,
    );
    final nickname = res['nickname'] as String?;
    if (nickname != null && nickname.isNotEmpty) {
      await storage.setAccountNickname(nickname);
    }
    // 新登录的账号必须先从服务端拉档案，不能把本机默认目标抢先写进账号
    await storage.clearLastPushedProfileSignature();
    // 未登录期间产生的本地记录归属到该账号（本地数据与账号绑定），
    // 之后再从 0 开始拉取云端历史
    await storage.bindGuestEntriesToAccount(res['userId'] as String);
    await storage.setSyncCursor(0);
    // 归属账号已切换：通知界面按新 owner 重载本地数据
    onSessionChanged?.call();
    // 实时监听顶号；随后立刻拉一次完整档案与头像
    SessionWatch.start(res['accessToken'] as String);
    await ProfileSync.sync(storage, force: true);
  }

  static Future<SyncResult> syncNow(LocalStorage storage) async {
    if (!storage.hasAccountSession) {
      return const SyncResult(message: '未登录');
    }
    if (_running) return const SyncResult();
    _running = true;
    try {
      final token = storage.syncToken!;

      final pending = await storage.loadPendingSyncEntries();
      var pushed = 0;
      final conflicted = <String>{};

      if (pending.isNotEmpty) {
        final res = await SyncApi.push(
          token,
          entries: pending.map(_looksLikeEntry).toList(),
        );
        pushed = (res['accepted'] as num?)?.toInt() ?? 0;

        for (final raw in (res['conflicts'] as List?) ?? const []) {
          if (raw is! Map || raw['type'] != 'entry') continue;
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
        }

        await storage.markEntriesSynced(
          pending
              .map((e) => e.clientId)
              .where((id) => !conflicted.contains(id))
              .toList(),
        );
      }

      var cursor = storage.syncCursor;
      var pulled = 0;
      while (true) {
        final res = await SyncApi.pull(token, cursor: cursor);
        final items = (res['items'] as List?) ?? const [];
        for (final raw in items) {
          if (raw is! Map || raw['type'] != 'entry') continue;
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
        }
        cursor = (res['cursor'] as num?)?.toInt() ?? cursor;
        await storage.setSyncCursor(cursor);
        if (res['hasMore'] != true) break;
      }

      await storage.setSyncLastSyncAt(DateTime.now());
      // 记录同步完成后，顺带同步账号资料（头像 / 饮水目标）
      await ProfileSync.sync(storage);
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
      return SyncResult(failed: true, message: '$e');
    } finally {
      _running = false;
    }
  }

  /// 无感同步：开关关闭或未登录时静默跳过（失败不打扰用户）
  static Future<SyncResult?> autoSync(LocalStorage storage) async {
    if (!storage.autoSyncEnabled || !storage.hasAccountSession) return null;
    return syncNow(storage);
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
