import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../../shared/models/drink_entry.dart';
import 'dao_keys.dart';
import 'dao_shared.dart';
import 'entry_prefs_store.dart';

/// 健康同步（Apple Health / Health Connect）：开关、时间与记录状态
class HealthDao {
  HealthDao(this.prefs, this.db);

  final SharedPreferences prefs;
  final Database? db;

  bool get hasDb => db != null;

  String get owner => ownerOf(prefs);

  EntryPrefsStore get _entryStore => EntryPrefsStore(prefs, owner);

  bool get healthSyncEnabled =>
      prefs.getBool(StorageKeys.healthEnabled) ?? false;

  Future<void> setHealthSyncEnabled(bool on) async {
    await prefs.setBool(StorageKeys.healthEnabled, on);
  }

  DateTime? get healthLastSyncAt {
    final s = prefs.getString(StorageKeys.healthLastSync);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> setHealthLastSyncAt(DateTime at) async {
    await prefs.setString(StorageKeys.healthLastSync, at.toIso8601String());
  }

  /// 待导出到健康 App 的记录（本地新增但还没写出去）
  Future<List<DrinkEntry>> loadHealthPendingEntries({
    DateTime? since,
    int limit = 500,
  }) async {
    final sinceIso = since?.toIso8601String();
    if (hasDb) {
      final rows = await db!.query(
        'drink_entries',
        where:
            'health_state = 0 AND deleted = 0 AND owner_user_id = ?'
            '${sinceIso == null ? '' : ' AND drank_at >= ?'}',
        whereArgs: sinceIso == null ? [owner] : [owner, sinceIso],
        orderBy: 'drank_at ASC',
        limit: limit,
      );
      return rows.map(DrinkEntry.fromMap).toList();
    }
    final all = await _entryStore.loadAll();
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
    if (hasDb) {
      final rows = await db!.query(
        'drink_entries',
        where: 'health_state = 1 AND deleted = 1 AND owner_user_id = ?',
        whereArgs: [owner],
        orderBy: 'drank_at ASC',
        limit: limit,
      );
      return rows.map(DrinkEntry.fromMap).toList();
    }
    final all = await _entryStore.loadAll();
    return all
        .where((e) => e.deleted && e.healthState == DrinkEntry.healthExported)
        .take(limit)
        .toList();
  }

  /// 该健康样本是否已导入过（按样本 UUID 去重）
  Future<bool> hasHealthSampleId(String sampleId) async {
    if (hasDb) {
      final rows = await db!.query(
        'drink_entries',
        columns: ['client_id'],
        where: 'health_sample_id = ? AND owner_user_id = ?',
        whereArgs: [sampleId, owner],
        limit: 1,
      );
      return rows.isNotEmpty;
    }
    final all = await _entryStore.loadAll();
    return all.any((e) => e.healthSampleId == sampleId);
  }

  /// 更新健康同步状态（导出成功后落库；从健康 App 删除成功后清零）
  Future<void> setHealthState(
    String clientId,
    int state, {
    String? sampleId,
  }) async {
    if (hasDb) {
      await db!.update(
        'drink_entries',
        {
          'health_state': state,
          if (sampleId != null) 'health_sample_id': sampleId,
        },
        where: 'client_id = ? AND owner_user_id = ?',
        whereArgs: [clientId, owner],
      );
    }
    final all = await _entryStore.loadAll();
    final idx = all.indexWhere((e) => e.clientId == clientId);
    if (idx >= 0) {
      all[idx] = all[idx].copyWith(
        healthState: state,
        healthSampleId: sampleId,
      );
      await prefs.setString(
        _entryStore.storeKey,
        jsonEncode(all.map((e) => e.toMap()).toList()),
      );
    }
  }
}
