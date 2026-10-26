import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/beverage.dart';
import '../../../shared/models/preferred_unit.dart';
import '../../../shared/widgets/drink_illustration.dart';
import '../../settings/settings_flags.dart';
import '../../settings/widget_settings_screen.dart';
import '../../home/providers/home_providers.dart';
import '../providers/custom_beverage_provider.dart';
import '../widgets/liquid_preview.dart';
import '../widgets/svg_container.dart';
import 'drink_animation_screen.dart';
import 'drink_color_screen.dart' show DrinkColorScreen, drinkColorPresets;
import 'drink_icon_screen.dart';
import 'drink_nutrient_screen.dart' show DrinkNutrientScreen, NutrientTab;

/// 添加 / 编辑自定义饮品页（对标原版：全屏编辑器）
///
/// 结构：
/// 1. 顶栏：左「取消」+ 右深色「⬆保存」胶囊
/// 2. 居中大预览（SVG 容器动态液体）
/// 3. iOS 风格分组行：名称 / 大小 ‖ 图标 / 颜色 / 动画 ‖ 进水量 / 卡路里 / 咖啡因 / 酒精
/// 4. 编辑模式下底部提供删除按钮
class DrinkEditScreen extends ConsumerStatefulWidget {
  const DrinkEditScreen({super.key, this.existing, this.readOnly = false});

  final Beverage? existing;

  /// 只读浏览模式（系统内置预设饮品）：可进入页面查看并修改各项，
  /// 但右上角无保存按钮、底部无删除按钮，改动不会被保存
  final bool readOnly;

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

  late Beverage _template;
  late TextEditingController _nameCtrl;
  late int _sizeMl;
  Color? _colorOverride;
  String? _animation; // null = 未选择（新增默认态）
  double? _ratioPercent; // 进水量覆盖（%），null = 跟随模板
  String? _containerId; // 容器图标 id（'svg:<文件名>'）
  int? _calories;
  int? _caffeineMg;
  int? _alcoholPercent;

  /// 保存中标志：防止连点保存生成重复饮品
  bool _saving = false;

  /// 用户是否手动选过图标（未手动选过时，切换分类会同步换成分类的默认容器）
  bool _iconTouched = false;

  /// 用户是否已手动选过分类（选过后随机初始化不再覆盖其选择）
  bool _categoryPicked = false;

  bool get _isEditing => widget.existing != null;

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
      if (b.id.startsWith('custom_')) {
        // 自定义饮品：以保存时的模板预设派生分类/折算比例等
        final tid = b.templateId ?? Beverage.fallbackIllustration(b.category);
        _template = Beverage.presets.firstWhere(
          (p) => p.id == tid,
          orElse: () => b,
        );
      } else {
        // 内置预设饮品：直接以自身为模板（无 templateId，
        // 避免回退到同分类的其他预设）
        _template = b;
      }
    } else {
      _nameCtrl = TextEditingController();
      // 新增默认模板（「类似于」入口已剔除）：分类/折算比例由此派生；
      // 分类可在此页「分类」行重新选择
      _template = Beverage.presets.firstWhere((p) => p.id == 'soda');
      _sizeMl = _template.defaultMl;
      // 先同步落一个默认容器，避免随机图标异步加载完成前预览区空白闪一下
      _containerId = _template.containerId;
      _randomizeNew();
    }
  }

  /// 新增模式：每次打开页面从容器图标库随机挑一个容器展示，
  /// 颜色同样随机取自预设色板，动画默认不选择
  Future<void> _randomizeNew() async {
    final ids = await loadSvgContainerIds();
    if (!mounted || _isEditing || _categoryPicked) return;
    final rnd = math.Random();
    setState(() {
      if (ids.isNotEmpty && !_iconTouched) {
        _containerId = ids[rnd.nextInt(ids.length)];
      }
      _colorOverride ??= drinkColorPresets[rnd.nextInt(drinkColorPresets.length)];
    });
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
        'leaves' => '茶叶',
        'micro' => '微气泡',
        'ice' => '冰块',
        'none' => '无',
        _ => '气泡',
      };

  // ---------------- 保存 ----------------

  Future<void> _save() async {
    if (_saving) return; // 防抖：连点保存只生效一次
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    // 同名校验：内置预设与其它自定义饮品都不可重名（编辑自身时排除自己）
    final selfId = widget.existing?.id;
    final duplicated = [...Beverage.presets, ...ref.read(customBeveragesProvider)]
        .any((b) => b.id != selfId && b.name.trim() == name);
    if (duplicated) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已存在名为「$name」的饮品'),
        duration: const Duration(milliseconds: 1500),
      ));
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
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
      // 编辑可能影响桌面小组件饮料格（名称/图标/容量），主动刷新一次
      // （走 Notifier 的 ref，页面销毁后也能安全完成）
      unawaited(ref.read(widgetSettingsProvider.notifier).refreshWidget());
    } else {
      await notifier.addCustom(beverage);
    }
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(_isEditing ? '已保存「$name」' : '已添加「$name」'),
      duration: const Duration(milliseconds: 1200),
    ));
  }

  // ---------------- 交互弹层 ----------------

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

  /// 容量选择：3 个固定档位 + 自定义量
  Future<void> _editSize() async {
    // 固定档位点选 pop(int) 回传新容量；自定义量路径 pop 无返回值
    final v = await showModalBottomSheet<int>(
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
                          child: Text('${UnitFormat.volume(v)}',
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
                  const maxMl = 2000; // 自定义容量上限（不局限于预设档位最大值）
                  Navigator.pop(ctx);
                  final custom = await _inputNumber(
                    title: '自定义量（${UnitFormat.unit.symbol}）',
                    hint:
                        '${UnitFormat.volume(10, compact: true)} - ${UnitFormat.volume(maxMl, compact: true)}',
                    initial: UnitFormat.number(_sizeMl),
                    allowNone: false,
                    volumeUnit: true,
                  );
                  if (custom == null) return; // 取消
                  if (!mounted) return;
                  if (custom < 10 || custom > maxMl) {
                    // 超出范围明确提示，不再静默丢弃
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                        '请输入 ${UnitFormat.volume(10, compact: true)} - '
                        '${UnitFormat.volume(maxMl, compact: true)} 之间的容量'),
                      duration: const Duration(milliseconds: 1500),
                    ));
                    return;
                  }
                  setState(() => _sizeMl = custom);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '自定义量${!_template.volumes.contains(_sizeMl) ? ' · ${UnitFormat.volume(_sizeMl)}' : ''}',
                          style: const TextStyle(
                              color: _textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (!_template.volumes.contains(_sizeMl))
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
    );
    if (v != null) setState(() => _sizeMl = v);
  }

  /// 解析可用于预览的 SVG 容器：当前容器不是 SVG 时回退模板容器并写回
  /// （老数据无 containerId 时会自动补齐，避免颜色/动画入口点了没反应）
  String? _resolvePreviewContainer() {
    if (isSvgContainer(_containerId)) return _containerId;
    final fallback = _template.containerId;
    if (isSvgContainer(fallback)) {
      setState(() => _containerId = fallback);
      return fallback;
    }
    return null;
  }

  /// 颜色选择：跳转全屏颜色选择页（预设色板 + 自定义滑杆）
  Future<void> _editColor() async {
    final id = _resolvePreviewContainer();
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('请先选择饮品图标，再调整颜色'),
        duration: Duration(milliseconds: 1500),
      ));
      return;
    }
    final c = await Navigator.of(context).push<Color>(
      MaterialPageRoute(
        builder: (_) => DrinkColorScreen(
          containerId: id,
          initial: _liquidColor,
        ),
      ),
    );
    if (c != null) setState(() => _colorOverride = c);
  }

  /// 动画选择：跳转全屏动画选择页（实时预览）
  Future<void> _editAnimation() async {
    final id = _resolvePreviewContainer();
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('请先选择饮品图标，再调整动画'),
        duration: Duration(milliseconds: 1500),
      ));
      return;
    }
    final v = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => DrinkAnimationScreen(
          containerId: id,
          color: _liquidColor,
          initial: _animation,
        ),
      ),
    );
    if (v != null) setState(() => _animation = v.isEmpty ? null : v);
  }

  /// 分类选择：决定折算比例、容量档位与动画推断
  Future<void> _editCategory() async {
    final c = await showModalBottomSheet<BeverageCategory>(
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
              const Text('饮品分类',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _textDark,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              for (final v in BeverageCategory.values)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(ctx, v),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(v.icon, size: 20, color: v.color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(v.label,
                              style: const TextStyle(
                                  color: _textDark,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (v == _template.category)
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
    );
    if (c == null || c == _template.category) return;
    // 取该分类的代表预设作为新模板（折算比例/容量档位/默认容器都随之切换）
    final preset = Beverage.presets.firstWhere((p) => p.category == c);
    setState(() {
      _categoryPicked = true;
      _template = preset;
      _ratioPercent = null; // 回落到新分类的默认折算比例
      _colorOverride = null; // 回落到新模板的液体色
      _animation = null; // 按新分类重新推断动画
      if (!preset.volumes.contains(_sizeMl)) _sizeMl = preset.defaultMl;
      // 用户没手动挑过图标时，顺手换成该分类的默认容器
      if (!_iconTouched) _containerId = preset.containerId;
    });
  }

  /// 数字输入弹层（digitsOnly；「无」返回 0，取消返回 null）
  /// [allowNone] 为 false 时隐藏「无」按钮（容量输入等没有「无」语义的场景）
  Future<int?> _inputNumber({
    required String title,
    required String hint,
    String? initial,
    bool allowNone = true,
    bool volumeUnit = false,
  }) async {
    // 容量输入跟随单位偏好：oz 模式允许一位小数，落库仍统一为 ml
    final isOz = volumeUnit && UnitFormat.unit == PreferredUnit.oz;
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
          keyboardType: TextInputType.numberWithOptions(decimal: isOz),
          inputFormatters: [
            isOz
                ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                : FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            hintText: hint,
            suffixText: volumeUnit ? UnitFormat.unit.symbol : null,
            filled: true,
            fillColor: _rowBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          if (allowNone)
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
    final n = double.tryParse(res);
    if (n == null) return null;
    return volumeUnit ? UnitFormat.unit.toMl(n).round() : n.round();
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
                  semanticFormatterCallback: (v) => label(v),
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
    if (id != null) {
      setState(() {
        _containerId = id;
        _iconTouched = true; // 手动选过图标后，切换分类不再覆盖
      });
    }
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

  /// 卡路里滚轮页（0 = 无）
  Future<void> _editCalories() async {
    final v = await _pushNutrient(NutrientTab.calories, _calories);
    // 0 归一为「无」，避免卡片显示「0 卡」而不是灰色「无」
    if (v != null) setState(() => _calories = v == 0 ? null : v);
  }

  /// 咖啡因滚轮页（0 = 无）
  Future<void> _editCaffeine() async {
    final v = await _pushNutrient(NutrientTab.caffeine, _caffeineMg);
    if (v != null) setState(() => _caffeineMg = v == 0 ? null : v);
  }

  /// 酒精分类滚轮页（无 / 五档 ABV）
  Future<void> _editAlcohol() async {
    final v = await _pushNutrient(NutrientTab.alcohol, _alcoholPercent);
    if (v != null) setState(() => _alcoholPercent = v);
  }

  /// 营养选项滚轮页统一跳转（对标原版卡路里 / 咖啡因 / 酒精选项卡）
  Future<int?> _pushNutrient(NutrientTab tab, int? initial) {
    return Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => DrinkNutrientScreen(
          tab: tab,
          color: switch (tab) {
            NutrientTab.calories => _calorieOrange,
            NutrientTab.caffeine => _caffeineBrown,
            NutrientTab.alcohol => _alcoholPurple,
          },
          containerId: _containerId,
          templateId: _template.templateId ?? _template.id,
          liquidColor: _liquidColor,
          animationKey: _animKey,
          initial: initial,
        ),
      ),
    );
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    // 单位切换后容量文案需要立即重绘
    ref.watch(preferredUnitProvider);
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
                    SizedBox(height: 270, child: _preview()),
                    if (widget.readOnly) ...[
                      const SizedBox(height: 4),
                      const Text(
                        '内置饮品为只读展示，如需自定义请返回后点右上「添加」',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _valueGray, fontSize: 12),
                      ),
                    ],
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
                      onTap: widget.readOnly ? null : _editName,
                    ),
                    const SizedBox(height: 10),
                    // 分类：决定折算比例 / 容量档位 / 动画推断（自定义饮品可选）
                    _row(
                      icon: _template.category.icon,
                      label: '分类',
                      value: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _template.category.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _template.category.label,
                            style: const TextStyle(
                                color: _textDark,
                                fontSize: 15,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      onTap: widget.readOnly ? null : _editCategory,
                    ),
                    const SizedBox(height: 10),
                    _row(
                      icon: Icons.straighten,
                      label: '大小',
                      value: Text(UnitFormat.volume(_sizeMl),
                          style: const TextStyle(
                              color: _textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      onTap: widget.readOnly ? null : _editSize,
                    ),
                    _groupDivider(),
                    _row(
                      icon: Icons.crop_free,
                      label: '图标',
                      value: !isSvgContainer(_containerId)
                          ? DrinkIllustration(
                              beverageId: _template.templateId ?? _template.id,
                              color: _liquidColor,
                              size: 30,
                            )
                          : SvgContainerIcon(
                              containerId: _containerId!,
                              color: _liquidColor,
                              fillRatio: 0.9, // 液体风格：液体占杯身 90%（全局统一）
                              size: 30,
                            ),
                      onTap: widget.readOnly ? null : _editIcon,
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
                      onTap: widget.readOnly ? null : _editColor,
                    ),
                    const SizedBox(height: 10),
                    _row(
                      icon: Icons.bubble_chart,
                      label: '动画',
                      // 未手动选择时展示自动推断的动画值（与预览一致），不再留白
                      value: Text(
                          _animation == null
                              ? '$_animationLabel（自动）'
                              : _animationLabel,
                          style: const TextStyle(
                              color: _valueGray,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      onTap: widget.readOnly ? null : _editAnimation,
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
                      onTap: widget.readOnly ? null : _editRatio,
                    ),
                    const SizedBox(height: 10),
                    // 「跟踪卡路里」总开关关闭：卡路里选项卡整行隐藏（新增/编辑通用）
                    ListenableBuilder(
                      listenable: SettingsFlags.instance,
                      builder: (ctx, _) => SettingsFlags.instance.trackCalories
                          ? Column(
                              children: [
                                _row(
                                  icon: Icons.local_fire_department_outlined,
                                  label: '卡路里',
                                  value: _nutritionText(
                                    value: _calories,
                                    text: _calories == null
                                        ? null
                                        : '$_calories 千卡',
                                    color: _calorieOrange,
                                  ),
                                  onTap: widget.readOnly ? null : _editCalories,
                                ),
                                const SizedBox(height: 10),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                    _row(
                      icon: Icons.medication_outlined,
                      label: '咖啡因',
                      value: _nutritionText(
                        value: _caffeineMg,
                        text: _caffeineMg == null ? null : '$_caffeineMg mg',
                        color: _caffeineBrown,
                      ),
                      onTap: widget.readOnly ? null : _editCaffeine,
                    ),
                    const SizedBox(height: 10),
                    _row(
                      icon: Icons.local_bar_outlined,
                      label: '酒精',
                      value: _alcoholText(),
                      onTap: widget.readOnly ? null : _editAlcohol,
                    ),
                    // 删除按钮仅自定义饮品编辑模式提供（内置预设只读浏览）
                    if (_isEditing && !widget.readOnly) ...[
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
          // 只读浏览模式（内置预设饮品）无保存按钮
          if (!widget.readOnly)
            GestureDetector(
              onTap: nameEmpty || _saving ? null : _save,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: nameEmpty || _saving
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

  /// 居中大预览：SVG 容器动态液体（颜色/动画实时渲染）
  /// （编辑老数据无容器时回退模板插画）
  Widget _preview() {
    final child = isSvgContainer(_containerId)
        ? LiquidPreview(
            containerId: _containerId!,
            color: _liquidColor,
            animation: _animKey,
          )
        : _isEditing
            ? DrinkIllustration(
                beverageId: _template.templateId ?? _template.id,
                color: _liquidColor,
                size: 150,
              )
            : const SizedBox(width: 170, height: 225);
    return Stack(
      alignment: Alignment.center,
      children: [
        child,
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
    return Text(
      _alcoholLabel,
      style: TextStyle(
          color: _alcoholPercent == null ? _valueGray : _alcoholPurple,
          fontSize: 15,
          fontWeight: FontWeight.w800),
    );
  }

  /// 酒精档位短名（按 ABV 区间映射，与选项页档位一致）
  String get _alcoholLabel {
    final v = _alcoholPercent;
    if (v == null) return '无';
    if (v < 4) return '淡酒';
    if (v < 5) return '微量';
    if (v < 6) return '低度';
    if (v < 15) return '中度';
    return '烈';
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
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // 桌面小组件槽位若用了这杯饮品：回退为纯净水，避免悬空 id 被静默
    // 回退成「纯净水」却仍按被删饮品记录
    final ws = ref.read(widgetSettingsProvider);
    var next = ws;
    if (ws.drink1 == b.id) {
      next = next.copyWith(drink1: 'water_pure', vol1: 250);
    }
    if (ws.drink2 == b.id) {
      next = next.copyWith(drink2: 'water_pure', vol2: 250);
    }
    if (ws.drink3 == b.id) {
      next = next.copyWith(drink3: 'water_pure', vol3: 250);
    }
    await ref.read(customBeveragesProvider.notifier).remove(b.id);
    if (!identical(next, ws)) {
      // update() 内部会即时刷新桌面小组件
      await ref.read(widgetSettingsProvider.notifier).update(next);
    }
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text('已删除「${b.name}」'),
      duration: const Duration(milliseconds: 1200),
    ));
  }
}
