import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'dao_keys.dart';
import 'dao_shared.dart';

/// 账号级偏好（跟随账号上云）+ 小游戏进度
class SettingsDao {
  SettingsDao(this.prefs);

  final SharedPreferences prefs;

  String get owner => ownerOf(prefs);

  String get settingsStoreKey =>
      '${StorageKeys.settingsPrefix}${ownerSuffix(owner)}';

  String get settingsPushedKey =>
      '${StorageKeys.settingsPushedPrefix}${ownerSuffix(owner)}';

  /// 当前归属（登录账号 / 游客）的偏好快照：key → {v: 值, at: 更新时间}
  Map<String, Map<String, dynamic>> loadAccountSettings() =>
      decodeSettings(prefs.getString(settingsStoreKey));

  /// 读取单个偏好值；不存在返回 null
  dynamic readAccountSetting(String key) => loadAccountSettings()[key]?['v'];

  /// 写入单个偏好：更新时间记为 now，云同步按 updatedAt 取新
  Future<void> writeAccountSetting(String key, Object? value) async {
    final all = loadAccountSettings();
    all[key] = {'v': value, 'at': nowIso()};
    await prefs.setString(settingsStoreKey, jsonEncode(all));
  }

  /// 应用云端偏好：本地更新时间更晚时保留本地（冲突时以服务端取新为准）
  Future<bool> applyRemoteAccountSetting(
    String key,
    Object? value,
    String updatedAt,
  ) async {
    final all = loadAccountSettings();
    final localAt = all[key]?['at']?.toString();
    if (localAt != null && isNewer(localAt, updatedAt)) return false;
    all[key] = {'v': value, 'at': updatedAt};
    await prefs.setString(settingsStoreKey, jsonEncode(all));
    return true;
  }

  Future<void> removeAccountSetting(String key) async {
    final all = loadAccountSettings()..remove(key);
    await prefs.setString(settingsStoreKey, jsonEncode(all));
  }

  /// 收集类偏好（角色）只增不减：与本机取并集后写入新的更新时间，
  /// 纯 LWW 会让另一台设备的收集进度被覆盖
  Future<void> mergeListSetting(String key, Iterable<String> values) async {
    final all = loadAccountSettings();
    final local =
        (all[key]?['v'] as List?)?.map((e) => e.toString()).toSet() ??
        <String>{};
    final union = {...local, ...values};
    if (union.length == local.length) return;
    all[key] = {'v': union.toList(), 'at': nowIso()};
    await prefs.setString(settingsStoreKey, jsonEncode(all));
  }

  /// 云同步上行载荷：只带自上次成功上行后变化的偏好，避免重复推送
  List<Map<String, dynamic>> settingsPushPayload() {
    final all = loadAccountSettings();
    final pushed = decodeStringMap(prefs.getString(settingsPushedKey));
    return all.entries
        .where((e) {
          final at = e.value['at'];
          // 时间戳为空的老数据不上行，避免服务端判为非法 item
          return at is String && at.isNotEmpty && at != pushed[e.key];
        })
        .map(
          (e) => {
            'key': e.key,
            'updatedAt': e.value['at'],
            'value': e.value['v'],
          },
        )
        .toList();
  }

  /// 标记这些偏好已成功上行（记录本次更新时间，下轮不再重复推送）
  Future<void> markAccountSettingsPushed(Set<String> keys) async {
    if (keys.isEmpty) return;
    final all = loadAccountSettings();
    final pushed = decodeStringMap(prefs.getString(settingsPushedKey));
    for (final key in keys) {
      final at = all[key]?['at']?.toString();
      if (at != null && at.isNotEmpty) pushed[key] = at;
    }
    await prefs.setString(settingsPushedKey, jsonEncode(pushed));
  }

  /// 登录后把游客偏好并入账号桶。
  /// 账号桶为空（首次登录该账号）才整桶复制；账号已有偏好说明是服务端下发或
  /// 用户在账号里改过的，不能再被游客旧值灌回（否则删掉的偏好会复活）。
  Future<void> adoptGuestAccountSettings(String userId) async {
    if (userId.isEmpty) return;
    final guest =
        decodeSettings(prefs.getString('${StorageKeys.settingsPrefix}guest'));
    if (guest.isEmpty) return;
    final userKey = '${StorageKeys.settingsPrefix}$userId';
    final existing = decodeSettings(prefs.getString(userKey));
    if (existing.isNotEmpty) return;
    await prefs.setString(userKey, jsonEncode(guest));
  }

  /// 启动早期（LocalStorage 尚未初始化）按当前归属账号读取偏好
  static dynamic peekAccountSetting(SharedPreferences prefs, String key) {
    final uid = prefs.getString(StorageKeys.syncUserId) ?? '';
    final map = decodeSettings(
      prefs.getString(
        '${StorageKeys.settingsPrefix}${ownerSuffix(uid)}',
      ),
    );
    return map[key]?['v'];
  }

  // ---------- 小游戏进度 ----------

  /// 消消乐闯关已解锁的最高关卡（默认第 1 关）
  int get match3Level {
    final v = prefs.getInt(StorageKeys.match3Level) ?? 1;
    return v < 1 ? 1 : v;
  }

  Future<void> setMatch3Level(int level) async {
    if (level < 1) return;
    await prefs.setInt(StorageKeys.match3Level, level);
  }

  /// 吨吨守卫战已通关的最高关卡数（0~5；只存本机）
  int get defenseClearedLevels {
    final v = prefs.getInt(StorageKeys.defenseLevel) ?? 0;
    if (v < 0) return 0;
    return v > 5 ? 5 : v;
  }

  Future<void> setDefenseClearedLevels(int cleared) async {
    if (cleared < 0) return;
    await prefs.setInt(
      StorageKeys.defenseLevel,
      cleared > 5 ? 5 : cleared,
    );
  }
}
