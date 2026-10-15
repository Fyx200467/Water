import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'habit_detail_screen.dart';

/// 已参加的习惯挑战集合——全局共享：模块标题「N/9」计数与详情页
/// 「立即开始→挑战进行中」实时联动。key = 习惯标题。
final ValueNotifier<Set<String>> habitsJoined = ValueNotifier(const {});

bool _habitsLoaded = false;

/// 启动时载入持久化的已参加习惯（幂等）
Future<void> ensureHabitsJoinedLoaded() async {
  if (_habitsLoaded) return;
  _habitsLoaded = true;
  final prefs = await SharedPreferences.getInstance();
  habitsJoined.value =
      (prefs.getStringList('habits_joined') ?? const []).toSet();
}

/// 参加一个习惯挑战：更新通知 + 持久化
Future<void> joinHabit(String title) async {
  if (habitsJoined.value.contains(title)) return;
  habitsJoined.value = {...habitsJoined.value, title};
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList('habits_joined', habitsJoined.value.toList());
}

/// 习惯挑战数据（对标原版 9 张卡；插画用现有动物 SVG 近似，
/// 后续管理端可替换资产）
class HabitData {
  const HabitData({
    required this.title,
    required this.subtitle,
    required this.bg,
    required this.asset,
    required this.intro,
    required this.benefits,
    required this.todo,
  });

  final String title;

  /// 详情页标题下的小字副标题
  final String subtitle;
  final Color bg;
  final String asset;
  final String intro;

  /// 好处段落（emoji + 文案）
  final List<(String, String)> benefits;
  final String todo;

  static const List<HabitData> all = [
    HabitData(
      title: '向咖啡因说不的\n卷尾猴',
      subtitle: '暂时告别咖啡因带来的兴奋',
      bg: Color(0xFF6D4C38),
      asset: 'assets/images/characters/red_squirrel.svg',
      intro: '咖啡因虽能短暂提神，但过量摄入会影响睡眠与情绪。用 10 天'
          '时间告别对咖啡因的依赖，找回自然的清醒节律。',
      benefits: [
        ('🦉', '改善睡眠质量。你会更快入睡，获得更多睡眠时间使身体恢复活力。'),
        ('🐢', '避免焦虑和抑郁。神经系统中的"战斗或逃跑"激素不会像现在这样经常受到刺激。'),
        ('🦷', '让牙齿更加健康洁白。咖啡渍更少，还能减少酸蚀度导致的牙釉质腐蚀情况。'),
      ],
      todo: '请保持在白天摄入的咖啡因总量低于 55 毫克。这通常等于半杯普通'
          '咖啡或卡布奇诺咖啡、一杯红茶或两杯绿茶或抹茶。请注意能量饮料'
          '和苏打水，因为可口可乐或百事可乐也含有咖啡因。',
    ),
    HabitData(
      title: '爱喝茶的\n霸王龙',
      subtitle: '用温和的茶水开启补水冒险',
      bg: Color(0xFF3FA65C),
      asset: 'assets/images/characters/turtle.svg',
      intro: '茶是世界上仅次于水的第二大饮品。用花草茶与绿茶替代含糖饮'
          '料，既满足味蕾又补充水分，10 天养成温和饮茶的好习惯。',
      benefits: [
        ('🍃', '摄入更多抗氧化物质。茶多酚帮助身体对抗自由基，保持年轻状态。'),
        ('💧', '温和补水。淡茶水同样计入每日饮水量，风味更佳更容易坚持。'),
        ('😌', '舒缓身心。花草茶的天然香气能帮助放松情绪，缓解一天的疲劳。'),
      ],
      todo: '每天至少用一杯淡茶替代一份含糖饮料。避免空腹饮浓茶，下午 4 '
          '点后优先选择花草茶或低咖啡因茶，以免影响入睡。',
    ),
    HabitData(
      title: '不吃糖的\n猎豹',
      subtitle: '暂时戒掉零食与甜饮料',
      bg: Color(0xFFD8354A),
      asset: 'assets/images/characters/leopard.svg',
      intro: '添加糖隐藏在饮料、零食甚至酱料里。10 天无糖挑战帮你重置味'
          '蕾，摆脱"甜蜜陷阱"，恢复敏锐的味觉与稳定的精力。',
      benefits: [
        ('⚡', '精力更稳定。血糖不再大起大落，午后犯困和情绪波动明显减少。'),
        ('✨', '皮肤更透亮。减少糖分摄入有助于维持胶原蛋白，肤色更均匀。'),
        ('🍋', '味觉更敏锐。重置味蕾后，水果的天然甜味也会变得格外迷人。'),
      ],
      todo: '挑战期间避免添加糖：不喝含糖饮料、不吃糖果与甜品。阅读配料'
          '表，白砂糖、果葡糖浆、蜂蜜等都算添加糖。天然水果可以正常吃。',
    ),
    HabitData(
      title: '积极瘦身的\n树懒',
      subtitle: '慢下来，也能轻盈起来',
      bg: Color(0xFF3F9E7B),
      asset: 'assets/images/characters/sheep.svg',
      intro: '瘦身不必激进节食。像树懒一样缓慢而坚定：饭前一杯水、细嚼'
          '慢咽、规律作息，10 天建立让身体自然轻盈的日常节奏。',
      benefits: [
        ('🥗', '饮食更自律。饭前喝水能带来适度饱腹感，避免无意识过量进食。'),
        ('💤', '睡眠与代谢更规律。固定的作息让身体修复效率更高。'),
        ('💪', '养成可持续的习惯。不反弹的减重，来自每天一点点的小改变。'),
      ],
      todo: '每天三餐前各喝一杯水，吃饭时专注细嚼慢咽（每口 15 次以上），'
          '晚上 11 点前入睡。不追求速度，坚持完成每一天就是胜利。',
    ),
    HabitData(
      title: '拒绝乳糖的\n鸭嘴兽',
      subtitle: '暂时告别牛奶和奶茶',
      bg: Color(0xFFE88BB6),
      asset: 'assets/images/characters/duck.svg',
      intro: '如果你乳糖不耐受，奶茶和拿铁可能带来腹胀与不适。10 天暂时'
          '告别乳制品，观察身体的轻松变化，找到更适合自己的饮品。',
      benefits: [
        ('🌿', '肠胃更舒服。腹胀、肠鸣等乳糖不耐受症状明显缓解。'),
        ('🫧', '减少隐形糖分。奶茶往往含大量糖与植脂末，戒断后摄入更干净。'),
        ('🥥', '发现新选择。燕麦奶、椰奶等植物奶同样香浓，还能补充水分。'),
      ],
      todo: '挑战期间不喝牛奶、奶茶、拿铁等含乳糖饮品。咖啡可换美式或燕'
          '麦拿铁，注意查看奶茶配料表中的乳清与奶粉同样是乳糖来源。',
    ),
    HabitData(
      title: '维生素满满的\n海雀',
      subtitle: '多吃水果与蔬菜',
      bg: Color(0xFFF59B31),
      asset: 'assets/images/characters/bird.svg',
      intro: '维生素与矿物质是身体运转的润滑剂。10 天里让蔬果成为每餐的'
          '主角，像海雀一样活力满满，皮肤、精力与免疫力都会回报你。',
      benefits: [
        ('🍊', '免疫力更强。维生素 C 帮助身体抵御换季的不适。'),
        ('🌟', '皮肤更有光泽。天然抗氧化剂由内而外滋养肌肤。'),
        ('🚀', '精力更充沛。均衡的微量营养素让疲劳感远离你。'),
      ],
      todo: '每天保证 3 份蔬菜 + 2 份水果（约每份一个拳头大小），颜色越'
          '丰富越好。果汁不能替代完整水果，尽量带皮吃以保留膳食纤维。',
    ),
    HabitData(
      title: '对酒说不的\n熊',
      subtitle: '暂时戒掉定时喝酒的习惯',
      bg: Color(0xFF5A5FC8),
      asset: 'assets/images/characters/polar_bear.svg',
      intro: '睡前小酌看似放松，实则打乱深睡节律。10 天不喝酒，让大脑与'
          '肝脏好好休息，你会发现清晨的自己比想象中清醒得多。',
      benefits: [
        ('🌙', '睡眠更深。快速眼动睡眠恢复，早晨醒来更有精神。'),
        ('❤️', '心血管减负。酒精带来的血压波动与潮红不再出现。'),
        ('🧠', '头脑更清晰。专注力与记忆力在戒断第一周就开始回升。'),
      ],
      todo: '挑战期间滴酒不沾，包括啤酒、红酒、白酒与含酒精饮料。聚会时'
          '可以用气泡水加青柠代替，睡前想小酌的冲动试试用一杯温水化解。',
    ),
    HabitData(
      title: '戒红酒的\n鼬鼠',
      subtitle: '暂时戒掉定时喝酒的习惯',
      bg: Color(0xFF9E1B2F),
      asset: 'assets/images/characters/otter.svg',
      intro: '红酒常被视作"健康选择"，但过量饮酒从来都不是健康的选择。'
          '大多数人并不依赖酒精，但我们常常需要一点额外的动力来帮助'
          '我们控制饮酒。',
      benefits: [
        ('🐬', '让皮肤更加健康。你不会因饮酒而血流加速并血管扩张，从而避免皮肤发红或浮肿。'),
        ('🦩', '让体重更加轻盈。你不会因为酒精而丧失做出明智饮食选择的能力。'),
        ('🕊️', '情绪更平稳。酒精是抑制剂，戒断后情绪波动明显减少。'),
      ],
      todo: '挑战期间不饮用任何种类的红酒，包括干红、甜型与起泡酒。晚餐'
          '想配酒的仪式感可以用无醇葡萄酒或葡萄气泡水替代。',
    ),
    HabitData(
      title: '不喝啤酒的\n鹿',
      subtitle: '聚会也不碰啤酒的清爽挑战',
      bg: Color(0xFFD9B426),
      asset: 'assets/images/characters/ram.svg',
      intro: '啤酒的热量常被低估——一大杯等于一碗米饭。10 天不喝啤酒，'
          '告别"啤酒肚"的隐忧，聚会照样尽兴，身体更轻快。',
      benefits: [
        ('🎯', '腰围更友好。啤酒热量高且促进食欲，戒断后更容易控制体重。'),
        ('💛', '肝脏更轻松。肝脏获得休息，代谢功能逐步恢复。'),
        ('🧊', '补水更纯粹。用气泡水与鲜榨饮品替代，水分吸收效率更高。'),
      ],
      todo: '挑战期间不喝任何啤酒，包括无醇啤酒（仍含微量酒精与啤酒风'
          '味）。观赛聚会场景提前备好冰镇气泡水或康普茶，避免口渴时'
          '顺手拿起啤酒。',
    ),
  ];
}

/// 「养成健康的日常习惯」模块（今日小贴士下方）
///
/// 结构：居中灰色标题「养成健康的日常习惯 N/9 🏆」（N=已参加数，
/// 实时联动）→ 纵向习惯卡列表（宽度与限时挑战卡/堆叠贴士卡视觉一致：
/// contentW = w − 52，整体 Transform.scale 0.9）→ 底部可横滑提示卡
/// 轮播（每张可「隐藏提示」）。
class HabitModule extends StatefulWidget {
  const HabitModule({super.key});

  @override
  State<HabitModule> createState() => _HabitModuleState();
}

class _HabitModuleState extends State<HabitModule> {
  final List<int> _hiddenHints = [];

  @override
  void initState() {
    super.initState();
    ensureHabitsJoinedLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        // 与限时挑战卡视觉同宽：卡布局宽 = w − 52，再整体 0.9 缩放
        final cardW = w - 52;
        const cardH = 196.0;
        return Transform.scale(
          scale: 0.9,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 44),
            child: Column(
              children: [
                // 标题行：养成健康的日常习惯 N/9 🏆
                ValueListenableBuilder<Set<String>>(
                  valueListenable: habitsJoined,
                  builder: (context, joined, _) => Text.rich(
                    TextSpan(
                      text: '养成健康的日常习惯 ',
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(
                          text: '${joined.length}/${HabitData.all.length} ',
                          style: const TextStyle(
                            color: Color(0xFF6B6B70),
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(text: '🏆'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // 习惯卡列表
                for (var i = 0; i < HabitData.all.length; i++) ...[
                  _HabitCard(data: HabitData.all[i], w: cardW, h: cardH),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 8),
                // 底部提示卡轮播（可横滑，逐张「隐藏提示」）
                _HintPager(
                  w: cardW,
                  hidden: _hiddenHints,
                  onHide: (idx) => setState(() => _hiddenHints.add(idx)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 单张习惯卡：左「10 天挑战」标签 + 白色大标题，右侧角色插画压边裁剪，
/// 点击打开详情页
class _HabitCard extends StatelessWidget {
  const _HabitCard({required this.data, required this.w, required this.h});

  final HabitData data;
  final double w;
  final double h;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => HabitDetailScreen(habit: data),
          transitionsBuilder: (_, animation, __, child) {
            final offset = Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
                parent: animation, curve: Curves.easeOutCubic));
            return SlideTransition(position: offset, child: child);
          },
          transitionDuration: const Duration(milliseconds: 350),
        ),
      ),
      child: Container(
        width: w,
        height: h,
        // 超出卡范围的角色部分直接裁剪（对标原版）
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: data.bg,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Stack(
          children: [
            // 角色插画：右侧底部锚定，压边溢出被裁剪
            Positioned(
              right: -68,
              bottom: -40,
              child: SizedBox(
                width: 230,
                height: 230,
                child: SvgPicture.asset(data.asset, fit: BoxFit.contain),
              ),
            ),
            // 文案层：左侧垂直居中偏下
            Positioned(
              left: 24,
              right: 150,
              bottom: 26,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '10 天挑战',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      height: 1.22,
                    ),
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

/// 底部提示卡轮播（对标原版：剩余饮水量/随机角色/喝水提醒）
class _HintPager extends StatelessWidget {
  const _HintPager({
    required this.w,
    required this.hidden,
    required this.onHide,
  });

  final double w;
  final List<int> hidden;
  final ValueChanged<int> onHide;

  static const _hints = [
    (
      Color(0xFFEAE6F8),
      Color(0xFF7A6FD8),
      Icons.water_drop_rounded,
      '剩余饮水量',
      '轻点你要填充的角色，查看还剩多少水可以喝。',
    ),
    (
      Color(0xFFDFF5EA),
      Color(0xFF23A06A),
      Icons.shuffle_rounded,
      '随机角色',
      '轻点角色缩略图。启用"随机"（左上角按钮）以每天更换角色。',
    ),
    (
      Color(0xFFDFF2F8),
      Color(0xFF2BB3CE),
      Icons.notifications_active_rounded,
      '喝水提醒',
      '到点轻推你喝水，助力连续打卡不断档。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (var i = 0; i < _hints.length; i++)
        if (!hidden.contains(i)) i,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 210,
      child: PageView.builder(
        itemCount: visible.length,
        controller: PageController(viewportFraction: 0.88),
        itemBuilder: (context, i) {
          final idx = visible[i];
          final (bg, fg, icon, title, desc) = _hints[idx];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 14),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: fg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      color: fg,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    desc,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: fg.withOpacity(0.75),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => onHide(idx),
                    child: Text(
                      '隐藏提示',
                      style: TextStyle(
                        color: fg.withOpacity(0.45),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
