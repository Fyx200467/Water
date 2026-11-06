import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../settings/account_settings.dart';
import 'dao_keys.dart';
import 'dao_shared.dart';

/// 记录表结构：主键 (owner_user_id, client_id)，不同账号可各自持有同 id 的记录
const String createEntriesTable = '''
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

Future<void> createSchema(Database db, int version) async {
  await db.execute(createEntriesTable);
  await db.execute('CREATE INDEX idx_drink_at ON drink_entries(drank_at)');
  await db.execute(
    'CREATE INDEX idx_synced ON drink_entries(synced, deleted)',
  );
  await db.execute(
    'CREATE INDEX idx_owner_at ON drink_entries(owner_user_id, drank_at)',
  );
}

Future<Database> openDrinkDatabase() async {
  // ignore: deprecated_member_use
  final dir = await getDatabasesPath();
  final dbPath = '$dir/${StorageKeys.dbName}';
  return openDatabase(
    dbPath,
    version: StorageKeys.dbVersion,
    onCreate: createSchema,
    onUpgrade: upgradeSchema,
  );
}

/// v5 升级：历史记录统一归属到当前登录账号（未登录则保持游客）。
/// 只执行一次，避免把之后新增的游客数据误并入账号。
Future<void> claimLegacyEntries(
  SharedPreferences prefs,
  Database db,
) async {
  const flag = 'entries_owner_migrated_v5';
  if (prefs.getBool(flag) == true) return;
  // 升级时若已退出登录，用最近一次登录的账号兜底归属，
  // 避免历史账号数据被当成游客数据显示出来
  final uid = prefs.getString(StorageKeys.syncUserId) ??
      prefs.getString(StorageKeys.lastUserId);
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
Future<void> migrateLegacySettings(SharedPreferences prefs) async {
  if (prefs.getBool(StorageKeys.settingsMigrated) == true) return;
  final uid = prefs.getString(StorageKeys.syncUserId) ?? '';
  final storeKey = '${StorageKeys.settingsPrefix}${ownerSuffix(uid)}';
  final existing = decodeSettings(prefs.getString(storeKey));
  final at = nowIso();
  for (final key in AccountSettingKeys.all) {
    if (existing.containsKey(key)) continue;
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) continue;
    existing[key] = {'v': decodeSettingValue(raw), 'at': at};
  }
  await prefs.setString(storeKey, jsonEncode(existing));
  // 旧全局 key 已并入归属桶，删除避免退出登录后串到游客视图
  for (final key in AccountSettingKeys.all) {
    await prefs.remove(key);
  }
  await prefs.setBool(StorageKeys.settingsMigrated, true);
}

/// v1 → v2：补上录入时快照的热量列（旧记录默认 -1 = 未记录）
/// v2 → v3：健康同步状态（0 未同步 / 1 已导出 / 2 已导入）
Future<void> upgradeSchema(
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
    await db.execute(createEntriesTable);
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

/// 老版本只有一个全局游标 `sync_cursor`：迁到当前归属桶，之后各账号各记各的
Future<void> migrateLegacyCursor(SharedPreferences prefs) async {
  final legacy = prefs.getInt(StorageKeys.syncCursorLegacy);
  if (legacy == null) return;
  final uid = prefs.getString(StorageKeys.syncUserId) ?? '';
  final key = '${StorageKeys.syncCursorPrefix}${ownerSuffix(uid)}';
  if (prefs.getInt(key) == null) await prefs.setInt(key, legacy);
  await prefs.remove(StorageKeys.syncCursorLegacy);
}

/// 老版本积分只有本机一个 `points_state`：迁入当前归属桶，并把余额转成
/// 一条 seed 流水，联网后补传到服务端（服务端按 eventId 去重，不会重复计分）
Future<void> migrateLegacyPoints(SharedPreferences prefs) async {
  if (prefs.getBool(StorageKeys.pointsMigrated) == true) return;
  final uid = prefs.getString(StorageKeys.syncUserId) ?? '';
  final owner = ownerSuffix(uid);
  final legacy = prefs.getString(StorageKeys.pointsLegacyKey);
  final bucketKey = 'points_state_$owner';
  if (legacy != null &&
      legacy.isNotEmpty &&
      prefs.getString(bucketKey) == null) {
    await prefs.setString(bucketKey, legacy);
    final balance =
        (decodeJsonMap(legacy)?['balance'] as num?)?.toInt() ?? 0;
    if (balance > 0) {
      final pendingKey = 'points_pending_$owner';
      final pending = decodePendingList(prefs.getString(pendingKey));
      final eventId = 'migrate:v1:$owner';
      if (!pending.any((e) => e['eventId']?.toString() == eventId)) {
        pending.add({
          'eventId': eventId,
          'source': 'migrate',
          'amount': balance,
          'occurredAt': nowIso(),
        });
        await prefs.setString(pendingKey, jsonEncode(pending));
      }
    }
  }
  await prefs.remove(StorageKeys.pointsLegacyKey);
  await prefs.setBool(StorageKeys.pointsMigrated, true);
}
