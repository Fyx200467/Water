import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../shared/models/animal_character.dart';
import '../../shared/models/drink_entry.dart';
import '../../shared/models/user_profile.dart';
import 'dao/account_dao.dart';
import 'dao/database_setup.dart';
import 'dao/drink_dao.dart';
import 'dao/health_dao.dart';
import 'dao/maintenance_dao.dart';
import 'dao/points_dao.dart';
import 'dao/profile_dao.dart';
import 'dao/settings_dao.dart';

/// 本地存储门面：public API 保持不变，实现按领域下沉到 `dao/` 下的 DAO。
/// 封装：SharedPreferences（轻配置）+ SQLite（结构化数据）；
/// 桌面 / Web 端 sqflite 不可用时降级为 shared_preferences-only。
class LocalStorage {
  // ignore: prefer_initializing_formals
  LocalStorage._({required this.prefs, Database? db}) : _db = db;

  late final SharedPreferences prefs;
  final Database? _db;

  late final ProfileDao _profile = ProfileDao(prefs);
  late final SettingsDao _settings = SettingsDao(prefs);
  late final PointsDao _points = PointsDao(prefs);
  late final DrinkDao _drink = DrinkDao(prefs, _db);
  late final HealthDao _health = HealthDao(prefs, _db);
  late final AccountDao _account = AccountDao(prefs);
  late final MaintenanceDao _maintenance = MaintenanceDao(prefs, _db);

  static Future<LocalStorage> init() async {
    final prefs = await SharedPreferences.getInstance();
    // 偏好迁移只依赖 prefs，先于（可能失败的）SQLite 初始化执行
    await migrateLegacySettings(prefs);
    await migrateLegacyPoints(prefs);
    await migrateLegacyCursor(prefs);
    try {
      if (kIsWeb) return LocalStorage._(prefs: prefs);
      final db = await openDrinkDatabase();
      await claimLegacyEntries(prefs, db);
      final storage = LocalStorage._(prefs: prefs, db: db);
      await storage.purgeOldTombstones();
      return storage;
    } catch (e) {
      // ignore: avoid_print
      print(
        '[LocalStorage] SQLite unavailable, falling back to prefs-only: $e',
      );
      return LocalStorage._(prefs: prefs);
    }
  }

  UserProfile? loadProfile() => _profile.loadProfile();

  Future<void> saveProfile(UserProfile profile) =>
      _profile.saveProfile(profile);

  String? loadPreferredUnit() => _profile.loadPreferredUnit();

  Future<void> savePreferredUnit(String unit) =>
      _profile.savePreferredUnit(unit);

  Map<String, Map<String, dynamic>> loadAccountSettings() =>
      _settings.loadAccountSettings();

  dynamic readAccountSetting(String key) => _settings.readAccountSetting(key);

  Future<void> writeAccountSetting(String key, Object? value) =>
      _settings.writeAccountSetting(key, value);

  Future<bool> applyRemoteAccountSetting(
    String key,
    Object? value,
    String updatedAt,
  ) =>
      _settings.applyRemoteAccountSetting(key, value, updatedAt);

  Future<void> removeAccountSetting(String key) =>
      _settings.removeAccountSetting(key);

  Future<void> mergeListSetting(String key, Iterable<String> values) =>
      _settings.mergeListSetting(key, values);

  List<Map<String, dynamic>> settingsPushPayload() =>
      _settings.settingsPushPayload();

  Future<void> markAccountSettingsPushed(Set<String> keys) =>
      _settings.markAccountSettingsPushed(keys);

  Future<void> adoptGuestAccountSettings(String userId) =>
      _settings.adoptGuestAccountSettings(userId);

  static dynamic peekAccountSetting(SharedPreferences prefs, String key) =>
      SettingsDao.peekAccountSetting(prefs, key);

  Map<String, dynamic>? loadPointsSnapshot() => _points.loadPointsSnapshot();

  Future<void> savePointsSnapshot(Map<String, dynamic> snapshot) =>
      _points.savePointsSnapshot(snapshot);

  List<Map<String, dynamic>> loadPendingPointEvents() =>
      _points.loadPendingPointEvents();

  Future<void> addPendingPointEvent(Map<String, dynamic> event) =>
      _points.addPendingPointEvent(event);

  Future<void> removePendingPointEvents(Iterable<String> eventIds) =>
      _points.removePendingPointEvents(eventIds);

  Future<void> applyPointsSummary(
    int balance,
    List<Map<String, dynamic>> history,
  ) =>
      _points.applyPointsSummary(balance, history);

  Future<void> adoptGuestPoints(String userId) =>
      _points.adoptGuestPoints(userId);

  bool hasSeenWelcome() => _profile.hasSeenWelcome();

  Future<void> markWelcomeSeen() => _profile.markWelcomeSeen();

  String? loadDailyAnimalId(DateTime day) => _profile.loadDailyAnimalId(day);

  Future<void> saveDailyAnimalId(DateTime day, String animalId) =>
      _profile.saveDailyAnimalId(day, animalId);

  AnimalCharacter pickOrLoadDailyAnimal() => _profile.pickOrLoadDailyAnimal();

  DateTime? loadLastResetDay() => _profile.loadLastResetDay();

  Future<void> saveLastResetDay(DateTime day) =>
      _profile.saveLastResetDay(day);

  Future<void> insertDrinkEntry(DrinkEntry entry) =>
      _drink.insertDrinkEntry(entry);

  Future<void> softDeleteEntry(String clientId) =>
      _drink.softDeleteEntry(clientId);

  /// 查询某逻辑日的记录（逻辑日区间 = [day + 重置时刻, day+1 + 重置时刻)）
  Future<List<DrinkEntry>> loadEntriesForDay(DateTime day) =>
      _drink.loadEntriesForDay(day);

  Future<List<DrinkEntry>> loadEntriesForRange(
    DateTime start,
    DateTime end,
  ) =>
      _drink.loadEntriesForRange(start, end);

  Future<List<DrinkEntry>> loadUnsyncedEntries() =>
      _drink.loadUnsyncedEntries();

  Future<void> markSynced(String clientId, {String? serverId}) =>
      _drink.markSynced(clientId, serverId: serverId);

  bool get healthSyncEnabled => _health.healthSyncEnabled;

  Future<void> setHealthSyncEnabled(bool on) =>
      _health.setHealthSyncEnabled(on);

  DateTime? get healthLastSyncAt => _health.healthLastSyncAt;

  Future<void> setHealthLastSyncAt(DateTime at) =>
      _health.setHealthLastSyncAt(at);

  int get match3Level => _settings.match3Level;

  Future<void> setMatch3Level(int level) => _settings.setMatch3Level(level);

  int get defenseClearedLevels => _settings.defenseClearedLevels;

  Future<void> setDefenseClearedLevels(int cleared) =>
      _settings.setDefenseClearedLevels(cleared);

  String? get accountAvatarPath => _account.accountAvatarPath;

  Future<void> setAccountAvatarPath(String? path) =>
      _account.setAccountAvatarPath(path);

  String? get accountAvatarRemoteUrl => _account.accountAvatarRemoteUrl;

  Future<void> setAccountAvatarRemoteUrl(String? url) =>
      _account.setAccountAvatarRemoteUrl(url);

  bool get avatarDirty => _account.avatarDirty;

  Future<void> markAvatarDirty() => _account.markAvatarDirty();

  Future<void> clearAvatarDirty() => _account.clearAvatarDirty();

  String? get lastPushedProfileSignature =>
      _account.lastPushedProfileSignature;

  Future<void> setLastPushedProfileSignature(String signature) =>
      _account.setLastPushedProfileSignature(signature);

  Future<void> clearLastPushedProfileSignature() =>
      _account.clearLastPushedProfileSignature();

  UserProfile? get guestProfileSnapshot => _profile.guestProfileSnapshot;

  Future<void> saveGuestProfileSnapshot(UserProfile profile) =>
      _profile.saveGuestProfileSnapshot(profile);

  Future<void> clearGuestProfileSnapshot() =>
      _profile.clearGuestProfileSnapshot();

  String? get lastRejectedNoticeOrderId =>
      _account.lastRejectedNoticeOrderId;

  Future<void> setLastRejectedNoticeOrderId(String orderId) =>
      _account.setLastRejectedNoticeOrderId(orderId);

  bool get autoSyncEnabled => _account.autoSyncEnabled;

  Future<void> setAutoSyncEnabled(bool on) => _account.setAutoSyncEnabled(on);

  String get accountAnonId => _account.accountAnonId;

  String get accountNickname => _account.accountNickname;

  Future<void> setAccountNickname(String name) =>
      _account.setAccountNickname(name);

  bool get nicknameDirty => _account.nicknameDirty;

  Future<void> markNicknameDirty() => _account.markNicknameDirty();

  Future<void> clearNicknameDirty() => _account.clearNicknameDirty();

  Future<void> saveGuestNicknameSnapshot() =>
      _account.saveGuestNicknameSnapshot();

  Future<void> restoreGuestNickname() => _account.restoreGuestNickname();

  DateTime? get accountLastBackupAt => _account.accountLastBackupAt;

  Future<void> setAccountLastBackupAt(DateTime at) =>
      _account.setAccountLastBackupAt(at);

  Future<List<DrinkEntry>> loadHealthPendingEntries({
    DateTime? since,
    int limit = 500,
  }) =>
      _health.loadHealthPendingEntries(since: since, limit: limit);

  Future<List<DrinkEntry>> loadHealthDeletedEntries({int limit = 200}) =>
      _health.loadHealthDeletedEntries(limit: limit);

  Future<bool> hasHealthSampleId(String sampleId) =>
      _health.hasHealthSampleId(sampleId);

  Future<void> setHealthState(
    String clientId,
    int state, {
    String? sampleId,
  }) =>
      _health.setHealthState(clientId, state, sampleId: sampleId);

  String? get syncUserId => _account.syncUserId;

  String? get syncToken => _account.syncToken;

  String? get accountEmail => _account.accountEmail;

  int get syncCursor => _account.syncCursor;

  DateTime? get syncLastSyncAt => _account.syncLastSyncAt;

  String? get syncLastError => _account.syncLastError;

  bool get hasSyncSession => _account.hasSyncSession;

  bool get hasAccountSession => _account.hasAccountSession;

  Future<void> setSyncSession(
    String userId,
    String token, {
    String? email,
  }) =>
      _account.setSyncSession(userId, token, email: email);

  Future<void> clearSyncSession() => _account.clearSyncSession();

  Future<void> setSyncCursor(int cursor) => _account.setSyncCursor(cursor);

  Future<void> reloadPrefs() => _account.reloadPrefs();

  Future<void> clearAccountEmail() => _account.clearAccountEmail();

  Future<void> setSyncLastSyncAt(DateTime at) =>
      _account.setSyncLastSyncAt(at);

  Future<void> setSyncLastError(String? message) =>
      _account.setSyncLastError(message);

  Future<List<DrinkEntry>> loadPendingSyncEntries({int limit = 200}) =>
      _drink.loadPendingSyncEntries(limit: limit);

  Future<int> countPendingSyncEntries() =>
      _drink.countPendingSyncEntries();

  Future<int> countGuestEntries() => _drink.countGuestEntries();

  Future<void> bindGuestEntriesToAccount(String userId) =>
      _drink.bindGuestEntriesToAccount(userId);

  Future<void> markEntriesSynced(List<String> clientIds) =>
      _drink.markEntriesSynced(clientIds);

  Future<void> applyRemoteEntry(DrinkEntry entry) =>
      _drink.applyRemoteEntry(entry);

  Future<void> clearAllData() => _maintenance.clearAllData();

  Future<void> purgeAccountData(String userId) =>
      _maintenance.purgeAccountData(userId);

  /// 定期清理超过 [days] 天的已同步墓碑，避免本地库无限增长
  Future<void> purgeOldTombstones({int days = 90}) =>
      _maintenance.purgeOldTombstones(days: days);
}
