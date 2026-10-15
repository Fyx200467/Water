import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../characters/character_art.dart';
import 'providers/home_providers.dart';

/// 今日回顾（对标原版 WaterLlama 庆祝流程，两张截图两步跳转）：
/// 1. DailyReviewScreen —— 全屏庆祝海报（我的清晰星期四 + 描边横幅 + 大角色剪影
///    + 目标量 + 页脚），停留 1.5 秒后自动跳转分享页
/// 2. SharePosterScreen —— 中央海报缩略卡 + 社交分享按钮组（信息/Messenger/
///    Instagram/Facebook，调起系统分享面板）
///
/// 入口：首页完成态轮播条点击任一页。
class DailyReviewScreen extends ConsumerStatefulWidget {
  const DailyReviewScreen({super.key, required this.animalId});

  final String animalId;

  @override
  ConsumerState<DailyReviewScreen> createState() => _DailyReviewScreenState();
}

class _DailyReviewScreenState extends ConsumerState<DailyReviewScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 海报页展示 1.5 秒后自动跳转到分享页（对标原版节奏）
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SharePosterScreen(animalId: widget.animalId),
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final goal = ref.watch(profileProvider)?.dailyGoalMl ?? 2000;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: PosterView(animalId: widget.animalId, goalMl: goal),
          ),
        ),
      ),
    );
  }
}

/// 庆祝海报内容（公共组件）：
/// 海报页以全尺寸直接渲染；分享页用 FittedBox 等比缩小嵌入卡片。
/// 设计基准尺寸 340×640，内部按比例布局。
class PosterView extends StatelessWidget {
  const PosterView({super.key, required this.animalId, required this.goalMl});

  final String animalId;
  final int goalMl;

  static const _cyan = Color(0xFF45B7D8);

  String _weekday() {
    const names = [
      '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日',
    ];
    return names[DateTime.now().weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340,
      height: 640,
      child: Column(
        children: [
          const SizedBox(height: 24),
          // 标题：我的「清晰」星期四（动态星期X）
          Text.rich(
            TextSpan(
              style: const TextStyle(
                color: _cyan,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
              children: [
                const TextSpan(text: '我的', style: TextStyle(fontSize: 42)),
                const TextSpan(text: '清晰', style: TextStyle(fontSize: 64)),
                TextSpan(text: '\n${_weekday()}', style: const TextStyle(fontSize: 64)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 描边横幅：角色头像 + 「今天主打纯净补水，干得漂亮！」
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _cyan, width: 1.6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CharacterArt(animalId: animalId, unlocked: true, size: 26),
                const SizedBox(width: 8),
                const Text(
                  '今天主打纯净补水，干得漂亮！',
                  style: TextStyle(
                    color: _cyan,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 大号青色角色剪影（点亮态纯色渲染）
          Expanded(
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(_cyan, BlendMode.srcIn),
              child: CharacterArt(animalId: animalId, unlocked: false, size: 300),
            ),
          ),
          // 目标量行：彩色小羊驼 + 青色水杯 + 「ml 2000」
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/animal_llama_full.png',
                width: 46,
                height: 46,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 6),
              Icon(Icons.local_drink_rounded, color: _cyan, size: 30),
              const SizedBox(width: 4),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    color: _cyan,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                  children: [
                    const TextSpan(text: 'ml\n', style: TextStyle(fontSize: 15)),
                    TextSpan(text: '$goalMl', style: const TextStyle(fontSize: 34)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 页脚：站点名 + 标语
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Waterllama.com  ',
                style: TextStyle(
                  color: Color(0xFF1C1C1E),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '保持充足的水分，拥有快乐的心情！',
                style: TextStyle(color: _cyan, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

/// 分享页（对标原版第四张截图）：
/// 右上角关闭圆钮 + 中央海报缩略卡（灰描边）+ 提及文案 + 4 个社交分享按钮。
/// 按钮点击调起系统分享面板（share_plus 分享庆祝文案）。
class SharePosterScreen extends ConsumerWidget {
  const SharePosterScreen({super.key, required this.animalId});

  final String animalId;

  static const _cyan = Color(0xFF45B7D8);

  Future<void> _share(int goalMl) async {
    await SharePlus.instance.share(
      ShareParams(
        text: '我在 Waterlllama 达成了今日 $goalMl ml 饮水目标！'
            '保持充足的水分，拥有快乐的心情！ Waterllama.com',
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(profileProvider)?.dailyGoalMl ?? 2000;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      body: SafeArea(
        child: Stack(
          children: [
            // 主体内容（可滚动，小屏不溢出）
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    // 海报缩略卡（灰描边白底，内嵌等比缩小的海报）
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFE2E2E7),
                          width: 1.5,
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: 250,
                          height: 470,
                          child: PosterView(
                            animalId: animalId,
                            goalMl: goal,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // 提及文案
                    const Text(
                      '要分享到社交媒体？🤗 提及我们，我们将回复你！',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF1C1C1E),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '@waterllama_app',
                      style: TextStyle(
                        color: _cyan,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 四个社交分享按钮（调起系统分享面板）
                    _shareButton(
                      bg: const Color(0xFFDCF8E6),
                      icon: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Color(0xFF34C759),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chat_bubble_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      label: '信息',
                      color: const Color(0xFF1DA84C),
                      onTap: () => _share(goal),
                    ),
                    const SizedBox(height: 12),
                    _shareButton(
                      bg: const Color(0xFFECEBFF),
                      icon: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF00B2FF), Color(0xFF006AFF)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.bolt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      label: 'Messenger',
                      color: const Color(0xFF006AFF),
                      onTap: () => _share(goal),
                    ),
                    const SizedBox(height: 12),
                    _shareButton(
                      bg: const Color(0xFFFBDDF0),
                      icon: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFFFEDA75),
                              Color(0xFFD62976),
                              Color(0xFF962FBF),
                            ],
                            begin: Alignment.bottomLeft,
                            end: Alignment.topRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      label: 'Instagram',
                      color: const Color(0xFFC13584),
                      onTap: () => _share(goal),
                    ),
                    const SizedBox(height: 12),
                    _shareButton(
                      bg: const Color(0xFFE3EDFF),
                      icon: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1877F2),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text(
                            'f',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                      label: 'Facebook',
                      color: const Color(0xFF1877F2),
                      onTap: () => _share(goal),
                    ),
                  ],
                ),
              ),
            ),
            // 右上角关闭圆钮
            Positioned(
              top: 8,
              right: 20,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4E4E9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 分享按钮：浅色底大胶囊 + 彩色平台图标 + 平台色文字
  Widget _shareButton({
    required Color bg,
    required Widget icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
