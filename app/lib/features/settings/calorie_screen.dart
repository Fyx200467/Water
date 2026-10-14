import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'settings_flags.dart';

// ============================================================
// 卡路里设置页（对标原版：角色插画 + 跟踪卡路里卡 + 卡路里羊驼推广卡）
//
// 1. 返回圆钮 + 居中大标题「卡路里」+ 羊驼插画
// 2. 白卡：跟踪卡路里开关（青色）+ 说明小字
// 3. 浅青推广卡：小图标 + 文案（卡路里羊驼 高亮青色）+ 开关
//    + AI 跟踪说明 + 好评数
// 开关状态经 SettingsFlags 持久化，设置页「卡路里」行角标实时同步
// ============================================================

class CalorieScreen extends StatefulWidget {
  const CalorieScreen({super.key});

  @override
  State<CalorieScreen> createState() => _CalorieScreenState();
}

class _CalorieScreenState extends State<CalorieScreen> {
  static const _cyan = Color(0xFF35B5D6);
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
                              Transform.scale(
                                scale: 0.9,
                                child: Switch(
                                  value:
                                      SettingsFlags.instance.trackCalories,
                                  onChanged: (v) => SettingsFlags.instance
                                      .save(trackCalories: v),
                                  activeTrackColor: _cyan,
                                  activeThumbColor: Colors.white,
                                  inactiveThumbColor: Colors.white,
                                  inactiveTrackColor:
                                      const Color(0xFFE5E5EA),
                                ),
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
                // 短分隔线
                Center(
                  child: Container(
                    width: 56,
                    height: 1,
                    margin: const EdgeInsets.symmetric(vertical: 26),
                    color: const Color(0xFFE5E5EA),
                  ),
                ),
                // 卡路里羊驼推广卡
                ListenableBuilder(
                  listenable: SettingsFlags.instance,
                  builder: (ctx, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4F7F2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // 小图标（白色圆角块 + 羊驼）
                              Container(
                                width: 44,
                                height: 44,
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SvgPicture.asset(
                                  'assets/images/characters/alpaca.svg',
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    style: const TextStyle(
                                        color: _textDark,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        height: 1.4),
                                    children: [
                                      const TextSpan(
                                          text: '同时，还可以使用 '),
                                      const TextSpan(
                                          text: '卡路里羊驼',
                                          style: TextStyle(color: _cyan)),
                                      const TextSpan(
                                          text:
                                              ' 跟踪食物中的卡路里含量'),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Transform.scale(
                                scale: 0.9,
                                child: Switch(
                                  value:
                                      SettingsFlags.instance.foodCalories,
                                  onChanged: (v) => SettingsFlags.instance
                                      .save(foodCalories: v),
                                  activeTrackColor: _cyan,
                                  activeThumbColor: Colors.white,
                                  inactiveThumbColor: Colors.white,
                                  inactiveTrackColor:
                                      const Color(0xFFE5E5EA),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '拍张照片，用 AI 跟踪卡路里。个人的减肥、维持体重或增重计划。',
                            style: TextStyle(
                                color: const Color(0xFF3C3C43)
                                    .withValues(alpha: 0.65),
                                fontSize: 13,
                                height: 1.5),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '1,000 多个5星好评。',
                            style: TextStyle(
                                color: const Color(0xFF3C3C43)
                                    .withValues(alpha: 0.65),
                                fontSize: 13,
                                height: 1.5),
                          ),
                        ],
                      ),
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
