import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'core/crash/crash_reporter.dart';
import 'core/sync/container_icon_sync.dart';
import 'core/sync/character_sync.dart';
import 'core/sync/sync_api.dart';

import 'features/settings/settings_flags.dart';
import 'features/settings/widget_background.dart';

/// PRD §1.3 前端层入口
/// M1：脚手架；M2：首页养成核心 + 饮水录入；M3：统计 + 提醒 + 设置
Future<void> main() async {
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
  // 保证渲染层首帧就能读到持久化的开关状态。
  // 必须 await：LogicalDay 的「一天重置时刻」口径来自这里，未加载完就
  // 查库会把重置时刻当作 00:00，跨重置点的那几秒会算错归属日
  await SettingsFlags.instance.ensureLoaded();
  // 统计页 DateFormat 使用 zh 语言环境，需预载符号表
  initializeDateFormatting('zh');
  // 小组件饮料格后台录入回调：注册后点按饮品格由广播在 headless 引擎
  // 内直接写库刷新桌面，无需启动 App（仅 Android 有桌面小组件）
  if (!kIsWeb && Platform.isAndroid) {
    registerHomeWidgetBackgroundCallback();
  }
  // 接口地址可由设置页运行时修改，启动前先读回已保存的值
  await SyncApi.loadFromPrefs();
  // 未捕获异常上报：内测阶段收集崩溃/报错，release 包才上报
  CrashReporter.init();
  // 云端容器图标缓存：准备本地目录并读回上次同步结果，
  // 首帧渲染图标时即可判断用本地缓存还是安装包内置资源
  await ContainerIconStore.init();
  // 云端角色目录缓存：分类/角色列表与 SVG 素材同样离线优先
  await CharacterStore.init();
  runApp(const ProviderScope(child: WaterLlamaApp()));
}
