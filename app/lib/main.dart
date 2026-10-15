import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'features/settings/settings_flags.dart';

/// PRD §1.3 前端层入口
/// M1：脚手架；M2：首页养成核心 + 饮水录入；M3：统计 + 提醒 + 设置
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 设置开关（动画/卡路里/重置时间等）启动即加载，
  // 保证渲染层首帧就能读到持久化的开关状态
  SettingsFlags.instance.ensureLoaded();
  // 统计页 DateFormat 使用 zh 语言环境，需预载符号表
  initializeDateFormatting('zh');
  runApp(const ProviderScope(child: WaterLlamaApp()));
}
