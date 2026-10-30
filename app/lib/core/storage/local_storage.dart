import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../shared/models/animal_character.dart';
import '../../shared/models/drink_entry.dart';
import '../../shared/models/user_profile.dart';
import '../settings/account_settings.dart';
import '../time/logical_day.dart';

/// PRD §4.2 断网可写、联网同步
/// PRD §4.4 用户数据加密存储（V1.0 仅本地，加密留 V2.0）
///
/// 封装：SharedPreferences（轻配置）+ SQLite（结构化数据）
/// 桌面 / Web 端 sqflite 不可用时降级为 shared_preferences-only
class LocalStorage {
  LocalStorage._({required this.prefs, Database? db}) : _db = db;

  static const String _dbName = 'water_llama.db';
  static const int _dbVersion = 6;

  late final SharedPreferences prefs;
  final Database? _db;

  bool get _hasDb => _db != null;

  static const String _kProfileKey = 'user_profile';
  static const String _kDailyAnimalKey = 'daily_animal_id_';
  static const String _kLastResetDayKey = 'last_reset_day';
  static const String _kEntriesPrefix = 'entries_';
  static const String _kWelcomeSeenKey = 'welcome_seen';

  static Future<LocalStorage> init() async {
    final prefs = await SharedPreferences.getInstance();
    // 偏好迁移只依赖 prefs，先于（可能失败的）SQLite 初始化执行，
    // 保证 Web / 桌面降级路径也能完成分桶
    await _migrateLegacySettings(prefs);
    await _migrateLegacyPoints(prefs);
    await _migrateLegacyCursor(prefs);
    try {
      if (kIsWeb) {
        // Web 端无法开 SQLite，降级到 prefs-only
        return LocalStorage._(prefs: prefs);
      }
      // Desktop / Mobile 走正规 sqflite
      // ignore: deprecated_member_use
      final dir = await getDatabasesPath();
      final dbPath = '$dir/$_dbName';
      final db = await openDatabase(
        dbPath,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      await _claimLegacyEntries(prefs, db);
      final storage = LocalStorage._(prefs: prefs, db: db);
      // 冷启动顺手清理已同步的老墓碑（异步等待，量很小）
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

  /// 记录表结构：主键 (owner_user_id, client_id)，不同账号可各自持有同 id 的记录
  static const String _createEntriesTable = '''
      CREATE TABLE drink_entries (
        client_id TEXT NOT NULL,
        server_id TEXT,
        beverage_id TEXT NOT NULL,
        beverage_category TEXT NOT NULL,
        beverage_name TEXT NOT NULL,
        volume_ml INTEGER NOT NULL,
        effective_ml INTEGER NOT NULL,
        drank_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        calories INTEGER NOT NULL DEFAULT -1,
        health_sample_id TEXT,
        health_state INTEGER NOT NULL DEFAULT 0,
        owner_user_id TEXT NOT NULL DEFAULT '',
        updated_at TEXT,
        PRIMARY KEY (owner_user_id, client_id)
      )
    ''';

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute(_createEntriesTable);
    await db.execute('CREATE INDEX idx_drink_at ON drink_entries(drank_at)');
    await db.execute(
      'CREATE INDEX idx_synced ON drink_entries(synced, deleted)',
    );
    await db.execute(
      'CREATE INDEX idx_owner_at ON drink_entries(owner_user_id, drank_at)',
    );
  }

  /// v5 升级：历史记录统一归属到当前登录账号（未登录则保持游客）。
  /// 只执行一次，避免把之后新增的游客数据误并入账号。
  static Future<void> _claimLegacyEntries(
    SharedPreferences prefs,
    Database db,
  ) async {
    const flag = 'entries_owner_migrated_v5';
    if (prefs.getBool(flag) == true) return;
    // 升级时若已退出登录，用最近一次登录的账号兜底归属，
    // 避免历史账号数据被当成游客数据显示出来
    final uid = prefs.getString(_kSyncUserId) ?? prefs.getString(_kLastUserId);
    try {
      if (uid != null && uid.isNotEmpty) {
        await db.update('drink_entries', {
          'owner_user_id': uid,
        }, where: "owner_user_id = ''");
      }
    } catch (_) {}
    await prefs.setBool(flag, true);
  }

  /// v1 偏好存储升级：老版本这些都是全局 key（不随账号），一次性并入
  /// 当前归属桶（登录态 → 账号桶，否则游客桶），之后按账号分桶读写。
  static Future<void> _migrateLegacySettings(SharedPreferences prefs) async {
    if (prefs.getBool(_kSettingsMigrated) == true) return;
    final uid = prefs.getString(_kSyncUserId) ?? '';
    final storeKey = '$_kSettingsPrefix${_ownerSuffix(uid)}';
    final existing = _decodeSettings(prefs.getString(storeKey));
    final at = _nowIso();
    for (final key in AccountSettingKeys.all) {
      if (existing.containsKey(key)) continue;
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      existing[key] = {'v': _decodeSettingValue(raw), 'at': at};
    }
    await prefs.setString(storeKey, jsonEncode(existing));
    // 旧全局 key 已并入归属桶，删除避免退出登录后串到游客视图
    for (final key in AccountSettingKeys.all) {
      await prefs.remove(key);
    }
    await prefs.setBool(_kSettingsMigrated, true);
  }

  /// v1 → v2：补上录入时快照的热量列（旧记录默认 -1 = 未记录）
  /// v2 → v3：健康同步状态（0 未同步 / 1 已导出 / 2 已导入）
  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE drink_entries ADD COLUMN calories INTEGER NOT NULL DEFAULT -1',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE drink_entries ADD COLUMN health_sample_id TEXT',
      );
      await db.execute(
        'ALTER TABLE drink_entries ADD COLUMN health_state INTEGER NOT NULL DEFAULT 0',
      );
    }
    // v3 → v4：云同步的修改时间（冲突按 updated_at 取新）
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE drink_entries ADD COLUMN updated_at TEXT');
    }
    // v4 → v5：记录归属（登录账号 ID；空串 = 游客）
    if (oldVersion < 5) {
      await db.execute(
        "ALTER TABLE drink_entries ADD COLUMN owner_user_id TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        'CREATE INDEX idx_owner_at ON drink_entries(owner_user_id, drank_at)',
      );
    }
    // v5 → v6：主键改为 (owner_user_id, client_id)。
    // 旧表只按 client_id 唯一，切账号后同一条记录会被 replace 到新账号名下，
    // 导致原账号丢掉记录，这里整体重建表。
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE drink_entries RENAME TO drink_entries_v5');
      await db.execute(_createEntriesTable);
      await db.execute('''
        INSERT INTO drink_entries
          (client_id, server_id, beverage_id, beverage_category, beverage_name,
           volume_ml, effective_ml, drank_at, synced, deleted, calories,
           health_sample_id, health_state, owner_user_id, updated_at)
        SELECT client_id, server_id, beverage_id, beverage_category, beverage_name,
               volume_ml, effective_ml, drank_at, synced, deleted, calories,
               health_sample_id, health_state, owner_user_id, updated_at
          FROM drink_entries_v5
      ''');
      // 旧表及其索引一并移除
      await db.execute('DROP TABLE drink_entries_v5');
      await db.execute('CREATE INDEX idx_drink_at ON drink_entries(drank_at)');
      await db.execute(
        'CREATE INDEX idx_synced ON drink_entries(synced, deleted)',
      );
      await db.execute(
        'CREATE INDEX idx_owner_at ON drink_entries(owner_user_id, drank_at)',
      );
    }
  }

  // ---------- UserProfile ----------

  UserProfile? loadProfile() {
    final raw = prefs.getString(_kProfileKey);
    if (raw == null) return null;
    // 简单 KV：JSON 风格 map
    final map = _decodeMap(raw);
    return UserProfile.fromMap(map);
  }

  Future<void> saveProfile(UserProfile profile) async {
    await prefs.setString(_kProfileKey, _encodeMap(profile.toMap()));
  }

  // ---------- 单位偏好（首次启动选择，跟随账号） ----------

  /// 返回 'ml' 或 'oz'，未设置返回 null（首次启动）
  String? loadPreferredUnit() =>
      readAccountSetting(AccountSettingKeys.preferredUnit)?.toString();

  Future<void> savePreferredUnit(String unit) =>
      writeAccountSetting(AccountSettingKeys.preferredUnit, unit);

  // ---------- 账号级偏好（跟随账号上云） ----------

  /// 偏好按归属分桶：`account_settings_<owner>`，value 里带更新时间用于云同步取新
  static const String _kSettingsPrefix = 'account_settings_';
  static const String _kSettingsPushedPrefix = 'account_settings_pushed_';
  static const String _kSettingsMigrated = 'account_settings_migrated_v1';

  String get _settingsStoreKey => '$_kSettingsPrefix${_ownerSuffix(_owner)}';

  String get _settingsPushedKey =>
      '$_kSettingsPushedPrefix${_ownerSuffix(_owner)}';

  /// 当前归属（登录账号 / 游客）的偏好快照：key → {v: 值, at: 更新时间}
  Map<String, Map<String, dynamic>> loadAccountSettings() =>
      _decodeSettings(prefs.getString(_settingsStoreKey));

  /// 读取单个偏好值；不存在返回 null
  dynamic readAccountSetting(String key) => loadAccountSettings()[key]?['v'];

  /// 写入单个偏好：更新时间记为 now，云同步按 updatedAt 取新
  Future<void> writeAccountSetting(String key, Object? value) async {
    final all = loadAccountSettings();
    all[key] = {'v': value, 'at': _nowIso()};
    await prefs.setString(_settingsStoreKey, jsonEncode(all));
  }

  /// 应用云端偏好：本地更新时间更晚时保留本地（冲突时以服务端取新为准）
  Future<bool> applyRemoteAccountSetting(
    String key,
    Object? value,
    String updatedAt,
  ) async {
    final all = loadAccountSettings();
    final localAt = all[key]?['at']?.toString();
    if (localAt != null && _isNewer(localAt, updatedAt)) return false;
    all[key] = {'v': value, 'at': updatedAt};
    await prefs.setString(_settingsStoreKey, jsonEncode(all));
    return true;
  }

  Future<void> removeAccountSetting(String key) async {
    final all = loadAccountSettings()..remove(key);
    await prefs.setString(_settingsStoreKey, jsonEncode(all));
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
    all[key] = {'v': union.toList(), 'at': _nowIso()};
    await prefs.setString(_settingsStoreKey, jsonEncode(all));
  }

  /// 云同步上行载荷：只带自上次成功上行后变化的偏好，避免重复推送
  List<Map<String, dynamic>> settingsPushPayload() {
    final all = loadAccountSettings();
    final pushed = _decodeStringMap(prefs.getString(_settingsPushedKey));
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
    final pushed = _decodeStringMap(prefs.getString(_settingsPushedKey));
    for (final key in keys) {
      final at = all[key]?['at']?.toString();
      if (at != null && at.isNotEmpty) pushed[key] = at;
    }
    await prefs.setString(_settingsPushedKey, jsonEncode(pushed));
  }

  /// 登录后把游客偏好并入账号桶。
  /// 账号桶为空（首次登录该账号）才整桶复制；账号已有偏好说明是服务端下发或
  /// 用户在账号里改过的，不能再被游客旧值灌回（否则删掉的偏好会复活）。
  Future<void> adoptGuestAccountSettings(String userId) async {
    if (userId.isEmpty) return;
    final guest = _decodeSettings(prefs.getString('${_kSettingsPrefix}guest'));
    if (guest.isEmpty) return;
    final userKey = '$_kSettingsPrefix$userId';
    final existing = _decodeSettings(prefs.getString(userKey));
    if (existing.isNotEmpty) return;
    await prefs.setString(userKey, jsonEncode(guest));
  }

  /// 启动早期（LocalStorage 尚未初始化）按当前归属账号读取偏好
  static dynamic peekAccountSetting(SharedPreferences prefs, String key) {
    final uid = prefs.getString(_kSyncUserId) ?? '';
    final map = _decodeSettings(
      prefs.getString('$_kSettingsPrefix${_ownerSuffix(uid)}'),
    );
    return map[key]?['v'];
  }

  // ---------- 积分流水（账号级，离线累计、联网补传） ----------

  static const String _kPointsLegacyKey = 'points_state';
  static const String _kPointsMigrated = 'points_bucket_migrated_v1';

  String get _pointsStoreKey => 'points_state_${_ownerSuffix(_owner)}';

  String get _pointsPendingKey => 'points_pending_${_ownerSuffix(_owner)}';

  /// 当前归属的积分快照（balance / todayEarned / dayKey / history）
  Map<String, dynamic>? loadPointsSnapshot() {
    final raw = prefs.getString(_pointsStoreKey);
    if (raw == null || raw.isEmpty) return null;
    return _decodeJsonMap(raw);
  }

  Future<void> savePointsSnapshot(Map<String, dynamic> snapshot) =>
      prefs.setString(_pointsStoreKey, jsonEncode(snapshot));

  /// 待上行的积分流水（eventId 去重，服务端也按同一 id 去重）
  List<Map<String, dynamic>> loadPendingPointEvents() =>
      _decodePendingList(prefs.getString(_pointsPendingKey));

  Future<void> addPendingPointEvent(Map<String, dynamic> event) async {
    final id = event['eventId']?.toString();
    if (id == null || id.isEmpty) return;
    final all = loadPendingPointEvents();
    if (all.any((e) => e['eventId']?.toString() == id)) return;
    all.add(event);
    await prefs.setString(_pointsPendingKey, jsonEncode(all));
  }

  Future<void> removePendingPointEvents(Iterable<String> eventIds) async {
    final removeIds = eventIds.toSet();
    if (removeIds.isEmpty) return;
    final all = loadPendingPointEvents()
        .where((e) => !removeIds.contains(e['eventId']?.toString()))
        .toList();
    if (all.isEmpty) {
      await prefs.remove(_pointsPendingKey);
    } else {
      await prefs.setString(_pointsPendingKey, jsonEncode(all));
    }
  }

  /// 应用服务端下发的余额与流水（服务端为准），保留本机今日累计用于上限判定
  Future<void> applyPointsSummary(
    int balance,
    List<Map<String, dynamic>> history,
  ) async {
    final snapshot = loadPointsSnapshot() ?? <String, dynamic>{};
    snapshot['balance'] = balance;
    snapshot['history'] = history;
    await savePointsSnapshot(snapshot);
  }

  /// 登录后把游客积分并入账号桶（余额、流水、待上行流水一起迁移）
  Future<void> adoptGuestPoints(String userId) async {
    if (userId.isEmpty) return;
    const guestSuffix = 'guest';
    final guestRaw = prefs.getString('points_state_$guestSuffix');
    final guestPendingRaw = prefs.getString('points_pending_$guestSuffix');
    final hasGuestPoints = guestRaw != null && guestRaw.isNotEmpty;
    final hasGuestPending =
        guestPendingRaw != null && guestPendingRaw.isNotEmpty;
    if (!hasGuestPoints && !hasGuestPending) return;

    final userKey = 'points_state_$userId';
    final userPendingKey = 'points_pending_$userId';
    final user = _decodeJsonMap(prefs.getString(userKey)) ?? {};
    final guest = _decodeJsonMap(guestRaw) ?? {};

    user['balance'] =
        ((user['balance'] as num?)?.toInt() ?? 0) +
        ((guest['balance'] as num?)?.toInt() ?? 0);
    user['todayEarned'] =
        ((user['todayEarned'] as num?)?.toInt() ?? 0) +
        ((guest['todayEarned'] as num?)?.toInt() ?? 0);
    user['dayKey'] = user['dayKey'] ?? guest['dayKey'];
    final history = <Map<String, dynamic>>[
      ...((user['history'] as List?) ?? const []).whereType<Map>().map(
        (e) => Map<String, dynamic>.from(e),
      ),
      ...((guest['history'] as List?) ?? const []).whereType<Map>().map(
        (e) => Map<String, dynamic>.from(e),
      ),
    ];
    user['history'] = history.take(60).toList();
    await prefs.setString(userKey, jsonEncode(user));

    final pending = _decodePendingList(prefs.getString(userPendingKey));
    final guestPending = _decodePendingList(guestPendingRaw);
    for (final event in guestPending) {
      final id = event['eventId']?.toString();
      if (id == null || id.isEmpty) continue;
      if (pending.any((e) => e['eventId']?.toString() == id)) continue;
      pending.add(event);
    }
    if (pending.isNotEmpty) {
      await prefs.setString(userPendingKey, jsonEncode(pending));
    }

    await prefs.remove('points_state_$guestSuffix');
    await prefs.remove('points_pending_$guestSuffix');
  }

  // ---------- 欢迎页已看标记（首次启动控制） ----------

  bool hasSeenWelcome() => prefs.getBool(_kWelcomeSeenKey) ?? false;

  Future<void> markWelcomeSeen() async {
    await prefs.setBool(_kWelcomeSeenKey, true);
  }

  // ---------- 每日动物选择 ----------

  String? loadDailyAnimalId(DateTime day) {
    return prefs.getString(_kDailyAnimalKey + _dayKey(day));
  }

  Future<void> saveDailyAnimalId(DateTime day, String animalId) async {
    await prefs.setString(_kDailyAnimalKey + _dayKey(day), animalId);
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
    final s = prefs.getString(_kLastResetDayKey);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> saveLastResetDay(DateTime day) async {
    await prefs.setString(_kLastResetDayKey, day.toIso8601String());
  }

  // ---------- DrinkEntry（双路：sqflite + prefs 降级）----------

  /// 当前记录归属：登录账号 ID；空串表示游客（未登录）。
  /// 退出登录后 owner 变回空串，账号数据自然从界面上消失。
  String get _owner => syncUserId ?? '';

  /// prefs 降级存储：按归属分桶，切换账号互不影响
  String get _entriesStoreKey =>
      '$_kEntriesPrefix${_owner.isEmpty ? 'guest' : _owner}';

  Future<void> insertDrinkEntry(DrinkEntry entry) async {
    if (_hasDb) {
      await _db!.insert(
        'drink_entries',
        entry.toMap()..['owner_user_id'] = _owner,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await _prefsInsertEntry(entry);
  }

  Future<void> softDeleteEntry(String clientId) async {
    if (_hasDb) {
      await _db!.update(
        'drink_entries',
        {
          'deleted': 1,
          'synced': 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'client_id = ? AND owner_user_id = ?',
        whereArgs: [clientId, _owner],
      );
    }
    await _prefsMarkDeleted(clientId);
  }

  /// 查询某逻辑日的记录（[day] 为逻辑日 key：时间部分为零点；
  /// 有效区间 = [day + 重置时刻, day+1 + 重置时刻)）
  Future<List<DrinkEntry>> loadEntriesForDay(DateTime day) async {
    if (_hasDb) {
      final start = LogicalDay.startOf(day);
      final end = LogicalDay.endOf(day);
      final rows = await _db!.query(
        'drink_entries',
        where:
            'drank_at >= ? AND drank_at < ? AND deleted = 0'
            ' AND owner_user_id = ?',
        whereArgs: [start.toIso8601String(), end.toIso8601String(), _owner],
        orderBy: 'drank_at DESC',
      );
      return rows.map(DrinkEntry.fromMap).toList();
    }
    final all = await _prefsLoadAllEntries();
    return all
        .where((e) => !e.deleted && LogicalDay.sameDay(e.drankAt, day))
        .toList()
      ..sort((a, b) => b.drankAt.compareTo(a.drankAt));
  }

  Future<List<DrinkEntry>> loadEntriesForRange(
    DateTime start,
    DateTime end,
  ) async {
    if (_hasDb) {
      final rows = await _db!.query(
        'drink_entries',
        where:
            'drank_at >= ? AND drank_at < ? AND deleted = 0'
            ' AND owner_user_id = ?',
        whereArgs: [start.toIso8601String(), end.toIso8601String(), _owner],
        orderBy: 'drank_at ASC',
      );
      return rows.map(DrinkEntry.fromMap).toList();
    }
    final all = await _prefsLoadAllEntries();
    return all
        .where(
          (e) =>
              !e.deleted && e.drankAt.isAfter(start) && e.drankAt.isBefore(end),
        )
        .toList()
      ..sort((a, b) => a.drankAt.compareTo(b.drankAt));
  }

  Future<List<DrinkEntry>> loadUnsyncedEntries() async {
    if (_hasDb) {
      final rows = await _db!.query(
        'drink_entries',
        where: "synced = 0 AND deleted = 0 AND owner_user_id = ?",
        whereArgs: [_owner],
        orderBy: 'drank_at ASC',
      );
      return rows.map(DrinkEntry.fromMap).toList();
    }
    final all = await _prefsLoadAllEntries();
    return all.where((e) => !e.synced && !e.deleted).toList();
  }

  Future<void> markSynced(String clientId, {String? serverId}) async {
    if (_hasDb) {
      await _db!.update(
        'drink_entries',
        {'synced': 1, 'server_id': serverId},
        where: 'client_id = ? AND owner_user_id = ?',
        whereArgs: [clientId, _owner],
      );
    }
    final all = await _prefsLoadAllEntries();
    final idx = all.indexWhere((e) => e.clientId == clientId);
    if (idx >= 0) {
      all[idx] = all[idx].copyWith(synced: true, serverId: serverId);
      await prefs.setString(
        _entriesStoreKey,
        jsonEncode(all.map((e) => e.toMap()).toList()),
      );
    }
  }

  // ---------- 健康同步（Apple Health / Health Connect） ----------

  static const String _kHealthEnabled = 'health_sync_enabled';
  static const String _kHealthLastSync = 'health_sync_last_at';

  bool get healthSyncEnabled => prefs.getBool(_kHealthEnabled) ?? false;

  Future<void> setHealthSyncEnabled(bool on) async {
    await prefs.setBool(_kHealthEnabled, on);
  }

  DateTime? get healthLastSyncAt {
    final s = prefs.getString(_kHealthLastSync);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> setHealthLastSyncAt(DateTime at) async {
    await prefs.setString(_kHealthLastSync, at.toIso8601String());
  }

  // ---------- 账号与云备份 ----------

  static const String _kAccountAnonId = 'account_anon_id';
  static const String _kAccountNickname = 'account_nickname';
  static const String _kAccountLastBackup = 'account_last_backup_at';
  static const String _kAccountAvatar = 'account_avatar_path';
  static const String _kLastUserId = 'last_account_user_id';
  static const String _kAutoSync = 'cloud_auto_sync';

  /// 头像按账号存放：切换账号不会看到上一个账号的头像；
  /// 未登录时读游客 key（实际不会设置，界面显示「未登录」图标）。
  String get _avatarKey {
    final uid = syncUserId;
    return (uid == null || uid.isEmpty)
        ? _kAccountAvatar
        : '${_kAccountAvatar}_$uid';
  }

  /// 本机自定义头像路径（相册 / 拍照保存到应用目录后的绝对路径）。
  /// 未设置时返回 null，由界面回退到默认头像；
  /// 后续接入 QQ / 微信登录时，第三方头像也可以先落盘再写入这里。
  String? get accountAvatarPath {
    final v = prefs.getString(_avatarKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setAccountAvatarPath(String? path) async {
    final key = _avatarKey;
    if (path == null || path.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, path);
    }
  }

  static const String _kAccountAvatarRemote = 'account_avatar_remote_url';
  static const String _kPushedProfile = 'account_pushed_profile';
  static const String _kGuestProfile = 'guest_profile_snapshot';
  static const String _kRejectedOrderNotice = 'account_rejected_order_notice';

  String get _accountUid {
    final uid = syncUserId;
    return (uid == null || uid.isEmpty) ? 'guest' : uid;
  }

  /// 服务端头像地址（/static/avatars/...），用于判断本机是否需要重新下载
  String? get accountAvatarRemoteUrl {
    final v = prefs.getString('${_kAccountAvatarRemote}_$_accountUid');
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setAccountAvatarRemoteUrl(String? url) async {
    final key = '${_kAccountAvatarRemote}_$_accountUid';
    if (url == null || url.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, url);
    }
  }

  /// 上次与服务端对齐的档案签名（性别/体重/身高/年龄/活动量/目标），
  /// 避免每轮同步重复 PATCH；为空表示该账号尚未与服务端对齐
  String? get lastPushedProfileSignature {
    final v = prefs.getString('${_kPushedProfile}_$_accountUid');
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setLastPushedProfileSignature(String signature) async {
    await prefs.setString('${_kPushedProfile}_$_accountUid', signature);
  }

  Future<void> clearLastPushedProfileSignature() async {
    await prefs.remove('${_kPushedProfile}_$_accountUid');
  }

  /// 登录前游客档案快照：退出账号后恢复，避免账号资料留在游客视图里
  UserProfile? get guestProfileSnapshot {
    final raw = prefs.getString(_kGuestProfile);
    return raw == null ? null : UserProfile.fromMap(_decodeMap(raw));
  }

  Future<void> saveGuestProfileSnapshot(UserProfile profile) async {
    await prefs.setString(_kGuestProfile, _encodeMap(profile.toMap()));
  }

  Future<void> clearGuestProfileSnapshot() async {
    await prefs.remove(_kGuestProfile);
  }

  /// 已经弹过「申请未通过」提示的订单 ID，避免重复打扰
  String? get lastRejectedNoticeOrderId {
    final v = prefs.getString('${_kRejectedOrderNotice}_$_accountUid');
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setLastRejectedNoticeOrderId(String orderId) async {
    await prefs.setString('${_kRejectedOrderNotice}_$_accountUid', orderId);
  }

  /// 无感同步开关：开启后在数据变动 / 冷启动 / 回前台时自动同步
  bool get autoSyncEnabled => prefs.getBool(_kAutoSync) ?? true;

  Future<void> setAutoSyncEnabled(bool on) async {
    await prefs.setBool(_kAutoSync, on);
  }

  /// 本机匿名标识：首次读取时生成并复用。
  /// 仅用于服务端识别设备，卸载后随之丢失（匿名身份不保证跨重装恢复）。
  String get accountAnonId {
    final existing = prefs.getString(_kAccountAnonId);
    if (existing != null && existing.isNotEmpty) return existing;
    final rnd = math.Random();
    const chars = '0123456789abcdef';
    final id = List.generate(32, (_) => chars[rnd.nextInt(16)]).join();
    prefs.setString(_kAccountAnonId, id);
    return id;
  }

  /// 本机昵称：未登录时也允许修改，登录后由服务端同步
  String get accountNickname {
    final n = prefs.getString(_kAccountNickname);
    return (n == null || n.trim().isEmpty) ? '喝水羊驼' : n;
  }

  Future<void> setAccountNickname(String name) async {
    await prefs.setString(_kAccountNickname, name.trim());
  }

  static const String _kNicknameDirty = 'account_nickname_dirty';
  static const String _kGuestNickname = 'guest_nickname_snapshot';

  /// 本机改过昵称但还没上行成功：同步时以本地为准推送，避免被云端覆盖
  bool get nicknameDirty => prefs.getBool(_kNicknameDirty) ?? false;

  Future<void> markNicknameDirty() async {
    await prefs.setBool(_kNicknameDirty, true);
  }

  Future<void> clearNicknameDirty() async {
    await prefs.remove(_kNicknameDirty);
  }

  /// 登录前快照游客昵称，退出账号后恢复
  Future<void> saveGuestNicknameSnapshot() async {
    await prefs.setString(_kGuestNickname, accountNickname);
  }

  Future<void> restoreGuestNickname() async {
    final snapshot = prefs.getString(_kGuestNickname);
    if (snapshot == null || snapshot.isEmpty) {
      await prefs.remove(_kAccountNickname);
    } else {
      await prefs.setString(_kAccountNickname, snapshot);
    }
    await prefs.remove(_kGuestNickname);
  }

  DateTime? get accountLastBackupAt {
    final s = prefs.getString(_kAccountLastBackup);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> setAccountLastBackupAt(DateTime at) async {
    await prefs.setString(_kAccountLastBackup, at.toIso8601String());
  }

  /// 待导出到健康 App 的记录（本地新增但还没写出去）
  Future<List<DrinkEntry>> loadHealthPendingEntries({
    DateTime? since,
    int limit = 500,
  }) async {
    final sinceIso = since?.toIso8601String();
    if (_hasDb) {
      final rows = await _db!.query(
        'drink_entries',
        where:
            'health_state = 0 AND deleted = 0 AND owner_user_id = ?'
            '${sinceIso == null ? '' : ' AND drank_at >= ?'}',
        whereArgs: sinceIso == null ? [_owner] : [_owner, sinceIso],
        orderBy: 'drank_at ASC',
        limit: limit,
      );
      return rows.map(DrinkEntry.fromMap).toList();
    }
    final all = await _prefsLoadAllEntries();
    return all
        .where(
          (e) =>
              !e.deleted &&
              e.healthState == DrinkEntry.healthNone &&
              (since == null || !e.drankAt.isBefore(since)),
        )
        .take(limit)
        .toList();
  }

  /// 已导出、后来被删除的记录（需要从健康 App 撤掉）
  Future<List<DrinkEntry>> loadHealthDeletedEntries({int limit = 200}) async {
    if (_hasDb) {
      final rows = await _db!.query(
        'drink_entries',
        where: 'health_state = 1 AND deleted = 1 AND owner_user_id = ?',
        whereArgs: [_owner],
        orderBy: 'drank_at ASC',
        limit: limit,
      );
      return rows.map(DrinkEntry.fromMap).toList();
    }
    final all = await _prefsLoadAllEntries();
    return all
        .where((e) => e.deleted && e.healthState == DrinkEntry.healthExported)
        .take(limit)
        .toList();
  }

  /// 该健康样本是否已导入过（按样本 UUID 去重）
  Future<bool> hasHealthSampleId(String sampleId) async {
    if (_hasDb) {
      final rows = await _db!.query(
        'drink_entries',
        columns: ['client_id'],
        where: 'health_sample_id = ? AND owner_user_id = ?',
        whereArgs: [sampleId, _owner],
        limit: 1,
      );
      return rows.isNotEmpty;
    }
    final all = await _prefsLoadAllEntries();
    return all.any((e) => e.healthSampleId == sampleId);
  }

  /// 更新健康同步状态（导出成功后落库；从健康 App 删除成功后清零）
  Future<void> setHealthState(
    String clientId,
    int state, {
    String? sampleId,
  }) async {
    if (_hasDb) {
      await _db!.update(
        'drink_entries',
        {
          'health_state': state,
          if (sampleId != null) 'health_sample_id': sampleId,
        },
        where: 'client_id = ? AND owner_user_id = ?',
        whereArgs: [clientId, _owner],
      );
    }
    final all = await _prefsLoadAllEntries();
    final idx = all.indexWhere((e) => e.clientId == clientId);
    if (idx >= 0) {
      all[idx] = all[idx].copyWith(
        healthState: state,
        healthSampleId: sampleId,
      );
      await prefs.setString(
        _entriesStoreKey,
        jsonEncode(all.map((e) => e.toMap()).toList()),
      );
    }
  }

  // ---------- 云同步（登录账号 + 增量同步） ----------

  static const String _kSyncUserId = 'sync_user_id';
  static const String _kSyncToken = 'sync_token';
  /// 增量拉取游标按归属分键：切账号不会拿上一个账号的进度跳过云端历史
  static const String _kSyncCursorPrefix = 'sync_cursor_';
  static const String _kSyncCursorLegacy = 'sync_cursor';
  static const String _kSyncLastAt = 'sync_last_at';
  /// 最近一次同步失败原因（成功后清除），用于在「数据同步」卡片上
  /// 暴露静默失败——否则用户只看到「待同步 N 条」却不知道为何不动
  static const String _kSyncLastError = 'sync_last_error';
  static const String _kAccountEmail = 'account_email';

  String get _cursorKey => '$_kSyncCursorPrefix${_ownerSuffix(_owner)}';

  String? get syncUserId => prefs.getString(_kSyncUserId);

  String? get syncToken => prefs.getString(_kSyncToken);

  /// 已登录账号的邮箱；为空表示本地模式（不同步）
  String? get accountEmail {
    final v = prefs.getString(_kAccountEmail);
    return (v == null || v.isEmpty) ? null : v;
  }

  int get syncCursor => prefs.getInt(_cursorKey) ?? 0;

  DateTime? get syncLastSyncAt {
    final s = prefs.getString(_kSyncLastAt);
    return s == null ? null : DateTime.tryParse(s);
  }

  String? get syncLastError {
    final s = prefs.getString(_kSyncLastError);
    return (s == null || s.isEmpty) ? null : s;
  }

  bool get hasSyncSession =>
      (syncUserId ?? '').isNotEmpty && (syncToken ?? '').isNotEmpty;

  /// 已登录正式账号：以「有 userId + token」为准，
  /// 邮箱只是某一种登录方式，解绑后不应把用户踢下线
  bool get hasAccountSession => hasSyncSession;

  Future<void> setSyncSession(
    String userId,
    String token, {
    String? email,
  }) async {
    await prefs.setString(_kSyncUserId, userId);
    await prefs.setString(_kSyncToken, token);
    if (email != null) await prefs.setString(_kAccountEmail, email);
  }

  /// 退出登录：清掉账号与令牌。记录本身保留在本地，但带有所属账号，
  /// 退出后不再属于当前（游客）视图，因此不会显示；重新登录该账号会恢复。
  Future<void> clearSyncSession() async {
    final last = syncUserId;
    if (last != null && last.isNotEmpty) {
      await prefs.setString(_kLastUserId, last);
    }
    await prefs.remove(_kSyncUserId);
    await prefs.remove(_kSyncToken);
    await prefs.remove(_kAccountEmail);
    // 游标不随会话清除：重新登录同一账号时继续增量拉取
  }

  Future<void> setSyncCursor(int cursor) async {
    await prefs.setInt(_cursorKey, cursor);
  }

  /// 重新读取磁盘偏好：小组件后台录入在独立 isolate（Android 上还有纯
  /// 原生侧）写库/写偏好，主进程内存中的 prefs 缓存会滞后；回前台时
  /// 先 reload 再查数据，避免读到旧值
  Future<void> reloadPrefs() async {
    try {
      await prefs.reload();
    } catch (_) {
      // 读取失败沿用当前缓存
    }
  }

  /// 解绑邮箱后清掉本机记录的邮箱展示，会话仍保留
  Future<void> clearAccountEmail() async {
    await prefs.remove(_kAccountEmail);
  }

  Future<void> setSyncLastSyncAt(DateTime at) async {
    await prefs.setString(_kSyncLastAt, at.toIso8601String());
  }

  /// 记录/清除最近一次同步失败原因（null 或空串表示清除）
  Future<void> setSyncLastError(String? message) async {
    if (message == null || message.isEmpty) {
      await prefs.remove(_kSyncLastError);
    } else {
      await prefs.setString(_kSyncLastError, message);
    }
  }

  /// 尚未上行到服务端的记录（含待同步的删除墓碑）
  Future<List<DrinkEntry>> loadPendingSyncEntries({int limit = 200}) async {
    if (_hasDb) {
      final rows = await _db!.query(
        'drink_entries',
        where: 'synced = 0 AND owner_user_id = ?',
        whereArgs: [_owner],
        orderBy: 'drank_at ASC',
        limit: limit,
      );
      return rows.map(DrinkEntry.fromMap).toList();
    }
    final all = await _prefsLoadAllEntries();
    return all.where((e) => !e.synced).take(limit).toList();
  }

  Future<int> countPendingSyncEntries() async {
    if (_hasDb) {
      final rows = await _db!.rawQuery(
        'SELECT COUNT(*) AS c FROM drink_entries'
        ' WHERE synced = 0 AND owner_user_id = ?',
        [_owner],
      );
      return (rows.first['c'] as int?) ?? 0;
    }
    final all = await _prefsLoadAllEntries();
    return all.where((e) => !e.synced).length;
  }

  /// 本机游客桶里仍未删除的记录条数：登录成功后据此询问「是否并入账号」
  Future<int> countGuestEntries() async {
    if (_hasDb) {
      final rows = await _db!.rawQuery(
        "SELECT COUNT(*) AS c FROM drink_entries"
        " WHERE deleted = 0 AND owner_user_id = ''",
      );
      return (rows.first['c'] as int?) ?? 0;
    }
    // prefs 降级：游客桶 + 旧版单桶，按 clientId 去重后计数
    final ids = <String>{};
    for (final key in ['${_kEntriesPrefix}guest', '$_kEntriesPrefix$_storeKey']) {
      for (final e in await _prefsLoadAllEntriesFromKey(key)) {
        if (!e.deleted) ids.add(e.clientId);
      }
    }
    return ids.length;
  }

  /// 登录后把未登录期间产生的记录归属到该账号（本地数据与账号绑定）
  Future<void> bindGuestEntriesToAccount(String userId) async {
    if (userId.isEmpty) return;
    if (_hasDb) {
      // OR REPLACE：若该 client_id 已属于这个账号（之前推过），保留游客侧
      // 这份更新的本地状态，避免复合主键冲突导致归属迁移失败
      await _db!.rawUpdate(
        "UPDATE OR REPLACE drink_entries SET owner_user_id = ?"
        " WHERE owner_user_id = ''",
        [userId],
      );
    }
    // prefs 降级：游客桶与旧版单桶数据合并进该账号桶
    final guestRaw =
        prefs.getString('${_kEntriesPrefix}guest') ??
        prefs.getString('$_kEntriesPrefix$_storeKey');
    if (guestRaw == null || guestRaw.isEmpty) return;
    final userKey = '$_kEntriesPrefix$userId';
    final merged = <String, DrinkEntry>{};
    for (final e in await _prefsLoadAllEntriesFromKey(userKey)) {
      merged[e.clientId] = e;
    }
    for (final e in await _prefsLoadAllEntriesFromKey(
      '${_kEntriesPrefix}guest',
    )) {
      merged.putIfAbsent(e.clientId, () => e);
    }
    for (final e in await _prefsLoadAllEntriesFromKey(
      '$_kEntriesPrefix$_storeKey',
    )) {
      merged.putIfAbsent(e.clientId, () => e);
    }
    await prefs.setString(
      userKey,
      jsonEncode(merged.values.map((e) => e.toMap()).toList()),
    );
    await prefs.remove('${_kEntriesPrefix}guest');
    await prefs.remove('$_kEntriesPrefix$_storeKey');
  }

  Future<void> markEntriesSynced(List<String> clientIds) async {
    if (clientIds.isEmpty) return;
    if (_hasDb) {
      final batch = _db!.batch();
      for (final id in clientIds) {
        batch.update(
          'drink_entries',
          {'synced': 1},
          where: 'client_id = ? AND owner_user_id = ?',
          whereArgs: [id, _owner],
        );
      }
      await batch.commit(noResult: true);
      return;
    }
    final all = await _prefsLoadAllEntries();
    for (var i = 0; i < all.length; i++) {
      if (clientIds.contains(all[i].clientId)) {
        all[i] = all[i].copyWith(synced: true);
      }
    }
    await prefs.setString(
      _entriesStoreKey,
      jsonEncode(all.map((e) => e.toMap()).toList()),
    );
  }

  /// 服务端下发的记录直接落库（视为已同步）
  Future<void> applyRemoteEntry(DrinkEntry entry) async {
    await insertDrinkEntry(entry.copyWith(synced: true));
  }

  // ---------- prefs 降级存储 ----------

  /// 旧版单桶 key（升级前的数据都在这，仅游客读取时兜底）
  static const String _storeKey = 'all';

  Future<List<DrinkEntry>> _prefsLoadAllEntries() async {
    final raw =
        prefs.getString(_entriesStoreKey) ??
        (_owner.isEmpty ? prefs.getString('$_kEntriesPrefix$_storeKey') : null);
    return _decodeEntries(raw);
  }

  Future<List<DrinkEntry>> _prefsLoadAllEntriesFromKey(String key) async =>
      _decodeEntries(prefs.getString(key));

  List<DrinkEntry> _decodeEntries(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => DrinkEntry.fromMap((e as Map).cast())).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _prefsInsertEntry(DrinkEntry entry) async {
    final all = await _prefsLoadAllEntries();
    final idx = all.indexWhere((e) => e.clientId == entry.clientId);
    if (idx >= 0) {
      all[idx] = entry;
    } else {
      all.add(entry);
    }
    await prefs.setString(
      _entriesStoreKey,
      jsonEncode(all.map((e) => e.toMap()).toList()),
    );
  }

  Future<void> _prefsMarkDeleted(String clientId) async {
    final all = await _prefsLoadAllEntries();
    final idx = all.indexWhere((e) => e.clientId == clientId);
    if (idx >= 0) {
      all[idx] = all[idx].copyWith(deleted: true, synced: false);
      await prefs.setString(
        _entriesStoreKey,
        jsonEncode(all.map((e) => e.toMap()).toList()),
      );
    }
  }

  // ---------- 清除数据 ----------

  /// PRD §2.8 清除全部本地数据（设置页入口）
  /// 只清当前归属（游客或当前账号）的饮水记录与偏好，不动登录态，
  /// 也不动其他账号留在本机的数据桶。
  Future<void> clearAllData() async {
    final owner = _owner;
    try {
      if (_hasDb) {
        await _db!.delete(
          'drink_entries',
          where: 'owner_user_id = ?',
          whereArgs: [owner],
        );
      }
    } catch (_) {}

    final keep = <String>{
      _kSyncUserId,
      _kSyncToken,
      _kAccountEmail,
      _kLastUserId,
      _kAccountAnonId,
      _kAutoSync,
      'api_base_url',
    };
    // 其他账号按 owner 前缀分桶的数据：前缀长的优先匹配，
    // 避免 account_settings_ 误删 account_settings_pushed_<uid> 的键
    final ownerPrefixes = <String>[
      _kSettingsPushedPrefix,
      _kSettingsPrefix,
      _kEntriesPrefix,
      _kSyncCursorPrefix,
      'points_state_',
      'points_pending_',
      '${_kAccountAvatar}_',
      '${_kAccountAvatarRemote}_',
      '${_kPushedProfile}_',
      '${_kRejectedOrderNotice}_',
    ]..sort((a, b) => b.length.compareTo(a.length));

    final currentSuffix = _ownerSuffix(owner);

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
    await setSyncCursor(0);
    await prefs.setBool(_kSettingsMigrated, true);
    await prefs.setBool(_kPointsMigrated, true);
  }

  /// 清除某个账号留在本机的全部数据（注销账号时调用）。
  /// 只删该账号的桶与记录，不影响游客与其他账号。
  Future<void> purgeAccountData(String userId) async {
    if (userId.isEmpty) return;
    try {
      if (_hasDb) {
        await _db!.delete(
          'drink_entries',
          where: 'owner_user_id = ?',
          whereArgs: [userId],
        );
      }
    } catch (_) {}
    final keys = <String>[
      '$_kSettingsPrefix$userId',
      '$_kSettingsPushedPrefix$userId',
      'points_state_$userId',
      'points_pending_$userId',
      '${_kAccountAvatar}_$userId',
      '${_kAccountAvatarRemote}_$userId',
      '${_kPushedProfile}_$userId',
      '${_kRejectedOrderNotice}_$userId',
      '$_kSyncCursorPrefix$userId',
      '$_kEntriesPrefix$userId',
    ];
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// 定期清理超过 [days] 天的已同步墓碑，避免本地库无限增长
  Future<void> purgeOldTombstones({int days = 90}) async {
    if (!_hasDb) return;
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);
    try {
      await _db!.delete(
        'drink_entries',
        where: 'deleted = 1 AND synced = 1 AND substr(updated_at, 1, 10) < ?',
        whereArgs: [cutoff],
      );
    } catch (_) {}
  }

  /// 老版本只有一个全局游标 `sync_cursor`：迁到当前归属桶，之后各账号各记各的
  static Future<void> _migrateLegacyCursor(SharedPreferences prefs) async {
    final legacy = prefs.getInt(_kSyncCursorLegacy);
    if (legacy == null) return;
    final uid = prefs.getString(_kSyncUserId) ?? '';
    final key = '$_kSyncCursorPrefix${_ownerSuffix(uid)}';
    if (prefs.getInt(key) == null) await prefs.setInt(key, legacy);
    await prefs.remove(_kSyncCursorLegacy);
  }

  /// 老版本积分只有本机一个 `points_state`：迁入当前归属桶，并把余额转成
  /// 一条 seed 流水，联网后补传到服务端（服务端按 eventId 去重，不会重复计分）
  static Future<void> _migrateLegacyPoints(SharedPreferences prefs) async {
    if (prefs.getBool(_kPointsMigrated) == true) return;
    final uid = prefs.getString(_kSyncUserId) ?? '';
    final owner = _ownerSuffix(uid);
    final legacy = prefs.getString(_kPointsLegacyKey);
    final bucketKey = 'points_state_$owner';
    if (legacy != null &&
        legacy.isNotEmpty &&
        prefs.getString(bucketKey) == null) {
      await prefs.setString(bucketKey, legacy);
      final balance =
          (_decodeJsonMap(legacy)?['balance'] as num?)?.toInt() ?? 0;
      if (balance > 0) {
        final pendingKey = 'points_pending_$owner';
        final pending = _decodePendingList(prefs.getString(pendingKey));
        final eventId = 'migrate:v1:$owner';
        if (!pending.any((e) => e['eventId']?.toString() == eventId)) {
          pending.add({
            'eventId': eventId,
            'source': 'migrate',
            'amount': balance,
            'occurredAt': _nowIso(),
          });
          await prefs.setString(pendingKey, jsonEncode(pending));
        }
      }
    }
    await prefs.remove(_kPointsLegacyKey);
    await prefs.setBool(_kPointsMigrated, true);
  }

  // ---------- 内部工具 ----------

  static String _ownerSuffix(String owner) => owner.isEmpty ? 'guest' : owner;

  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  /// [a] 是否比 [b] 更新时间更晚（ISO 时间串，解析失败时退化为字符串比较）
  static bool _isNewer(String a, String b) {
    final ta = DateTime.tryParse(a);
    final tb = DateTime.tryParse(b);
    if (ta != null && tb != null) return ta.isAfter(tb);
    return a.compareTo(b) > 0;
  }

  /// 偏好桶解码：容错老数据（直接存的裸值）
  static Map<String, Map<String, dynamic>> _decodeSettings(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, Map<String, dynamic>>{};
      decoded.forEach((k, v) {
        out[k.toString()] = v is Map
            ? Map<String, dynamic>.from(v)
            : {'v': v, 'at': ''};
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static Map<String, String> _decodeStringMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  static Map<String, dynamic>? _decodeJsonMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>> _decodePendingList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 老版本偏好是 jsonEncode 字符串：能解析就还原成原始类型
  static dynamic _decodeSettingValue(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  static String _dayKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  /// 简易 map 编码（不依赖 dart:convert 暴露的复杂结构）
  static String _encodeMap(Map<String, dynamic> m) {
    return m.entries
        .map((e) {
          final v = e.value;
          final s = v == null ? '' : v.toString();
          // 转义分号与等号
          final ev = s.replaceAll(';', '\\;').replaceAll('=', '\\=');
          return '${e.key}=$ev';
        })
        .join(';');
  }

  static Map<String, dynamic> _decodeMap(String s) {
    if (s.isEmpty) return {};
    final out = <String, dynamic>{};
    // 先按未转义的分号拆分
    final parts = _splitUnescaped(s, ';');
    for (final part in parts) {
      final kv = _splitUnescaped(part, '=');
      if (kv.length == 2) {
        final k = kv[0];
        var v = kv[1].replaceAll('\\;', ';').replaceAll('\\=', '=');
        if (v == 'null' || v.isEmpty) v = '';
        out[k] = v;
      }
    }
    return out;
  }

  static List<String> _splitUnescaped(String s, String sep) {
    final out = <String>[];
    var buf = StringBuffer();
    var i = 0;
    while (i < s.length) {
      if (s[i] == '\\') {
        buf.write(s[i]);
        i++;
        if (i < s.length) buf.write(s[i]);
      } else if (s.substring(i).startsWith(sep)) {
        out.add(buf.toString());
        buf = StringBuffer();
        i += sep.length;
        continue;
      } else {
        buf.write(s[i]);
      }
      i++;
    }
    out.add(buf.toString());
    return out;
  }
}
