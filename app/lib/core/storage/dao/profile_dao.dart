import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/animal_character.dart';
import '../../../shared/models/user_profile.dart';
import '../../settings/account_settings.dart';
import '../../time/logical_day.dart';
import 'dao_keys.dart';
import 'dao_shared.dart';
import 'settings_dao.dart';

/// 用户档案 / 单位偏好 / 欢迎标记 / 每日动物 / 重置日（SharedPreferences）
class ProfileDao {
  ProfileDao(this.prefs);

  final SharedPreferences prefs;

  UserProfile? loadProfile() {
    final raw = prefs.getString(StorageKeys.profile);
    if (raw == null) return null;
    // 简单 KV：JSON 风格 map
    final map = decodeMap(raw);
    return UserProfile.fromMap(map);
  }

  Future<void> saveProfile(UserProfile profile) async {
    await prefs.setString(StorageKeys.profile, encodeMap(profile.toMap()));
  }

  /// 返回 'ml' 或 'oz'，未设置返回 null（首次启动）
  String? loadPreferredUnit() =>
      readAccountSetting(AccountSettingKeys.preferredUnit)?.toString();

  Future<void> savePreferredUnit(String unit) =>
      writeAccountSetting(AccountSettingKeys.preferredUnit, unit);

  // 账号级偏好读写转调 SettingsDao，保持门面原有行为
  dynamic readAccountSetting(String key) => SettingsDao(prefs).readAccountSetting(key);

  Future<void> writeAccountSetting(String key, Object? value) =>
      SettingsDao(prefs).writeAccountSetting(key, value);

  bool hasSeenWelcome() => prefs.getBool(StorageKeys.welcomeSeen) ?? false;

  Future<void> markWelcomeSeen() async {
    await prefs.setBool(StorageKeys.welcomeSeen, true);
  }

  String? loadDailyAnimalId(DateTime day) {
    return prefs.getString(StorageKeys.dailyAnimalPrefix + dayKey(day));
  }

  Future<void> saveDailyAnimalId(DateTime day, String animalId) async {
    await prefs.setString(StorageKeys.dailyAnimalPrefix + dayKey(day), animalId);
  }

  /// 自动选动物：当天（逻辑日）未选过则按日期 hash 选一个
  AnimalCharacter pickOrLoadDailyAnimal() {
    final today = LogicalDay.today();
    final saved = loadDailyAnimalId(today);
    if (saved != null) {
      final match = AnimalCharacter.all.where((a) => a.id == saved).firstOrNull;
      if (match != null) return match;
    }
    final pool = AnimalCharacter.all;
    final idx = today.day % pool.length;
    final picked = pool[idx];
    saveDailyAnimalId(today, picked.id);
    return picked;
  }

  DateTime? loadLastResetDay() {
    final s = prefs.getString(StorageKeys.lastResetDay);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> saveLastResetDay(DateTime day) async {
    await prefs.setString(StorageKeys.lastResetDay, day.toIso8601String());
  }

  /// 登录前游客档案快照：退出账号后恢复，避免账号资料留在游客视图里
  UserProfile? get guestProfileSnapshot {
    final raw = prefs.getString(StorageKeys.guestProfile);
    return raw == null ? null : UserProfile.fromMap(decodeMap(raw));
  }

  Future<void> saveGuestProfileSnapshot(UserProfile profile) async {
    await prefs.setString(
      StorageKeys.guestProfile,
      encodeMap(profile.toMap()),
    );
  }

  Future<void> clearGuestProfileSnapshot() async {
    await prefs.remove(StorageKeys.guestProfile);
  }
}
