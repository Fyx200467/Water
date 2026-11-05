import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import '../../shared/widgets/app_back_button.dart';
import '../../shared/widgets/app_switch.dart';
import 'settings_flags.dart';

// ============================================================
// App、声音、动画设置页（对标原版：4 张灰卡，每卡 = 标题 + 青色开关 + 说明小字）
//
// 1. 告诉我的朋友 —— 饮水目标完成后，主屏幕上显示"告诉我的朋友"按钮
//    （关闭后首页完成目标时的分享横幅整体隐藏）
// 2. App 声音 —— 在 App 中播放简单的声音（完成目标、弹弓命中时）
// 3. 小部件声音 —— 从小部件添加饮料时发出声音（原生点按即时播放）
// 4. 杯子里的动画 —— 动画粒子，如：气泡、冰块、茶叶（总开关，所有杯子预览生效）
// 开关状态经 SettingsFlags 持久化（默认全开）
// ============================================================

class AppPrefsScreen extends StatefulWidget {
  const AppPrefsScreen({super.key});

  @override
  State<AppPrefsScreen> createState() => _AppPrefsScreenState();
}

class _AppPrefsScreenState extends State<AppPrefsScreen> {
  static const _textDark = Color(0xFF1C1C1E);

  @override
  void initState() {
    super.initState();
    SettingsFlags.instance.ensureLoaded();
  }

  /// 单张设置卡：标题（左）+ 青色开关（右）+ 说明小字（标题下方跨全宽）
  Widget _card(
    String title,
    String desc,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: _textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(desc,
                    style: TextStyle(
                        color: const Color(0xFF3C3C43).withValues(alpha: 0.6),
                        fontSize: 15,
                        height: 1.45)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  /// 开关同步到原生小组件偏好：点按小组件时 QuickAddReceiver 直接读取该键
  /// 决定是否播放提示音（不经过 Dart 引擎）
  Future<void> _syncWidgetSound(bool on) async {
    try {
      await HomeWidget.saveWidgetData<bool>('widget_sounds', on);
    } catch (_) {
      // 非 Android / 插件不可用时静默
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = SettingsFlags.instance;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AppBackButton(),
                  ),
                ),
                const SizedBox(height: 10),
                const Center(
                  child: Text('App、声音、动画',
                      style: TextStyle(
                          color: _textDark,
                          fontSize: 28,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 18),
                ListenableBuilder(
                  listenable: f,
                  builder: (ctx, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        _card(
                            '告诉我的朋友',
                            '饮水目标完成后，主屏幕上会显示"告诉我的朋友"按钮',
                            f.celebrateDay,
                            (v) => f.save(celebrateDay: v)),
                        const SizedBox(height: 14),
                        _card('App 声音',
                            '在 App 中播放简单的声音，例如完成目标、弹弓命中时。',
                            f.appSounds, (v) => f.save(appSounds: v)),
                        const SizedBox(height: 14),
                        _card('小部件声音', '从小部件添加饮料时发出声音', f.widgetSounds,
                            (v) {
                          f.save(widgetSounds: v);
                          _syncWidgetSound(v);
                        }),
                        const SizedBox(height: 14),
                        _card('杯子里的动画', '动画粒子，如：气泡、冰块、茶叶',
                            f.cupAnimations,
                            (v) => f.save(cupAnimations: v)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
