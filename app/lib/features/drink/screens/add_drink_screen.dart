import 'dart:math' as math;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart'
    show SystemUiOverlayStyle, FilteringTextInputFormatter;

import '../../../core/storage/providers.dart';
import '../../../shared/models/beverage.dart';
import '../../../shared/models/drink_entry.dart';
import '../../../shared/models/preferred_unit.dart';
import '../../home/providers/home_providers.dart';
import '../../settings/settings_flags.dart';
import '../providers/custom_beverage_provider.dart';
import '../widgets/svg_container.dart';

/// 对标原版 WaterLlama 加水页（全屏模态）
///
/// 交互要点：
/// 1. 容器造型随饮品种类变化（茶杯/咖啡杯/果汁杯/牛奶瓶/啤酒杯/红酒杯等）
/// 2. 液体颜色匹配饮品，支持手指上下拖动调节液量
/// 3. 容量滚轮选择预设档位，选中项放大加粗
/// 4. 气泡从容器底部随机向上冒出（仅在有液体部分）
class AddDrinkScreen extends ConsumerStatefulWidget {
  const AddDrinkScreen({
    super.key,
    this.beverageId = 'water_pure',
    this.pickOnly = false,
  });

  final String beverageId;

  /// 只选容量不记账：供首页娱乐玩法（弹弓）复用，确认后返回选中 ml
  final bool pickOnly;

  @override
  ConsumerState<AddDrinkScreen> createState() => _AddDrinkScreenState();
}

class _AddDrinkScreenState extends ConsumerState<AddDrinkScreen>
    with TickerProviderStateMixin {
  static const _textDark = Color(0xFF333333);
  static const _hintGray = Color(0xFFC7C7CC);

  late final Beverage _beverage;

  /// 容量档位（内置档位 + 持久化的自定义覆盖，始终升序）
  late List<int> _volumes;

  /// 自定义量持久化 key：{beverageId: [档位数组]}
  static const _kCustomVolumes = 'beverage_custom_volumes';

  late final PageController _pageCtrl;
  late final AnimationController _waveCtrl;
  late final AnimationController _bubbleCtrl;

  /// 连续时间时钟（茶叶粒子浮动相位，永不跳回）
  final Stopwatch _animClock = Stopwatch()..start();

  /// 当前选中的容量档位索引
  int _cupMaxIdx = 0;
  int get _cupMax => _volumes[_cupMaxIdx];
  int _selected = 0;

  /// 饮品主题色（液体 + 按钮）——优先使用饮品独立液体色
  Color get _drinkColor => _beverage.color;

  /// 液体色过浅（乳白类）时按钮文字改用深棕调，保证可读性
  Color get _onDrinkColor => _drinkColor.computeLuminance() > 0.72
      ? Color.lerp(_drinkColor, const Color(0xFF5B4A2F), 0.6)!
      : Colors.white;

  /// 图标主色：浅液体时加深，深液体时保持原色
  Color get _accentIconColor => _drinkColor.computeLuminance() > 0.72
      ? Color.lerp(_drinkColor, const Color(0xFF5B4A2F), 0.6)!
      : _drinkColor;

  @override
  void initState() {
    super.initState();
    // 完整饮品库 = 内置预设 + 自定义饮品（首页快捷栏可跳转自定义饮品加量页）
    final customs = ref.read(customBeveragesProvider);
    _beverage = allBeverages(customs).firstWhere(
      (b) => b.id == widget.beverageId,
      orElse: () => Beverage.presets.first,
    );
    _volumes = [..._beverage.volumes]..sort();
    // 打开即满杯：默认选中中间档位（水 5 档取中 300ml，其他 3 档取中 330ml），
    // 液面 = 该档满杯（满杯时液面与杯口的安全间距由 Painter 保证）
    _cupMaxIdx = (_volumes.length - 1) ~/ 2;
    _selected = _volumes[_cupMaxIdx];
    _pageCtrl = PageController(
        viewportFraction: 0.5, initialPage: _cupMaxIdx);
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _bubbleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14), // 气泡序列循环周期
    );
    // 「杯子里的动画」总开关：关闭时液面波浪/气泡/茶叶/米粒全部静止
    _syncCupAnimation(notify: false);
    SettingsFlags.instance.addListener(_onFlagsChanged);
    _applyPersistedCustom();
  }

  void _onFlagsChanged() => _syncCupAnimation();

  /// 按总开关启停杯子动画（实时联动：设置页切换后立即生效）
  void _syncCupAnimation({bool notify = true}) {
    final on = SettingsFlags.instance.cupAnimations;
    if (on) {
      if (!_waveCtrl.isAnimating) _waveCtrl.repeat();
      if (!_bubbleCtrl.isAnimating) _bubbleCtrl.repeat();
    } else {
      _waveCtrl.stop();
      _bubbleCtrl.stop();
      _waveCtrl.value = 0;
      _bubbleCtrl.value = 0;
    }
    if (notify && mounted) setState(() {});
  }

  /// 加载持久化的自定义档位覆盖（永久覆盖直到下次自定义）
  Future<void> _applyPersistedCustom() async {
    final storage = await ref.read(localStorageProvider.future);
    final raw = storage.prefs.getString(_kCustomVolumes);
    if (raw == null || !mounted) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final list = map[widget.beverageId];
      if (list is! List || list.length != _volumes.length) return;
      final custom = list.map((e) => int.parse(e.toString())).toList()
        ..sort();
      setState(() {
        _volumes = custom;
        // 打开即满杯：重新定位到中间档位
        _cupMaxIdx = (_volumes.length - 1) ~/ 2;
        _selected = _volumes[_cupMaxIdx];
        // PageView 未 attach 时 jumpToPage 会断言崩溃；此时自定义档位
        // 数量与内置一致 → 中间档 index 不变，initialPage 本就正确无需跳
        if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(_cupMaxIdx);
      });
    } catch (_) {
      // 持久化数据异常时忽略，使用内置档位
    }
  }

  /// 自定义量：覆盖当前档位 → 升序重排 → 持久化永久覆盖 → 滚轮跳到新位置
  void _applyCustomVolume(int ml) {
    setState(() {
      _volumes[_cupMaxIdx] = ml;
      _volumes.sort();
      _cupMaxIdx = _volumes.indexOf(ml);
      _selected = ml;
    });
    _pageCtrl.animateToPage(
      _cupMaxIdx,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    _persistVolumes();
  }

  Future<void> _persistVolumes() async {
    final storage = await ref.read(localStorageProvider.future);
    final raw = storage.prefs.getString(_kCustomVolumes);
    final map = raw == null
        ? <String, dynamic>{}
        : (jsonDecode(raw) as Map<String, dynamic>);
    map[widget.beverageId] = _volumes;
    await storage.prefs.setString(_kCustomVolumes, jsonEncode(map));
  }

  @override
  void dispose() {
    SettingsFlags.instance.removeListener(_onFlagsChanged);
    _pageCtrl.dispose();
    _waveCtrl.dispose();
    _bubbleCtrl.dispose();
    super.dispose();
  }

  /// 液面比例 = 当前水量 / 杯子最大容量（0~1）
  /// 拖动范围已限制最少 10ml；满杯时由 Painter 保证液面与杯口保留安全距离
  double get _fillRatio => (_selected / _cupMax).clamp(0.0, 1.0);

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
    // 娱乐玩法选容量：只把容量回传给弹弓轨道，由命中后再记账
    if (widget.pickOnly) {
      if (mounted) Navigator.pop(context, _selected);
      return;
    }
    final entry = DrinkEntry.create(
      beverage: _beverage,
      volumeMl: _selected,
    );
    await ref.read(todayEntriesProvider.notifier).add(entry);
    if (mounted) Navigator.pop(context, true);
  }

  /// 自定义量：下限固定 10ml，上限为当前饮品最大容量档；
  /// 确认后覆盖当前档位并永久持久化
  Future<void> _showCustomInput() async {
    final maxMl = _volumes.last;
    final ctrl = TextEditingController(text: UnitFormat.number(_selected));
    final decimals = UnitFormat.unit == PreferredUnit.oz;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('自定义量', textAlign: TextAlign.center),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(decimal: decimals),
          inputFormatters: [
            decimals
                ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                : FilteringTextInputFormatter.digitsOnly,
          ],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            suffixText: UnitFormat.unit.symbol,
            helperText:
                '范围 ${UnitFormat.volume(10, compact: true)} ~ ${UnitFormat.volume(maxMl, compact: true)}',
          ),
          onSubmitted: (v) {
            final n = double.tryParse(v);
            if (n != null) {
              Navigator.pop(
                  ctx, UnitFormat.unit.toMl(n).round().clamp(10, maxMl));
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: _hintGray)),
          ),
          ElevatedButton(
            onPressed: () {
              final n = double.tryParse(ctrl.text);
              if (n != null) {
                Navigator.pop(
                    ctx, UnitFormat.unit.toMl(n).round().clamp(10, maxMl));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _drinkColor,
              foregroundColor: _onDrinkColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('+ 自定义量'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      _applyCustomVolume(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 单位切换后容量档位文案需要立即重绘
    ref.watch(preferredUnitProvider);
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
                              duration: SettingsFlags.instance.cupAnimations
                                  ? const Duration(milliseconds: 300)
                                  : Duration.zero,
                              curve: Curves.easeOutCubic,
                              builder: (ctx, ratio, __) {
                                // SVG 矢量容器：液体按 SVG alpha 蒙版填充
                                if (isSvgContainer(
                                    _beverage.containerId)) {
                                  return SvgContainerFill(
                                    containerId:
                                        _beverage.containerId!,
                                    color: _drinkColor,
                                    fillRatio: ratio,
                                    capacityMl: _cupMax.toDouble(),
                                    phase: SettingsFlags
                                            .instance.cupAnimations
                                        ? _waveCtrl.value * math.pi * 2
                                        : 0,
                                    bubbleSeed: SettingsFlags
                                            .instance.cupAnimations
                                        ? _bubbleCtrl.value
                                        : 0,
                                  );
                                }
                                return CustomPaint(
                                  size: Size(260, cupH),
                                  painter: _DrinkContainerPainter(
                                    beverageId: _beverage.id,
                                    fillRatio: ratio,
                                    capacityMl: _cupMax.toDouble(),
                                    color: _drinkColor,
                                    phase: SettingsFlags.instance.cupAnimations
                                        ? _waveCtrl.value * math.pi * 2
                                        : 0,
                                    bubbleSeed:
                                        SettingsFlags.instance.cupAnimations
                                            ? _bubbleCtrl.value
                                            : 0,
                                    tSec:
                                        SettingsFlags.instance.cupAnimations
                                            ? _animClock.elapsedMilliseconds /
                                                1000
                                            : 0,
                                  ),
                                );
                              },
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
                        // page getter 在 PageView 未 attach 时会断言崩溃
                        // （positions.isNotEmpty），必须用 hasClients 守卫；
                        // 未 attach 时回退当前档位，保证中间档首帧即高亮
                        final page = _pageCtrl.hasClients
                            ? (_pageCtrl.page ?? _cupMaxIdx.toDouble())
                            : _cupMaxIdx.toDouble();
                        return PageView.builder(
                          controller: _pageCtrl,
                          itemCount: _volumes.length,
                          itemBuilder: (ctx, i) {
                            final dist = (i - page).abs();
                            final selected = dist < 0.5;
                            final label = UnitFormat.volume(
                                selected ? _selected : _volumes[i],
                                compact: true);
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
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 30),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 左侧：自定义量（Expanded 等宽包裹，保证 CTA 严格居中）
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _RoundIcon(
                              icon: Icons.apps,
                              label: '自定义',
                              color: _accentIconColor,
                              onTap: _showCustomInput,
                            ),
                          ),
                        ),
                        // 中间 "+ 饮品名" CTA（InspiraUI ShimmerButton 流光效果）
                        _ShimmerCtaButton(
                          color: _drinkColor,
                          foreground: _onDrinkColor,
                          label: widget.pickOnly ? '确定' : _beverage.name,
                          showPlus: !widget.pickOnly,
                          onTap: _submit,
                        ),
                        // 右侧空 Expanded：与左侧等宽 → CTA 恒为屏幕水平居中
                        const Expanded(child: SizedBox.shrink()),
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

/// 加量页 CTA：InspiraUI ShimmerButton 移植
/// 亮光只从按钮边缘的细环透出（内层实心面盖住中心，对应 Web 版
/// 内层 span 的 border: var(--cut) + bg-clip-padding 结构），
/// 旋转的 SweepGradient 光段绕轮廓转圈（对应 conic-gradient 旋转）
class _ShimmerCtaButton extends StatefulWidget {
  const _ShimmerCtaButton({
    required this.color,
    required this.foreground,
    required this.label,
    required this.onTap,
    this.showPlus = true,
  });

  final Color color;
  final Color foreground;
  final String label;
  final VoidCallback onTap;
  final bool showPlus;

  @override
  State<_ShimmerCtaButton> createState() => _ShimmerCtaButtonState();
}

class _ShimmerCtaButtonState extends State<_ShimmerCtaButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 136,
        height: 50,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (ctx, _) => CustomPaint(
            painter: _ShimmerCtaPainter(
              progress: _ctrl.value,
              face: widget.color,
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.showPlus)
                    Text(
                      '+ ',
                      style: TextStyle(
                        color: widget.foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 边缘流光绘制：按钮整体为纯饮品色（无边框感），
/// 流光只画在边缘 2px 环带（外轮廓减内层面的差集）里，
/// SweepGradient 亮段绕中心旋转 → 白光沿轮廓滑过，其余时刻不可见
class _ShimmerCtaPainter extends CustomPainter {
  _ShimmerCtaPainter({required this.progress, required this.face});

  final double progress; // 0~1 一个绕圈周期
  final Color face; // 按钮面色（饮品色）

  static const _cut = 2.0; // 边缘环带厚度（Web 版 shimmerSize 2px）

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Offset.zero & size;
    final outerRrect = RRect.fromRectAndRadius(
      outer,
      Radius.circular(size.height / 2),
    );

    // 1. 整个按钮实心饮品色
    canvas.drawRRect(outerRrect, Paint()..color = face);

    // 2. 环带区域 = 外轮廓 - 内层（内缩 cut 的圆角矩形）
    final outerPath = Path()..addRRect(outerRrect);
    final facePath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        outer.deflate(_cut),
        Radius.circular(size.height / 2 - _cut),
      ));
    final rimPath =
        Path.combine(PathOperation.difference, outerPath, facePath);

    // 3. 亮段只在环带内可见：绕中心旋转，经过处即沿轮廓滑动的白光
    canvas.save();
    canvas.clipPath(rimPath);
    final angle = progress * 2 * math.pi;
    final glint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.9),
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.42, 0.5, 0.58, 1.0],
        transform: GradientRotation(angle),
      ).createShader(outer.inflate(24));
    canvas.drawRect(outer.inflate(24), glint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShimmerCtaPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.face != face;
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
  const _RoundIcon({
    required this.icon,
    required this.onTap,
    required this.color,
    this.label,
  });
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
            child: Center(
              child: Icon(icon, color: color, size: 24),
            ),
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
    required this.capacityMl,
    required this.color,
    required this.phase,
    required this.bubbleSeed,
    required this.tSec,
  });

  final String beverageId;
  final double fillRatio;
  final double capacityMl; // 容器容量 ml（10ml 气泡生成线用）
  final Color color;
  final double phase;
  final double bubbleSeed;
  final double tSec; // 连续时钟秒（茶叶浮动相位）

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 根据饮品类型获取容器路径
    final container = _containerPath(w, h);

    // 1. 茶杯把手先画（垫在杯体下层，不参与液体裁剪与填充）
    if (beverageId == 'tea') _drawHandle(canvas, w, h);

    // 1.5 红酒杯梗与底座（始终酒红色，垫在杯碗下层）
    if (beverageId == 'alcohol_wine') {
      canvas.drawPath(_wineStemFootPath(w, h), Paint()..color = color);
    }

    // 2. 空容器底色（浅灰）
    canvas.drawPath(container, Paint()..color = const Color(0xFFECECEC));

    // 3. 液体（裁剪到容器内）
    canvas.save();
    canvas.clipPath(container);

    // 液面最高点与杯口保留安全距离（满杯也不触口），
    // 最低保留 10ml 的浅浅一层（拖动下限已限制 10ml）
    final fillTop = _fillTopFraction * h;
    final surfaceY =
        fillTop + (1 - fillRatio) * (_containerBottomFraction * h - fillTop);

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

    // 4. 气泡（有水时；碳酸饮料稍密；白粥用米粒替代气泡）：
    //    10ml 线以上且容器下半部随机生成（不随水量压缩），S 形上升，
    //    浅色圆盘 + 弯月高光，尺寸极小 → 正常 → 缩小消散
    if (fillRatio > 0.04 && beverageId != 'soup_porridge') {
      final containerBottom = _containerBottomFraction * h;
      final fullDepth = containerBottom - fillTop;
      final floorY = capacityMl <= 10
          ? containerBottom - fullDepth * 0.7
          : containerBottom - fullDepth * (10 / capacityMl);
      drawRisingBubbles(
        canvas,
        liquidColor: color,
        left: 0,
        right: w,
        bottom: containerBottom,
        surface: surfaceY,
        refDepth: fullDepth,
        floorY: floorY,
        tSeconds: bubbleSeed * 14, // 驱动控制器周期 14s
        count: beverageId == 'soda' ? 7 : 5,
        seed: 11,
      );
    }

    // 4.5 白粥米粒（少量米粒悬浮在粥里，随时间缓慢浮动）：
    //     分布在满杯固定区间（15%~80% 液深），不随当前液量压缩；
    //     高于当前液面的米粒跳过（低液量时自然隐藏，与气泡同哲学）
    if (beverageId == 'soup_porridge' &&
        fillRatio > 0.04 &&
        SettingsFlags.instance.cupAnimations) {
      final containerBottom = _containerBottomFraction * h;
      final fullDepth = containerBottom - fillTop;
      final rng = math.Random(7);
      for (var i = 0; i < 7; i++) {
        final cycleOffset = i * 0.17;
        final t = (bubbleSeed * 0.25 + cycleOffset) % 1.0;
        final cx = w * (0.22 + rng.nextDouble() * 0.56);
        final baseY = fillTop + fullDepth * (0.15 + rng.nextDouble() * 0.65);
        if (baseY < surfaceY + 3) continue; // 液面之上（含 ±3px 浮动余量）不显示
        final cy = baseY + math.sin(t * math.pi * 2) * 3;
        final rw = 3.5 + rng.nextDouble() * 2.5;
        final rh = rw * 0.6;
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(rng.nextDouble() * math.pi);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: rw * 2, height: rh * 2),
          Paint()
            ..color = const Color(0xFFE8DCC2).withValues(alpha: 0.9),
        );
        canvas.restore();
      }
    }
    canvas.restore();

    // 5. 容器轮廓线（在裁剪之外绘制；原版为无描边平涂风格的容器跳过）
    if (beverageId != 'water_pure' &&
        beverageId != 'alcohol_wine' &&
        beverageId != 'milk_milk' &&
        beverageId != 'milk_juice') {
      canvas.drawPath(
        container,
        Paint()
          ..color = color.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // 6. 容器顶部盖子/杯口高光
    _drawLid(canvas, w, h);
  }

  /// 根据饮品类型返回容器主体路径
  Path _containerPath(double w, double h) {
    if (beverageId == 'tea') {
      return _teacupPath(w, h);
    } else if (beverageId == 'coffee' ||
        beverageId == 'milk_tea' ||
        beverageId == 'milk_juice') {
      return _takeawayCupPath(w, h);
    } else if (beverageId == 'soda') {
      return _sodaCanPath(w, h);
    } else if (beverageId == 'milk_milk') {
      return _milkBottlePath(w, h);
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

  /// 玻璃杯（水）：上宽下窄收底平底杯（对标原版——平直杯口顶边 + 杯口/
  /// 杯底大圆角、侧边直边内收、无描边平涂风格）
  Path _waterGlassPath(double w, double h) {
    final rimY = h * 0.05;
    final rimL = w * 0.06;
    final rimR = w * 0.94;
    final bl = Offset(w * 0.23, h); // 底宽约为口宽的 63%
    final br = Offset(w * 0.77, h);
    final rt = w * 0.075; // 杯口圆角（平顶边）
    final r = w * 0.08; // 底部圆角
    return Path()
      ..moveTo(rimL + rt, rimY)
      // 平直杯口顶边
      ..lineTo(rimR - rt, rimY)
      ..quadraticBezierTo(rimR, rimY, rimR, rimY + rt)
      // 右侧直边内收至底部圆角
      ..lineTo(br.dx, br.dy - r)
      ..quadraticBezierTo(br.dx, br.dy, br.dx - r, br.dy)
      ..lineTo(bl.dx + r, bl.dy)
      ..quadraticBezierTo(bl.dx, bl.dy, bl.dx, bl.dy - r)
      // 左侧直边回到左上圆角
      ..lineTo(rimL, rimY + rt)
      ..quadraticBezierTo(rimL, rimY, rimL + rt, rimY)
      ..close();
  }

  /// 茶杯（杯体；把手由 _drawHandle 描边绘制，不参与液体填充）
  Path _teacupPath(double w, double h) {
    final bodyTop = h * 0.28;
    final bodyBottom = h * 0.82;
    final bodyLeft = w * 0.08;
    final bodyRight = w * 0.72;
    final r = w * 0.15;

    return Path()
      ..moveTo(bodyLeft, bodyTop)
      ..lineTo(bodyRight, bodyTop)
      ..quadraticBezierTo(bodyRight + r * 0.3, bodyTop, bodyRight + r * 0.3, bodyTop + r * 0.3)
      ..lineTo(bodyRight + r * 0.3, bodyBottom - r * 0.5)
      ..quadraticBezierTo(bodyRight + r * 0.3, bodyBottom, bodyRight - r * 0.3, bodyBottom)
      ..lineTo(bodyLeft + r * 0.5, bodyBottom)
      ..quadraticBezierTo(bodyLeft, bodyBottom, bodyLeft, bodyBottom - r * 0.5)
      ..lineTo(bodyLeft, bodyTop)
      ..close();
  }

  /// 各容器的杯口/口沿位置（占高度比例），与容器路径定义保持一致
  double get _rimYFraction {
    if (beverageId == 'tea') return 0.28;
    if (beverageId == 'soda') return 0.06; // 易拉罐口
    if (beverageId == 'coffee' ||
        beverageId == 'milk_tea' ||
        beverageId == 'milk_juice') {
      return 0.265; // 外带杯杯口（盖子下方）
    }
    if (beverageId == 'milk_milk') return 0.175;
    if (beverageId.startsWith('soup_')) return 0.40;
    if (beverageId == 'alcohol_beer') return 0.05; // 啤酒杯口
    if (beverageId == 'alcohol_wine') return 0.06; // 红酒碗口
    if (beverageId == 'alcohol_spirits') return 0.35;
    return 0.05; // 水杯
  }

  /// 满杯时液面最高点 = 杯口 + 5% 高度的自然间距（所有容器统一）
  double get _fillTopFraction => _rimYFraction + 0.05;

  /// 容器内部底面位置（占高度比例），液面映射的底部参考。
  /// 必须与各容器路径的实际内部底边保持一致（底部圆角/收底略上收），
  /// 这样低液量（拖动下限 10ml）时液面始终在容器底边之上、
  /// 液体保底可见一层——机制全饮品统一（复用水杯，无需逐饮品处理）
  double get _containerBottomFraction {
    if (beverageId == 'soda') return 0.925; // 易拉罐底（罐底过渡上收）
    if (beverageId == 'alcohol_beer') return 0.915; // 啤酒杯底
    if (beverageId == 'alcohol_wine') return 0.64; // 红酒碗底
    if (beverageId == 'tea') return 0.805; // 茶杯底
    if (beverageId == 'coffee' ||
        beverageId == 'milk_tea' ||
        beverageId == 'milk_juice') {
      return 0.885; // 外带杯底
    }
    if (beverageId == 'milk_milk') return 0.935; // 牛奶瓶底
    if (beverageId.startsWith('soup_')) return 0.835; // 汤碗底
    if (beverageId == 'alcohol_spirits') return 0.885; // 烈酒杯底
    return 0.985; // 水杯底（接近画布底）
  }

  /// 茶杯把手（C 形双层描边，垫在杯体下层）
  void _drawHandle(Canvas canvas, double w, double h) {
    final bodyTop = h * 0.28;
    final bodyBottom = h * 0.82;
    final bodyRight = w * 0.72;
    final r = w * 0.15;
    final handle = Path()
      ..moveTo(bodyRight, bodyTop + r * 0.5)
      ..quadraticBezierTo(
          w * 0.95, bodyTop + r * 0.5, w * 0.95, (bodyTop + bodyBottom) / 2)
      ..quadraticBezierTo(
          w * 0.95, bodyBottom - r * 0.5, bodyRight, bodyBottom - r * 0.5);
    // 外描边（略宽一圈，形成带轮廓的把手）
    canvas.drawPath(
      handle,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.07 + 3,
    );
    // 把手主体（与空杯底色一致）
    canvas.drawPath(
      handle,
      Paint()
        ..color = const Color(0xFFECECEC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.07,
    );
  }

  /// 外带杯（咖啡/奶茶/果汁）：宽盖杯身、缓收底 + 大圆角（对标原版）
  Path _takeawayCupPath(double w, double h) {
    final topY = h * 0.265;
    final bottomY = h * 0.90;
    final insetTop = w * 0.175;
    final insetBottom = w * 0.215;
    final r = w * 0.11;

    final tl = Offset(insetTop, topY);
    final tr = Offset(w - insetTop, topY);
    final br = Offset(w - insetBottom, bottomY);
    final bl = Offset(insetBottom, bottomY);

    return Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      // 右侧斜边下行至圆角起点，以 br 为控制点弯到杯底（避免底边斜切缺口）
      ..lineTo(br.dx, br.dy - r)
      ..quadraticBezierTo(br.dx, br.dy, br.dx - r, br.dy)
      ..lineTo(bl.dx + r, bl.dy)
      ..quadraticBezierTo(bl.dx, bl.dy, bl.dx, bl.dy - r)
      ..close();
  }

  /// 易拉罐（碳酸饮料）：矮胖罐体 + 宽罐口 + 快速圆肩，底部与顶部镜像对称（对标原版）
  Path _sodaCanPath(double w, double h) {
    const lidL = 0.17; // 罐口/罐底左
    const lidR = 0.83; // 罐口/罐底右
    const bodyL = 0.07; // 罐身左
    const bodyR = 0.93; // 罐身右
    const rimY = 0.06; // 罐顶
    const stepY = 0.145; // 罐口下沿（肩部过渡起点）
    const shoulderY = 0.19; // 罐肩（外翻完成处）
    // 底部与顶部镜像：bodyEnd = 1 - shoulder, stepBot = 1 - step, bottom = 1 - rim
    const bodyEndY = 0.81; // 罐身直段结束
    const stepBotY = 0.855; // 罐底过渡起点
    const bottomY = 0.94; // 罐底
    final midTop = (stepY + shoulderY) / 2;
    final midBot = (bodyEndY + stepBotY) / 2;
    final r = w * 0.04; // 罐口/罐底圆角

    return Path()
      ..moveTo(w * lidL + r, h * rimY)
      ..lineTo(w * lidR - r, h * rimY)
      ..quadraticBezierTo(w * lidR, h * rimY, w * lidR, h * rimY + r)
      ..lineTo(w * lidR, h * stepY)
      // 右肩：快速 S 形外翻至罐身
      ..cubicTo(
          w * lidR, h * midTop, w * bodyR, h * midTop, w * bodyR, h * shoulderY)
      ..lineTo(w * bodyR, h * bodyEndY)
      // 右下：S 形内收至罐底（与右肩镜像）
      ..cubicTo(w * bodyR, h * midBot, w * lidR, h * midBot, w * lidR,
          h * stepBotY)
      ..lineTo(w * lidR, h * bottomY - r)
      ..quadraticBezierTo(w * lidR, h * bottomY, w * lidR - r, h * bottomY)
      ..lineTo(w * lidL + r, h * bottomY)
      ..quadraticBezierTo(w * lidL, h * bottomY, w * lidL, h * bottomY - r)
      ..lineTo(w * lidL, h * stepBotY)
      // 左下：S 形外翻回罐身（与左肩镜像）
      ..cubicTo(w * lidL, h * midBot, w * bodyL, h * midBot, w * bodyL,
          h * bodyEndY)
      ..lineTo(w * bodyL, h * shoulderY)
      // 左肩：快速 S 形内收到罐口
      ..cubicTo(w * bodyL, h * midTop, w * lidL, h * midTop, w * lidL,
          h * stepY)
      ..lineTo(w * lidL, h * rimY + r)
      ..quadraticBezierTo(w * lidL, h * rimY, w * lidL + r, h * rimY)
      ..close();
  }

  /// 牛奶瓶：高瓶身 + S 形顺滑肩 + 直筒大圆角底（对标原版；
  /// 瓶盖与盖下颈环由 _drawLid 绘制）
  Path _milkBottlePath(double w, double h) {
    const neckL = 0.335; // 瓶颈左
    const neckR = 0.665; // 瓶颈右
    const bodyL = 0.19; // 瓶身左
    const bodyR = 0.81; // 瓶身右
    const neckTopY = 0.175; // 颈顶（藏入颈环后）
    const shoulderTopY = 0.27; // 肩部过渡起点
    const bodyTopY = 0.52; // 肩部过渡终点（直筒开始）
    const bottomY = 0.95;
    final r = w * 0.09; // 瓶底圆角
    final midY = (shoulderTopY + bodyTopY) / 2;

    return Path()
      ..moveTo(w * neckL, h * neckTopY)
      ..lineTo(w * neckR, h * neckTopY)
      ..lineTo(w * neckR, h * shoulderTopY)
      // 右肩：S 形顺滑外扩至瓶身直筒
      ..cubicTo(
          w * neckR, h * midY, w * bodyR, h * midY, w * bodyR, h * bodyTopY)
      ..lineTo(w * bodyR, h * bottomY - r)
      ..quadraticBezierTo(w * bodyR, h * bottomY, w * bodyR - r, h * bottomY)
      ..lineTo(w * bodyL + r, h * bottomY)
      ..quadraticBezierTo(w * bodyL, h * bottomY, w * bodyL, h * bottomY - r)
      ..lineTo(w * bodyL, h * bodyTopY)
      // 左肩：S 形顺滑回收至瓶颈
      ..cubicTo(
          w * bodyL, h * midY, w * neckL, h * midY, w * neckL, h * shoulderTopY)
      ..lineTo(w * neckL, h * neckTopY)
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

  /// 啤酒杯（直身微收腰 + 底部小外翻脚，对标原版）
  Path _beerGlassPath(double w, double h) {
    const rimL = 0.18; // 杯口左
    const rimR = 0.82; // 杯口右
    const waistL = 0.247; // 下腰最窄左
    const waistR = 0.753; // 下腰最窄右
    const footL = 0.22; // 底部外翻左
    const footR = 0.78; // 底部外翻右
    const rimY = 0.05;
    const waistY = 0.78;
    const bottomY = 0.93;
    final r = w * 0.06; // 杯口圆角
    final rc = w * 0.05; // 杯底圆角

    return Path()
      ..moveTo(w * rimL + r, h * rimY)
      ..lineTo(w * rimR - r, h * rimY)
      ..quadraticBezierTo(w * rimR, h * rimY, w * rimR, h * rimY + r)
      // 右侧：竖直切线缓收至下腰
      ..cubicTo(
          w * 0.815, h * 0.38, w * waistR, h * 0.55, w * waistR, h * waistY)
      // 右下：竖直切线外翻至底脚
      ..cubicTo(w * waistR, h * waistY + 0.07 * h, w * footR, h * bottomY - rc * 2,
          w * footR, h * bottomY - rc)
      ..quadraticBezierTo(w * footR, h * bottomY, w * footR - rc, h * bottomY)
      ..lineTo(w * footL + rc, h * bottomY)
      ..quadraticBezierTo(w * footL, h * bottomY, w * footL, h * bottomY - rc)
      // 左下：外翻回腰
      ..cubicTo(w * footL, h * bottomY - rc * 2, w * waistL,
          h * waistY + 0.07 * h, w * waistL, h * waistY)
      // 左侧：缓收回杯口
      ..cubicTo(
          w * waistL, h * 0.55, w * 0.185, h * 0.38, w * rimL, h * rimY + r)
      ..quadraticBezierTo(w * rimL, h * rimY, w * rimL + r, h * rimY)
      ..close();
  }

  /// 红酒杯杯碗（纤细宽口碗型，碗高略大于碗腹宽，对标原版；液体仅填充碗内）
  Path _wineGlassPath(double w, double h) {
    const rimL = 0.24; // 碗口左（碗口 ≈ 碗腹宽 83%）
    const rimR = 0.76; // 碗口右
    const bellyL = 0.185; // 碗腹最宽左
    const bellyR = 0.815; // 碗腹最宽右
    const stemL = 0.445; // 杯梗左
    const stemR = 0.555; // 杯梗右
    const rimY = 0.06;
    const bellyY = 0.375; // 碗腹最宽处
    const bowlBottomY = 0.655; // 碗底（与杯梗衔接）
    final r = w * 0.06; // 碗口圆角

    return Path()
      ..moveTo(w * rimL + r, h * rimY)
      ..lineTo(w * rimR - r, h * rimY)
      ..quadraticBezierTo(w * rimR, h * rimY, w * rimR, h * rimY + r)
      // 右侧：缓外扩至碗腹
      ..cubicTo(
          w * 0.775, h * 0.17, w * bellyR, h * 0.26, w * bellyR, h * bellyY)
      // 碗底：圆弧收进杯梗
      ..cubicTo(w * bellyR, h * 0.52, w * 0.62, h * 0.635, w * stemR,
          h * bowlBottomY)
      ..lineTo(w * stemL, h * bowlBottomY)
      // 左侧镜像
      ..cubicTo(w * 0.38, h * 0.635, w * bellyL, h * 0.52, w * bellyL,
          h * bellyY)
      ..cubicTo(w * bellyL, h * 0.26, w * 0.225, h * 0.17, w * rimL,
          h * rimY + r)
      ..quadraticBezierTo(w * rimL, h * rimY, w * rimL + r, h * rimY)
      ..close();
  }

  /// 红酒杯杯梗 + 底座（粗短梗圆滑外扩 + 两端半圆低底座；
  /// 始终为酒红色，垫在杯碗下层；全部使用比例坐标，禁止混入像素值）
  Path _wineStemFootPath(double w, double h) {
    const stemL = 0.445;
    const stemR = 0.555;
    const footL = 0.30; // 底座左（≈ 碗腹宽 64%）
    const footR = 0.70; // 底座右
    const stemTopY = 0.60; // 梗顶（藏入碗内）
    const flareY = 0.845; // 梗外扩起点
    const footTopY = 0.885;
    const footY = 0.945;
    final fr = (footY - footTopY) * h / 2; // 底座端部圆角（半高，扁圆端）

    return Path()
      // 底座：两端半圆的扁平圆角矩形
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(w * footL, h * footTopY, w * (footR - footL),
              h * (footY - footTopY)),
          Radius.circular(fr)))
      // 杯梗：下段圆滑外扩与底座融合
      ..moveTo(w * stemL, h * stemTopY)
      ..lineTo(w * stemR, h * stemTopY)
      ..lineTo(w * stemR, h * flareY)
      ..quadraticBezierTo(w * (stemR + 0.025), h * (footTopY - 0.005),
          w * (footR - 0.05), h * (footTopY + 0.008))
      ..lineTo(w * (footL + 0.05), h * (footTopY + 0.008))
      ..quadraticBezierTo(w * (stemL - 0.025), h * (footTopY - 0.005),
          w * stemL, h * flareY)
      ..close();
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
    if (beverageId == 'coffee') {
      // 奶白圆顶盖 + 外翻盖沿（对标原版咖啡杯样式）
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(w * 0.22, h * 0.10, w * 0.56, h * 0.10),
          topLeft: Radius.circular(w * 0.10),
          topRight: Radius.circular(w * 0.10),
          bottomLeft: const Radius.circular(2),
          bottomRight: const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFFF2EFE9),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.15, h * 0.185, w * 0.70, h * 0.045),
          Radius.circular(w * 0.03),
        ),
        Paint()..color = const Color(0xFFE8E3DA),
      );
      return;
    }
    if (beverageId == 'soda') return; // 易拉罐为整体轮廓，无单独杯盖
    if (beverageId == 'water_pure') return; // 水杯无杯口高光条（平涂风格）
    if (beverageId == 'alcohol_wine') return; // 红酒为平涂风格，无杯口高光
    final isTakeaway = beverageId == 'milk_tea' || beverageId == 'milk_juice';
    final isMilkBottle = beverageId == 'milk_milk';
    if (isTakeaway) {
      // 外带杯盖：宽出杯身 + 右上凸嘴（对标原版）
      final lidTop = h * 0.125;
      final lidBottom = h * 0.27;
      final lidL = w * 0.10;
      final lidR = w * 0.90;
      // 右上凸嘴（先画，垫在盖子下层）
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(w * 0.66, lidTop - h * 0.055, w * 0.12, h * 0.085),
          topLeft: const Radius.circular(3),
          topRight: Radius.circular(w * 0.045),
          bottomLeft: const Radius.circular(2),
          bottomRight: const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFFE8E8E8),
      );
      // 盖子主体
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(lidL, lidTop, lidR - lidL, lidBottom - lidTop),
          Radius.circular(w * 0.05),
        ),
        Paint()..color = const Color(0xFFE8E8E8),
      );
    } else if (isMilkBottle) {
      // 牛奶瓶：盖下颈环（先画，微宽于瓶盖形成凸缘）+ 宽瓶盖
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.29, h * 0.125, w * 0.42, h * 0.06),
          Radius.circular(w * 0.035),
        ),
        Paint()..color = const Color(0xFFE8E8E8),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.30, h * 0.05, w * 0.40, h * 0.09),
          Radius.circular(w * 0.05),
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
      // 杯口高光条（跟随各容器口沿位置）
      final (rimY, left, right) = switch (beverageId) {
        'tea' => (0.28, 0.08, 0.765),
        'alcohol_beer' => (0.05, 0.19, 0.81),
        'alcohol_spirits' => (0.35, 0.10, 0.90),
        _ => (0.05, 0.08, 0.92),
      };
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(w * left, h * rimY - 2, w * (right - left), 5),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.8),
      );
    }
  }

  /// 装饰元素（咖啡豆/茶包等；冰块/珍珠装饰已按原版要求删除）
  void _drawDecorations(Canvas canvas, double w, double h, double surfaceY) {
    if (beverageId == 'coffee') {
      _drawCoffeeBean(canvas, w * 0.5, h * 0.56, w * 0.18);
    } else if (beverageId == 'tea') {
      _drawTeaBag(canvas, w, h);
      // 茶叶粒子：沉在容器底部（固定区间，不随液量压缩）
      drawTeaLeaves(
        canvas,
        liquidColor: color,
        left: 0,
        right: w,
        bottom: _containerBottomFraction * h,
        top: _fillTopFraction * h,
        surface: surfaceY,
        tSeconds: tSec,
        seed: 13,
      );
    }
  }

  /// 单颗咖啡豆（米白豆身 + S 形中缝，对标原版）
  void _drawCoffeeBean(Canvas canvas, double cx, double cy, double ry) {
    final rx = ry * 0.62;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-0.30);
    // 豆身
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
      Paint()..color = const Color(0xFFF2EFE8),
    );
    // S 形中缝（用液体色描边，两端渐尖）
    canvas.drawPath(
      Path()
        ..moveTo(0, -ry * 0.88)
        ..quadraticBezierTo(-rx * 1.05, -ry * 0.30, 0, 0)
        ..quadraticBezierTo(rx * 1.05, ry * 0.30, 0, ry * 0.88),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = rx * 0.42
        ..strokeCap = StrokeCap.round,
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

  @override
  bool shouldRepaint(covariant _DrinkContainerPainter old) =>
      old.beverageId != beverageId ||
      old.fillRatio != fillRatio ||
      old.color != color ||
      old.phase != phase ||
      old.bubbleSeed != bubbleSeed ||
      old.tSec != tSec;
}
