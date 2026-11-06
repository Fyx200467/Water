import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/entries/entries_providers.dart';
import '../../../core/profile/profile_provider.dart';
import '../../../core/settings/account_settings.dart';
import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/widget/widget_settings_provider.dart';
import '../../../shared/models/animal_character.dart';
import '../../../shared/models/drink_entry.dart';
import '../../../shared/models/preferred_unit.dart';
import '../../drink/services/hydration_calculator.dart';

// 用户档案 / 当日记录已下沉至 core；此处 export 保持既有引用方无需改动
export '../../../core/profile/profile_provider.dart';
export '../../../core/entries/entries_providers.dart';

/// 数据变更源头推送：当日记录/目标变化后即时刷新桌面小组件
/// （不依赖各页面手动调用，避免遗漏导致小组件数据滞后）
Future<void> pushHomeWidget(Ref ref) async {
  try {
    await ref.read(widgetSyncTriggerProvider)();
  } catch (_) {
    // 小组件推送失败不影响录入主流程
  }
}

/// 单位偏好（首次启动在欢迎页选择，之后跟随账号上云）
final preferredUnitProvider =
    StateNotifierProvider<PreferredUnitNotifier, PreferredUnit>((ref) {
      // 会话切换 / 云端偏好更新后，按新归属账号的单位重新加载
      ref.watch(sessionEpochProvider);
      ref.watch(accountSettingsRevisionProvider);
      return PreferredUnitNotifier(ref);
    });

class PreferredUnitNotifier extends StateNotifier<PreferredUnit> {
  PreferredUnitNotifier(this.ref) : super(PreferredUnit.ml) {
    _load();
  }
  final Ref ref;

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final raw = storage
        .readAccountSetting(AccountSettingKeys.preferredUnit)
        ?.toString();
    state = raw == 'oz' ? PreferredUnit.oz : PreferredUnit.ml;
    UnitFormat.unit = state;
  }

  Future<void> select(PreferredUnit unit) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.writeAccountSetting(
      AccountSettingKeys.preferredUnit,
      unit.name,
    );
    state = unit;
    UnitFormat.unit = unit;
    // 账号级偏好改动：联网时立即上行，其他设备与后台口径随之同步
    unawaited(SyncService.autoSync(storage));
  }
}

/// PRD §2.2 当日动物形象
final dailyAnimalProvider = FutureProvider<AnimalCharacter>((ref) async {
  final storage = await ref.read(localStorageProvider.future);
  return storage.pickOrLoadDailyAnimal();
});

/// 首页聚合状态：当前进度 / 剩余 / 完成率
final dailyProgressProvider = Provider<DailyProgress>((ref) {
  final profile = ref.watch(profileProvider);
  final entries = ref.watch(todayEntriesProvider);
  final goalMl = profile?.dailyGoalMl ?? 2000;
  return DailyProgress(
    goalMl: goalMl,
    totalEffectiveMl: HydrationCalculator.sumEffective(entries),
    totalVolumeMl: HydrationCalculator.sumVolume(entries),
    entries: entries,
    progress: HydrationCalculator.progress(entries, goalMl),
    remaining: HydrationCalculator.remaining(entries, goalMl),
  );
});

class DailyProgress {
  const DailyProgress({
    required this.goalMl,
    required this.totalEffectiveMl,
    required this.totalVolumeMl,
    required this.entries,
    required this.progress,
    required this.remaining,
  });
  final int goalMl;
  final int totalEffectiveMl;
  final int totalVolumeMl;
  final List<DrinkEntry> entries;
  final double progress;
  final int remaining;

  bool get isComplete => progress >= 1.0;
}
