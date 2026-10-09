import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_storage.dart';

/// 单例 LocalStorage 提供者
final localStorageProvider = FutureProvider<LocalStorage>((ref) async {
  return LocalStorage.init();
});
