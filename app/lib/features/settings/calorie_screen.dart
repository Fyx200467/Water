import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../shared/widgets/app_back_button.dart';
import '../../shared/widgets/app_switch.dart';
import 'settings_flags.dart';

// ============================================================
// 卡路里设置页（角色插画 + 跟踪卡路里开关）
//
// 1. 返回圆钮 + 居中大标题「卡路里」+ 羊驼插画
// 2. 白卡：跟踪卡路里开关（青色）+ 说明小字
// 开关状态经 SettingsFlags 持久化，设置页「卡路里」行角标、
// 历史页「热量」指标页签与饮品录入页的卡路里文案均随之联动
// ============================================================

class CalorieScreen extends StatefulWidget {
  const CalorieScreen({super.key});

  @override
  State<CalorieScreen> createState() => _CalorieScreenState();
}

class _CalorieScreenState extends State<CalorieScreen> {
  static const _textDark = Color(0xFF1C1C1E);

  @override
  void initState() {
    super.initState();
    SettingsFlags.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
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
                  child: const Align(
                    alignment: Alignment.centerLeft,
                    child: AppBackButton(),
                  ),
                ),
                const SizedBox(height: 10),
                const Center(
                  child: Text('卡路里',
                      style: TextStyle(
                          color: _textDark,
                          fontSize: 28,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 12),
                // 羊驼插画（复用角色资产 alpaca）
                Center(
                  child: SvgPicture.asset(
                    'assets/images/characters/alpaca.svg',
                    width: 190,
                    height: 190,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 22),
                // 跟踪卡路里卡
                ListenableBuilder(
                  listenable: SettingsFlags.instance,
                  builder: (ctx, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text('跟踪卡路里',
                                    style: TextStyle(
                                        color: _textDark,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800)),
                              ),
                              AppSwitch(
                                value: SettingsFlags.instance.trackCalories,
                                onChanged: (v) => SettingsFlags.instance
                                    .save(trackCalories: v),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '每种添加饮料旁边都显示了卡路里含量。',
                            style: TextStyle(
                                color: const Color(0xFF3C3C43)
                                    .withValues(alpha: 0.6),
                                fontSize: 13,
                                height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 卡路里羊驼（食物热量跟踪）尚未实现，先不展示推广入口，
                // 避免用户打开一个没有任何实际作用的开关
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
