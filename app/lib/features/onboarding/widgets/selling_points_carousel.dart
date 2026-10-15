import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 卖点文案轮播（对标原版欢迎页录屏逆向）：
///
/// 原版欢迎页顶部没有常驻插画——只有三组彩色 ✓ 卖点文案
/// 每 2 秒淡入淡出轮换：
///   红「填满 100+ 角色」→ 青「更多炫酷功能即将发布」→ 绿「跟踪 150 多种饮料」
class SellingPointsCarousel extends StatefulWidget {
  const SellingPointsCarousel({super.key, this.width = 260});

  final double width;

  @override
  State<SellingPointsCarousel> createState() => _SellingPointsCarouselState();
}

class _SellingPointsCarouselState extends State<SellingPointsCarousel> {
  /// 单组展示时长（对标原版录屏每组约 2s）
  static const _period = Duration(milliseconds: 2000);

  /// 切换过渡时长
  static const _swap = Duration(milliseconds: 350);

  int _index = 0;

  static const _sellColors = <Color>[
    Color(0xFFE8446A), // 红粉：角色
    Color(0xFF2BB3CE), // 青：功能
    Color(0xFF3FA65C), // 绿：饮料
  ];

  static const _sellTexts = <String>[
    '填满 100+ 角色',
    '更多炫酷功能即将发布',
    '跟踪 150 多种饮料',
  ];

  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future<void>.delayed(_period);
      while (mounted) {
        setState(() => _index = (_index + 1) % 3);
        await Future<void>.delayed(_period);
      }
      return false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: 24,
      child: AnimatedSwitcher(
        duration: _swap,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        child: Row(
          key: ValueKey(_index),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_rounded, color: _sellColors[_index], size: 17),
            const SizedBox(width: 4),
            Text(
              _sellTexts[_index],
              style: TextStyle(
                color: _sellColors[_index],
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 三饮品循环置换动画（对标用户提供的原版截图）：
///
/// 三个随机饮品图标位于「左底 / 右底 / 中顶」三槽位（中顶杯最大、最上层），
/// 每轮置换：中顶杯向左滑动下降到底层左位 → 右底杯向左滑动上升为顶层
/// → 左底杯向右滑动补位到右底 → 循环往复。
///
/// 节奏（1.6s 一轮）：静止(0~0.44) → easeInOutCubic 移动(0.44~0.88) → 静止
/// 跨圈瞬间槽位置换 slot=(slot+1)%3：帧内插值 from=当前槽位，
/// p=0 显示的正是上圈动画终点 → 无跳变
/// 绘制层级按当前 scale 升序：大杯最后画 = 最上层，动画中随插值自然换层
class DrinksTrioCarousel extends StatefulWidget {
  const DrinksTrioCarousel({super.key});

  @override
  State<DrinksTrioCarousel> createState() => _DrinksTrioCarouselState();
}

class _DrinksTrioCarouselState extends State<DrinksTrioCarousel>
    with SingleTickerProviderStateMixin {
  /// 已有饮品图标池（assets/images/drinks/ 的 13 个分类饮品 SVG）
  static const _drinkPool = <String>[
    'water_pure', 'tea', 'coffee', 'milk_tea', 'milk_milk', 'milk_juice',
    'soda', 'soup_porridge', 'soup_chicken', 'alcohol_beer', 'alcohol_wine',
    'alcohol_spirits', 'llama',
  ];

  /// 槽位位姿：0=左底 1=右底 2=中顶（offset 相对画布中心，y 向下为正）
  static const _poses = <_SlotPose>[
    _SlotPose(Offset(-44, 6), 0.68, -0.10),
    _SlotPose(Offset(44, 5), 0.70, 0.10),
    _SlotPose(Offset(0, -6), 1.00, 0),
  ];

  static const _moveStart = 0.44;
  static const _moveEnd = 0.88;
  static const _cupBase = 68.0;

  late final AnimationController _ctrl;
  late final List<String> _cups; // 每次启动随机抽中的 3 个饮品图标
  late final List<int> _slotOfCup; // 每杯当前槽位
  double _last = 0;

  @override
  void initState() {
    super.initState();
    final pool = List<String>.of(_drinkPool)..shuffle(Random());
    _cups = pool.sublist(0, 3);
    _slotOfCup = [0, 1, 2];
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _ctrl.addListener(_onTick);
  }

  /// 跨圈瞬间置换槽位（与上圈动画终点无缝衔接）
  void _onTick() {
    final v = _ctrl.value;
    if (_last > 0.9 && v < 0.1) {
      for (var i = 0; i < 3; i++) {
        _slotOfCup[i] = (_slotOfCup[i] + 1) % 3;
      }
    }
    _last = v;
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTick);
    _ctrl.dispose();
    super.dispose();
  }

  double _moveP(double t) {
    if (t < _moveStart) return 0;
    if (t >= _moveEnd) return 1;
    final p = (t - _moveStart) / (_moveEnd - _moveStart);
    return Curves.easeInOutCubic.transform(p);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 140,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) {
          final p = _moveP(_ctrl.value);
          // 绘制顺序按当前 scale 升序：大杯最后画（最上层）
          final order = List<int>.generate(3, (i) => i)
            ..sort((a, b) => _scaleOf(a, p).compareTo(_scaleOf(b, p)));
          return Stack(
            alignment: Alignment.center,
            children: [for (final i in order) _cup(i, p)],
          );
        },
      ),
    );
  }

  double _scaleOf(int cup, double p) {
    final slot = _slotOfCup[cup];
    return _lerp(_poses[slot].scale, _poses[(slot + 1) % 3].scale, p);
  }

  Widget _cup(int cup, double p) {
    final slot = _slotOfCup[cup];
    final from = _poses[slot];
    final to = _poses[(slot + 1) % 3];
    final size = _cupBase * _lerp(from.scale, to.scale, p);
    return Transform.translate(
      offset: Offset(
        _lerp(from.offset.dx, to.offset.dx, p),
        _lerp(from.offset.dy, to.offset.dy, p),
      ),
      child: Transform.rotate(
        angle: _lerp(from.tilt, to.tilt, p),
        alignment: Alignment.center,
        child: SvgPicture.asset(
          'assets/images/drinks/${_cups[cup]}.svg',
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// 槽位位姿：偏移 / 缩放 / 倾斜（弧度）
class _SlotPose {
  const _SlotPose(this.offset, this.scale, this.tilt);

  final Offset offset;
  final double scale;
  final double tilt;
}
