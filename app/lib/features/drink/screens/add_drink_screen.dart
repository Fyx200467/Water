import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart'
    show SystemUiOverlayStyle, FilteringTextInputFormatter;

import '../../../shared/models/beverage.dart';
import '../../../shared/models/drink_entry.dart';
import '../../home/providers/home_providers.dart';

/// 对标原版 WaterLlama 加水页（全屏模态）
///
/// 交互要点：
/// 1. 容器造型随饮品种类变化（茶杯/咖啡杯/果汁杯/牛奶瓶/啤酒杯/红酒杯等）
/// 2. 液体颜色匹配饮品，支持手指上下拖动调节液量
/// 3. 容量滚轮选择预设档位，选中项放大加粗
/// 4. 气泡从容器底部随机向上冒出（仅在有液体部分）
class AddDrinkScreen extends ConsumerStatefulWidget {
  const AddDrinkScreen({super.key, this.beverageId = 'water_pure'});

  final String beverageId;

  @override
  ConsumerState<AddDrinkScreen> createState() => _AddDrinkScreenState();
}

class _AddDrinkScreenState extends ConsumerState<AddDrinkScreen>
    with TickerProviderStateMixin {
  static const _textDark = Color(0xFF333333);
  static const _hintGray = Color(0xFFC7C7CC);

  late final Beverage _beverage;

  /// 容量档位（饮品默认档位）
  List<int> get _volumes => [
        _beverage.defaultMl,
        (_beverage.defaultMl * 1.3).round(),
        (_beverage.defaultMl * 1.5).round(),
      ];

  late final PageController _pageCtrl;
  late final AnimationController _waveCtrl;
  late final AnimationController _bubbleCtrl;

  /// 当前选中的容量档位索引
  int _cupMaxIdx = 0;
  int get _cupMax => _volumes[_cupMaxIdx];
  int _selected = 0;

  /// 饮品主题色（液体 + 按钮）——优先使用饮品独立液体色
  Color get _drinkColor => _beverage.color;

  @override
  void initState() {
    super.initState();
    _beverage = Beverage.presets.firstWhere(
      (b) => b.id == widget.beverageId,
      orElse: () => Beverage.presets.first,
    );
    _selected = _beverage.defaultMl;
    _pageCtrl = PageController(viewportFraction: 0.5, initialPage: 0);
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _bubbleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _waveCtrl.dispose();
    _bubbleCtrl.dispose();
    super.dispose();
  }

  /// 液面高度比例 = 当前水量 / 杯子最大容量，上限 0.88 留出杯口距离
  double get _fillRatio =>
      (_selected / _cupMax).clamp(0.02, 0.88);

  void _onVerticalDragUpdate(DragUpdateDetails d, double cupH) {
    setState(() {
      final delta = -d.delta.dy * (_cupMax / cupH);
      _selected = (_selected + delta).round().clamp(10, _cupMax);
    });
  }

  void _onVolumeSelected(int idx) {
    setState(() {
      _cupMaxIdx = idx;
      _selected = _cupMax;
    });
  }

  Future<void> _submit() async {
    final entry = DrinkEntry.create(
      beverage: _beverage,
      volumeMl: _selected,
    );
    await ref.read(todayEntriesProvider.notifier).add(entry);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _showCustomInput() async {
    final ctrl = TextEditingController(text: '$_selected');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('自定义量', textAlign: TextAlign.center),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            suffixText: 'ml',
            helperText: '范围 10 ~ $_cupMax ml',
          ),
          onSubmitted: (v) {
            final n = int.tryParse(v);
            if (n != null) Navigator.pop(ctx, n.clamp(10, _cupMax));
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: _hintGray)),
          ),
          ElevatedButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text);
              if (n != null) Navigator.pop(ctx, n.clamp(10, _cupMax));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _drinkColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      setState(() => _selected = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: LayoutBuilder(
            builder: (ctx, constraints) {
              final cupH = constraints.maxHeight * 0.44;
              return Column(
                children: [
                  // 1. 右上角 X 关闭按钮
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, right: 12),
                      child: _CloseButton(
                          onTap: () => Navigator.pop(context)),
                    ),
                  ),
                  // 2. 大饮品容器（支持手指上下拖动调节液量）
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onVerticalDragUpdate: (d) =>
                            _onVerticalDragUpdate(d, cupH),
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          width: 260,
                          height: cupH,
                          child: AnimatedBuilder(
                            animation: Listenable.merge(
                                [_waveCtrl, _bubbleCtrl]),
                            builder: (ctx, _) =>
                                TweenAnimationBuilder<double>(
                              tween: Tween(end: _fillRatio),
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              builder: (ctx, ratio, __) => CustomPaint(
                                size: Size(260, cupH),
                                painter: _DrinkContainerPainter(
                                  beverageId: _beverage.id,
                                  fillRatio: ratio,
                                  color: _drinkColor,
                                  phase: _waveCtrl.value * math.pi * 2,
                                  bubbleSeed: _bubbleCtrl.value,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 3. 容量滚轮
                  SizedBox(
                    height: 64,
                    child: AnimatedBuilder(
                      animation: _pageCtrl,
                      builder: (ctx, _) {
                        final page =
                            _pageCtrl.hasClients ? (_pageCtrl.page ?? 0) : 0.0;
                        return PageView.builder(
                          controller: _pageCtrl,
                          itemCount: _volumes.length,
                          itemBuilder: (ctx, i) {
                            final dist = (i - page).abs();
                            final selected = dist < 0.5;
                            final label =
                                selected ? '${_selected}ml' : '${_volumes[i]}ml';
                            return GestureDetector(
                              onTap: () {
                                _pageCtrl.animateToPage(i,
                                    duration:
                                        const Duration(milliseconds: 200),
                                    curve: Curves.easeOut);
                              },
                              child: Center(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: selected
                                        ? (38 - dist * 6).clamp(30.0, 38.0)
                                        : 30,
                                    fontWeight: selected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color:
                                        selected ? _textDark : _hintGray,
                                  ),
                                ),
                              ),
                            );
                          },
                          onPageChanged: (i) => _onVolumeSelected(i),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 4. 底部按钮组
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 左侧：自定义量（九宫格）
                        _RoundIcon(
                          icon: Icons.apps,
                          label: '自定义',
                          color: _drinkColor,
                          onTap: _showCustomInput,
                        ),
                        // 中间 "+ 饮品名" CTA
                        SizedBox(
                          width: 160,
                          height: 60,
                          child: ElevatedButton(
                            onPressed: _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _drinkColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(30)),
                              textStyle: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('+ '),
                                Text(_beverage.name),
                              ],
                            ),
                          ),
                        ),
                        // 右侧：占位（原版的更多选项按钮）
                        _RoundIcon(
                          icon: Icons.more_horiz,
                          label: '更多',
                          color: _drinkColor,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
            ),
          ),
        ),
      ),
    );
  }
}

/// 灰色圆形关闭按钮
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Color(0xFFE9E9EB),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, color: Color(0xFF8E8E93), size: 22),
      ),
    );
  }
}

/// 圆形图标按钮 + 下方标签
class _RoundIcon extends StatelessWidget {
  const _RoundIcon(
      {required this.icon, required this.onTap, required this.color, this.label});
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label!,
              style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// 饮品容器 Painter
// 根据 beverageId 绘制不同造型：水杯/茶杯/咖啡杯/果汁杯/牛奶瓶/汤碗/啤酒杯/红酒杯/烈酒杯
// ============================================================================

class _DrinkContainerPainter extends CustomPainter {
  _DrinkContainerPainter({
    required this.beverageId,
    required this.fillRatio,
    required this.color,
    required this.phase,
    required this.bubbleSeed,
  });

  final String beverageId;
  final double fillRatio;
  final Color color;
  final double phase;
  final double bubbleSeed;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 根据饮品类型获取容器路径
    final container = _containerPath(w, h);

    // 1. 空容器底色（浅灰）
    canvas.drawPath(container, Paint()..color = const Color(0xFFECECEC));

    // 2. 液体（裁剪到容器内）
    canvas.save();
    canvas.clipPath(container);

    final surfaceY = h - h * fillRatio;

    // 液体填充（带轻微波浪）
    const samples = 30;
    final liquidPath = Path()..moveTo(0, h);
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final x = w * t;
      final wave = math.sin(t * math.pi * 2 + phase) * 3;
      liquidPath.lineTo(x, surfaceY + wave);
    }
    liquidPath.lineTo(w, h);
    liquidPath.close();
    canvas.drawPath(liquidPath, Paint()..color = color);

    // 液面高光线
    final surface = Path();
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final x = w * t;
      final wave = math.sin(t * math.pi * 2 + phase) * 3;
      if (i == 0) {
        surface.moveTo(x, surfaceY + wave);
      } else {
        surface.lineTo(x, surfaceY + wave);
      }
    }
    canvas.drawPath(
      surface,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 3. 装饰元素（绘制在液体之上）
    _drawDecorations(canvas, w, h, surfaceY);

    // 4. 气泡（有水时）
    if (fillRatio > 0.04) {
      final rng = math.Random(42);
      const bubbleCount = 6;
      for (var i = 0; i < bubbleCount; i++) {
        final cycleOffset = i * 0.14;
        final t = (bubbleSeed + cycleOffset) % 1.0;
        final bx = w * (0.18 + rng.nextDouble() * 0.64);
        final by = h - t * (h - surfaceY) * 0.95;
        final br = 2.0 + rng.nextDouble() * 2.5;
        final alpha = (1.0 - t) * 0.4;
        canvas.drawCircle(
          Offset(bx, by),
          br,
          Paint()..color = Colors.white.withValues(alpha: alpha),
        );
      }
    }
    canvas.restore();

    // 5. 容器轮廓线（在裁剪之外绘制）
    canvas.drawPath(
      container,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 6. 容器顶部盖子/杯口高光
    _drawLid(canvas, w, h);
  }

  /// 根据饮品类型返回容器主体路径
  Path _containerPath(double w, double h) {
    if (beverageId.startsWith('tea_')) {
      return _teacupPath(w, h);
    } else if (beverageId.startsWith('coffee_')) {
      return _takeawayCupPath(w, h);
    } else if (beverageId == 'milk_milk') {
      return _milkBottlePath(w, h);
    } else if (beverageId == 'milk_tea' || beverageId == 'milk_juice') {
      return _takeawayCupPath(w, h);
    } else if (beverageId.startsWith('soup_')) {
      return _bowlPath(w, h);
    } else if (beverageId == 'alcohol_beer') {
      return _beerGlassPath(w, h);
    } else if (beverageId == 'alcohol_wine') {
      return _wineGlassPath(w, h);
    } else if (beverageId == 'alcohol_spirits') {
      return _lowballGlassPath(w, h);
    } else {
      // water_* 默认玻璃杯
      return _waterGlassPath(w, h);
    }
  }

  /// 玻璃杯（水）
  Path _waterGlassPath(double w, double h) {
    final insetTop = w * 0.08;
    final insetBottom = w * 0.12;
    final r = w * 0.08;
    final tl = Offset(insetTop, h * 0.05);
    final tr = Offset(w - insetTop, h * 0.05);
    final br = Offset(w - insetBottom, h);
    final bl = Offset(insetBottom, h);
    return Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx - r, br.dy)
      ..quadraticBezierTo(br.dx, br.dy, br.dx, br.dy - r)
      ..lineTo(bl.dx + r, bl.dy)
      ..quadraticBezierTo(bl.dx, bl.dy, bl.dx, bl.dy - r)
      ..close();
  }

  /// 茶杯（带把手）
  Path _teacupPath(double w, double h) {
    final bodyTop = h * 0.28;
    final bodyBottom = h * 0.82;
    final bodyLeft = w * 0.08;
    final bodyRight = w * 0.72;
    final r = w * 0.15;

    final path = Path()
      ..moveTo(bodyLeft, bodyTop)
      ..lineTo(bodyRight, bodyTop)
      ..quadraticBezierTo(bodyRight + r * 0.3, bodyTop, bodyRight + r * 0.3, bodyTop + r * 0.3)
      ..lineTo(bodyRight + r * 0.3, bodyBottom - r * 0.5)
      ..quadraticBezierTo(bodyRight + r * 0.3, bodyBottom, bodyRight - r * 0.3, bodyBottom)
      ..lineTo(bodyLeft + r * 0.5, bodyBottom)
      ..quadraticBezierTo(bodyLeft, bodyBottom, bodyLeft, bodyBottom - r * 0.5)
      ..lineTo(bodyLeft, bodyTop)
      ..close();

    // 把手（右侧 C 形）
    final handlePath = Path()
      ..moveTo(bodyRight, bodyTop + r * 0.5)
      ..quadraticBezierTo(w * 0.95, bodyTop + r * 0.5, w * 0.95, (bodyTop + bodyBottom) / 2)
      ..quadraticBezierTo(w * 0.95, bodyBottom - r * 0.5, bodyRight, bodyBottom - r * 0.5);

    path.addPath(handlePath, Offset.zero);
    return path;
  }

  /// 外带咖啡杯
  Path _takeawayCupPath(double w, double h) {
    final topY = h * 0.18;
    final bottomY = h * 0.92;
    final insetTop = w * 0.18;
    final insetBottom = w * 0.28;
    final r = w * 0.08;

    final tl = Offset(insetTop, topY);
    final tr = Offset(w - insetTop, topY);
    final br = Offset(w - insetBottom, bottomY);
    final bl = Offset(insetBottom, bottomY);

    return Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx - r, br.dy)
      ..quadraticBezierTo(br.dx, br.dy, br.dx, br.dy - r)
      ..lineTo(bl.dx + r, bl.dy)
      ..quadraticBezierTo(bl.dx, bl.dy, bl.dx, bl.dy - r)
      ..close();
  }

  /// 牛奶瓶
  Path _milkBottlePath(double w, double h) {
    final neckTop = h * 0.12;
    final neckBottom = h * 0.25;
    final neckW = w * 0.32;
    final neckX = (w - neckW) / 2;
    final bodyTop = neckBottom;
    final bodyBottom = h * 0.95;
    final bodyInset = w * 0.06;
    final r = w * 0.18;

    return Path()
      ..moveTo(neckX, neckTop)
      ..lineTo(neckX + neckW, neckTop)
      ..lineTo(neckX + neckW, neckBottom)
      ..quadraticBezierTo(w - bodyInset, bodyTop, w - bodyInset, bodyTop + r)
      ..lineTo(w - bodyInset, bodyBottom - r)
      ..quadraticBezierTo(w - bodyInset, bodyBottom, w - bodyInset - r, bodyBottom)
      ..lineTo(bodyInset + r, bodyBottom)
      ..quadraticBezierTo(bodyInset, bodyBottom, bodyInset, bodyBottom - r)
      ..lineTo(bodyInset, bodyTop + r)
      ..quadraticBezierTo(bodyInset, bodyTop, neckX, neckBottom)
      ..close();
  }

  /// 汤碗
  Path _bowlPath(double w, double h) {
    final topY = h * 0.4;
    final bottomY = h * 0.85;
    final r = w * 0.1;
    return Path()
      ..moveTo(w * 0.08, topY)
      ..lineTo(w * 0.92, topY)
      ..quadraticBezierTo(w * 0.92, bottomY, w * 0.5, bottomY)
      ..quadraticBezierTo(w * 0.08, bottomY, w * 0.08, topY)
      ..close()
      ..addOval(Rect.fromLTWH(w * 0.08, topY - r * 0.3, w * 0.84, r * 0.6));
  }

  /// 啤酒杯（郁金香形）
  Path _beerGlassPath(double w, double h) {
    final topY = h * 0.12;
    final midY = h * 0.55;
    final bottomY = h * 0.9;
    final topInset = w * 0.12;
    final midInset = w * 0.32;
    final bottomInset = w * 0.2;
    final r = w * 0.08;

    final tl = Offset(topInset, topY);
    final tr = Offset(w - topInset, topY);
    final ml = Offset(midInset, midY);
    final mr = Offset(w - midInset, midY);
    final bl = Offset(bottomInset, bottomY);
    final br = Offset(w - bottomInset, bottomY);

    return Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..quadraticBezierTo(mr.dx + r, (tr.dy + mr.dy) / 2, mr.dx, mr.dy)
      ..quadraticBezierTo(br.dx - r, (mr.dy + br.dy) / 2, br.dx, br.dy)
      ..lineTo(bl.dx + r, bl.dy)
      ..quadraticBezierTo(bl.dx, bl.dy, bl.dx, bl.dy - r)
      ..lineTo(ml.dx, ml.dy)
      ..quadraticBezierTo(tl.dx - r, (tl.dy + ml.dy) / 2, tl.dx, tl.dy)
      ..close();
  }

  /// 红酒杯
  Path _wineGlassPath(double w, double h) {
    final bowlTop = h * 0.15;
    final bowlBottom = h * 0.58;
    final stemTop = bowlBottom;
    final stemBottom = h * 0.82;
    final baseY = h * 0.88;
    final bowlCx = w * 0.5;
    final bowlRx = w * 0.38;
    final bowlRy = (bowlBottom - bowlTop) * 0.5;
    final stemW = w * 0.06;
    final baseRx = w * 0.22;
    final baseRy = h * 0.04;

    final path = Path();
    // 杯碗（半圆）
    path.moveTo(bowlCx - bowlRx, bowlTop);
    path.quadraticBezierTo(
        bowlCx - bowlRx, bowlBottom, bowlCx, bowlBottom);
    path.quadraticBezierTo(
        bowlCx + bowlRx, bowlBottom, bowlCx + bowlRx, bowlTop);
    path.lineTo(bowlCx - bowlRx, bowlTop);
    path.close();

    // 杯柄
    path.moveTo(bowlCx - stemW / 2, stemTop);
    path.lineTo(bowlCx - stemW / 2, stemBottom);
    path.lineTo(bowlCx + stemW / 2, stemBottom);
    path.lineTo(bowlCx + stemW / 2, stemTop);
    path.close();

    // 底座
    path.addOval(Rect.fromCenter(
      center: Offset(bowlCx, baseY),
      width: baseRx * 2,
      height: baseRy * 2,
    ));

    return path;
  }

  /// 烈酒杯（矮宽杯）
  Path _lowballGlassPath(double w, double h) {
    final topY = h * 0.35;
    final bottomY = h * 0.9;
    final inset = w * 0.1;
    final r = w * 0.12;
    return Path()
      ..moveTo(inset, topY)
      ..lineTo(w - inset, topY)
      ..lineTo(w - inset + r * 0.3, bottomY - r)
      ..quadraticBezierTo(w - inset + r * 0.3, bottomY, w - inset - r * 0.5, bottomY)
      ..lineTo(inset + r * 0.5, bottomY)
      ..quadraticBezierTo(inset - r * 0.3, bottomY, inset - r * 0.3, bottomY - r)
      ..lineTo(inset, topY)
      ..close();
  }

  /// 容器顶部盖子/杯口
  void _drawLid(Canvas canvas, double w, double h) {
    final isTakeaway = beverageId.startsWith('coffee_') ||
        beverageId == 'milk_tea' ||
        beverageId == 'milk_juice';
    final isMilkBottle = beverageId == 'milk_milk';
    if (isTakeaway || isMilkBottle) {
      final lidTop = isMilkBottle ? h * 0.06 : h * 0.12;
      final lidBottom = isMilkBottle ? h * 0.14 : h * 0.2;
      final lidW = isMilkBottle ? w * 0.4 : w * 0.64;
      final lidX = (w - lidW) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(lidX, lidTop, lidW, lidBottom - lidTop),
          Radius.circular(w * 0.04),
        ),
        Paint()..color = const Color(0xFFE8E8E8),
      );
    } else if (beverageId.startsWith('soup_')) {
      // 汤碗口高光
      canvas.drawOval(
        Rect.fromLTWH(w * 0.12, h * 0.38, w * 0.76, h * 0.06),
        Paint()..color = Colors.white.withValues(alpha: 0.6),
      );
    } else {
      // 杯口高光条
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(w * 0.08, h * 0.05 - 2, w * 0.84, 5),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.8),
      );
    }
  }

  /// 装饰元素（咖啡豆/茶包/冰块/吸管等）
  void _drawDecorations(Canvas canvas, double w, double h, double surfaceY) {
    if (beverageId.startsWith('coffee_')) {
      _drawCoffeeBean(canvas, w * 0.5, h * 0.55, w * 0.12);
    } else if (beverageId.startsWith('tea_')) {
      _drawTeaBag(canvas, w, h);
      _drawTeaLeaves(canvas, w, h, surfaceY);
    } else if (beverageId == 'milk_juice') {
      _drawStraw(canvas, w, h);
      _drawIceCubes(canvas, w, h, surfaceY, 3);
    } else if (beverageId == 'milk_tea') {
      _drawTapiocaPearls(canvas, w, h, surfaceY);
    } else if (beverageId == 'alcohol_spirits') {
      _drawIceCubes(canvas, w, h, surfaceY, 4);
    }
  }

  /// 吸管（果汁）
  void _drawStraw(Canvas canvas, double w, double h) {
    final strawX = w * 0.62;
    final strawTop = h * 0.02;
    final strawBottom = h * 0.35;
    final strawW = w * 0.05;
    // 吸管主体
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(strawX, strawTop, strawW, strawBottom - strawTop),
        Radius.circular(strawW * 0.3),
      ),
      Paint()..color = const Color(0xFFFF6B6B),
    );
    // 吸管高光
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(strawX + strawW * 0.2, strawTop, strawW * 0.3, strawBottom - strawTop),
        Radius.circular(strawW * 0.15),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );
  }

  /// 珍珠（奶茶）
  void _drawTapiocaPearls(Canvas canvas, double w, double h, double surfaceY) {
    final pearlPaint = Paint()..color = const Color(0xFF3E2723);
    final rng = math.Random(11);
    for (var i = 0; i < 6; i++) {
      final cx = w * (0.25 + rng.nextDouble() * 0.5);
      final cy = surfaceY + h * (0.3 + rng.nextDouble() * 0.3);
      if (cy > h - h * 0.08) continue;
      final r = w * 0.04;
      canvas.drawCircle(Offset(cx, cy), r, pearlPaint);
      // 高光
      canvas.drawCircle(
        Offset(cx - r * 0.3, cy - r * 0.3),
        r * 0.25,
        Paint()..color = Colors.white.withValues(alpha: 0.4),
      );
    }
  }

  /// 咖啡豆图标
  void _drawCoffeeBean(Canvas canvas, double cx, double cy, double r) {
    final paint = Paint()..color = const Color(0xFFF5E6D3);
    // 左半
    canvas.save();
    canvas.translate(cx - r * 0.5, cy);
    canvas.rotate(-0.4);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r, height: r * 1.6), paint);
    canvas.drawPath(
      Path()
        ..moveTo(0, -r * 0.8)
        ..quadraticBezierTo(r * 0.2, 0, 0, r * 0.8),
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.restore();
    // 右半
    canvas.save();
    canvas.translate(cx + r * 0.5, cy);
    canvas.rotate(0.4);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r, height: r * 1.6), paint);
    canvas.drawPath(
      Path()
        ..moveTo(0, -r * 0.8)
        ..quadraticBezierTo(-r * 0.2, 0, 0, r * 0.8),
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.restore();
  }

  /// 茶包（从顶部垂下的白色标签）
  void _drawTeaBag(Canvas canvas, double w, double h) {
    final bagX = w * 0.35;
    final bagTop = h * 0.28;
    final bagW = w * 0.14;
    final bagH = h * 0.12;
    // 茶包主体
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bagX, bagTop, bagW, bagH),
        Radius.circular(bagW * 0.2),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    // 茶包线
    canvas.drawLine(
      Offset(bagX + bagW / 2, bagTop),
      Offset(bagX + bagW / 2, h * 0.2),
      Paint()
        ..color = const Color(0xFFCCCCCC)
        ..strokeWidth = 1.5,
    );
    // 顶部标签
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bagX - bagW * 0.1, h * 0.14, bagW * 1.2, h * 0.06),
        Radius.circular(bagW * 0.15),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
  }

  /// 茶叶（漂浮在液体中）
  void _drawTeaLeaves(Canvas canvas, double w, double h, double surfaceY) {
    final leafColor = color.withValues(alpha: 0.7);
    final paint = Paint()..color = leafColor;
    // 几片茶叶
    final leaves = [
      Offset(w * 0.3, surfaceY + h * 0.1),
      Offset(w * 0.55, surfaceY + h * 0.2),
      Offset(w * 0.4, surfaceY + h * 0.35),
      Offset(w * 0.6, surfaceY + h * 0.45),
    ];
    for (final pos in leaves) {
      if (pos.dy > h - h * 0.1) continue;
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(pos.dx * 0.01);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: w * 0.06, height: w * 0.03),
        paint,
      );
      canvas.restore();
    }
  }

  /// 冰块
  void _drawIceCubes(Canvas canvas, double w, double h, double surfaceY, int count) {
    final icePaint = Paint()..color = Colors.white.withValues(alpha: 0.7);
    final rng = math.Random(7);
    for (var i = 0; i < count; i++) {
      final cx = w * (0.2 + rng.nextDouble() * 0.6);
      final cy = surfaceY + h * (0.1 + rng.nextDouble() * 0.4);
      if (cy > h - h * 0.08) continue;
      final size = w * (0.06 + rng.nextDouble() * 0.03);
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(rng.nextDouble() * 0.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: size, height: size),
          Radius.circular(size * 0.2),
        ),
        icePaint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _DrinkContainerPainter old) =>
      old.beverageId != beverageId ||
      old.fillRatio != fillRatio ||
      old.color != color ||
      old.phase != phase ||
      old.bubbleSeed != bubbleSeed;
}
