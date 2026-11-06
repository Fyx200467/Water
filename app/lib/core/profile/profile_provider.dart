import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/user_profile.dart';
import '../storage/providers.dart';
import '../sync/profile_sync.dart';

/// PRD §2.1 用户档案
final profileProvider = StateNotifierProvider<ProfileNotifier, UserProfile?>((
  ref,
) {
  return ProfileNotifier(ref);
});

class ProfileNotifier extends StateNotifier<UserProfile?> {
  ProfileNotifier(this.ref, {UserProfile? initial}) : super(initial) {
    // 仅当未预加载时才异步读取（避免覆盖 main.dart 预加载的初始值）
    loaded = initial == null ? _load() : Future<void>.value();
  }
  final Ref ref;

  /// 磁盘加载完成信号：完成前 state 为 null。小组件后台录入回调若不
  /// 等待它，目标值会走 2000 兜底 → 桌面百分比虚高（如 56% vs App 53%）
  late final Future<void> loaded;

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    state = storage.loadProfile();
  }

  Future<void> save(UserProfile p) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.saveProfile(p);
    state = p;
    // 档案改了：立刻上行到服务端，后台用户列表 / 打卡明细与 App 保持一致
    unawaited(ProfileSync.pushProfile(storage));
  }

  Future<void> updateGoal(int newGoal) async {
    final cur = state;
    if (cur == null) return;
    final next = cur.copyWith(dailyGoalMl: newGoal.clamp(1000, 5000));
    await save(next);
  }

}
