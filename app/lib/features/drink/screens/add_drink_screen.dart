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
/// 1. 水杯里的水量支持手指上下拖动调节（10ml ~ 当前模式上限）
/// 2. 左下角按钮切换杯装(1000ml)/桶装(2000ml)
/// 3. 右下角九宫格 → 自定义量输入
/// 4. 气泡从水杯底部随机向上冒出（仅在有水部分）
/// 5. 容量滚轮选择预设档位，选中项放大加粗
class AddDrinkScreen extends ConsumerStatefulWidget {
  const AddDrinkScreen({super.key});

  @override
  ConsumerState<AddDrinkScreen> createState() => _AddDrinkScreenState();
}

class _AddDrinkScreenState extends ConsumerState<AddDrinkScreen>
    with TickerProviderStateMixin {
  static const _brandCyan = Color(0xFF2EC9D3);
  static const _textDark = Color(0xFF333333);
  static const _hintGray = Color(0xFFC7C7CC);

  /// 杯装 / 桶装模式
  bool _bottle = false; // false=杯装 true=桶装

  /// 容量档位（随模式变化）—每个选项都是杯子的最大容量
  List<int> get _volumes =>
      _bottle ? [500, 1000, 2000] : [500, 750, 1000];

  late final PageController _pageCtrl;
  late final AnimationController _waveCtrl;
  late final AnimationController _bubbleCtrl;

  /// 当前选中的容量档位索引（决定杯子最大容量）
  int _cupMaxIdx = 0;
  /// 杯子最大容量 = 选中档位值
  int get _cupMax => _volumes[_cupMaxIdx];
  /// 当前水量（默认=杯子最大容量即全满）
  int _selected = 500;

  @override
  void initState() {
    super.initState();
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

  /// 手指上下拖动调节水量（10 ~ 杯子最大容量）
  void _onVerticalDragUpdate(DragUpdateDetails d, double cupH) {
    setState(() {
      final delta = -d.delta.dy * (_cupMax / cupH);
      _selected = (_selected + delta).round().clamp(10, _cupMax);
    });
  }

  /// 选中容量档位 → 杯子最大容量变更，水默认全满
  void _onVolumeSelected(int idx) {
    setState(() {
      _cupMaxIdx = idx;
      _selected = _cupMax; // 默认全满
    });
  }

  /// 切换杯装/桶装
  void _toggleBottle() {
    setState(() {
      _bottle = !_bottle;
      _cupMaxIdx = 0;
      _selected = _cupMax; // 切换后默认全满
      _pageCtrl.jumpToPage(0);
    });
  }

  Future<void> _submit() async {
    final entry = DrinkEntry.create(
      beverage: Beverage.presets.firstWhere(
        (b) => b.id == 'water_pure',
        orElse: () => Beverage.presets.first,
      ),
      volumeMl: _selected,
    );
    await ref.read(todayEntriesProvider.notifier).add(entry);
    if (mounted) Navigator.pop(context, true);
  }

  /// 自定义量输入
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
              backgroundColor: _brandCyan,
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
      // AnnotatedRegion 包裹整个页面：状态栏图标深色，且不占用布局空间
      // 注意不能用零高度 appBar——它会让 SafeArea 误以为状态栏已被处理，
      // 导致 X 按钮顶到状态栏区域（看不见也点不到）
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: LayoutBuilder(
            builder: (ctx, constraints) {
              final cupH = constraints.maxHeight * 0.42;
              return Column(
                children: [
                  // 1. 右上角 X 关闭按钮（紧贴安全区顶部）
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, right: 12),
                      child: _CloseButton(
                          onTap: () => Navigator.pop(context)),
                    ),
                  ),
                  // 2. 大水杯（支持手指上下拖动调节水量）
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onVerticalDragUpdate: (d) =>
                            _onVerticalDragUpdate(d, cupH),
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          width: 280,
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
                                size: Size(280, cupH),
                                painter: _BigCupPainter(
                                  fillRatio: ratio,
                                  phase: _waveCtrl.value * math.pi * 2,
                                  bubbleSeed: _bubbleCtrl.value,
                                  isBottle: _bottle,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 3. 容量滚轮：选中项实时显示杯内当前水量（拖动联动），
                  //    未选中项显示各杯型的最大容量
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
                            // 选中项 → 实时当前水量；未选中 → 杯型容量
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
                  // 5. 底部按钮组
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 左下角：杯装/桶装切换
                        _RoundIcon(
                          icon: _bottle
                              ? Icons.water_drop_outlined
                              : Icons.local_drink,
                          label: _bottle ? '桶装' : '杯装',
                          onTap: _toggleBottle,
                        ),
                        // 中间 "+ 水" CTA
                        SizedBox(
                          width: 140,
                          height: 60,
                          child: ElevatedButton(
                            onPressed: _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _brandCyan,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(30)),
                              textStyle: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600),
                            ),
                            child: const Text('+ 水'),
                          ),
                        ),
                        // 右下角九宫格（自定义量）
                        _RoundIcon(
                          icon: Icons.apps,
                          label: '自定义',
                          onTap: _showCustomInput,
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

/// 灰色圆形关闭按钮（紧贴安全区）
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

/// 浅青色圆形图标按钮 + 下方标签
class _RoundIcon extends StatelessWidget {
  const _RoundIcon(
      {required this.icon, required this.onTap, this.label});
  final IconData icon;
  final VoidCallback onTap;
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
              color: const Color(0xFF2EC9D3).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF2EC9D3), size: 24),
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

/// 大水杯/水瓶 Painter
///
/// 杯装：对称圆台体（上宽下窄，侧壁直线收敛，底部大圆角）
/// 桶装：超椭圆主体 + 顶部台阶式小瓶口 + 大圆角底座
class _BigCupPainter extends CustomPainter {
  _BigCupPainter({
    required this.fillRatio,
    required this.phase,
    required this.bubbleSeed,
    required this.isBottle,
  });
  final double fillRatio;
  final double phase;
  final double bubbleSeed;
  final bool isBottle;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cup = isBottle ? _bottlePath(w, h) : _cupPath(w, h);

    // 1. 空杯底色
    canvas.drawPath(cup, Paint()..color = const Color(0xFFECECEC));

    // 2. 液体（裁剪到杯内）
    canvas.save();
    canvas.clipPath(cup);
    final surfaceY = h - h * fillRatio;

    // 液体填充
    const samples = 30;
    final path = Path()..moveTo(0, h);
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final x = w * t;
      final wave = math.sin(t * math.pi * 2 + phase) * 4;
      path.lineTo(x, surfaceY + wave);
    }
    path..lineTo(w, h)..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF2EC9D3));

    // 液面高光线
    final surface = Path();
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final x = w * t;
      final wave = math.sin(t * math.pi * 2 + phase) * 4;
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

    // 3. 底部冒气泡（独立动画，不受拖动影响）
    //    仅在有水区域 surfaceY~h 内显示
    if (fillRatio > 0.04) {
      // 固定种子 → 气泡 x 位置和大小稳定不抖动
      final rng = math.Random(42);
      const bubbleCount = 7;
      for (var i = 0; i < bubbleCount; i++) {
        // 每个气泡有不同周期偏移
        final cycleOffset = i * 0.14;
        final t = (bubbleSeed + cycleOffset) % 1.0;
        // x 位置稳定（基于固定种子）
        final bx = w * (0.18 + rng.nextDouble() * 0.64);
        // y 从底部向上移动，范围限制在有水部分
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

    // 4. 杯口高光条
    if (isBottle) {
      // 桶装：在瓶口位置画高光
      final neckW = w * 0.28;
      final neckX = (w - neckW) / 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(neckX, -2, neckW, 5),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.7),
      );
    } else {
      // 杯装：杯口高光
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(w * 0.08, -2, w * 0.84, 5),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.8),
      );
    }
  }

  /// 杯装路径：对称圆台体（上宽下窄，侧壁直线，底部大圆角）
  Path _cupPath(double w, double h) {
    // 上宽下窄：顶部内缩少，底部内缩多
    final insetTop = w * 0.06;   // 顶部每侧内缩 6%
    final insetBottom = w * 0.22; // 底部每侧内缩 22%（形成收敛斜边）
    final r = w * 0.12;           // 圆角半径

    // 四个角点（完全对称）
    final tl = Offset(insetTop, 0);
    final tr = Offset(w - insetTop, 0);
    final br = Offset(w - insetBottom, h);
    final bl = Offset(insetBottom, h);

    // 沿 from→to 方向走 dist 距离的点
    Offset along(Offset from, Offset to, double dist) {
      final d = to - from;
      final len = d.distance;
      return from + d * (dist / len);
    }

    // 顺时针：左上圆角 → 顶边 → 右上圆角 → 右斜边 → 右下圆角 → 底边 → 左下圆角 → 左斜边
    // 关键：每条 lineTo 必须沿着当前边走到距下一个角点 r 距离处，方向不能搞反
    return Path()
      ..moveTo(tl.dx + r, tl.dy)           // 起点：顶边左上角 +r
      ..lineTo(tr.dx - r, tr.dy)           // 顶边 → 右上角 -r
      ..quadraticBezierTo(                 // 右上圆角
          tr.dx, tr.dy, along(tr, br, r).dx, along(tr, br, r).dy)
      ..lineTo(                            // 右斜边 → 距 br 为 r（沿右斜边向上）
          along(br, tr, r).dx, along(br, tr, r).dy)
      ..quadraticBezierTo(                 // 右下圆角
          br.dx, br.dy, along(br, bl, r).dx, along(br, bl, r).dy)
      ..lineTo(bl.dx + r, bl.dy)           // 底边 → 左下角 +r
      ..quadraticBezierTo(                 // 左下圆角
          bl.dx, bl.dy, along(bl, tl, r).dx, along(bl, tl, r).dy)
      ..lineTo(                            // 左斜边 → 距 tl 为 r（沿左斜边向下）
          along(tl, bl, r).dx, along(tl, bl, r).dy)
      ..quadraticBezierTo(                 // 左上圆角
          tl.dx, tl.dy, tl.dx + r, tl.dy)
      ..close();
  }

  /// 桶装路径：超椭圆主体 + 顶部台阶式小瓶口 + 大圆角底座
  Path _bottlePath(double w, double h) {
    final neckH = h * 0.08;  // 瓶口高度占比 8%
    final neckW = w * 0.28;  // 瓶口宽度
    final neckX = (w - neckW) / 2; // 瓶口左边 x
    final bodyTop = neckH;   // 瓶身顶部 y
    final rTop = w * 0.20;   // 肩部圆角（大弧度过渡）
    final rBot = w * 0.15;   // 底部圆角

    // 瓶身边缘内缩（略微）
    final bodyInset = w * 0.03;

    // 主体四角
    final tl = Offset(bodyInset, bodyTop);
    final tr = Offset(w - bodyInset, bodyTop);
    final br = Offset(w - bodyInset, h);
    final bl = Offset(bodyInset, h);

    return Path()
      // 瓶口左边 → 瓶口顶边 → 瓶口右边
      ..moveTo(neckX, 0)
      ..lineTo(neckX + neckW, 0)
      // 瓶口右下角 → 肩部右上方（圆角过渡到瓶身右侧）
      ..lineTo(neckX + neckW, bodyTop)
      ..quadraticBezierTo(
          tr.dx, bodyTop, tr.dx, bodyTop + rTop)
      // 瓶身右侧直线向下
      ..lineTo(tr.dx, br.dy - rBot)
      // 右下圆角
      ..quadraticBezierTo(
          br.dx, br.dy, br.dx - rBot, br.dy)
      // 底边
      ..lineTo(bl.dx + rBot, bl.dy)
      // 左下圆角
      ..quadraticBezierTo(
          bl.dx, bl.dy, bl.dx, bl.dy - rBot)
      // 瓶身左侧直线向上
      ..lineTo(tl.dx, bodyTop + rTop)
      // 肩部左上方（圆角过渡到瓶口左侧）
      ..quadraticBezierTo(
          tl.dx, bodyTop, neckX, bodyTop)
      // 瓶口左边
      ..lineTo(neckX, 0)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _BigCupPainter old) =>
      old.fillRatio != fillRatio ||
      old.phase != phase ||
      old.bubbleSeed != bubbleSeed ||
      old.isBottle != isBottle;
}
