import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/beverage.dart';
import '../../shared/widgets/drink_illustration.dart';
import '../drink/screens/add_drink_screen.dart';
import '../onboarding/widgets/animal_silhouette.dart';
import '../stats/history_screen.dart';
import '../stats/providers/stats_providers.dart';
import 'providers/home_providers.dart';

/// PRD §2.2 首页（对标原版 WaterLlama 主页）
///
/// 布局（自上而下）：
/// 1. 顶部：左上"1 天"青色圆形徽章 + 右上菜单按钮
/// 2. 核心数据：青色大字"{totalMl}" + 灰色"进水量·{percent}% 的目标"
/// 3. 中央：大羊驼剪影（空杯态浅灰 + 按进度纯青色填充 + 波浪水面晃动）
/// 4. 底部操作栏：水杯按钮(+) / "+98 种物品和功能"胶囊 / 羊驼头像(+)
/// 5. 最底部：浅青色圆角横幅"滴酒不沾的十月"挑战
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // 品牌色规范
  static const _brandCyan = Color(0xFF4DB8D8);
  static const _hintGray = Color(0xFF8E8E93);

  /// 底部水平滚动饮品快捷栏：水 / +98物品胶囊 / 羊驼卢娜 / 各类饮品（锁定的带锁）
  Widget _buildDrinkBar() {
    final member = ref.watch(memberProvider);
    final drinks = Beverage.presets
        .where((b) => b.id != 'water_pure' && (!b.memberOnly || member.isValid))
        .take(8)
        .toList();

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // 1. 水（青色玻璃杯大插画 + 底部 ⊕ 徽章）
        _DrinkItem(
          beverageId: 'water_pure',
          label: '水',
          color: _brandCyan,
          highlight: true,
          badgeIcon: Icons.add,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddDrinkScreen()),
          ),
        ),
        // 2. "+98 种物品和功能"胶囊
        const _ItemsChip(),
        // 3. 羊驼卢娜头像
        _DrinkItem(
          beverageId: 'llama',
          label: '羊驼卢娜',
          color: const Color(0xFF8B6F47),
          bg: const Color(0xFFF5E6D3),
          badgeIcon: Icons.refresh,
          onTap: () {},
        ),
        // 4. 各类饮品
        for (final b in drinks)
          _DrinkItem(
            beverageId: b.id,
            label: b.name,
            color: b.category.color,
            locked: b.memberOnly,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddDrinkScreen()),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(dailyProgressProvider);
    final streak = ref.watch(streakProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        // Stack 结构：顶部按钮悬浮于内容之上，内容可滚动（后续功能卡片）
        child: Stack(
          children: [
            // 底层：可滚动内容（IntrinsicHeight 让羊驼区弹性撑开、挑战横幅贴底；
            // 内容超过一屏后可下滑——为后续功能卡片预留）
            Positioned.fill(
              child: LayoutBuilder(
                builder: (ctx, cons) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: cons.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          // 给悬浮按钮留出空间
                          const SizedBox(height: 64),
                          // 1. 核心数据：大字饮水量 + 进度百分比
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              children: [
                                Text(
                                  '${progress.totalEffectiveMl}ml',
                                  style: const TextStyle(
                                    color: _brandCyan,
                                    fontSize: 56,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '进水量 · ${(progress.progress * 100).round()}% 的目标',
                                  style: const TextStyle(color: _hintGray, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 2. 中央：大羊驼剪影（弹性区域撑开）
                          Expanded(
                            child: Center(
                              child: AnimalSilhouette(
                                animalId: 'llama',
                                fillRatio: progress.progress.clamp(0.0, 1.0),
                                accentColor: _brandCyan,
                                solidFillColor: _brandCyan,
                                size: 280,
                                // 目标未完成时只显示轮廓剪影，完成后点亮全彩插画
                                fullArt: progress.isComplete,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 3. 底部操作栏：水平滚动的饮品快捷栏（对标原版）
                          SizedBox(
                            height: 96,
                            child: _buildDrinkBar(),
                          ),
                          // 4. 挑战横幅（贴底）
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                            child: _ChallengeBanner(
                              title: '滴酒不沾的十月',
                              onTap: () => context.push('/stats'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 顶层：悬浮按钮（不随内容滚动）
            Positioned(
              top: 8,
              left: 20,
              right: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 左上角：连续签到徽章 → 打开历史记录页
                  streak.maybeWhen(
                    data: (s) => _DayBadge(
                      days: s.current,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const HistoryScreen()),
                      ),
                    ),
                    orElse: () => const _DayBadge(days: 0, onTap: null),
                  ),
                  // 右上角：菜单按钮
                  IconButton(
                    icon: const Icon(Icons.menu, color: _hintGray),
                    onPressed: () => context.push('/settings'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 左上角"N 天"青色圆形徽章（点击打开历史记录页）
class _DayBadge extends StatelessWidget {
  const _DayBadge({required this.days, this.onTap});
  final int days;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF4DB8D8),
          borderRadius: BorderRadius.circular(20),
        ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$days',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          const Text(
            '天',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
      ),
    );
  }
}

/// 饮品快捷项：圆底图标 + 标签（锁定项右下角小锁徽章）
class _DrinkItem extends StatelessWidget {
  const _DrinkItem({
    required this.beverageId,
    required this.label,
    required this.color,
    required this.onTap,
    this.bg,
    this.locked = false,
    this.highlight = false,
    this.badgeIcon,
  });
  final String beverageId;
  final String label;
  final Color color;
  final Color? bg;
  final VoidCallback onTap;
  final bool locked;
  final bool highlight;

  /// 底部中央徽章图标（如水的 ⊕、羊驼的 ↻）；锁定项自动显示锁
  final IconData? badgeIcon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 对标原版：无圆底，饮品插画独立大图直接立在白色背景上
            SizedBox(
              width: 52,
              height: 56,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  DrinkIllustration(
                    beverageId: beverageId,
                    color: color,
                    size: 52,
                    highlight: highlight,
                  ),
                  // 底部中央徽章：锁定项灰底白锁，水的 ⊕ 用品牌色
                  if (locked)
                    Positioned(
                      bottom: -2,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: const Color(0xFF9E9E9E).withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(Icons.lock,
                            size: 11, color: Colors.white),
                      ),
                    )
                  else if (badgeIcon != null)
                    Positioned(
                      bottom: -2,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Icon(badgeIcon,
                            size: 12, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: highlight ? color : const Color(0xFF8E8E93),
                fontSize: 12,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "+98 种物品和功能"白色虚线胶囊按钮
class _ItemsChip extends StatelessWidget {
  const _ItemsChip();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Center(
        child: Container(
          width: 120,
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: const Color(0xFFD8D8DC),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xFFF2F2F5),
                  shape: BoxShape.circle,
                ),
                child: const DrinkIllustration(
                    beverageId: 'llama',
                    color: Color(0xFF6B6B70),
                    size: 22,
                  ),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '+98 种物品和功能',
                  style: TextStyle(
                    color: Color(0xFF6B6B70),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部挑战横幅（浅青色圆角矩形 + 两侧图标 + 标题）
class _ChallengeBanner extends StatelessWidget {
  const _ChallengeBanner({required this.title, required this.onTap});
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFE0F4F8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // 左侧羽毛/月亮图标
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.nightlight,
                color: Color(0xFF4DB8D8),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            // 标题
            const Expanded(
              child: Text(
                '滴酒不沾的十月',
                style: TextStyle(
                  color: Color(0xFF1C1C1E),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // 右侧饮品图标（带禁止斜线）
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.no_drinks,
                color: Color(0xFFE05252),
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
