import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// 「养成健康的日常习惯」模块
///
/// 结构：居中灰色标题「养成健康的日常习惯 N/9 🏆」（N=已参加数，
/// 实时联动）→ 习惯卡堆叠区（滚动到顶部后依次吸附堆叠，参考
/// VueBits card-stack 效果）。
class HabitModule extends StatefulWidget {
  const HabitModule({super.key, required this.scrollPixels});

  /// 首页外层 CustomScrollView 的滚动像素
  final ValueListenable<double> scrollPixels;

  @override
  State<HabitModule> createState() => _HabitModuleState();
}

class _HabitModuleState extends State<HabitModule> {
  final GlobalKey _moduleKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    ensureHabitsJoinedLoaded();
  }

  /// 标题行：养成健康的日常习惯 N/9 🏆
  Widget _buildTitle() {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: habitsJoined,
      builder: (context, joined, _) => Text.rich(
        TextSpan(
          text: '养成健康的日常习惯 ',
          style: const TextStyle(
            color: Color(0xFF8E8E93),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          children: [
            TextSpan(
              text: '${joined.length}/${HabitData.all.length} ',
              style: const TextStyle(
                color: Color(0xFF6B6B70),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const TextSpan(text: '🏆'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        // 与限时挑战卡视觉同宽：原 w−52 再整体 0.9 缩放 → 直接按缩放后尺寸排布
        final cardW = (w - 52) * 0.9;
        const cardH = 196.0 * 0.9;
        // 标题区高度、标题与第一张卡的间距、牌堆上浮边缘预留
        const titleH = 26.0;
        const headerGap = 18.0;
        const peekReserve = _HabitDeckState._peek * _HabitDeckState._maxDepth;
        final n = HabitData.all.length;
        final stride = cardH + _HabitDeck.gap;
        final deckH = (n - 1) * stride + cardH;
        // 牌堆吸附线（= 第一张卡吸附后距视口顶部的位置）
        final stickTop = topInset + titleH + headerGap + peekReserve;
        // 目标是「滚到页面底部时，倒数第三张卡刚好叠到牌堆顶」，最后两张卡
        // 自然铺在页面尾部填满屏幕；因此下方只补刚好够用的过渡距离，
        // 不再垫一整屏留白（否则页面底部会空出一大片）
        final pinTarget = math.max(0.0, (n - 3) * stride);
        // 页面末尾固定占用：模块底部留白 44 + 「到底啦」块 42 + 底部安全区
        final endBlocks =
            44.0 + 8 + 18 + 16 + MediaQuery.paddingOf(context).bottom;
        // 不留过渡距离时，滚到页面底部最多只能吸附到这里
        final reachable =
            stickTop + deckH + endBlocks - MediaQuery.sizeOf(context).height;
        final tail = math.max(0.0, pinTarget - reachable);
        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 44),
          child: Stack(
            key: _moduleKey,
            clipBehavior: Clip.hardEdge,
            children: [
              Column(
                children: [
                  // 标题占位（真正显示的是下面那层可吸附的标题）
                  const SizedBox(height: titleH),
                  const SizedBox(height: headerGap),
                  // 习惯卡堆叠区
                  _HabitDeck(
                    fullW: w,
                    cardW: cardW,
                    cardH: cardH,
                    stickTop: stickTop,
                    scrollPixels: widget.scrollPixels,
                  ),
                  SizedBox(height: tail),
                ],
              ),
              // 标题层：跟着页面滚到顶部后吸附，与第一张卡保持固定距离，
              // 整摞叠完后随牌堆一起上滑退场
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<double>(
                  valueListenable: widget.scrollPixels,
                  builder: (context, pixels, _) {
                    final sectionTop = _screenTopOf(_moduleKey, pixels);
                    final pinExcess = math.max(0.0, topInset - sectionTop);
                    final release = math.min(
                        0.0, (n - 1) * stride - pinExcess - peekReserve);
                    return Transform.translate(
                      offset: Offset(0, pinExcess + release),
                      child: SizedBox(
                        height: titleH,
                        child: Center(child: _buildTitle()),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 某个 widget 顶部到视口顶部的有符号距离（负值 = 已滚过视口顶部）
double _screenTopOf(GlobalKey key, double pixels) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  // 首帧还没有布局结果：视为远在视口下方，避免误判成已吸附
  if (box == null || !box.hasSize) return 1e6;
  return RenderAbstractViewport.of(box).getOffsetToReveal(box, 0.0).offset -
      pixels;
}

/// 习惯卡堆叠区
///
/// 参考 VueBits card-stack：
/// 1. 卡 0 保持自然位置（标题正下方），页面滚动把它带到距视口顶部
///    [stickTop] 后固定不动（此时标题也吸附在状态栏下方）；
/// 2. 后续卡片随页面滚动逐张升到同一位置，盖在前一张之上形成牌堆，
///    被压住的卡片按层数轻微上移、缩小，露出牌堆边缘；
/// 3. 全部叠完后（[stickTop] 之上累计滚动 (n-1) 个步长），整摞牌堆
///    连同标题随页面一起上滑退场；
/// 4. 堆叠区高度 = 全部步长 + 一张卡，滚完刚好轮到下方提示卡轮播。
class _HabitDeck extends StatefulWidget {
  const _HabitDeck({
    required this.fullW,
    required this.cardW,
    required this.cardH,
    required this.stickTop,
    required this.scrollPixels,
  });

  /// 卡牌之间的原始间距（未吸附时首尾相隔）
  static const double gap = 16;

  final double fullW;
  final double cardW;
  final double cardH;

  /// 卡牌吸附位置（距视口顶部）
  final double stickTop;

  final ValueListenable<double> scrollPixels;

  @override
  State<_HabitDeck> createState() => _HabitDeckState();
}

class _HabitDeckState extends State<_HabitDeck> {
  final GlobalKey _deckKey = GlobalKey();

  /// 被压住的卡片每层上移量 / 缩放量（露出牌堆边缘）
  static const double _peek = 6;
  static const double _depthScale = 0.04;
  static const int _maxDepth = 3;

  double get _stride => widget.cardH + _HabitDeck.gap;

  /// 视口顶部到堆叠区顶部的有符号距离（负值表示已滚过视口顶部）
  double _sectionTop(double pixels) {
    final box = _deckKey.currentContext?.findRenderObject() as RenderBox?;
    // 首帧还没有布局结果：视为远在视口下方，避免误判成已吸附
    if (box == null || !box.hasSize) return 1e6;
    final viewport = RenderAbstractViewport.of(box);
    return viewport.getOffsetToReveal(box, 0.0).offset - pixels;
  }

  @override
  Widget build(BuildContext context) {
    final n = HabitData.all.length;
    // 全部卡片升到堆叠位所需的滚动距离
    final stackDone = (n - 1) * _stride;
    final height = stackDone + widget.cardH;
    return ValueListenableBuilder<double>(
      valueListenable: widget.scrollPixels,
      builder: (context, pixels, _) {
        final sectionTop = _sectionTop(pixels);
        // 堆叠区顶部越过吸附线之后继续滚动的距离：卡 0 在此距离内被
        // 固定在视口 [stickTop]，卡 i 在 i 个步长处升到堆叠位
        final pinExcess = math.max(0.0, widget.stickTop - sectionTop);
        // 全部叠完之后整摞随页面上滑退场（负值 = 上移量）
        final release = math.min(0.0, stackDone - pinExcess);
        // 已叠上来的卡片数量
        final pinned =
            math.min(n, (pinExcess / _stride).floor() + 1);
        return SizedBox(
          key: _deckKey,
          height: height,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (var i = 0; i < n; i++)
                _buildCard(i, pinExcess, pinned, release),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard(int i, double pinExcess, int pinned, double release) {
    // 自然位置（未吸附时）与吸附位置取较大者：
    // 前者 = 页面滚动带来的自然上移，后者 = 固定在 [_stackTop]；
    // 叠加 release 后在整摞牌堆滚完时一起退场
    final depth = math.min(_maxDepth, math.max(0, pinned - 1 - i));
    final localTop =
        math.max(i * _stride, pinExcess) + release - depth * _peek;
    return Positioned(
      top: localTop,
      left: (widget.fullW - widget.cardW) / 2,
      width: widget.cardW,
      child: Transform.scale(
        scale: 1 - _depthScale * depth,
        alignment: Alignment.topCenter,
        child: _HabitCard(
          data: HabitData.all[i],
          w: widget.cardW,
          h: widget.cardH,
        ),
      ),
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
          borderRadius: BorderRadius.circular(25),
        ),
        child: Stack(
          children: [
            // 角色插画：右侧底部锚定，压边溢出被裁剪
            Positioned(
              right: -61,
              bottom: -36,
              child: SizedBox(
                width: 207,
                height: 207,
                child: SvgPicture.asset(data.asset, fit: BoxFit.contain),
              ),
            ),
            // 文案层：左边距固定为卡宽的 10%，垂直居中（所有卡文字起点一致）
            Positioned(
              left: w * 0.1,
              right: 135,
              top: 0,
              bottom: 0,
              // centerLeft：垂直居中、水平靠左——Center 会把文字块整体水平
              // 居中，标题长度不同的卡文字起点就会各不相同
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '10 天挑战',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 13.5,
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
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.22,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
