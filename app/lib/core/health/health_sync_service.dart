import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../../shared/models/beverage.dart';
import '../../shared/models/drink_entry.dart';
import '../storage/local_storage.dart';

/// 健康 App 的可用状态
enum HealthAvailability {
  /// 当前平台不支持（Web / Windows）
  notSupported,

  /// 可以直接读写
  ready,

  /// Android 未安装 Health Connect
  needInstall,
}

/// 一次同步的结果
class HealthSyncReport {
  const HealthSyncReport({
    this.exported = 0,
    this.removed = 0,
    this.imported = 0,
    this.failed = false,
  });

  /// 本次写入健康 App 的条数
  final int exported;

  /// 本次从健康 App 撤掉的条数
  final int removed;

  /// 本次从健康 App 导入的条数
  final int imported;

  /// 健康 App 不可用/权限被拒
  final bool failed;

  int get total => exported + removed + imported;

  HealthSyncReport merge(HealthSyncReport other) => HealthSyncReport(
        exported: exported + other.exported,
        removed: removed + other.removed,
        imported: imported + other.imported,
        failed: failed || other.failed,
      );
}

/// 健康同步（Apple Health / Health Connect）
///
/// 双向同步水摄入：
///  * 导出：本地新增的饮水记录写入健康 App（首次连接补录最近 30 天）
///  * 撤回：本地删除记录时按时间段删掉 App 写入的样本
///  * 导入：读取其他来源的饮水记录，按样本 UUID 去重后落库
///
/// 所有失败都只记日志，不抛给 UI，避免健康 App 未授权时拖垮主流程。
class HealthSyncService {
  HealthSyncService._();

  static final Health _health = Health();
  static const HealthDataType _type = HealthDataType.WATER;

  /// 首次连接补录窗口
  static const int _backfillDays = 30;

  /// 每次同步导入的回看窗口
  static const int _importDays = 30;

  /// 启动时自动同步的最小间隔
  static const Duration _autoSyncGap = Duration(hours: 6);

  static bool _configured = false;

  static bool get supported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  static Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  static Future<HealthAvailability> availability() async {
    if (!supported) return HealthAvailability.notSupported;
    if (Platform.isIOS) return HealthAvailability.ready;
    try {
      final status = await _health.getHealthConnectSdkStatus();
      return status == HealthConnectSdkStatus.sdkAvailable
          ? HealthAvailability.ready
          : HealthAvailability.needInstall;
    } catch (e) {
      debugPrint('[health] getHealthConnectSdkStatus failed: $e');
      return HealthAvailability.needInstall;
    }
  }

  /// 引导安装 Health Connect（仅 Android）；iOS 不做任何事
  static Future<void> installHealthConnect() async {
    if (!supported || Platform.isIOS) return;
    try {
      await _health.installHealthConnect();
    } catch (e) {
      debugPrint('[health] installHealthConnect failed: $e');
    }
  }

  /// 申请读写水数据的权限；返回是否成功
  static Future<bool> requestPermissions() async {
    if (!supported) return false;
    if (await availability() != HealthAvailability.ready) return false;
    await _ensureConfigured();

    // 若用户已在系统「健康连接」里手动授权，这里直接放行：
    // Android 的 requestAuthorization 在「没有新的可授权项」时会返回空集合（false）。
    if (await hasPermissions() == true) return true;

    try {
      final granted = await _health.requestAuthorization(
        [_type],
        permissions: [HealthDataAccess.READ_WRITE],
      );
      // 部分机型弹窗后仍返回 false，以系统实际授权状态为准
      return granted || (await hasPermissions() ?? false);
    } catch (e) {
      debugPrint('[health] requestAuthorization failed: $e');
      return false;
    }
  }

  /// 是否已拿到读写权限（iOS 读取权限不可探测，返回 null）
  static Future<bool?> hasPermissions() async {
    if (!supported) return false;
    await _ensureConfigured();
    try {
      return await _health.hasPermissions(
        [_type],
        permissions: [HealthDataAccess.READ_WRITE],
      );
    } catch (e) {
      return false;
    }
  }

  /// 全量同步：导出待同步记录 + 撤回已删除样本 + 导入外部记录
  static Future<HealthSyncReport> syncNow(LocalStorage storage) async {
    if (!storage.healthSyncEnabled || !supported) {
      return const HealthSyncReport();
    }
    if (await availability() != HealthAvailability.ready) {
      return const HealthSyncReport(failed: true);
    }
    await _ensureConfigured();
    final now = DateTime.now();
    final exported = await _exportPending(
      storage,
      since: now.subtract(const Duration(days: _backfillDays)),
    );
    final removed = await _syncDeleted(storage);
    final imported = await _import(
      storage,
      since: now.subtract(const Duration(days: _importDays)),
    );
    await storage.setHealthLastSyncAt(now);
    return HealthSyncReport(
      exported: exported,
      removed: removed,
      imported: imported,
    );
  }

  /// 新增饮水后立刻写出（只处理未同步的记录，代价很小）
  static Future<void> afterEntryAdded(LocalStorage storage) async {
    if (!storage.healthSyncEnabled || !supported) return;
    if (await availability() != HealthAvailability.ready) return;
    await _ensureConfigured();
    await _exportPending(storage);
    await storage.setHealthLastSyncAt(DateTime.now());
  }

  /// 删除饮水后立刻撤回健康 App 里的样本
  static Future<void> afterEntryRemoved(LocalStorage storage) async {
    if (!storage.healthSyncEnabled || !supported) return;
    if (await availability() != HealthAvailability.ready) return;
    await _ensureConfigured();
    await _syncDeleted(storage);
  }

  /// App 启动时静默同步（[gap] 内不重复跑）
  static Future<HealthSyncReport> maybeAutoSync(LocalStorage storage) async {
    if (!storage.healthSyncEnabled || !supported) {
      return const HealthSyncReport();
    }
    final last = storage.healthLastSyncAt;
    if (last != null && DateTime.now().difference(last) < _autoSyncGap) {
      return const HealthSyncReport();
    }
    return syncNow(storage);
  }

  // ---------- 导出 ----------

  static Future<int> _exportPending(
    LocalStorage storage, {
    DateTime? since,
  }) async {
    var done = 0;
    try {
      final pending = await storage.loadHealthPendingEntries(since: since);
      for (final e in pending) {
        if (e.volumeMl <= 0 || e.deleted) continue;
        if (await _writeSample(e)) {
          await storage.setHealthState(e.clientId, DrinkEntry.healthExported);
          done++;
        } else {
          // 权限或环境异常，交给下次同步，不在本次循环里硬刷
          break;
        }
      }
    } catch (e) {
      debugPrint('[health] export failed: $e');
    }
    return done;
  }

  static Future<bool> _writeSample(DrinkEntry e) async {
    try {
      return await _health.writeHealthData(
        // health 包对 WATER 的默认单位是升
        value: e.volumeMl / 1000.0,
        type: _type,
        startTime: e.drankAt,
        endTime: e.drankAt.add(const Duration(seconds: 1)),
        // iOS 只接受 manual / automatic
        recordingMethod: RecordingMethod.manual,
        // Android Health Connect 用它做幂等
        clientRecordId: e.clientId,
      );
    } catch (e) {
      debugPrint('[health] write failed: $e');
      return false;
    }
  }

  // ---------- 撤回 ----------

  static Future<int> _syncDeleted(LocalStorage storage) async {
    var done = 0;
    try {
      final list = await storage.loadHealthDeletedEntries();
      for (final e in list) {
        try {
          final ok = await _health.delete(
            type: _type,
            startTime: e.drankAt,
            // 导出时 end = start + 1s，删除窗口略放宽
            endTime: e.drankAt.add(const Duration(seconds: 2)),
          );
          if (ok) {
            await storage.setHealthState(e.clientId, DrinkEntry.healthNone);
            done++;
          }
        } catch (e) {
          debugPrint('[health] delete failed: $e');
          break;
        }
      }
    } catch (e) {
      debugPrint('[health] sync deleted failed: $e');
    }
    return done;
  }

  // ---------- 导入 ----------

  static Future<int> _import(
    LocalStorage storage, {
    required DateTime since,
  }) async {
    var done = 0;
    try {
      final points = await _health.getHealthDataFromTypes(
        types: [_type],
        startTime: since,
        endTime: DateTime.now(),
      );
      final seen = <String>{};
      for (final p in points) {
        final uuid = p.uuid;
        if (uuid.isEmpty || seen.contains(uuid)) continue;
        seen.add(uuid);
        // 自己写出去的样本不要导回来
        if (_isOwnSource(p)) continue;
        if (await storage.hasHealthSampleId(uuid)) continue;
        final value = p.value;
        final liters = value is NumericHealthValue
            ? value.numericValue.toDouble()
            : 0.0;
        final ml = (liters * 1000).round();
        if (ml <= 0) continue;
        if (p.dateFrom.isBefore(since)) continue;
        await storage.insertDrinkEntry(DrinkEntry(
          clientId: 'health_$uuid',
          beverageId: 'water',
          beverageCategory: BeverageCategory.water,
          beverageName: '水',
          volumeMl: ml,
          effectiveMl: ml,
          drankAt: p.dateFrom,
          synced: false,
          calories: 0,
          healthSampleId: uuid,
          healthState: DrinkEntry.healthImported,
        ));
        done++;
      }
    } catch (e) {
      debugPrint('[health] import failed: $e');
    }
    return done;
  }

  /// 判断样本是否由本 App 写入（iOS 看 bundleId / 应用名，Android 看包名）
  static bool _isOwnSource(HealthDataPoint p) {
    final source = '${p.sourceId} ${p.sourceName}'.toLowerCase();
    return source.contains('waterllama') ||
        source.contains('water_llama') ||
        source.contains('water llama') ||
        source.contains('喝水羊驼');
  }
}
