import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../membership/membership_provider.dart';
import 'character_catalog.dart';

/// 当前选中角色（首页液体填充用）
///
/// 业务规则（PRD §2.3）：
/// - 默认值 'alpaca'
/// - 持久化到 SharedPreferences，App 重启后保持上次选择
class CurrentCharacterNotifier extends StateNotifier<String> {
  CurrentCharacterNotifier(this.ref) : super('alpaca') {
    _load();
  }

  final Ref ref;
  static const _key = 'current_character_id';

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final saved = storage.prefs.getString(_key);
    if (saved != null && saved.isNotEmpty) {
      state = saved;
    }
  }

  /// 切换当前角色（仅接受已注册的 animalId）
  Future<void> select(String animalId) async {
    state = animalId;
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(_key, animalId);
  }
}

final currentCharacterProvider =
    StateNotifierProvider<CurrentCharacterNotifier, String>((ref) {
  return CurrentCharacterNotifier(ref);
});

/// 实际生效的填充角色：非会员时若选中的是会员专属角色，回退到默认羊驼。
///
/// 退出登录 / 账号被挤下线后会员权益立即失效，首页不会继续展示
/// 上一个会员账号使用的专属角色。
final effectiveCurrentCharacterProvider = Provider<String>((ref) {
  final selected = ref.watch(currentCharacterProvider);
  if (ref.watch(membershipProvider).isMember) return selected;
  final catalog = ref.watch(characterCatalogProvider).asData?.value;
  if (catalog != null && catalog.isMemberOnly(selected)) return 'alpaca';
  return selected;
});
