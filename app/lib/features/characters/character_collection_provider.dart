import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/account_settings.dart';
import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../home/providers/home_providers.dart';
import 'character_data.dart';

/// 角色收集规则：
/// - 计量 = 用户历史饮水总量（全部饮水记录的饮品体积之和）
/// - 每累计 [collectMilestoneStepMl] 在「每日」分类中随机点亮一个未收集角色
/// - 点亮即收集成功，可设为首页角色
const collectMilestoneStepMl = 2000;

/// 角色收集状态
class CharacterCollectionState {
  const CharacterCollectionState({
    required this.collectedIds,
    required this.totalMl,
  });

  /// 已点亮（收集）的角色，至少包含初始角色 alpaca
  final Set<String> collectedIds;

  /// 历史饮水总量（ml）
  final int totalMl;

  /// 下一个点亮里程碑（历史总量达到即再点亮一个）
  int get nextMilestoneMl => collectedIds.length * collectMilestoneStepMl;
}

/// 角色收集状态管理：持久化点亮集合，饮水总量跨过里程碑时随机点亮
class CharacterCollectionNotifier
    extends StateNotifier<AsyncValue<CharacterCollectionState>> {
  CharacterCollectionNotifier(this.ref) : super(const AsyncLoading()) {
    _load();
  }

  final Ref ref;

  Set<String> _collected = {'alpaca'};

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final raw = storage.readAccountSetting(
      AccountSettingKeys.characterCollected,
    );
    if (raw is List && raw.isNotEmpty) {
      _collected = {...raw.map((e) => e.toString()), 'alpaca'};
    }
    await refreshTotals();
  }

  /// 重算历史饮水总量；跨过新里程碑时随机点亮「每日」分类的未收集角色
  Future<void> refreshTotals() async {
    final storage = await ref.read(localStorageProvider.future);
    final entries = await storage.loadEntriesForRange(
      DateTime(2000),
      DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day + 1,
      ),
    );
    final totalMl = entries.fold<int>(0, (s, e) => s + e.volumeMl);

    // 目标里程碑数 = 总量 / 步长；初始角色 alpaca 占第 0 个收集位
    final targetMilestones = totalMl ~/ collectMilestoneStepMl;
    var appliedMilestones = _collected.length - 1;
    if (targetMilestones > appliedMilestones) {
      final pool = characterCategories
          .firstWhere((c) => c.id == 'daily')
          .characterIds
          .where((id) => !_collected.contains(id))
          .toList();
      final rng = math.Random();
      while (appliedMilestones < targetMilestones && pool.isNotEmpty) {
        final pick = pool.removeAt(rng.nextInt(pool.length));
        _collected.add(pick);
        appliedMilestones++;
      }
      await storage.writeAccountSetting(
        AccountSettingKeys.characterCollected,
        _collected.toList(),
      );
      // 收集进度是账号资产：联网立即上行（云端按并集合并）
      unawaited(SyncService.autoSync(storage));
    }

    if (!mounted) return;
    state = AsyncData(
      CharacterCollectionState(
        collectedIds: Set.unmodifiable(_collected),
        totalMl: totalMl,
      ),
    );
  }
}

/// 角色收集 provider；新增/删除/补录饮水后自动重算并触发里程碑点亮
final characterCollectionProvider =
    StateNotifierProvider<
      CharacterCollectionNotifier,
      AsyncValue<CharacterCollectionState>
    >((ref) {
      // 会话切换 / 云端偏好更新：按新归属账号的角色收集进度重载
      ref.watch(sessionEpochProvider);
      ref.watch(accountSettingsRevisionProvider);
      final notifier = CharacterCollectionNotifier(ref);
      ref.listen(todayEntriesProvider, (_, __) => notifier.refreshTotals());
      return notifier;
    });
