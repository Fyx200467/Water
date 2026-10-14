import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'settings_flags.dart';

// ============================================================
// App、声音、动画设置页（对标原版：5 张灰卡，每卡 = 标题 + 青色开关 + 说明小字）
//
// 1. 每日回顾 —— 达成目标后，快速查看当天的饮品摄入回顾
// 2. 庆祝我的一天！ —— 饮水目标完成后，主屏幕上会显示"庆祝我的一天！"按钮
// 3. App 声音 —— 在 App 中播放简单的声音，例如当你饮水、完成目标或挑战时。
// 4. 小部件声音 —— 从小部件添加饮料时发出声音
// 5. 杯子里的动画 —— 动画粒子，如：气泡、冰块、茶叶
// 开关状态经 SettingsFlags 持久化（默认全开）
// ============================================================

class AppPrefsScreen extends StatefulWidget {
  const AppPrefsScreen({super.key});

  @override
  State<AppPrefsScreen> createState() => _AppPrefsScreenState();
}

class _AppPrefsScreenState extends State<AppPrefsScreen> {
  static const _cyan = Color(0xFF35B5D6);
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
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: _cyan,
              activeThumbColor: Colors.white,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFFE5E5EA),
            ),
          ),
        ],
      ),
    );
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE9E9EC),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.chevron_left,
                            color: Color(0xFF5A5A60), size: 28),
                      ),
                    ),
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
                        _card('每日回顾', '达成目标后，快速查看当天的饮品摄入回顾',
                            f.dailyReview,
                            (v) => f.save(dailyReview: v)),
                        const SizedBox(height: 14),
                        _card(
                            '庆祝我的一天！',
                            '饮水目标完成后，主屏幕上会显示"庆祝我的一天！"按钮',
                            f.celebrateDay,
                            (v) => f.save(celebrateDay: v)),
                        const SizedBox(height: 14),
                        _card('App 声音',
                            '在 App 中播放简单的声音，例如当你饮水、完成目标或挑战时。',
                            f.appSounds, (v) => f.save(appSounds: v)),
                        const SizedBox(height: 14),
                        _card('小部件声音', '从小部件添加饮料时发出声音', f.widgetSounds,
                            (v) => f.save(widgetSounds: v)),
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
