import 'dart:async';
import 'dart:convert';

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
  static const int _dbVersion = 2;

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
        calories INTEGER NOT NULL DEFAULT -1
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_drink_at ON drink_entries(drank_at)',
    );
    await db.execute(
      'CREATE INDEX idx_synced ON drink_entries(synced, deleted)',
    );
  }

  /// v1 → v2：补上录入时快照的热量列（旧记录默认 -1 = 未记录）
  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE drink_entries ADD COLUMN calories INTEGER NOT NULL DEFAULT -1',
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

  Future<void> insertDrinkEntry(DrinkEntry entry) async {
    if (_hasDb) {
      await _db!.insert(
        'drink_entries',
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await _prefsInsertEntry(entry);
  }

  Future<void> softDeleteEntry(String clientId) async {
    if (_hasDb) {
      await _db!.update(
        'drink_entries',
        {'deleted': 1, 'synced': 0},
        where: 'client_id = ?',
        whereArgs: [clientId],
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
        where: 'drank_at >= ? AND drank_at < ? AND deleted = 0',
        whereArgs: [start.toIso8601String(), end.toIso8601String()],
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
        where: 'drank_at >= ? AND drank_at < ? AND deleted = 0',
        whereArgs: [start.toIso8601String(), end.toIso8601String()],
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
        where: 'synced = 0 AND deleted = 0',
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
        where: 'client_id = ?',
        whereArgs: [clientId],
      );
    }
    final all = await _prefsLoadAllEntries();
    final idx = all.indexWhere((e) => e.clientId == clientId);
    if (idx >= 0) {
      all[idx] = all[idx].copyWith(synced: true, serverId: serverId);
      await prefs.setString('$_kEntriesPrefix$_storeKey', jsonEncode(all.map((e) => e.toMap()).toList()));
    }
  }

  // ---------- prefs 降级存储 ----------

  static const String _storeKey = 'all';

  Future<List<DrinkEntry>> _prefsLoadAllEntries() async {
    final raw = prefs.getString('$_kEntriesPrefix$_storeKey');
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
    await prefs.setString('$_kEntriesPrefix$_storeKey',
        jsonEncode(all.map((e) => e.toMap()).toList()));
  }

  Future<void> _prefsMarkDeleted(String clientId) async {
    final all = await _prefsLoadAllEntries();
    final idx = all.indexWhere((e) => e.clientId == clientId);
    if (idx >= 0) {
      all[idx] = all[idx].copyWith(deleted: true, synced: false);
      await prefs.setString('$_kEntriesPrefix$_storeKey',
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
