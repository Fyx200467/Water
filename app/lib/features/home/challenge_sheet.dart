import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'challenge_detail_screen.dart';

/// 挑战参加状态持久化 key
const String _kChallengeJoinedKey = 'challenge_joined_oct';

/// 挑战参加状态全局通知器：首页挑战卡与详情页底部按钮共享，跨页实时同步
final ValueNotifier<bool> challengeJoined = ValueNotifier(false);
bool _challengeJoinedLoaded = false;

/// 从 SharedPreferences 载入参加状态（幂等，多处 initState 可安全调用）
Future<void> ensureChallengeJoinedLoaded() async {
  if (_challengeJoinedLoaded) return;
  _challengeJoinedLoaded = true;
  final prefs = await SharedPreferences.getInstance();
  challengeJoined.value = prefs.getBool(_kChallengeJoinedKey) ?? false;
}

/// 参加挑战：持久化 + 通知所有监听方 + SnackBar 反馈
Future<void> joinChallenge(BuildContext context) async {
  challengeJoined.value = true;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kChallengeJoinedKey, true);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('十月挑战已开始，这一个月别碰酒哦！')),
    );
  }
}

/// 「限时挑战」面板（对标原版：首页可滚动内容的尾段，上滑滚入展开）
///
/// 结构（自上而下）：
/// 1. 浅青色大圆角容器（四角统一圆角 28）+ 标题行（滚动联动双态：常态=左羽毛
///    徽章 + 挑战名称「滴酒不沾的十月」+ 右北极熊头像；酒红卡「31 天挑战」
///    滚入视口后=图标隐匿、仅居中「挑战」，回滚至标签不可见则恢复常态）
/// 2. 酒红色挑战大卡：左上「31 天挑战」标签 + 白色大标题「滴酒不沾的十月」
///    + 有效期描述 + 右侧垂直居中的北极熊插画（左倾、超出卡缘部分裁剪）
/// 3. 黑色「立即开始」胶囊按钮（参加后变绿色「挑战进行中」）
/// 4. 「查看挑战规则」文字链接 → 白底规则弹层
///
/// 交互闭环：参加状态持久化到 SharedPreferences（challenge_joined_oct），
/// 跨会话保持。
class ChallengePanel extends StatelessWidget {
  const ChallengePanel({super.key, required this.compact});

  /// true = 酒红卡「31 天挑战」已滚入视口：图标隐匿、文案切换为「挑战」
  final ValueListenable<bool> compact;

  @override
  Widget build(BuildContext context) {
    // 点击浅青容器/酒红卡任意位置 → 跳转挑战详情页
    // （卡内「立即开始」「查看挑战规则」按钮自身消费点击，不触发跳转）
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDetail(context),
      child: Container(
        // 左右 margin 26 = 酒红卡外缘（浅青容器与卡同宽对齐）
        margin: const EdgeInsets.symmetric(horizontal: 26),
      decoration: const BoxDecoration(
        color: Color(0xFFD9F2F7),
        // 四角统一圆角：与酒红卡一致，四边等高
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
      child: Column(
        children: [
          // 1. 标题行：随滚动联动切换双态（AnimatedSwitcher 过渡，不生硬）
          ValueListenableBuilder<bool>(
            valueListenable: compact,
            builder: (context, isCompact, _) => Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: SizedBox(
                height: 36,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  // 淡入淡出 + 轻微上滑：新态自下而上浮现，旧态下沉淡出
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.12),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  // 紧凑态：图标隐匿，仅居中「限时挑战」
                  child: isCompact
                      ? const Center(
                          key: ValueKey('compact'),
                          child: Text(
                            '限时挑战',
                            style: TextStyle(
                              color: Color(0xFF7E2438),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      // 常态：左羽毛徽章 + 挑战名称 + 右北极熊头像（首屏露出即可见）
                      : const Row(
                          key: ValueKey('normal'),
                          children: [
                            // 左：灰白圆底 + 紫红羽毛徽章（对标原版会员羽饰位置）
                            _BadgeCircle(
                              bg: Color(0xFFE8F5F8),
                              child: Icon(
                                Icons.spa,
                                size: 18,
                                color: Color(0xFFA85D75),
                              ),
                            ),
                            // 中：挑战名称 = 酒红卡里的标题
                            Expanded(
                              child: Text(
                                '滴酒不沾的十月',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF7E2438),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            // 右：白圆底 + 北极熊头像
                            _BadgeCircle(
                              bg: Colors.white,
                              child: _PolarBearAvatar(),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 2. 挑战卡（直接贴面板底边，浅青底部不露出）
          ChallengeCard(),
        ],
      ),
      ),
    );
  }

  /// 跳转挑战详情页（从底部滑入，与角色详情页转场一致）
  void _openDetail(BuildContext context) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const ChallengeDetailScreen(),
        transitionsBuilder: (_, animation, __, child) {
          final offset = Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          );
          return SlideTransition(position: offset, child: child);
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }
}

/// 标题行圆形徽章底座（const 构造，放进 const 上下文）
class _BadgeCircle extends StatelessWidget {
  const _BadgeCircle({required this.bg, required this.child});

  final Color bg;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// 北极熊小头像（非 const 的 SVG 包一层 const 可构造组件）
class _PolarBearAvatar extends StatelessWidget {
  const _PolarBearAvatar();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/characters/polar_bear.svg',
      width: 26,
      height: 26,
      fit: BoxFit.contain,
    );
  }
}

/// 酒红色挑战大卡（北极熊插画压右缘溢出，Stack 不裁剪）
class ChallengeCard extends StatefulWidget {
  const ChallengeCard({super.key});

  @override
  State<ChallengeCard> createState() => _ChallengeCardState();
}

class _ChallengeCardState extends State<ChallengeCard> {
  static const _maroon = Color(0xFF7E2438);
  static const _maroonSoft = Color(0xFFE7A9B8);
  static const _maroonDesc = Color(0xFFD894A6);

  @override
  void initState() {
    super.initState();
    // 参加状态跨页共享（详情页加入后返回首页同步生效）
    ensureChallengeJoinedLoaded();
  }

  /// 挑战规则弹层
  void _showRules() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  '挑战规则',
                  style: TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ruleItem('1', '挑战期间记录任何含酒精饮品，当日挑战失败。'),
              _ruleItem('2', '每天完成饮水目标即累计 1 天进度，坚持 31 天点亮徽章。'),
              _ruleItem('3', '挑战有效期：10 月 1 – 10 月 15。中断后可重新开始。'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ruleItem(String no, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFE0F4F8),
              shape: BoxShape.circle,
            ),
            child: Text(
              no,
              style: const TextStyle(
                color: Color(0xFF31A8C9),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF6B6B70),
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 卡片强制正方形（宽 = 高）。内容以 359 逻辑宽（Pixel 6 基准）设计：
    // 熊 + 文字 + 按钮整体放在参考坐标系里，经 FittedBox 等比缩放铺满
    // 卡片（宽屏 1:1、窄屏整体缩小）。窄屏（如 vivo ≈308 逻辑宽）不再把
    // 描述挤成 6 行短句、也不再把「查看挑战规则」挤出卡外，构图恒定
    return AspectRatio(
      aspectRatio: 1.0,
      child: Stack(
        // 溢出卡片的熊的部分直接裁剪掉（对标原版：熊贴卡右缘被切平）
        clipBehavior: Clip.hardEdge,
        children: [
          // 底层：酒红背景（四角统一圆角 28，四边等高的圆角四边形）
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _maroon,
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
          // 内容层：359×359 参考坐标系（熊在右、文字在左），FittedBox
          // 等比缩放适配实际卡宽，避免窄屏内容溢出
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 359,
                height: 359,
                child: Stack(
                  children: [
                    // 北极熊插画（右侧垂直居中、向左倾斜，压在背景上、文字下）
                    // 270px（1.8 倍）+ right 负值补偿 SVG 透明边距：熊贴住卡右缘被裁
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: -150,
                      child: Center(
                        child: Transform.rotate(
                          angle: -0.385, // 约 -22°：向左倾斜
                          child: SvgPicture.asset(
                            'assets/images/characters/polar_bear.svg',
                            width: 270,
                            height: 270,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    // 文字 + 按钮（压在熊上面）
                    Padding(
                      // 底部留白对标原版加大：卡向下加长，四角圆弧完整舒展
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '31 天挑战',
                            style: TextStyle(
                              color: _maroonSoft,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 标题 = 挑战名称（字号较原版收小）
                          const Text(
                            '滴酒不沾的\n十月',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 描述：右侧避让大熊（熊视觉左缘≈160），文字收窄自动换行三行
                          const Padding(
                            padding: EdgeInsets.only(right: 190),
                            child: Text(
                              '有效期：10 月 1 – 10 月 15。打破饮酒习惯.',
                              style: TextStyle(
                                color: _maroonDesc,
                                fontSize: 13.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          // 立即开始按钮（居中，参加状态全局共享：详情页加入后回首页同步）
                          Center(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: challengeJoined,
                              builder: (context, joined, _) => GestureDetector(
                                onTap: joined ? null : () => joinChallenge(context),
                                child: Container(
                                  height: 52,
                                  padding: const EdgeInsets.symmetric(horizontal: 34),
                                  decoration: BoxDecoration(
                                    color: joined
                                        ? const Color(0xFF23A06A)
                                        : const Color(0xFF1C1C22),
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (joined) ...[
                                        const Icon(Icons.check_rounded,
                                            color: Colors.white, size: 20),
                                        const SizedBox(width: 8),
                                      ],
                                      Text(
                                        joined ? '挑战进行中' : '立即开始',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          // 查看挑战规则
                          Center(
                            child: GestureDetector(
                              onTap: _showRules,
                              child: const Text(
                                '查看挑战规则',
                                style: TextStyle(
                                  color: _maroonSoft,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
