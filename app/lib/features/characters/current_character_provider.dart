import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';

/// 当前选中角色（首页液体填充用）
///
/// 业务规则（PRD §2.3）：
/// - 默认值 'alpaca'（非会员主页固定角色）
/// - 主页角色自由切换需要会员资格；非会员只能用 'alpaca'
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
