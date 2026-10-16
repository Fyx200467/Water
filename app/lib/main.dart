import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'features/settings/settings_flags.dart';

/// PRD §1.3 前端层入口
/// M1：脚手架；M2：首页养成核心 + 饮水录入；M3：统计 + 提醒 + 设置
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 状态栏透明 + 关闭系统对比度蒙层：App 处于 edge-to-edge 模式（内容
  // 延伸到状态栏后面），部分 ROM（如 vivo）默认在状态栏区域强制画一层
  // 半透明灰色 scrim 保证图标对比度，白底页面上呈现为顶部一条阴影。
  // 各页 AnnotatedRegion 只改图标亮度（statusBarColor 为 null 不覆盖），
  // 此处一次性声明的透明状态栏全程生效
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
  ));
  // 设置开关（动画/卡路里/重置时间等）启动即加载，
  // 保证渲染层首帧就能读到持久化的开关状态
  SettingsFlags.instance.ensureLoaded();
  // 统计页 DateFormat 使用 zh 语言环境，需预载符号表
  initializeDateFormatting('zh');
  runApp(const ProviderScope(child: WaterLlamaApp()));
}
