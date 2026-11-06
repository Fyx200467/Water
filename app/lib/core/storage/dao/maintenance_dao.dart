import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'dao_keys.dart';
import 'dao_shared.dart';

/// 清数据 / 注销清理 / 墓碑清理（跨领域维护操作）
class MaintenanceDao {
  MaintenanceDao(this.prefs, this.db);

  final SharedPreferences prefs;
  final Database? db;

  bool get hasDb => db != null;

  String get owner => ownerOf(prefs);

  /// PRD §2.8 清除全部本地数据（设置页入口）
  /// 只清当前归属（游客或当前账号）的饮水记录与偏好，不动登录态，
  /// 也不动其他账号留在本机的数据桶。
  Future<void> clearAllData() async {
    final currentOwner = owner;
    try {
      if (hasDb) {
        await db!.delete(
          'drink_entries',
          where: 'owner_user_id = ?',
          whereArgs: [currentOwner],
        );
      }
    } catch (_) {}

    final keep = <String>{
      StorageKeys.syncUserId,
      StorageKeys.syncToken,
      StorageKeys.accountEmail,
      StorageKeys.lastUserId,
      StorageKeys.accountAnonId,
      StorageKeys.autoSync,
      'api_base_url',
    };
    // 其他账号按 owner 前缀分桶的数据：前缀长的优先匹配，
    // 避免 account_settings_ 误删 account_settings_pushed_<uid> 的键
    final ownerPrefixes = <String>[
      StorageKeys.settingsPushedPrefix,
      StorageKeys.settingsPrefix,
      StorageKeys.entriesPrefix,
      StorageKeys.syncCursorPrefix,
      'points_state_',
      'points_pending_',
      '${StorageKeys.accountAvatar}_',
      '${StorageKeys.accountAvatarRemote}_',
      '${StorageKeys.avatarDirty}_',
      '${StorageKeys.pushedProfile}_',
      '${StorageKeys.rejectedOrderNotice}_',
    ]..sort((a, b) => b.length.compareTo(a.length));

    final currentSuffix = ownerSuffix(currentOwner);

    /// 按 owner 分桶的 key 返回其归属后缀（最长前缀优先），否则返回 null
    String? bucketSuffix(String key) {
      for (final p in ownerPrefixes) {
        if (key.startsWith(p) && key.length > p.length) {
          return key.substring(p.length);
        }
      }
      return null;
    }

    for (final key in prefs.getKeys().toList()) {
      if (keep.contains(key)) continue;
      // 其他账号的桶保留：清数据不该把别人留在本机的数据也删掉
      final suffix = bucketSuffix(key);
      if (suffix != null && suffix != currentSuffix && suffix != 'guest') {
        continue;
      }
      await prefs.remove(key);
    }
    // 当前归属的偏好桶本身已随上面循环清理；把游标重置为从头拉取
    await prefs.setInt(
      '${StorageKeys.syncCursorPrefix}$currentSuffix',
      0,
    );
    await prefs.setBool(StorageKeys.settingsMigrated, true);
    await prefs.setBool(StorageKeys.pointsMigrated, true);
  }

  /// 清除某个账号留在本机的全部数据（注销账号时调用）。
  /// 只删该账号的桶与记录，不影响游客与其他账号。
  Future<void> purgeAccountData(String userId) async {
    if (userId.isEmpty) return;
    try {
      if (hasDb) {
        await db!.delete(
          'drink_entries',
          where: 'owner_user_id = ?',
          whereArgs: [userId],
        );
      }
    } catch (_) {}
    final keys = <String>[
      '${StorageKeys.settingsPrefix}$userId',
      '${StorageKeys.settingsPushedPrefix}$userId',
      'points_state_$userId',
      'points_pending_$userId',
      '${StorageKeys.accountAvatar}_$userId',
      '${StorageKeys.accountAvatarRemote}_$userId',
      '${StorageKeys.avatarDirty}_$userId',
      '${StorageKeys.pushedProfile}_$userId',
      '${StorageKeys.rejectedOrderNotice}_$userId',
      '${StorageKeys.syncCursorPrefix}$userId',
      '${StorageKeys.entriesPrefix}$userId',
    ];
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// 定期清理超过 [days] 天的已同步墓碑，避免本地库无限增长
  Future<void> purgeOldTombstones({int days = 90}) async {
    if (!hasDb) return;
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);
    try {
      await db!.delete(
        'drink_entries',
        where: 'deleted = 1 AND synced = 1 AND substr(updated_at, 1, 10) < ?',
        whereArgs: [cutoff],
      );
    } catch (_) {}
  }
}
