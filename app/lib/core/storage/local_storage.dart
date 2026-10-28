import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../shared/models/animal_character.dart';
import '../../shared/models/drink_entry.dart';
import '../../shared/models/user_profile.dart';
import '../time/logical_day.dart';

/// PRD §4.2 断网可写、联网同步
/// PRD §4.4 用户数据加密存储（V1.0 仅本地，加密留 V2.0）
///
/// 封装：SharedPreferences（轻配置）+ SQLite（结构化数据）
/// 桌面 / Web 端 sqflite 不可用时降级为 shared_preferences-only
class LocalStorage {
  LocalStorage._({
    required this.prefs,
    Database? db,
  }) : _db = db;

  static const String _dbName = 'water_llama.db';
  static const int _dbVersion = 5;

  late final SharedPreferences prefs;
  final Database? _db;

  bool get _hasDb => _db != null;

  static const String _kProfileKey = 'user_profile';
  static const String _kDailyAnimalKey = 'daily_animal_id_';
  static const String _kLastResetDayKey = 'last_reset_day';
  static const String _kEntriesPrefix = 'entries_';
  static const String _kPreferredUnitKey = 'preferred_unit';
  static const String _kWelcomeSeenKey = 'welcome_seen';

  static Future<LocalStorage> init() async {
    final prefs = await SharedPreferences.getInstance();
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
      return LocalStorage._(prefs: prefs, db: db);
    } catch (e) {
      // ignore: avoid_print
      print('[LocalStorage] SQLite unavailable, falling back to prefs-only: $e');
      return LocalStorage._(prefs: prefs);
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE drink_entries (
        client_id TEXT PRIMARY KEY,
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
        updated_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_drink_at ON drink_entries(drank_at)',
    );
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
    final uid = prefs.getString(_kSyncUserId) ??
        prefs.getString(_kLastUserId);
    try {
      if (uid != null && uid.isNotEmpty) {
        await db.update(
          'drink_entries',
          {'owner_user_id': uid},
          where: "owner_user_id = ''",
        );
      }
    } catch (_) {}
    await prefs.setBool(flag, true);
  }

  /// v1 → v2：补上录入时快照的热量列（旧记录默认 -1 = 未记录）
  /// v2 → v3：健康同步状态（0 未同步 / 1 已导出 / 2 已导入）
  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
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

  // ---------- 单位偏好（首次启动选择） ----------

  /// 返回 'ml' 或 'oz'，未设置返回 null（首次启动）
  String? loadPreferredUnit() {
    return prefs.getString(_kPreferredUnitKey);
  }

  Future<void> savePreferredUnit(String unit) async {
    await prefs.setString(_kPreferredUnitKey, unit);
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
        where: 'drank_at >= ? AND drank_at < ? AND deleted = 0'
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

  Future<List<DrinkEntry>> loadEntriesForRange(DateTime start, DateTime end) async {
    if (_hasDb) {
      final rows = await _db!.query(
        'drink_entries',
        where: 'drank_at >= ? AND drank_at < ? AND deleted = 0'
            ' AND owner_user_id = ?',
        whereArgs: [start.toIso8601String(), end.toIso8601String(), _owner],
        orderBy: 'drank_at ASC',
      );
      return rows.map(DrinkEntry.fromMap).toList();
    }
    final all = await _prefsLoadAllEntries();
    return all
        .where((e) =>
            !e.deleted &&
            e.drankAt.isAfter(start) &&
            e.drankAt.isBefore(end))
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
      await prefs.setString(_entriesStoreKey, jsonEncode(all.map((e) => e.toMap()).toList()));
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
    return (uid == null || uid.isEmpty) ? _kAccountAvatar : '${_kAccountAvatar}_$uid';
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
        where: 'health_state = 0 AND deleted = 0 AND owner_user_id = ?'
            '${sinceIso == null ? '' : ' AND drank_at >= ?'}',
        whereArgs: sinceIso == null ? [_owner] : [_owner, sinceIso],
        orderBy: 'drank_at ASC',
        limit: limit,
      );
      return rows.map(DrinkEntry.fromMap).toList();
    }
    final all = await _prefsLoadAllEntries();
    return all
        .where((e) =>
            !e.deleted &&
            e.healthState == DrinkEntry.healthNone &&
            (since == null || !e.drankAt.isBefore(since)))
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
      all[idx] =
          all[idx].copyWith(healthState: state, healthSampleId: sampleId);
      await prefs.setString(_entriesStoreKey,
          jsonEncode(all.map((e) => e.toMap()).toList()));
    }
  }

  // ---------- 云同步（登录账号 + 增量同步） ----------

  static const String _kSyncUserId = 'sync_user_id';
  static const String _kSyncToken = 'sync_token';
  static const String _kSyncCursor = 'sync_cursor';
  static const String _kSyncLastAt = 'sync_last_at';
  static const String _kAccountEmail = 'account_email';

  String? get syncUserId => prefs.getString(_kSyncUserId);

  String? get syncToken => prefs.getString(_kSyncToken);

  /// 已登录账号的邮箱；为空表示本地模式（不同步）
  String? get accountEmail {
    final v = prefs.getString(_kAccountEmail);
    return (v == null || v.isEmpty) ? null : v;
  }

  int get syncCursor => prefs.getInt(_kSyncCursor) ?? 0;

  DateTime? get syncLastSyncAt {
    final s = prefs.getString(_kSyncLastAt);
    return s == null ? null : DateTime.tryParse(s);
  }

  bool get hasSyncSession =>
      (syncUserId ?? '').isNotEmpty && (syncToken ?? '').isNotEmpty;

  /// 已登录正式账号（只有登录后才允许云同步）
  bool get hasAccountSession => hasSyncSession && accountEmail != null;

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
    await prefs.remove(_kSyncCursor);
  }

  Future<void> setSyncCursor(int cursor) async {
    await prefs.setInt(_kSyncCursor, cursor);
  }

  Future<void> setSyncLastSyncAt(DateTime at) async {
    await prefs.setString(_kSyncLastAt, at.toIso8601String());
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

  /// 登录后把未登录期间产生的记录归属到该账号（本地数据与账号绑定）
  Future<void> bindGuestEntriesToAccount(String userId) async {
    if (userId.isEmpty) return;
    if (_hasDb) {
      await _db!.update(
        'drink_entries',
        {'owner_user_id': userId},
        where: "owner_user_id = ''",
      );
    }
    // prefs 降级：游客桶与旧版单桶数据合并进该账号桶
    final guestRaw = prefs.getString('${_kEntriesPrefix}guest') ??
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
    await prefs.setString(_entriesStoreKey,
        jsonEncode(all.map((e) => e.toMap()).toList()));
  }

  /// 服务端下发的记录直接落库（视为已同步）
  Future<void> applyRemoteEntry(DrinkEntry entry) async {
    await insertDrinkEntry(entry.copyWith(synced: true));
  }

  // ---------- prefs 降级存储 ----------

  /// 旧版单桶 key（升级前的数据都在这，仅游客读取时兜底）
  static const String _storeKey = 'all';

  Future<List<DrinkEntry>> _prefsLoadAllEntries() async {
    final raw = prefs.getString(_entriesStoreKey) ??
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
    await prefs.setString(_entriesStoreKey,
        jsonEncode(all.map((e) => e.toMap()).toList()));
  }

  Future<void> _prefsMarkDeleted(String clientId) async {
    final all = await _prefsLoadAllEntries();
    final idx = all.indexWhere((e) => e.clientId == clientId);
    if (idx >= 0) {
      all[idx] = all[idx].copyWith(deleted: true, synced: false);
      await prefs.setString(_entriesStoreKey,
          jsonEncode(all.map((e) => e.toMap()).toList()));
    }
  }

  // ---------- 清除数据 ----------

  /// PRD §2.8 清除全部本地数据（设置页入口）
  /// 饮水记录 + 档案 + 提醒/音效/主题等全部偏好
  Future<void> clearAllData() async {
    // DB 删除容错：个别 ROM/旧库可能抛异常，失败也不阻断
    // prefs.clear()（双路存储下 prefs 一清，读取链路仍视为空库）
    try {
      if (_hasDb) {
        await _db!.delete('drink_entries');
      }
    } catch (_) {}
    await prefs.clear();
  }

  // ---------- 内部工具 ----------

  static String _dayKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  /// 简易 map 编码（不依赖 dart:convert 暴露的复杂结构）
  static String _encodeMap(Map<String, dynamic> m) {
    return m.entries.map((e) {
      final v = e.value;
      final s = v == null ? '' : v.toString();
      // 转义分号与等号
      final ev = s.replaceAll(';', '\\;').replaceAll('=', '\\=');
      return '${e.key}=$ev';
    }).join(';');
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
