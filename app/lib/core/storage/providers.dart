import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_storage.dart';

/// 单例 LocalStorage 提供者
final localStorageProvider = FutureProvider<LocalStorage>((ref) async {
  return LocalStorage.init();
});

/// 数据/同步版本号：本地写入或一轮同步结束后自增。
/// 「待同步 N 条」「上次同步时间」这类状态型 provider 依赖它，
/// 否则只在启动/登录时算一次，同步完成后仍显示旧快照
final syncRevisionProvider = StateProvider<int>((ref) => 0);
