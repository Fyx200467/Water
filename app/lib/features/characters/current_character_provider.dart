import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/account_settings.dart';
import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../home/providers/home_providers.dart';
import '../membership/membership_provider.dart';
import 'character_catalog.dart';

/// 当前选中角色（首页液体填充用）
///
/// 业务规则（PRD §2.3）：
/// - 默认值 'sheep'（游客首次使用即点亮绵羊）
/// - 持久化到账号级偏好，App 重启 / 换设备后保持上次选择
class CurrentCharacterNotifier extends StateNotifier<String> {
  CurrentCharacterNotifier(this.ref) : super('sheep') {
    _load();
  }

  final Ref ref;

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final saved = storage
        .readAccountSetting(AccountSettingKeys.currentCharacter)
        ?.toString();
    if (saved != null && saved.isNotEmpty) {
      state = saved;
    }
  }

  /// 切换当前角色（仅接受已注册的 animalId）
  Future<void> select(String animalId) async {
    state = animalId;
    final storage = await ref.read(localStorageProvider.future);
    await storage.writeAccountSetting(
      AccountSettingKeys.currentCharacter,
      animalId,
    );
    unawaited(SyncService.autoSync(storage));
  }
}

final currentCharacterProvider =
    StateNotifierProvider<CurrentCharacterNotifier, String>((ref) {
      // 会话切换 / 云端偏好更新后按新归属重载
      ref.watch(sessionEpochProvider);
      ref.watch(accountSettingsRevisionProvider);
      return CurrentCharacterNotifier(ref);
    });

/// 实际生效的填充角色：非会员时若选中的是会员专属角色，回退到默认绵羊。
///
/// 退出登录 / 账号被挤下线后会员权益立即失效，首页不会继续展示
/// 上一个会员账号使用的专属角色。
final effectiveCurrentCharacterProvider = Provider<String>((ref) {
  final selected = ref.watch(currentCharacterProvider);
  if (ref.watch(membershipProvider).isMember) return selected;
  final catalog = ref.watch(characterCatalogProvider).asData?.value;
  if (catalog != null && catalog.isMemberOnly(selected)) return 'sheep';
  return selected;
});
