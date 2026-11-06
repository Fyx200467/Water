import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/drink_entry.dart';
import 'dao_keys.dart';

/// 旧版单桶 key（升级前的数据都在这，仅游客读取时兜底）
const String legacyEntryStoreKey = 'all';

List<DrinkEntry> decodeEntries(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List;
    return list.map((e) => DrinkEntry.fromMap((e as Map).cast())).toList();
  } catch (_) {
    return [];
  }
}

/// prefs 降级存储：按归属分桶，切换账号互不影响
class EntryPrefsStore {
  EntryPrefsStore(this.prefs, this.owner);

  final SharedPreferences prefs;
  final String owner;

  String get storeKey =>
      '${StorageKeys.entriesPrefix}${owner.isEmpty ? 'guest' : owner}';

  Future<List<DrinkEntry>> loadAll() async {
    final raw = prefs.getString(storeKey) ??
        (owner.isEmpty
            ? prefs.getString('${StorageKeys.entriesPrefix}$legacyEntryStoreKey')
            : null);
    return decodeEntries(raw);
  }

  Future<List<DrinkEntry>> loadFromKey(String key) async =>
      decodeEntries(prefs.getString(key));

  Future<void> insert(DrinkEntry entry) async {
    final all = await loadAll();
    final idx = all.indexWhere((e) => e.clientId == entry.clientId);
    if (idx >= 0) {
      all[idx] = entry;
    } else {
      all.add(entry);
    }
    await prefs.setString(
      storeKey,
      jsonEncode(all.map((e) => e.toMap()).toList()),
    );
  }

  Future<void> markDeleted(String clientId) async {
    final all = await loadAll();
    final idx = all.indexWhere((e) => e.clientId == clientId);
    if (idx >= 0) {
      final e = all[idx];
      // 从未上行过的记录：直接移除，不生成无意义的删除墓碑
      if (e.serverId == null || e.serverId!.isEmpty) {
        all.removeAt(idx);
      } else {
        all[idx] = e.copyWith(deleted: true, synced: false);
      }
      await prefs.setString(
        storeKey,
        jsonEncode(all.map((e) => e.toMap()).toList()),
      );
    }
  }

  Future<void> removeEntry(String clientId) async {
    final all = await loadAll();
    all.removeWhere((e) => e.clientId == clientId);
    await prefs.setString(
      storeKey,
      jsonEncode(all.map((e) => e.toMap()).toList()),
    );
  }
}
