import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../../shared/models/drink_entry.dart';
import '../../time/logical_day.dart';
import 'dao_keys.dart';
import 'dao_shared.dart';
import 'entry_prefs_store.dart';

/// 饮水记录（双路：sqflite + prefs 降级）+ 云同步记录读写
class DrinkDao {
  DrinkDao(this.prefs, this.db);

  final SharedPreferences prefs;
  final Database? db;

  bool get hasDb => db != null;

  /// 当前记录归属：登录账号 ID；空串表示游客（未登录）。
  /// 退出登录后 owner 变回空串，账号数据自然从界面上消失。
  String get owner => ownerOf(prefs);

  EntryPrefsStore get _entryStore => EntryPrefsStore(prefs, owner);

  Future<void> insertDrinkEntry(DrinkEntry entry) async {
    if (hasDb) {
      await db!.insert(
        'drink_entries',
        entry.toMap()..['owner_user_id'] = owner,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await _entryStore.insert(entry);
  }

  Future<void> softDeleteEntry(String clientId) async {
    if (hasDb) {
      // 从未上行到服务端的记录（server_id 为空）直接物理删除：
      // 否则会留下一条无意义的删除墓碑，导致「待同步 N 条」永远不清零
      final rows = await db!.query(
        'drink_entries',
        columns: ['server_id'],
        where: 'client_id = ? AND owner_user_id = ?',
        whereArgs: [clientId, owner],
        limit: 1,
      );
      final serverId = rows.isEmpty ? null : rows.first['server_id'] as String?;
      if (rows.isNotEmpty && (serverId == null || serverId.isEmpty)) {
        await db!.delete(
          'drink_entries',
          where: 'client_id = ? AND owner_user_id = ?',
          whereArgs: [clientId, owner],
        );
        await _entryStore.removeEntry(clientId);
        return;
      }
      await db!.update(
        'drink_entries',
        {
          'deleted': 1,
          'synced': 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'client_id = ? AND owner_user_id = ?',
        whereArgs: [clientId, owner],
      );
    }
    await _entryStore.markDeleted(clientId);
  }

  /// 查询某逻辑日的记录（[day] 为逻辑日 key：时间部分为零点；
  /// 有效区间 = [day + 重置时刻, day+1 + 重置时刻)）
  Future<List<DrinkEntry>> loadEntriesForDay(DateTime day) async {
    if (hasDb) {
      final start = LogicalDay.startOf(day);
      final end = LogicalDay.endOf(day);
      final rows = await db!.query(
        'drink_entries',
        where:
            'drank_at >= ? AND drank_at < ? AND deleted = 0'
            ' AND owner_user_id = ?',
        whereArgs: [start.toIso8601String(), end.toIso8601String(), owner],
        orderBy: 'drank_at DESC',
      );
      return rows.map(DrinkEntry.fromMap).toList();
    }
    final all = await _entryStore.loadAll();
    return all
        .where((e) => !e.deleted && LogicalDay.sameDay(e.drankAt, day))
        .toList()
      ..sort((a, b) => b.drankAt.compareTo(a.drankAt));
  }

  Future<List<DrinkEntry>> loadEntriesForRange(
    DateTime start,
    DateTime end,
  ) async {
    if (hasDb) {
      final rows = await db!.query(
        'drink_entries',
        where:
            'drank_at >= ? AND drank_at < ? AND deleted = 0'
            ' AND owner_user_id = ?',
        whereArgs: [start.toIso8601String(), end.toIso8601String(), owner],
        orderBy: 'drank_at ASC',
      );
      return rows.map(DrinkEntry.fromMap).toList();
    }
    final all = await _entryStore.loadAll();
    return all
        .where(
          (e) =>
              !e.deleted && e.drankAt.isAfter(start) && e.drankAt.isBefore(end),
        )
        .toList()
      ..sort((a, b) => a.drankAt.compareTo(b.drankAt));
  }

  Future<List<DrinkEntry>> loadUnsyncedEntries() async {
    if (hasDb) {
      final rows = await db!.query(
        'drink_entries',
        where: "synced = 0 AND deleted = 0 AND owner_user_id = ?",
        whereArgs: [owner],
        orderBy: 'drank_at ASC',
      );
      return rows.map(DrinkEntry.fromMap).toList();
    }
    final all = await _entryStore.loadAll();
    return all.where((e) => !e.synced && !e.deleted).toList();
  }

  Future<void> markSynced(String clientId, {String? serverId}) async {
    if (hasDb) {
      await db!.update(
        'drink_entries',
        {'synced': 1, 'server_id': serverId},
        where: 'client_id = ? AND owner_user_id = ?',
        whereArgs: [clientId, owner],
      );
    }
    final all = await _entryStore.loadAll();
    final idx = all.indexWhere((e) => e.clientId == clientId);
    if (idx >= 0) {
      all[idx] = all[idx].copyWith(synced: true, serverId: serverId);
      await prefs.setString(
        _entryStore.storeKey,
        jsonEncode(all.map((e) => e.toMap()).toList()),
      );
    }
  }

  /// 尚未上行到服务端的记录（含待同步的删除墓碑；
  /// 从未上行过的删除墓碑没有意义，不再计入/上报）
  Future<List<DrinkEntry>> loadPendingSyncEntries({int limit = 200}) async {
    if (hasDb) {
      final rows = await db!.query(
        'drink_entries',
        where: "synced = 0 AND owner_user_id = ?"
            " AND (deleted = 0 OR (server_id IS NOT NULL AND server_id != ''))",
        whereArgs: [owner],
        orderBy: 'drank_at ASC',
        limit: limit,
      );
      return rows.map(DrinkEntry.fromMap).toList();
    }
    final all = await _entryStore.loadAll();
    return all
        .where((e) => !e.synced && (!e.deleted || (e.serverId?.isNotEmpty ?? false)))
        .take(limit)
        .toList();
  }

  Future<int> countPendingSyncEntries() async {
    if (hasDb) {
      final rows = await db!.rawQuery(
        'SELECT COUNT(*) AS c FROM drink_entries'
        " WHERE synced = 0 AND owner_user_id = ?"
        " AND (deleted = 0 OR (server_id IS NOT NULL AND server_id != ''))",
        [owner],
      );
      return (rows.first['c'] as int?) ?? 0;
    }
    final all = await _entryStore.loadAll();
    return all
        .where((e) => !e.synced && (!e.deleted || (e.serverId?.isNotEmpty ?? false)))
        .length;
  }

  /// 本机游客桶里仍未删除的记录条数：登录成功后据此询问「是否并入账号」
  Future<int> countGuestEntries() async {
    if (hasDb) {
      final rows = await db!.rawQuery(
        "SELECT COUNT(*) AS c FROM drink_entries"
        " WHERE deleted = 0 AND owner_user_id = ''",
      );
      return (rows.first['c'] as int?) ?? 0;
    }
    // prefs 降级：游客桶 + 旧版单桶，按 clientId 去重后计数
    final ids = <String>{};
    for (final key in [
      '${StorageKeys.entriesPrefix}guest',
      '${StorageKeys.entriesPrefix}$legacyEntryStoreKey',
    ]) {
      for (final e in await _entryStore.loadFromKey(key)) {
        if (!e.deleted) ids.add(e.clientId);
      }
    }
    return ids.length;
  }

  /// 登录后把未登录期间产生的记录归属到该账号（本地数据与账号绑定）
  Future<void> bindGuestEntriesToAccount(String userId) async {
    if (userId.isEmpty) return;
    if (hasDb) {
      // OR REPLACE：若该 client_id 已属于这个账号（之前推过），保留游客侧
      // 这份更新的本地状态，避免复合主键冲突导致归属迁移失败
      await db!.rawUpdate(
        "UPDATE OR REPLACE drink_entries SET owner_user_id = ?"
        " WHERE owner_user_id = ''",
        [userId],
      );
    }
    // prefs 降级：游客桶与旧版单桶数据合并进该账号桶
    final guestRaw = prefs.getString('${StorageKeys.entriesPrefix}guest') ??
        prefs.getString('${StorageKeys.entriesPrefix}$legacyEntryStoreKey');
    if (guestRaw == null || guestRaw.isEmpty) return;
    final userKey = '${StorageKeys.entriesPrefix}$userId';
    final merged = <String, DrinkEntry>{};
    for (final e in await _entryStore.loadFromKey(userKey)) {
      merged[e.clientId] = e;
    }
    for (final e in await _entryStore.loadFromKey(
      '${StorageKeys.entriesPrefix}guest',
    )) {
      merged.putIfAbsent(e.clientId, () => e);
    }
    for (final e in await _entryStore.loadFromKey(
      '${StorageKeys.entriesPrefix}$legacyEntryStoreKey',
    )) {
      merged.putIfAbsent(e.clientId, () => e);
    }
    await prefs.setString(
      userKey,
      jsonEncode(merged.values.map((e) => e.toMap()).toList()),
    );
    await prefs.remove('${StorageKeys.entriesPrefix}guest');
    await prefs.remove('${StorageKeys.entriesPrefix}$legacyEntryStoreKey');
  }

  Future<void> markEntriesSynced(List<String> clientIds) async {
    if (clientIds.isEmpty) return;
    if (hasDb) {
      final batch = db!.batch();
      for (final id in clientIds) {
        batch.update(
          'drink_entries',
          {'synced': 1},
          where: 'client_id = ? AND owner_user_id = ?',
          whereArgs: [id, owner],
        );
      }
      await batch.commit(noResult: true);
      return;
    }
    final all = await _entryStore.loadAll();
    for (var i = 0; i < all.length; i++) {
      if (clientIds.contains(all[i].clientId)) {
        all[i] = all[i].copyWith(synced: true);
      }
    }
    await prefs.setString(
      _entryStore.storeKey,
      jsonEncode(all.map((e) => e.toMap()).toList()),
    );
  }

  /// 服务端下发的记录直接落库（视为已同步）。
  /// 本机存在更新且尚未上行的同一条记录时保留本机版本，
  /// 避免「拉取覆盖本机新改动」造成数据丢失（它会由下一轮上行补传）。
  Future<void> applyRemoteEntry(DrinkEntry entry) async {
    final local = await _loadEntryByClientId(entry.clientId);
    if (local != null &&
        !local.synced &&
        local.effectiveUpdatedAt.isAfter(entry.effectiveUpdatedAt)) {
      return;
    }
    await insertDrinkEntry(entry.copyWith(synced: true));
  }

  Future<DrinkEntry?> _loadEntryByClientId(String clientId) async {
    if (clientId.isEmpty) return null;
    if (hasDb) {
      final rows = await db!.query(
        'drink_entries',
        where: 'client_id = ? AND owner_user_id = ?',
        whereArgs: [clientId, owner],
        limit: 1,
      );
      return rows.isEmpty ? null : DrinkEntry.fromMap(rows.first);
    }
    final all = await _entryStore.loadAll();
    for (final e in all) {
      if (e.clientId == clientId) return e;
    }
    return null;
  }
}
