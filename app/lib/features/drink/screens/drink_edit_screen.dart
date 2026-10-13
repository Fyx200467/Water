import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/beverage.dart';
import '../../../shared/widgets/drink_illustration.dart';
import '../../home/providers/home_providers.dart';
import '../providers/custom_beverage_provider.dart';
import '../widgets/container_shapes.dart';
import 'drink_icon_screen.dart';

/// 添加 / 编辑自定义饮品页（对标原版：全屏编辑器）
///
/// 结构：
/// 1. 顶栏：左「取消」+ 右深色「⬆保存」胶囊
/// 2. 「类似于: X」模板选择胶囊 + 居中大预览插画（会员模板带锁徽章）
/// 3. iOS 风格分组行：名称 / 大小 ‖ 图标 / 颜色 / 动画 ‖ 进水量 / 卡路里 / 咖啡因 / 酒精
/// 4. 编辑模式下底部提供删除按钮
class DrinkEditScreen extends ConsumerStatefulWidget {
  const DrinkEditScreen({super.key, this.existing});

  final Beverage? existing;

  @override
  ConsumerState<DrinkEditScreen> createState() => _DrinkEditScreenState();
}

class _DrinkEditScreenState extends ConsumerState<DrinkEditScreen> {
  static const _brandCyan = Color(0xFF4DB8D8);
  static const _textDark = Color(0xFF1C1C1E);
  static const _valueGray = Color(0xFFB9B9C0);
  static const _rowBg = Color(0xFFF4F4F6);
  static const _calorieOrange = Color(0xFFE8A33D);
  static const _ratioRed = Color(0xFFC9364F);
  static const _caffeineBrown = Color(0xFF8D6E63);
  static const _alcoholPurple = Color(0xFF7E57C2);

  /// 「类似于」品牌饮品模板（决定分类/颜色/进水量/插画）
  static const _brands = <_BrandSpec>[
    _BrandSpec('可口可乐', BeverageCategory.soda, Color(0xFFC9364F), 0.83),
    _BrandSpec('雪碧', BeverageCategory.soda, Color(0xFFA5DE5C), 0.90),
    _BrandSpec('芬达', BeverageCategory.soda, Color(0xFFFF8A3D), 0.88),
    _BrandSpec('无糖可乐', BeverageCategory.soda, Color(0xFF3A3A3C), 0.83),
    _BrandSpec('冰红茶', BeverageCategory.tea, Color(0xFFC96A2E), 0.90),
    _BrandSpec('柠檬茶', BeverageCategory.tea, Color(0xFFE8C84A), 0.90),
    _BrandSpec('拿铁咖啡', BeverageCategory.coffee, Color(0xFFB08968), 0.70),
    _BrandSpec('美式咖啡', BeverageCategory.coffee, Color(0xFF5D4037), 0.70),
    _BrandSpec('纯牛奶', BeverageCategory.milk, Color(0xFFC8CDD0), 0.80),
    _BrandSpec('橙汁', BeverageCategory.milk, Color(0xFFFFA726), 0.80),
    _BrandSpec('苹果汁', BeverageCategory.milk, Color(0xFF9CCC65), 0.80),
    _BrandSpec('矿泉水', BeverageCategory.water, Color(0xFF6AD7E0), 1.00),
    _BrandSpec('苏打水', BeverageCategory.water, Color(0xFF8FDDE8), 1.00),
    _BrandSpec('运动饮料', BeverageCategory.soda, Color(0xFF4DB8D8), 0.95),
    _BrandSpec('青岛啤酒', BeverageCategory.alcohol, Color(0xFFF5A623), -0.40),
    _BrandSpec('红酒', BeverageCategory.alcohol, Color(0xFFA62034), -0.95),
    _BrandSpec('白酒', BeverageCategory.alcohol, Color(0xFFE3E8EC), -3.18),
    _BrandSpec('豆浆', BeverageCategory.soup, Color(0xFFF5EFE2), 0.85),
  ];

  /// 颜色可选色板（第一项 = 跟随模板）
  static const _palette = <int>[
    0xFFC9364F,
    0xFFFF8A65,
    0xFFFFC107,
    0xFF8BC34A,
    0xFF4DB8D8,
    0xFF5B8DEF,
    0xFF7E57C2,
    0xFFF06292,
    0xFF8D6E63,
    0xFF9E9E9E,
    0xFF3A3A3C,
    0xFFF5EFE2,
  ];

  late Beverage _template;
  late TextEditingController _nameCtrl;
  late int _sizeMl;
  Color? _colorOverride;
  String? _animation; // null = 跟随模板
  double? _ratioPercent; // 进水量覆盖（%），null = 跟随模板
  String? _containerId; // 容器图标形状，null = 沿用模板插画
  int? _calories;
  int? _caffeineMg;
  int? _alcoholPercent;

  bool get _isEditing => widget.existing != null;
  bool get _isMember => ref.watch(memberProvider).isValid;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    if (b != null) {
      _nameCtrl = TextEditingController(text: b.name);
      _sizeMl = b.defaultMl;
      _colorOverride = b.liquidColor;
      _animation = b.animation;
      _containerId = b.containerId;
      _ratioPercent = b.hydrationRatio != null ? b.hydrationRatio! * 100 : null;
      _calories = b.calories;
      _caffeineMg = b.caffeineMg;
      _alcoholPercent = b.alcoholPercent;
      final tid = b.templateId ?? Beverage.fallbackIllustration(b.category);
      _template = Beverage.presets.firstWhere(
        (p) => p.id == tid,
        orElse: () => b,
      );
    } else {
      _nameCtrl = TextEditingController();
      _template = Beverage.presets.firstWhere((p) => p.id == 'soda');
      _sizeMl = _template.defaultMl;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ---------------- 状态派生 ----------------

  /// 当前生效液体色：覆盖色 → 模板液体色 → 模板分类色
  Color get _liquidColor => _colorOverride ?? _template.color;

  /// 生效折算比例（%）：手动覆盖 → 模板覆盖 → 分类比例
  double get _ratio =>
      _ratioPercent ??
      (_template.hydrationRatio ?? _template.category.hydrationRatio) * 100;

  /// 生效动画 key：手动选择 → 按模板分类推断
  String get _animKey => _animation ??
      (_template.category == BeverageCategory.soup ? 'rice' : 'bubbles');

  String get _animationLabel => switch (_animKey) {
        'rice' => '米粒',
        'micro' => '微气泡',
        'ice' => '冰块',
        'none' => '无',
        _ => '气泡',
      };

  // ---------------- 保存 ----------------

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final navigator = Navigator.of(context);
    final notifier = ref.read(customBeveragesProvider.notifier);
    final id = widget.existing?.id ??
        'custom_${DateTime.now().millisecondsSinceEpoch}';
    final beverage = Beverage(
      id: id,
      category: _template.category,
      name: name,
      defaultMl: _sizeMl,
      icon: _template.category.icon,
      liquidColor: _liquidColor,
      hydrationRatio: _ratioPercent != null
          ? _ratioPercent! / 100
          : _template.hydrationRatio,
      templateId: _template.templateId ?? _template.id,
      animation: _animation,
      containerId: _containerId,
      calories: _calories,
      caffeineMg: _caffeineMg,
      alcoholPercent: _alcoholPercent,
    );
    if (_isEditing) {
      await notifier.updateCustom(beverage);
    } else {
      await notifier.addCustom(beverage);
    }
    navigator.pop();
  }

  // ---------------- 交互弹层 ----------------

  /// 「类似于」品牌选择器：从品牌库中挑选一个饮品作为模板
  Future<void> _pickTemplate() async {
    final spec = await showModalBottomSheet<_BrandSpec>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          children: [
            const Text('类似于哪个饮品？',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _textDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            for (final s in _brands)
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.pop(ctx, s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: s.color,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          s.category.icon,
                          size: 17,
                          color: s.color.computeLuminance() > 0.72
                              ? const Color(0xFF5B4A2F)
                              : Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(s.name,
                            style: const TextStyle(
                                color: _textDark,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                      Text(
                        '${(s.ratio * 100).round()}%',
                        style: TextStyle(
                          color: s.ratio >= 0 ? _brandCyan : _ratioRed,
                          fontSize: 13,
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
    );
    if (spec == null) return;
    setState(() {
      _template = Beverage(
        id: 'brand_${spec.name}',
        category: spec.category,
        name: spec.name,
        defaultMl: 330,
        icon: spec.category.icon,
        liquidColor: spec.color,
        hydrationRatio: spec.ratio,
        templateId: Beverage.fallbackIllustration(spec.category),
      );
      // 切换模板后重置所有跟随模板的覆盖项
      _colorOverride = null;
      _animation = null;
      _ratioPercent = null;
      _sizeMl = 330;
    });
  }

  /// 名称输入（无字符过滤，避免破坏中文 IME 组合输入）
  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _nameCtrl.text);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('饮品名称',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLength: 8,
                  style: const TextStyle(
                      color: _textDark,
                      fontSize: 17,
                      fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: '最多 8 字',
                    counterText: '',
                    filled: true,
                    fillColor: _rowBg,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: _brandCyan,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text('确定',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok == true) {
      setState(() => _nameCtrl.text = ctrl.text.trim());
    }
  }

  /// 容量选择：3 个固定档位 + 会员专属自定义量
  Future<void> _editSize() async {
    final member = _isMember;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('饮品大小',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _textDark,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              for (final v in _template.volumes)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(ctx, v),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('$v ml',
                              style: const TextStyle(
                                  color: _textDark,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (v == _sizeMl)
                          const Icon(Icons.check,
                              size: 20, color: _brandCyan),
                      ],
                    ),
                  ),
                ),
              const Divider(height: 1),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  if (!member) {
                    Navigator.pop(ctx);
                    _showMembershipSheet();
                    return;
                  }
                  Navigator.pop(ctx);
                  final custom = await _inputNumber(
                    title: '自定义量（ml）',
                    hint: '10 - ${_template.volumes.last}',
                    initial: _sizeMl.toString(),
                  );
                  if (custom != null &&
                      custom >= 10 &&
                      custom <= _template.volumes.last) {
                    setState(() => _sizeMl = custom);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '自定义量${!_template.volumes.contains(_sizeMl) ? ' · $_sizeMl ml' : ''}',
                          style: const TextStyle(
                              color: _textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (!_template.volumes.contains(_sizeMl))
                        const Icon(Icons.check,
                            size: 20, color: _brandCyan),
                      if (!member) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.lock,
                            size: 15, color: Color(0xFFB9B9C0)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 颜色选择：跟随模板 + 固定色板
  Future<void> _editColor() async {
    await showModalBottomSheet<Object?>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('液体颜色',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _textDark,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                alignment: WrapAlignment.center,
                children: [
                  _ColorDot(
                    color: _template.color,
                    selected: _colorOverride == null,
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                  for (final c in _palette)
                    _ColorDot(
                      color: Color(c),
                      selected: _colorOverride?.toARGB32() == c,
                      onTap: () => Navigator.pop(ctx, Color(c)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((r) {
      if (r == false) {
        setState(() => _colorOverride = null);
      } else if (r is Color) {
        setState(() => _colorOverride = r);
      }
    });
  }

  /// 动画选择：气泡 / 微气泡 / 冰块 / 米粒 / 无
  Future<void> _editAnimation() async {
    const options = {
      'bubbles': '气泡',
      'micro': '微气泡',
      'ice': '冰块',
      'rice': '米粒',
      'none': '无',
    };
    await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('液体动画',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _textDark,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              for (final e in options.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(ctx, e.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(e.value,
                              style: const TextStyle(
                                  color: _textDark,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (_animationLabel == e.value)
                          const Icon(Icons.check,
                              size: 20, color: _brandCyan),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ).then((v) {
      if (v != null) setState(() => _animation = v);
    });
  }

  /// 数字输入弹层（digitsOnly；空 = 无）
  Future<int?> _inputNumber({
    required String title,
    required String hint,
    String? initial,
  }) async {
    final ctrl = TextEditingController(text: initial ?? '');
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: _rowBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('无', style: TextStyle(color: _valueGray)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child:
                const Text('确定', style: TextStyle(color: _brandCyan)),
          ),
        ],
      ),
    );
    if (res == null) return null; // 取消
    if (res.isEmpty) return 0; // 「无」
    return int.tryParse(res);
  }

  /// 通用滑杆弹层：返回选定值；取消返回 null 不改动状态
  Future<double?> _sliderSheet({
    required String title,
    required double min,
    required double max,
    required int divisions,
    required double initial,
    required String Function(double v) label,
    required Color Function(double v) valueColor,
  }) {
    var value = initial;
    return showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: _textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                Text(
                  label(value),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: valueColor(value),
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  activeColor: valueColor(value),
                  onChanged: (v) => setSheet(() => value = v),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label(min),
                        style: const TextStyle(
                            color: _valueGray, fontSize: 12)),
                    Text(label(max),
                        style: const TextStyle(
                            color: _valueGray, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, value),
                    style: FilledButton.styleFrom(
                      backgroundColor: _brandCyan,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text('确定',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 图标选择：跳转全屏容器图标选择页
  Future<void> _editIcon() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => DrinkIconScreen(
          color: _liquidColor,
          initialId: _containerId,
        ),
      ),
    );
    if (id != null) setState(() => _containerId = id);
  }

  /// 进水量滑杆：-400% ~ 200%（负值 = 脱水扣减）
  Future<void> _editRatio() async {
    final v = await _sliderSheet(
      title: '饮料对进水量的影响',
      min: -400,
      max: 200,
      divisions: 120,
      initial: _ratio.clamp(-400, 200),
      label: (v) => '${v.round()}%',
      valueColor: (v) => v >= 0 ? _brandCyan : _ratioRed,
    );
    if (v != null) setState(() => _ratioPercent = v);
  }

  /// 卡路里滑杆：0 ~ 1000 卡（0 = 无）
  Future<void> _editCalories() async {
    final v = await _sliderSheet(
      title: '卡路里',
      min: 0,
      max: 1000,
      divisions: 100,
      initial: (_calories ?? 0).toDouble(),
      label: (v) => '${v.round()} 卡',
      valueColor: (v) => _calorieOrange,
    );
    if (v != null) {
      setState(() => _calories = v.round() == 0 ? null : v.round());
    }
  }

  /// 会员占位弹层（正式会员购买页后续接入）
  void _showMembershipSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F7FB),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.workspace_premium,
                  size: 34, color: Color(0xFF3BB3DB)),
            ),
            const SizedBox(height: 14),
            const Text('解锁自定义量',
                style: TextStyle(
                    color: _textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
              '开通会员即可自由设置饮品容量档位',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final name = _nameCtrl.text.trim();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildTopBar(name.isEmpty),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    const SizedBox(height: 8),
                    Center(child: _templatePill()),
                    const SizedBox(height: 6),
                    SizedBox(height: 270, child: _preview()),
                    _row(
                      icon: Icons.sell_outlined,
                      label: '名称',
                      value: Text(
                        name.isEmpty ? '未命名' : name,
                        style: TextStyle(
                          color: name.isEmpty ? _valueGray : _textDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: _editName,
                    ),
                    const SizedBox(height: 10),
                    _row(
                      icon: Icons.straighten,
                      label: '大小',
                      value: Text('$_sizeMl ml',
                          style: const TextStyle(
                              color: _textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      onTap: _editSize,
                    ),
                    _groupDivider(),
                    _row(
                      icon: Icons.crop_free,
                      label: '图标',
                      value: _containerId == null
                          ? DrinkIllustration(
                              beverageId: _template.templateId ?? _template.id,
                              color: _liquidColor,
                              size: 30,
                            )
                          : CustomPaint(
                              size: const Size(30, 32),
                              painter: ContainerShapePainter(
                                id: _containerId!,
                                color: _liquidColor,
                              ),
                            ),
                      onTap: _editIcon,
                    ),
                    const SizedBox(height: 10),
                    _row(
                      icon: Icons.palette_outlined,
                      label: '颜色',
                      value: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: _liquidColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      onTap: _editColor,
                    ),
                    const SizedBox(height: 10),
                    _row(
                      icon: Icons.bubble_chart,
                      label: '动画',
                      value: Text(_animationLabel,
                          style: const TextStyle(
                              color: _valueGray,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      onTap: _editAnimation,
                    ),
                    _groupDivider(),
                    _row(
                      icon: Icons.water_drop_outlined,
                      label: '进水量',
                      value: Text(
                        '${_ratio.round()}%',
                        style: TextStyle(
                          color: _ratio >= 0 ? _brandCyan : _ratioRed,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onTap: _editRatio,
                    ),
                    const SizedBox(height: 10),
                    _row(
                      icon: Icons.local_fire_department_outlined,
                      label: '卡路里',
                      value: _nutritionText(
                        value: _calories,
                        text: _calories == null ? null : '$_calories 卡',
                        color: _calorieOrange,
                      ),
                      onTap: _editCalories,
                    ),
                    const SizedBox(height: 10),
                    _row(
                      icon: Icons.medication_outlined,
                      label: '咖啡因',
                      value: _nutritionText(
                        value: _caffeineMg,
                        text: _caffeineMg == null ? null : '$_caffeineMg mg',
                        color: _caffeineBrown,
                      ),
                      onTap: () async {
                        final v = await _inputNumber(
                            title: '咖啡因（mg）', hint: '留空为无');
                        if (v != null) {
                          setState(() =>
                              _caffeineMg = v == 0 ? null : v);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    _row(
                      icon: Icons.local_bar_outlined,
                      label: '酒精',
                      value: _alcoholText(),
                      onTap: () async {
                        final v = await _inputNumber(
                            title: '酒精含量（%）', hint: '留空为无');
                        if (v != null) {
                          setState(() =>
                              _alcoholPercent = v == 0 ? null : v);
                        }
                      },
                    ),
                    if (_isEditing) ...[
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: _confirmDelete,
                        child: const Text('删除饮品',
                            style: TextStyle(
                                color: Color(0xFFC9364F),
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- 子组件 ----------------

  Widget _buildTopBar(bool nameEmpty) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Text('取消',
                  style: TextStyle(
                      color: Color(0xFF8E8E93),
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: nameEmpty ? null : _save,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: nameEmpty
                    ? const Color(0xFF1F2733).withValues(alpha: 0.35)
                    : const Color(0xFF1F2733),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.upload, size: 15, color: Colors.white),
                  SizedBox(width: 5),
                  Text('保存',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 「类似于: X ⌄」模板胶囊（模板色浅底）
  Widget _templatePill() {
    return GestureDetector(
      onTap: _pickTemplate,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: _liquidColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '类似于: ${_template.name}',
              style: TextStyle(
                color: _liquidColor.computeLuminance() > 0.75
                    ? Color.lerp(_liquidColor, const Color(0xFF5B4A2F), 0.5)
                    : _liquidColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            Icon(Icons.keyboard_arrow_down,
                size: 18,
                color: _liquidColor.computeLuminance() > 0.75
                    ? Color.lerp(_liquidColor, const Color(0xFF5B4A2F), 0.5)
                    : _liquidColor),
          ],
        ),
      ),
    );
  }

  /// 居中大预览：动态液体容器（颜色实时渲染 + 液体晃动 + 动画粒子）+ 会员锁徽章
  Widget _preview() {
    return Stack(
      alignment: Alignment.center,
      children: [
        _LiquidPreview(
          color: _liquidColor,
          animation: _animKey,
          containerId: _containerId,
        ),
        if (_template.memberOnly)
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_outline,
                size: 34, color: Colors.white),
          ),
      ],
    );
  }

  /// iOS 风格设置行：左图标 + 标签，右侧值
  Widget _row({
    required IconData icon,
    required String label,
    required Widget value,
    VoidCallback? onTap,
  }) {
    return Material(
      color: _rowBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(icon, size: 22, color: _textDark),
              const SizedBox(width: 12),
              Text(label,
                  style: const TextStyle(
                      color: _textDark,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              value,
            ],
          ),
        ),
      ),
    );
  }

  /// 组间分隔（居中短灰线，对标原版）
  Widget _groupDivider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Container(
            width: 64,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFECECEE),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );

  /// 营养值文本：无 = 灰，有值 = 对应色
  Widget _nutritionText({required int? value, String? text, required Color color}) {
    return Text(
      text ?? '无',
      style: TextStyle(
        color: value == null ? _valueGray : color,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _alcoholText() {
    final v = _alcoholPercent;
    return Text(
      v == null ? '无' : '$v%',
      style: const TextStyle(
          color: _alcoholPurple, fontSize: 15, fontWeight: FontWeight.w800),
    );
  }

  Future<void> _confirmDelete() async {
    final b = widget.existing!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('删除饮品',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
        content: Text(
          '确定删除「${b.name}」吗？历史记录不会被清除。',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child:
                const Text('取消', style: TextStyle(color: Color(0xFF8E8E93))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('删除',
                style: TextStyle(color: Color(0xFFC9364F))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(customBeveragesProvider.notifier).remove(b.id);
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text('已删除「${b.name}」'),
      duration: const Duration(milliseconds: 1200),
    ));
  }
}

/// 颜色选择圆点
class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? const Color(0xFF1C1C1E) : Colors.transparent,
            width: 2.5,
          ),
        ),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// 动态液体预览容器：液体颜色实时渲染 + 液面晃动 + 按动画选项渲染粒子
class _LiquidPreview extends StatefulWidget {
  const _LiquidPreview({
    required this.color,
    required this.animation,
    this.containerId,
  });

  final Color color;

  /// 动画 key：bubbles / micro / ice / rice / none
  final String animation;

  /// 容器形状 id；null = 默认圆角玻璃杯
  final String? containerId;

  @override
  State<_LiquidPreview> createState() => _LiquidPreviewState();
}

class _LiquidPreviewState extends State<_LiquidPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => CustomPaint(
        painter: _LiquidPainter(
          color: widget.color,
          animation: widget.animation,
          containerId: widget.containerId,
          t: _ctrl.value * 12,
        ),
        child: const SizedBox(width: 170, height: 225),
      ),
    );
  }
}

/// 液体自绘：
/// - 默认容器为圆角玻璃杯（上圆角 30、下圆角 24）；选择容器形状后按形状裁剪
/// - 液面由多重正弦叠加产生真实晃动效果
/// - bubbles：气泡自底部升起，上升途中渐显、顶端渐散
/// - micro：微气泡（数量多、体积小、上升更快）
/// - ice：冰块悬浮于液面下方，带轻微上下浮动与旋转
/// - rice：米粒悬浮于液体中，轻微上下浮动（粥类）
class _LiquidPainter extends CustomPainter {
  _LiquidPainter({
    required this.color,
    required this.animation,
    required this.t,
    this.containerId,
  });

  final Color color;
  final String animation;
  final double t;
  final String? containerId;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const inset = 9.0;

    // 容器裁剪路径：形状库容器 或 默认圆角玻璃杯
    final Path clipPath;
    final ContainerShape? shape =
        containerId == null ? null : containerShapeById(containerId);
    if (shape != null) {
      clipPath = scaledContainerPath(
        shape,
        Rect.fromLTWH(0, 0, w, h),
      );
    } else {
      clipPath = Path()
        ..addRRect(RRect.fromRectAndCorners(
          Rect.fromLTWH(inset, inset, w - inset * 2, h - inset * 2),
          topLeft: const Radius.circular(30),
          topRight: const Radius.circular(30),
          bottomLeft: const Radius.circular(24),
          bottomRight: const Radius.circular(24),
        ));
    }

    // 空容器底色
    canvas.drawPath(clipPath, Paint()..color = const Color(0xFFF3F3F6));

    canvas.save();
    canvas.clipPath(clipPath);

    final left = inset + 7;
    final right = w - inset - 7;
    final bottom = h - inset - 7;
    final baseLevel = bottom - h * 0.50;

    // 液面：多重正弦叠加 → 真实晃动
    double surfaceY(double x) =>
        baseLevel +
        math.sin(t * 1.5) * 5 +
        math.sin(t * 0.9 + 1.7) * 3 +
        math.sin(x * 0.045 + t * 2.6) * 1.8 +
        math.sin(x * 0.09 - t * 1.9) * 1.1;

    // 液体主体
    final liquid = Path()
      ..moveTo(left, bottom)
      ..lineTo(left, surfaceY(left));
    for (double x = left; x <= right; x += 6) {
      liquid.lineTo(x, surfaceY(x));
    }
    liquid
      ..lineTo(right, surfaceY(right))
      ..lineTo(right, bottom)
      ..close();
    canvas.drawPath(liquid, Paint()..color = color);

    // 液面高光
    final highlight = Path();
    for (double x = left; x <= right; x += 6) {
      final y = surfaceY(x);
      if (x == left) {
        highlight.moveTo(x, y);
      } else {
        highlight.lineTo(x, y);
      }
    }
    canvas.drawPath(
      highlight,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // 粒子层（按动画选项）
    final paint = Paint();
    switch (animation) {
      case 'bubbles':
        for (int i = 0; i < 10; i++) {
          final speed = 0.14 + _rnd(i, 1) * 0.16;
          final p = (t * speed + _rnd(i, 3)) % 1;
          final cx = left + _rnd(i, 5) * (right - left);
          final by = bottom - p * (bottom - baseLevel - 6);
          final r = 2.5 + _rnd(i, 7) * 3;
          paint.color = Colors.white
              .withValues(alpha: _fadeAlpha(p) * 0.55);
          canvas.drawCircle(Offset(cx, by), r, paint);
        }
      case 'micro':
        for (int i = 0; i < 24; i++) {
          final speed = 0.22 + _rnd(i, 1) * 0.2;
          final p = (t * speed + _rnd(i, 3)) % 1;
          final cx = left + _rnd(i, 5) * (right - left);
          final by = bottom - p * (bottom - baseLevel - 6);
          final r = 1 + _rnd(i, 7) * 1.4;
          paint.color = Colors.white
              .withValues(alpha: _fadeAlpha(p) * 0.5);
          canvas.drawCircle(Offset(cx, by), r, paint);
        }
      case 'ice':
        for (int i = 0; i < 2; i++) {
          final bob = math.sin(t * 1.2 + i * 2.1) * 4;
          final rot = math.sin(t * 0.8 + i * 1.4) * 0.10;
          final cx = left + (right - left) * (i == 0 ? 0.36 : 0.66);
          final cy = surfaceY(cx) + 20 + bob;
          canvas.save();
          canvas.translate(cx, cy);
          canvas.rotate(rot);
          final rect = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: 34, height: 34),
            const Radius.circular(8),
          );
          paint.color = Colors.white.withValues(alpha: 0.62);
          canvas.drawRRect(rect, paint);
          paint
            ..color = Colors.white.withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
          canvas.drawRRect(rect, paint);
          paint.style = PaintingStyle.fill;
          canvas.restore();
        }
      case 'rice':
        for (int i = 0; i < 10; i++) {
          final gy = baseLevel + 16 + _rnd(i, 9) * (bottom - baseLevel - 30);
          final cy = gy + math.sin(t * 1.1 + i * 1.3) * 3;
          final cx = left + _rnd(i, 5) * (right - left);
          canvas.save();
          canvas.translate(cx, cy);
          canvas.rotate(_rnd(i, 11) * math.pi);
          paint.color = Colors.white.withValues(alpha: 0.78);
          canvas.drawOval(
            Rect.fromCenter(
                center: Offset.zero, width: 7, height: 4.2),
            paint,
          );
          canvas.restore();
        }
      case 'none':
        break;
    }

    canvas.restore();

    if (shape != null) {
      // 容器把手（描边）
      if (shape.handle != null) {
        final matrix = Matrix4.diagonal3Values(w / 100, h / 100, 1);
        canvas.drawPath(
          shape.handle!.transform(matrix.storage),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    } else {
      // 默认玻璃杯杯口描边
      canvas.drawPath(
        Path()
          ..addRRect(RRect.fromRectAndCorners(
            Rect.fromLTWH(inset, inset, w - inset * 2, h - inset * 2),
            topLeft: const Radius.circular(30),
            topRight: const Radius.circular(30),
            bottomLeft: const Radius.circular(24),
            bottomRight: const Radius.circular(24),
          )),
        Paint()
          ..color = const Color(0xFFE7E7EC)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  /// 粒子生命周期透明度：入场渐显（p<0.15）、顶端渐散（p>0.72）
  double _fadeAlpha(double p) {
    if (p < 0.15) return p / 0.15;
    if (p > 0.72) return (1 - (p - 0.72) / 0.28).clamp(0.0, 1.0);
    return 1;
  }

  /// 确定性伪随机（每帧稳定，无抖动）
  double _rnd(int i, int salt) {
    final v =
        math.sin((i + 1) * 12.9898 + salt * 78.233) * 43758.5453;
    return v - v.floor();
  }

  @override
  bool shouldRepaint(_LiquidPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.animation != animation ||
      oldDelegate.containerId != containerId ||
      oldDelegate.t != t;
}

/// 「类似于」品牌饮品模板描述（名称 + 分类 + 液体色 + 进水量折算比例）
class _BrandSpec {
  const _BrandSpec(this.name, this.category, this.color, this.ratio);

  final String name;
  final BeverageCategory category;
  final Color color;
  final double ratio;
}
