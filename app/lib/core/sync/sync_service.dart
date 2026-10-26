import 'package:flutter/foundation.dart';

import '../../shared/models/drink_entry.dart';
import '../storage/local_storage.dart';
import 'sync_api.dart';

class SyncResult {
  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.failed = false,
    this.message,
  });

  final int pushed;
  final int pulled;
  final bool failed;
  final String? message;
}

/// 云同步：匿名身份注册 + 记录批量上行 + 增量下行
///
/// 离线优先：本地写入永远先落库，同步只是后台补充动作。
class SyncService {
  static bool _running = false;

  static Future<void> ensureSession(LocalStorage storage) async {
    if (storage.hasSyncSession) return;
    final res = await SyncApi.guest(storage.accountAnonId);
    await storage.setSyncSession(
      res['userId'] as String,
      res['accessToken'] as String,
    );
  }

  static Future<SyncResult> syncNow(LocalStorage storage) async {
    if (_running) return const SyncResult();
    _running = true;
    try {
      await ensureSession(storage);
      final token = storage.syncToken!;

      final pending = await storage.loadPendingSyncEntries();
      var pushed = 0;
      final conflicted = <String>{};

      if (pending.isNotEmpty) {
        final res = await SyncApi.push(
          token,
          entries: pending.map(_looksLikeEntry).toList(),
        );
        pushed = (res['accepted'] as num?)?.toInt() ?? 0;

        for (final raw in (res['conflicts'] as List?) ?? const []) {
          if (raw is! Map || raw['type'] != 'entry') continue;
          final clientId = raw['clientId']?.toString();
          final data = raw['data'];
          if (clientId == null || data is! Map) continue;
          await storage.applyRemoteEntry(
            _entryFromRemote(
              Map<String, dynamic>.from(data),
              clientId: clientId,
              deletedAt: raw['deletedAt']?.toString(),
            ),
          );
          conflicted.add(clientId);
        }

        await storage.markEntriesSynced(
          pending
              .map((e) => e.clientId)
              .where((id) => !conflicted.contains(id))
              .toList(),
        );
      }

      var cursor = storage.syncCursor;
      var pulled = 0;
      while (true) {
        final res = await SyncApi.pull(token, cursor: cursor);
        final items = (res['items'] as List?) ?? const [];
        for (final raw in items) {
          if (raw is! Map || raw['type'] != 'entry') continue;
          final clientId = raw['clientId']?.toString();
          final data = raw['data'];
          if (clientId == null || data is! Map) continue;
          await storage.applyRemoteEntry(
            _entryFromRemote(
              Map<String, dynamic>.from(data),
              clientId: clientId,
              deletedAt: raw['deletedAt']?.toString(),
            ),
          );
          pulled += 1;
        }
        cursor = (res['cursor'] as num?)?.toInt() ?? cursor;
        await storage.setSyncCursor(cursor);
        if (res['hasMore'] != true) break;
      }

      await storage.setSyncLastSyncAt(DateTime.now());
      return SyncResult(pushed: pushed, pulled: pulled);
    } catch (e) {
      debugPrint('[Sync] failed: $e');
      return SyncResult(failed: true, message: '$e');
    } finally {
      _running = false;
    }
  }

  static Map<String, dynamic> _looksLikeEntry(DrinkEntry e) {
    final updatedAt = e.effectiveUpdatedAt.toUtc().toIso8601String();
    return {
      'clientId': e.clientId,
      'updatedAt': updatedAt,
      'deletedAt': e.deleted ? updatedAt : null,
      'data': e.toMap(),
    };
  }

  static DrinkEntry _entryFromRemote(
    Map<String, dynamic> data, {
    required String clientId,
    String? deletedAt,
  }) {
    final parsed = DrinkEntry.fromMap(data);
    final updated = DateTime.tryParse(deletedAt ?? '') ??
        DateTime.tryParse(data['updated_at']?.toString() ?? '');
    return parsed.copyWith(
      synced: true,
      deleted: deletedAt != null,
      updatedAt: updated?.toUtc(),
    );
  }
}
