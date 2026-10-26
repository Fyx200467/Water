import 'package:flutter/material.dart';

import '../widgets/liquid_preview.dart';
import '../widgets/picker_frame.dart';

/// 预设液体色板（对标原版：5 + 5 分组 + 分隔线下蓝 / 黄绿 / 赭棕 3 色）
/// 添加饮品页新增时也从该色板随机取色
const List<Color> drinkColorPresets = <Color>[
  Color(0xFFE4E4E9), // 浅灰
  Color(0xFFF7CE46), // 黄
  Color(0xFFF2994A), // 橙
  Color(0xFFF178B6), // 粉
  Color(0xFFD7264D), // 红
  Color(0xFF6FCF97), // 绿
  Color(0xFF56CCF2), // 青
  Color(0xFF9B51E0), // 紫
  Color(0xFF8D6E63), // 棕
  Color(0xFF2F3A4F), // 深蓝黑
  Color(0xFF4A90F4), // 蓝
  Color(0xFFC6E837), // 黄绿
  Color(0xFFB05C33), // 赭棕
];

/// 颜色选择页（对标原版全屏页）
///
/// 1. 顶部：当前容器按实时颜色填充的动态预览
/// 2. 浅灰卡片：预设色板（选中深色描边 + 白色对勾）、分隔线、
///    自定义「+」圆钮 + 色相 / 饱和度 / 亮度三条渐变滑杆（实时调节）
/// 3. 底部：悬浮「取消 / 应用」胶囊；应用返回当前颜色，取消返回 null
class DrinkColorScreen extends StatefulWidget {
  const DrinkColorScreen({
    super.key,
    required this.containerId,
    required this.initial,
  });

  /// 当前容器图标 id（顶部预览用）
  final String containerId;

  /// 初始颜色
  final Color initial;

  @override
  State<DrinkColorScreen> createState() => _DrinkColorScreenState();
}

class _DrinkColorScreenState extends State<DrinkColorScreen> {
  static const _textDark = Color(0xFF1C1C1E);
  static const _plusBg = Color(0xFFE9E9EB);
  static const _plusIcon = Color(0xFF8E8E93);
  static const _divider = Color(0xFFE3E3E8);

  late Color _color;

  /// 滑杆区域锚点：自定义「+」点击后滚动到滑杆处
  final GlobalKey _slidersKey = GlobalKey();

  // HSV 是滑杆的唯一真值来源（色相 0~1 / 饱和度 0~1 / 亮度 0~1）。
  // 不能每次从 RGB 反推：色相 360° 会回绕成 0°、低饱和/低亮度时色相
  // 会被抹掉，导致拖动时滑块位置与手指不一致、在原位左右跳动
  late double _hue;
  late double _sat;
  late double _val;

  @override
  void initState() {
    super.initState();
    _color = widget.initial;
    final hsv = HSVColor.fromColor(_color);
    _hue = hsv.hue / 360;
    _sat = hsv.saturation;
    _val = hsv.value;
  }

  /// 当前颜色是否命中预设（未命中 = 自定义模式，「+」高亮）
  bool get _isCustom =>
      !drinkColorPresets.any((c) => c.toARGB32() == _color.toARGB32());

  /// 点选预设色：以 RGB 为准确颜色，同时反向同步三个滑杆的值
  void _setColor(Color c) {
    final hsv = HSVColor.fromColor(c);
    setState(() {
      _color = c;
      _hue = hsv.hue / 360;
      _sat = hsv.saturation;
      _val = hsv.value;
    });
  }

  void _setHsv({double? hue, double? sat, double? val}) {
    setState(() {
      _hue = hue ?? _hue;
      _sat = sat ?? _sat;
      _val = val ?? _val;
      // 360° 与 0° 是同一颜色：取模避免色相滑到最右端时颜色回绕
      // （滑杆自身仍保留 1.0，滑块不会跳回左端）
      _color = HSVColor.fromAHSV(
        1,
        (_hue * 360) % 360,
        _sat,
        _val,
      ).toColor();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pureHue = HSVColor.fromAHSV(1, _hue * 360, 1, 1).toColor();
    final brightHue = HSVColor.fromAHSV(1, _hue * 360, _sat, 1).toColor();

    return PickerScaffold(
      preview: LiquidPreview(
        containerId: widget.containerId,
        color: _color,
        width: 150,
        height: 195,
      ),
      title: '颜色',
      onCancel: () => Navigator.pop(context),
      onApply: () => Navigator.pop(context, _color),
      content: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F9),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              // 预设色板：两行 5 色
              _dotRow([
                for (final c in drinkColorPresets.sublist(0, 5)) _dot(c),
              ]),
              const SizedBox(height: 18),
              _dotRow([
                for (final c in drinkColorPresets.sublist(5, 10)) _dot(c),
              ]),
              // 分隔线
              Container(
                margin: const EdgeInsets.symmetric(vertical: 16),
                width: 96,
                height: 1,
                color: _divider,
              ),
              // 第三行：蓝 / 黄绿 / 赭棕 + 自定义「+」（占位对齐第 5 列）
              _dotRow([
                for (final c in drinkColorPresets.sublist(10, 13)) _dot(c),
                _plusDot(),
                const SizedBox(width: 46),
              ]),
              const SizedBox(height: 22),
              // 色相 / 饱和度 / 亮度 滑杆（实时渲染顶部预览）
              Column(
                key: _slidersKey,
                children: [
                  _GradSlider(
                    value: _hue,
                    colors: const [
                      Color(0xFFFF3B30),
                      Color(0xFFFFCC00),
                      Color(0xFF34C759),
                      Color(0xFF32ADE6),
                      Color(0xFF007AFF),
                      Color(0xFFAF52DE),
                      Color(0xFFFF3B30),
                    ],
                    thumbColor: _color,
                    onChanged: (v) => _setHsv(hue: v),
                  ),
                  const SizedBox(height: 18),
                  _GradSlider(
                    value: _sat,
                    colors: const [Colors.white, Color(0x00FFFFFF)],
                    solidEnd: pureHue,
                    thumbColor: _color,
                    onChanged: (v) => _setHsv(sat: v),
                  ),
                  const SizedBox(height: 18),
                  _GradSlider(
                    value: _val,
                    colors: const [Colors.black, Color(0x00FFFFFF)],
                    solidEnd: brightHue,
                    thumbColor: _color,
                    onChanged: (v) => _setHsv(val: v),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 一行色点（等宽 spaceBetween 对齐 5 列）
  Widget _dotRow(List<Widget> children) {
    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: children,
      ),
    );
  }

  /// 预设色点：选中渲染深色描边 + 白色对勾
  Widget _dot(Color color) {
    final selected = !_isCustom && color.toARGB32() == _color.toARGB32();
    return GestureDetector(
      onTap: () => _setColor(color),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? _textDark : Colors.transparent,
            width: 2.5,
          ),
        ),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: selected
              ? const Icon(Icons.check,
                  size: 22, color: Colors.white, weight: 3)
              : null,
        ),
      ),
    );
  }

  /// 自定义色圆钮：滑杆调出的颜色不在预设中时高亮描边
  /// （点击滚动到下方三条滑杆，自定义色由滑杆实时调节）
  Widget _plusDot() {
    return GestureDetector(
      onTap: () {
        final ctx = _slidersKey.currentContext;
        if (ctx == null) return;
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      },
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _isCustom ? _textDark : Colors.transparent,
            width: 2.5,
          ),
        ),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration:
              const BoxDecoration(color: _plusBg, shape: BoxShape.circle),
          child: const Icon(Icons.add, size: 24, color: _plusIcon),
        ),
      ),
    );
  }
}

/// 渐变轨道滑杆（色相 / 饱和度 / 亮度）：圆点滑块带白描边
class _GradSlider extends StatelessWidget {
  const _GradSlider({
    required this.value,
    required this.colors,
    this.solidEnd,
    required this.thumbColor,
    required this.onChanged,
  });

  /// 当前值 0~1
  final double value;

  /// 轨道渐变色；[solidEnd] 非空时替换最后一个颜色
  /// （用于「透明端」在渐变里表达为纯色端）
  final List<Color> colors;
  final Color? solidEnd;
  final Color thumbColor;
  final ValueChanged<double> onChanged;

  static const _thumbR = 10.0;

  void _set(double dx, double width) {
    final track = width - _thumbR * 2;
    onChanged(((dx - _thumbR) / track).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final effective = solidEnd != null
        ? [...colors.sublist(0, colors.length - 1), solidEnd!]
        : colors;
    return LayoutBuilder(
      builder: (ctx, box) {
        final w = box.maxWidth;
        final track = w - _thumbR * 2;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _set(d.localPosition.dx, w),
          onHorizontalDragStart: (d) => _set(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) => _set(d.localPosition.dx, w),
          child: SizedBox(
            height: 30,
            width: w,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // 渐变轨道
                Positioned(
                  left: _thumbR,
                  right: _thumbR,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      gradient: LinearGradient(colors: effective),
                    ),
                  ),
                ),
                // 滑块圆点
                Positioned(
                  left: value * track,
                  child: Container(
                    width: _thumbR * 2,
                    height: _thumbR * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: thumbColor,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
