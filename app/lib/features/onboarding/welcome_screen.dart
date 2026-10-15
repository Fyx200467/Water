import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../home/providers/home_providers.dart';
import 'unit_selection_sheet.dart';
import 'widgets/animal_silhouette.dart';
import 'widgets/selling_points_carousel.dart';

/// PRD 对标 §开屏体验：欢迎页
///
/// 动画时间线（v4）：
/// 1. 0~16s 羊驼→熊猫→老虎 依次轮换 + 慢速顺序填色（每只 5s）
/// 2. 16~25s 横向轮播滑动（左滑入右滑出，每只 2s）
/// 3. 25s+ 触发持续全屏礼炮雨 + 顶部饮料杯定格为水滴
///          用户点击"开始使用"→ 弹出单位选择 → 进入 onboarding
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _master;
  late final AnimationController _carousel; // 横向轮播
  bool _confettiStarted = false;
  bool _carouselActive = false;

  static const _accent = Color(0xFF4DB8D8);

  static const _animals = <String>['octopus', 'panda', 'llama'];

  static const _tInitialEnd = 16.0; // 初始轮换结束（每只 5s）
  static const _tCarouselEnd = 25.0; // 轮播结束 → 礼炮
  static const _tFillPerAnimal = 5.0; // 每只填色 5s

  @override
  void initState() {
    super.initState();
    _master = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..forward();
    _carousel = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2), // 每只 2s
    );

    _master.addListener(_onMasterTick);
  }

  void _onMasterTick() {
    final t = _master.value * _master.duration!.inSeconds;
    if (t >= _tInitialEnd && !_carouselActive) {
      _carouselActive = true;
      _carousel.repeat();
    }
    if (t >= _tCarouselEnd && !_confettiStarted) {
      _confettiStarted = true;
      _carousel.stop();
      // ConfettiRain widget 内部自带 controller，只需 setState 让 active=true
      setState(() {});
    }
  }

  @override
  void dispose() {
    _master.removeListener(_onMasterTick);
    _master.dispose();
    _carousel.dispose();
    super.dispose();
  }

  double _seg(double totalSec, double a, double b) =>
      ((totalSec - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
            child: Column(
              children: [
                // 顶部：卖点文案轮换（对标原版：无插画，彩色✓文案淡入淡出）
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    children: [
                      // 三饮品循环置换动画（对标用户截图：中顶杯左滑降底
                      // → 右底杯左滑升顶 → 左底杯右滑补位，循环往复）
                      const DrinksTrioCarousel(),
                      const SizedBox(height: 8),
                      const SellingPointsCarousel(width: 260),
                      const SizedBox(height: 8),
                      Text(
                        '跟踪你的饮水量',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF2C3E50),
                        ),
                      ),
                    ],
                  ),
                ),

                // 中央：动物轮播
                Expanded(child: Center(child: _buildAnimalLayer())),

                // 底部：按钮水平居中 + 语言标识
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 180,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _onStart,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2C3E50),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          child: const Text('开始使用'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const _LangChip(),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }

  /// 动物层：初始轮换 → 轮播滑动 → 礼炮定格
  Widget _buildAnimalLayer() {
    return AnimatedBuilder(
      animation: Listenable.merge([_master, _carousel]),
      builder: (ctx, _) {
        final t = _master.value * _master.duration!.inSeconds;

        if (_confettiStarted) {
          return AnimalSilhouette(
            animalId: _animals.last,
            fillRatio: 1.0,
            accentColor: _accent,
            size: 300,
          );
        }

        if (_carouselActive) {
          return _buildCarousel();
        }

        return _buildInitialRotation(t);
      },
    );
  }

  /// 横向轮播（左滑入右滑出）
  Widget _buildCarousel() {
    // _carousel.value: 0→1 一个循环
    // 把它映射到 _animals.length 次循环
    final cycleProgress = _carousel.value * _animals.length;
    final currentIndex = cycleProgress.floor() % _animals.length;
    final nextIndex = (currentIndex + 1) % _animals.length;
    final slideProgress = cycleProgress - cycleProgress.floor();

    // 当前动物从 0 向右滑出（+280），下一只从左滑入（-280→0）
    final curOffset = slideProgress * 280;
    final nextOffset = (1 - slideProgress) * -280;

    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: Offset(curOffset, 0),
            child: Opacity(
              opacity: 1 - slideProgress * 0.5,
              child: AnimalSilhouette(
                key: ValueKey('carousel_$currentIndex'),
                animalId: _animals[currentIndex],
                fillRatio: 1.0,
                accentColor: _accent,
                size: 300,
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(nextOffset, 0),
            child: Opacity(
              opacity: 0.5 + slideProgress * 0.5,
              child: AnimalSilhouette(
                key: ValueKey('carousel_$nextIndex'),
                animalId: _animals[nextIndex],
                fillRatio: 1.0,
                accentColor: _accent,
                size: 300,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 初始轮换（3 只动物依次登场、慢速填色）
  Widget _buildInitialRotation(double t) {
    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _slot(0, t),
          _slot(1, t),
          _slot(2, t),
        ],
      ),
    );
  }

  Widget _slot(int index, double t) {
    final animal = _animals[index];
    final startT = index * _tFillPerAnimal;
    final endT = (index + 1) * _tFillPerAnimal;
    final enterDur = 0.6;
    final fillStart = startT + enterDur;
    final fillEnd = endT - 0.6;
    final exitStart = endT;
    final exitEnd = endT + 0.8;

    double offset;
    double opacity;
    double fill;

    if (index == 0) {
      fill = _seg(t, fillStart, fillEnd);
      final exit = _seg(t, exitStart, exitEnd);
      offset = exit * 280;
      opacity = 1 - exit;
    } else if (index == 1) {
      final enter = _seg(t, startT, startT + enterDur);
      final exit = _seg(t, exitStart, exitEnd);
      fill = _seg(t, fillStart, fillEnd);
      offset = (1 - enter) * -280 + exit * 280;
      opacity = (t < startT) ? 0 : (1 - exit);
    } else {
      final enter = _seg(t, startT, startT + enterDur);
      fill = _seg(t, fillStart, fillEnd);
      offset = (1 - enter) * -280;
      opacity = (t < startT) ? 0 : 1;
    }

    if (opacity <= 0.01) return const SizedBox.shrink();

    return Transform.translate(
      offset: Offset(offset, 0),
      child: Opacity(
        opacity: opacity,
        child: AnimalSilhouette(
          animalId: animal,
          fillRatio: fill,
          accentColor: _accent,
          size: 300,
        ),
      ),
    );
  }

  void _onStart() async {
    final unit = await UnitSelectionSheet.show(context);
    if (unit != null && mounted) {
      await ref.read(preferredUnitProvider.notifier).select(unit);
      if (mounted) context.go('/onboarding');
    }
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Color(0xFFFF8C42),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Text(
            '简',
            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '简体中文',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }
}
