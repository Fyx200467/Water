import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../challenges/challenge_art.dart';
import '../challenges/challenge_catalog.dart';
import '../challenges/challenge_service.dart';
import 'habit_detail_screen.dart';

/// 「养成健康的日常习惯」模块
///
/// 结构：居中灰色标题「养成健康的日常习惯 N/9 🏆」（N=已完成挑战数，
/// 随 [challengeOverviewProvider] 实时联动）→ 习惯卡堆叠区（滚动到
/// 顶部后依次吸附堆叠，参考 VueBits card-stack 效果）。
class HabitModule extends ConsumerStatefulWidget {
  const HabitModule({super.key, required this.scrollPixels});

  /// 首页外层 CustomScrollView 的滚动像素
  final ValueListenable<double> scrollPixels;

  @override
  ConsumerState<HabitModule> createState() => _HabitModuleState();
}

class _HabitModuleState extends ConsumerState<HabitModule> {
  final GlobalKey _moduleKey = GlobalKey();

  /// 首页进入时结算已完成挑战的积分（详情页打开时也会结算，两者互斥；
  /// 是否已发放由 claimed 标记判定，可安全多次调用）
  Future<void> _settleCompleted(Map<String, ChallengeProgress> map) async {
    final pending =
        map.values.where((p) => p.completed && !p.claimed).toList();
    if (pending.isEmpty) return;
    var total = 0;
    for (final p in pending) {
      total += await ensureChallengeReward(ref, p);
    }
    if (total <= 0) return;
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('挑战完成，+$total 积分已到账'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 标题行：养成健康的日常习惯 N/9 🏆（N 只统计挑战成功后的数量）
  Widget _buildTitle(int completed, int total) {
    return Text.rich(
      TextSpan(
        text: '养成健康的日常习惯 ',
        style: const TextStyle(
          color: Color(0xFF8E8E93),
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        children: [
          TextSpan(
            text: '$completed/$total ',
            style: const TextStyle(
              color: Color(0xFF6B6B70),
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(text: '🏆'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    // 挑战目录：服务端下发，未就绪时用内置 9 张
    final plans = challengePlans(ref);
    // 挑战完成即自动发放积分（不打开详情页也能到账）
    final overview = ref.watch(challengeOverviewProvider).valueOrNull;
    if (overview != null) _settleCompleted(overview);
    // 标题的 N/9 只计「挑战成功」的挑战：开始但未完成不计；
    // 已领取奖励的记录在结束后仍保留（claimed），成功数不会回退
    final completed =
        overview?.values.where((p) => p.completed || p.claimed).length ?? 0;
    // 后台把所有挑战下架后目录为空：保留标题与占位提示，避免空堆叠计算
    if (plans.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 44),
        child: Column(
          children: [
            const SizedBox(height: 26),
            _buildTitle(completed, 0),
            const SizedBox(height: 36),
            const Text(
              '暂无挑战，敬请期待',
              style: TextStyle(color: Color(0xFFA6ADB1), fontSize: 15),
            ),
          ],
        ),
      );
    }
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
        final n = plans.length;
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
                    plans: plans,
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
                        child: Center(child: _buildTitle(completed, n)),
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
    required this.plans,
    required this.fullW,
    required this.cardW,
    required this.cardH,
    required this.stickTop,
    required this.scrollPixels,
  });

  /// 当前挑战目录（服务端下发或内置兜底）
  final List<HabitData> plans;

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
    final n = widget.plans.length;
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
          data: widget.plans[i],
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
            // 角色插画：右侧底部锚定，压边溢出被裁剪（等比缩小到 180，
            // 让标题与角色之间留出呼吸感）
            Positioned(
              right: -53,
              bottom: -31,
              child: SizedBox(
                width: 180,
                height: 180,
                child: ChallengeArt(asset: data.asset, fit: BoxFit.contain),
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
                      '${data.days} 天挑战',
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
