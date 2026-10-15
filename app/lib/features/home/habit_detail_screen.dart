import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'habit_module.dart';

/// 习惯挑战详情页（对标原版录屏：点击习惯卡后底部滑入）
///
/// 结构与挑战详情页同构：
/// - 彩色头部：•••/× 悬浮圆钮 +「10 天挑战」标签 + 大标题 + 副标题
///   +「告诉朋友」胶囊 + 右侧角色插画压边裁剪
/// - 白色正文：介绍段落 →「好处」→ emoji 好处段落 →「要做的事情」
/// - 底部悬浮「立即开始」胶囊（参加后变绿「挑战进行中」，全局联动）
class HabitDetailScreen extends StatelessWidget {
  const HabitDetailScreen({super.key, required this.habit});

  final HabitData habit;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 滚动正文（含彩色头部）
          Positioned.fill(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(habit: habit, topPad: topPad),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 140),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          habit.intro,
                          style: const TextStyle(
                            color: Color(0xFF1C1C1E),
                            fontSize: 16,
                            height: 1.65,
                          ),
                        ),
                        const SizedBox(height: 36),
                        Text(
                          '好处',
                          style: TextStyle(
                            color: habit.bg,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final (emoji, text) in habit.benefits) ...[
                          Text.rich(
                            TextSpan(
                              text: '$emoji ',
                              style: const TextStyle(fontSize: 16, height: 1.65),
                              children: [
                                TextSpan(
                                  text: text,
                                  style: const TextStyle(
                                    color: Color(0xFF1C1C1E),
                                    fontSize: 16,
                                    height: 1.65,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        const SizedBox(height: 22),
                        Text(
                          '要做的事情',
                          style: TextStyle(
                            color: habit.bg,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          habit.todo,
                          style: const TextStyle(
                            color: Color(0xFF1C1C1E),
                            fontSize: 16,
                            height: 1.65,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 顶部悬浮圆钮（••• / ×）
          Positioned(
            top: topPad + 8,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _roundBtn(Icons.more_horiz, null),
                  _roundBtn(Icons.close, () => Navigator.of(context).maybePop()),
                ],
              ),
            ),
          ),
          // 底部悬浮「立即开始」胶囊（参加后变绿，全局状态联动）
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 20,
            child: Center(
              child: ValueListenableBuilder<Set<String>>(
                valueListenable: habitsJoined,
                builder: (context, joined, _) {
                  final isJoined = joined.contains(habit.title);
                  return GestureDetector(
                    onTap: isJoined ? null : () => joinHabit(habit.title),
                    child: Container(
                      height: 58,
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      decoration: BoxDecoration(
                        color: isJoined
                            ? const Color(0xFF23A06A)
                            : const Color(0xFF1C1C22),
                        borderRadius: BorderRadius.circular(29),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 小角色头像
                          Container(
                            width: 34,
                            height: 34,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: const BoxDecoration(
                              color: Colors.white24,
                              shape: BoxShape.circle,
                            ),
                            clipBehavior: Clip.antiAlias,
                            alignment: Alignment.center,
                            child: SvgPicture.asset(
                              habit.asset,
                              width: 26,
                              height: 26,
                              fit: BoxFit.contain,
                            ),
                          ),
                          Text(
                            isJoined ? '挑战进行中' : '立即开始',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (isJoined) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.check_rounded,
                                color: Colors.white, size: 20),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.22),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

/// 彩色头部：标签 + 大标题 + 副标题 + 告诉朋友 + 右侧角色压边
class _Header extends StatelessWidget {
  const _Header({required this.habit, required this.topPad});

  final HabitData habit;
  final double topPad;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 350,
      // 角色超出头部范围的部分直接裁剪
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: habit.bg),
      child: Stack(
        children: [
          // 角色插画：右下角压边裁剪
          Positioned(
            right: -80,
            bottom: -46,
            child: SizedBox(
              width: 280,
              height: 280,
              child: SvgPicture.asset(habit.asset, fit: BoxFit.contain),
            ),
          ),
          // 文案层
          Padding(
            padding: EdgeInsets.fromLTRB(24, topPad + 78, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '10 天挑战',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  habit.title.replaceAll('\n', ''),
                  maxLines: 2,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  habit.subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                // 告诉朋友（调起系统分享）
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(23),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.card_giftcard,
                            color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '告诉朋友',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
