import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';

import '../../shared/widgets/drink_illustration.dart';
import 'challenge_sheet.dart' show challengeJoined, joinChallenge;

/// 挑战详情页（对标原版：点击首页挑战卡任意位置跳转，从底部滑入）
///
/// 结构（自上而下滚动）：
/// 1. 酒红头部：「31 天挑战」+ 白色大标题「滴酒不沾的十月」+ 有效期描述
///    + 黑色「告诉朋友」胶囊 + 右缘北极熊插画（超出头部即裁剪）
/// 2. 白色正文：介绍段落 /「好处」/「要做的事情」（禁饮饮品网格 +
///    「+ 其他 33 个」胶囊 + 浅粉提示卡）/「成功的 5 个技巧」编号列表
/// 3. 悬浮层：顶部酒红渐变 + •••/× 圆钮（随滚动常驻，× 返回）；
///    底部黑色「立即开始」大胶囊（参加后变绿「挑战进行中」，
///    与首页挑战卡通过 challengeJoined 全局同步）
class ChallengeDetailScreen extends StatelessWidget {
  const ChallengeDetailScreen({super.key});

  static const _maroon = Color(0xFF7E2438);
  static const _maroonSoft = Color(0xFFE7A9B8);
  static const _maroonDesc = Color(0xFFD894A6);
  static const _bodyGray = Color(0xFF6B6B70);
  static const _pillDark = Color(0xFF1C1C22);
  static const _pillGreen = Color(0xFF23A06A);

  /// 禁饮饮品网格（名称 + 复用现有酒类插画）
  static const _forbidden = [
    ('代基里鸡尾酒', 'alcohol_spirits'),
    ('伏特加酒', 'alcohol_spirits'),
    ('内格罗尼鸡尾酒', 'alcohol_wine'),
    ('古典鸡尾酒', 'alcohol_spirits'),
    ('吉姆雷特鸡尾酒', 'alcohol_spirits'),
    ('含羞草鸡尾酒', 'alcohol_wine'),
    ('啤酒', 'alcohol_beer'),
    ('大都会鸡尾酒', 'alcohol_wine'),
    ('威士忌', 'alcohol_spirits'),
    ('威士忌酸酒', 'alcohol_spirits'),
    ('子弹酒', 'alcohol_spirits'),
    ('干邑白兰地', 'alcohol_spirits'),
  ];

  /// 成功的 5 个技巧
  static const _tips = [
    '研究不含酒精的饮料，享受尝试各种食谱的乐趣！',
    '参加活动时，提前考虑你需要做什么。这样，你就不会当场做出不理智的决定。另外，想想如何告诉别人你不喝酒，并练习说出来！',
    '你可能会惊讶地发现，不喝酒的时候会有如此多的空闲时间。用空闲时间去做一些新的事情，例如尝试一门新的健身课程或者研究一个新食谱！',
    '想象自己大获成功，想想那会是什么样子！不要把自己看成是在戒酒，而要觉得自己将拥有更多的收获 - 充沛的精力、清爽的肌肤、清晰的头脑等。',
    '寻找其他人或挑战自己的朋友，以保持戒酒的连胜记录！你不仅会得到支持，还会有人分享你的戒酒之旅。',
  ];

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 滚动内容
          Positioned.fill(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(topPad),
                  _intro(),
                  _benefits(),
                  _todos(context),
                  _tipsSection(),
                  SizedBox(height: 130 + bottomPad), // 底部给悬浮按钮留位
                ],
              ),
            ),
          ),
          // 顶部酒红渐变 + •••/× 圆钮（随滚动常驻）
          Positioned(top: 0, left: 0, right: 0, child: _topBar(context, topPad)),
          // 底部悬浮「立即开始」
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _joinFab(context, bottomPad),
          ),
        ],
      ),
    );
  }

  // ---------- 酒红头部 ----------

  Widget _header(double topPad) {
    return Container(
      width: double.infinity,
      color: _maroon,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // 右缘北极熊插画（超出头部即裁剪，对标原版）
          Positioned(
            top: topPad + 30,
            right: -110,
            child: Transform.rotate(
              angle: -0.2,
              child: SvgPicture.asset(
                'assets/images/characters/polar_bear.svg',
                width: 320,
                height: 320,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, topPad + 64, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '31 天挑战',
                  style: TextStyle(
                    color: _maroonSoft,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '滴酒不沾的\n十月',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '有效期: 10月1 - 10月15。打破饮酒习惯.',
                  style: TextStyle(
                    color: _maroonDesc,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 24),
                // 告诉朋友
                GestureDetector(
                  onTap: _tellFriends,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: _pillDark,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.celebration, color: Colors.white, size: 20),
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

  // ---------- 白色正文各节 ----------

  Widget _intro() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: Text(
        '这是一次暂时戒酒并尝试其他饮料甚至苏打水的绝佳机会。'
        '这项挑战也是一个让你清楚自己实际喝了多少酒的好方法。',
        style: TextStyle(color: _bodyGray, fontSize: 15.5, height: 1.55),
      ),
    );
  }

  Widget _benefits() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '好处',
            style: TextStyle(
              color: _maroon,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '无酒精饮食对你的健康具有神奇功效。',
            style: TextStyle(color: _bodyGray, fontSize: 15.5, height: 1.55),
          ),
          const SizedBox(height: 16),
          _para('🦉 改善睡眠质量。你的深度睡眠阶段会持续更长时间，'
              '你的身体在此阶段可以很好地恢复，同时增强你的免疫系统。'),
          _para('🌊 提高运动表现。当你脱水时，运动表现会下降；'
              '而当你获得充足的水分时，你的表现会提高。'),
          _para('🦞 减肥。酒精含有的空卡路里毫无营养价值。'
              '含酒精饮料让人长胖的另一个原因是饮酒后想吃咸食或油腻食物。'),
          const SizedBox(height: 16),
          const Text(
            '在以下其他无酒精挑战中获得另外 9 项益处：戒红酒的鼬鼠, 不喝啤酒的鹿。',
            style: TextStyle(color: _bodyGray, fontSize: 15.5, height: 1.55),
          ),
        ],
      ),
    );
  }

  Widget _todos(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '要做的事情',
            style: TextStyle(
              color: _maroon,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '避免喝任何含有酒精的饮料。',
            style: TextStyle(color: _bodyGray, fontSize: 15.5, height: 1.55),
          ),
          const SizedBox(height: 12),
          // 禁饮饮品网格（4 列 × 3 行）
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            mainAxisSpacing: 16,
            crossAxisSpacing: 8,
            childAspectRatio: 0.74,
            children: [
              for (final (name, id) in _forbidden) _forbiddenTile(name, id),
            ],
          ),
          const SizedBox(height: 10),
          // + 其他 33 个
          Center(
            child: GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('功能开发中')),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F1F4),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  '+ 其他 33 个',
                  style: TextStyle(
                    color: _bodyGray,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 浅粉提示卡
          _persistenceCard(),
        ],
      ),
    );
  }

  Widget _tipsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '成功的 5 个技巧',
            style: TextStyle(
              color: _maroon,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 22),
          for (var i = 0; i < _tips.length; i++) ...[
            _tipItem(i + 1, _tips[i]),
            if (i < _tips.length - 1) const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  // ---------- 组件 ----------

  Widget _para(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        text,
        style: const TextStyle(color: _bodyGray, fontSize: 15.5, height: 1.55),
      ),
    );
  }

  /// 禁饮网格瓦片：彩色饮品插画 + 红色禁止徽章 + 名称
  Widget _forbiddenTile(String name, String id) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DrinkIllustration(beverageId: id, size: 54),
              ),
              // 红色禁止徽章（白圈 + 白色横杠）
              Positioned(
                bottom: -2,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5484D),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Center(
                    child: Container(
                      width: 9,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 11),
        ),
      ],
    );
  }

  /// 浅粉提示卡：白圆熊头像 + 提示文案
  Widget _persistenceCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
      decoration: BoxDecoration(
        color: const Color(0xFFF2E2E8),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: _maroon, width: 2.5),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: SvgPicture.asset(
              'assets/images/characters/polar_bear.svg',
              width: 36,
              height: 36,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '坚持每日完成饮水目标，让挑战持续下去。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _maroon,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipItem(int no, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: _maroon,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$no',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: _bodyGray,
              fontSize: 15.5,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }

  // ---------- 悬浮层 ----------

  /// 顶部酒红渐变遮罩 + •••/× 圆钮（渐变不拦截手势，内容可从顶部继续滚动）
  Widget _topBar(BuildContext context, double topPad) {
    return SizedBox(
      height: topPad + 56,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_maroon, _maroon.withOpacity(0)],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, topPad, 16, 0),
            child: Row(
              children: [
                _circleBtn(Icons.more_horiz, () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('功能开发中')),
                  );
                }),
                const Spacer(),
                _circleBtn(Icons.close, () => Navigator.of(context).maybePop()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  /// 底部悬浮「立即开始」（参加后变绿「挑战进行中」，状态与首页共享）
  Widget _joinFab(BuildContext context, double bottomPad) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad + 20),
      child: Center(
        child: ValueListenableBuilder<bool>(
          valueListenable: challengeJoined,
          builder: (context, joined, _) => GestureDetector(
            onTap: joined ? null : () => joinChallenge(context),
            child: Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: joined ? _pillGreen : _pillDark,
                borderRadius: BorderRadius.circular(29),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x29000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'assets/images/characters/polar_bear.svg',
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    joined ? '挑战进行中' : '立即开始',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  // 参加后显示对勾（未参加不加锁图标：会员功能补齐时再加回）
                  if (joined) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.check_rounded,
                        color: Colors.white, size: 22),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 系统分享
  void _tellFriends() {
    SharePlus.instance.share(
      ShareParams(
        text: '我正在参加「滴酒不沾的十月」31 天挑战，这个月一起戒酒打卡吧！',
      ),
    );
  }
}
