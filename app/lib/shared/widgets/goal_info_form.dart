import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/preferred_unit.dart';
import '../models/user_profile.dart';
import 'underwater_scene.dart';

/// 信息录入页的表单值（性别 / 体重 / 身高 / 运动强度 / 温度 / 自定义目标）。
///
/// onboarding 第 1 步与设置页「我的饮水目标」共用这一份数据模型与同一套
/// UI（[GoalInfoForm]），避免两处重复实现导致视觉/计算口径不一致。
@immutable
class GoalInfoValues {
  const GoalInfoValues({
    this.gender,
    this.genderLabel,
    this.weightKg = 60,
    this.heightCm = 170,
    this.activityLevel = ActivityLevel.medium,
    this.temperature = GoalTemperature.mild,
    this.customGoalMl,
    this.weightSelected = false,
    this.age = 25,
  });

  final Gender? gender;

  /// 性别展示标签（怀孕/母乳喂养等），与计算用 Gender 枚举分离
  final String? genderLabel;
  final double weightKg;
  final double heightCm;
  final ActivityLevel activityLevel;
  final GoalTemperature temperature;

  /// 用户自定义目标（ml）；null = 使用推荐算法
  final int? customGoalMl;

  /// 体重卡片是否已被用户点选过
  final bool weightSelected;
  final int age;

  bool get genderSelected => gender != null;

  /// 当前预览目标（自定义优先；否则推荐算法 + 温度修正，夹紧 [1500, 4500]）
  int get previewGoal {
    if (customGoalMl != null) return customGoalMl!.clamp(500, 5000);
    final base = UserProfile.create(
      gender: gender ?? Gender.male,
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      activityLevel: activityLevel,
    ).dailyGoalMl;
    return (base + temperature.deltaMl).clamp(1500, 4500);
  }

  GoalInfoValues copyWith({
    Gender? gender,
    String? genderLabel,
    double? weightKg,
    double? heightCm,
    ActivityLevel? activityLevel,
    GoalTemperature? temperature,
    int? customGoalMl,
    bool clearCustomGoal = false,
    bool? weightSelected,
    int? age,
  }) {
    return GoalInfoValues(
      gender: gender ?? this.gender,
      genderLabel: genderLabel ?? this.genderLabel,
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm ?? this.heightCm,
      activityLevel: activityLevel ?? this.activityLevel,
      temperature: temperature ?? this.temperature,
      customGoalMl:
          clearCustomGoal ? null : (customGoalMl ?? this.customGoalMl),
      weightSelected: weightSelected ?? this.weightSelected,
      age: age ?? this.age,
    );
  }
}

/// 初始化信息录入页（白底水下场景 + 白胶囊选项卡）。
///
/// 完全受控：值来自 [values]，任一选项变化通过 [onChanged] 回传，
/// 两个入口（onboarding / 设置页）各自决定如何保存。
class GoalInfoForm extends StatefulWidget {
  const GoalInfoForm({
    super.key,
    required this.values,
    required this.onChanged,
    required this.continueLabel,
    required this.onContinue,
  });

  final GoalInfoValues values;
  final ValueChanged<GoalInfoValues> onChanged;

  /// 底部主按钮文案（onboarding: 继续 / 设置页: 完成）
  final String continueLabel;
  final VoidCallback onContinue;

  @override
  State<GoalInfoForm> createState() => _GoalInfoFormState();
}

class _GoalInfoFormState extends State<GoalInfoForm>
    with SingleTickerProviderStateMixin {
  /// 驱动性别/体重胶囊颤动的循环控制器（与水下背景同周期 12s）
  late final AnimationController _anim;

  static const _brandCyan = Color(0xFF4DB8D8);

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// 运动强度展示值（对标原版「中等运动量」文案）
  static String _activityAmountLabel(ActivityLevel a) => switch (a) {
        ActivityLevel.low => '低运动量',
        ActivityLevel.medium => '中等运动量',
        ActivityLevel.high => '高运动量',
      };

  /// 运动强度对应的选项图标（选择后展示在胶囊右侧）
  static IconData _activityIcon(ActivityLevel a) => switch (a) {
        ActivityLevel.low => Icons.chair_outlined,
        ActivityLevel.medium => Icons.directions_run,
        ActivityLevel.high => Icons.fitness_center,
      };

  /// 天气对应的选项图标
  static IconData _tempIcon(GoalTemperature t) => switch (t) {
        GoalTemperature.cold => Icons.ac_unit,
        GoalTemperature.mild => Icons.wb_cloudy_outlined,
        GoalTemperature.hot => Icons.wb_sunny_outlined,
      };

  /// 已选性别的展示图标（未选择时由胶囊回退为箭头）
  IconData _genderIcon() {
    final label = widget.values.genderLabel;
    if (label == null) return Icons.chevron_right;
    return kGenderOptions
        .firstWhere((o) => o.label == label, orElse: () => kGenderOptions.first)
        .icon;
  }

  void _update(GoalInfoValues next) => widget.onChanged(next);

  // ============== 底部弹层 ==============

  void _showGenderSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GenderSheet(
        selectedLabel: widget.values.genderLabel,
        onSelected: (o) {
          _update(widget.values.copyWith(
            gender: o.gender,
            genderLabel: o.label,
            clearCustomGoal: true,
          ));
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showActivitySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ActivitySheet(
        selected: widget.values.activityLevel,
        onSelected: (a) {
          _update(widget.values.copyWith(
            activityLevel: a,
            clearCustomGoal: true,
          ));
          Navigator.pop(context);
        },
      ),
    );
  }

  /// 体重录入：滚轮底部弹窗（数字轮 kg + 高亮带 + 蓝青色「完成」胶囊）
  void _showWeightSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF7F6FB),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _NumberWheelSheet(
        title: '体重',
        min: 30,
        max: 200,
        initial: widget.values.weightKg,
        onDone: (kg) => _update(widget.values.copyWith(
          weightKg: kg,
          weightSelected: true,
          clearCustomGoal: true,
        )),
      ),
    );
  }

  /// 温度选择影响目标计算（寒冷 -150 / 温和 0 / 炎热 +300）
  void _showTempSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _TemperatureSheet(
        selected: widget.values.temperature,
        onSelected: (t) {
          _update(widget.values.copyWith(
            temperature: t,
            clearCustomGoal: true,
          ));
          Navigator.pop(context);
        },
      ),
    );
  }

  /// 自定义目标：大号数字 + ml 键盘输入（对标参考图的数字键盘弹层）
  void _showCustomGoalSheet(BuildContext context) {
    final values = widget.values;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF2F2F4),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CustomGoalSheet(
        initialMl: values.customGoalMl ?? values.previewGoal,
        onDone: (ml) => _update(widget.values.copyWith(customGoalMl: ml)),
      ),
    );
  }

  /// 「常见目标 ⓘ」说明弹层：常见目标与推荐目标的区别
  void _showCommonGoalSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _CommonGoalSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final values = widget.values;
    // 性别与体重均已选择才允许继续下一步
    final canContinue = values.genderSelected && values.weightSelected;
    return Stack(
      children: [
        // 底层：白底，气泡与冰晶用淡青灰着色保证可见
        const Positioned.fill(
          child: UnderwaterBackground(
            gradientColors: [Colors.white, Colors.white],
            decorTint: Color(0xFFB7E6F0),
          ),
        ),
        // 内容层
        SafeArea(
          child: AnimatedBuilder(
            animation: _anim,
            builder: (context, _) {
              final t = _anim.value;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    // 大字目标
                    Text(
                      UnitFormat.volume(values.previewGoal),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _brandCyan,
                        fontSize: 56,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _showCommonGoalSheet(context),
                      behavior: HitTestBehavior.opaque,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('常见目标',
                              style: TextStyle(
                                  color: _brandCyan, fontSize: 14)),
                          SizedBox(width: 4),
                          Icon(Icons.info_outline,
                              color: _brandCyan, size: 16),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '计算你的目标',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _brandCyan,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    // 白胶囊选项卡：未选择显示「标题 + 箭头」，选择后显示「值 + 图标」
                    PillSway(
                      t: t,
                      phase: 0.0,
                      child: _OptionCapsule(
                        label: '性别',
                        value: values.gender == null ? null : values.genderLabel,
                        icon: _genderIcon(),
                        onTap: () => _showGenderSheet(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    PillSway(
                      t: t,
                      phase: math.pi,
                      child: _OptionCapsule(
                        label: '体重',
                        value: values.weightSelected
                            ? '${values.weightKg.round()}kg'
                            : null,
                        icon: Icons.monitor_weight_outlined,
                        onTap: () => _showWeightSheet(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _OptionCapsule(
                      label: '运动强度',
                      value: _activityAmountLabel(values.activityLevel),
                      icon: _activityIcon(values.activityLevel),
                      onTap: () => _showActivitySheet(context),
                    ),
                    const SizedBox(height: 12),
                    _OptionCapsule(
                      label: '温度',
                      value: values.temperature.label,
                      icon: _tempIcon(values.temperature),
                      onTap: () => _showTempSheet(context),
                    ),
                    const SizedBox(height: 10),
                    // 自定义目标文本链接
                    Center(
                      child: TextButton(
                        onPressed: () => _showCustomGoalSheet(context),
                        child: const Text('自定义目标',
                            style: TextStyle(
                                color: Color(0xFF2C3E50),
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                      ),
                    ),
                    const Spacer(),
                    // 底部主按钮（性别与体重均已选择才可点击）
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: canContinue ? widget.onContinue : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brandCyan,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              Colors.white.withValues(alpha: 0.55),
                          disabledForegroundColor:
                              _brandCyan.withValues(alpha: 0.5),
                          elevation: 0,
                          shadowColor: _brandCyan.withValues(alpha: 0.35),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28)),
                          textStyle: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                        child: Text(widget.continueLabel),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 白胶囊选项卡：未选择时显示「标题 + 箭头」，选择后整行换成
/// 「已选值 + 对应图标」，让用户一眼看到当前状态。
class _OptionCapsule extends StatelessWidget {
  const _OptionCapsule({
    required this.label,
    required this.icon,
    required this.onTap,
    this.value,
  });
  final String label;
  final String? value;
  final IconData icon;
  final VoidCallback onTap;

  /// 值/箭头颜色：跟随信息录入页的水下背景色
  static const _waterAccent = Color(0xFF4DB8D8);

  @override
  Widget build(BuildContext context) {
    final selected = value != null;
    // 胶囊占内容区 5/8 宽度并居中（比通栏窄，留出呼吸感）
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.625,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2C3E50).withValues(alpha: 0.10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(28),
              child: Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selected ? value! : label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? _waterAccent
                              : const Color(0xFF171A26),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      selected ? icon : Icons.chevron_right,
                      color: _waterAccent,
                      size: selected ? 22 : 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶部小拖把（标准 Material sheet 视觉提示）
class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFE5E5EA),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ============================ 体重滚轮选择弹层 ============================

/// 滚轮数字选择弹层（体重 kg / 身高 cm 共用；对标原版：数字轮，
/// 选中行深色大字 + 浅灰高亮带 + 上下渐隐，底部「完成」胶囊随页面水色）
class _NumberWheelSheet extends StatefulWidget {
  const _NumberWheelSheet({
    required this.title,
    required this.min,
    required this.max,
    required this.initial,
    required this.onDone,
  });

  final String title;
  final int min;
  final int max;
  final double initial;
  final void Function(double value) onDone;

  @override
  State<_NumberWheelSheet> createState() => _NumberWheelSheetState();
}

class _NumberWheelSheetState extends State<_NumberWheelSheet> {
  static const _sheetBg = Color(0xFFF7F6FB);
  static const _accentCyan = Color(0xFF4DB8D8); // 与信息录入页水色一致
  static const _inkDark = Color(0xFF171A26);
  static const _inkGray = Color(0xFF3A3F52);
  static const double _itemExtent = 56;

  late final int _kMin = widget.min, _kMax = widget.max;

  late int _numSel; // 数字轮当前下标
  late double _value;
  late final FixedExtentScrollController _numCtrl;

  @override
  void initState() {
    super.initState();
    _value = widget.initial.clamp(_kMin.toDouble(), _kMax.toDouble());
    _numSel = _value.round() - _kMin;
    _numCtrl = FixedExtentScrollController(initialItem: _numSel);
  }

  @override
  void dispose() {
    _numCtrl.dispose();
    super.dispose();
  }

  void _onNumChanged(int i) {
    if (i == _numSel) return;
    HapticFeedback.selectionClick();
    setState(() {
      _numSel = i;
      _value = (_kMin + i).toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          // 顶部拖把（浅底上用稍深的灰）
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E8),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.title,
            style: const TextStyle(
                color: _inkDark, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          // 滚轮区：高亮带垫底 + 数字轮 + 上下渐隐遮罩
          SizedBox(
            height: _itemExtent * 5,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 选中行浅灰高亮带
                Positioned(
                  left: 36,
                  right: 36,
                  child: Container(
                    height: 66,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBEBF0),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                _buildWheel(
                  childCount: _kMax - _kMin + 1,
                  controller: _numCtrl,
                  selectedIndex: _numSel,
                  onSelectedItemChanged: _onNumChanged,
                  textOf: (i) => '${_kMin + i}',
                ),
                // 上下渐隐：用弹层底色渐变盖住滚出高亮带的数字
                _fadeEdge(top: true),
                _fadeEdge(top: false),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // 「完成」胶囊（背景色跟随信息录入页的水色）
          ElevatedButton(
            onPressed: () {
              widget.onDone(_value);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentCyan,
              foregroundColor: Colors.white,
              minimumSize: const Size(180, 54),
              elevation: 0,
              shape: const StadiumBorder(),
              textStyle:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            child: const Text('完成'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 顶部/底部同色渐隐遮罩（不拦截滚动手势）
  Widget _fadeEdge({required bool top}) {
    return Positioned(
      left: 0,
      right: 0,
      top: top ? 0 : null,
      bottom: top ? null : 0,
      child: IgnorePointer(
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [_sheetBg, _sheetBg.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }

  /// 滚轮：选中行深色大字，按与选中位的距离递减透明度
  Widget _buildWheel({
    required int childCount,
    required FixedExtentScrollController controller,
    required int selectedIndex,
    required ValueChanged<int> onSelectedItemChanged,
    required String Function(int) textOf,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: _itemExtent,
      diameterRatio: 2.2,
      perspective: 0.001, // 合法下限：柱面曲率接近零，保持竖列齐直（对标原版）
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onSelectedItemChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: childCount,
        builder: (ctx, i) {
          final dist = (i - selectedIndex).abs();
          final isSel = dist == 0;
          final opacity =
              isSel ? 1.0 : dist == 1 ? 0.42 : dist == 2 ? 0.18 : 0.06;
          return Center(
            child: Opacity(
              opacity: opacity,
              child: Text(
                textOf(i),
                style: TextStyle(
                  fontSize: isSel ? 28 : 21,
                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                  color: isSel ? _inkDark : _inkGray,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================ 弹层通用组件 ============================

/// 弹层右上角关闭圆钮
class _SheetCloseButton extends StatelessWidget {
  const _SheetCloseButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE9E9EE),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () => Navigator.of(context).maybePop(),
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 38,
          height: 38,
          child: Icon(Icons.close, size: 20, color: Color(0xFF8E8E93)),
        ),
      ),
    );
  }
}

/// 居中标题 + 右上角关闭按钮
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 52),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF171A26),
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Align(alignment: Alignment.centerRight, child: _SheetCloseButton()),
      ],
    );
  }
}

/// 选项行：浅灰圆角卡片 + 右侧图标（选中时高亮为勾选态）
class _SheetOptionTile extends StatelessWidget {
  const _SheetOptionTile({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.selected = false,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? const Color(0xFFEAF7FB) : const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF171A26),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  selected ? Icons.check_circle : icon,
                  size: 24,
                  color: selected
                      ? const Color(0xFF4DB8D8)
                      : const Color(0xFF1C1C1E),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹层底部隐私说明
class _SheetPrivacyNote extends StatelessWidget {
  const _SheetPrivacyNote();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.only(top: 6, bottom: 4),
        child: Text(
          '不会收集或共享你的个人信息',
          style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
        ),
      ),
    );
  }
}

// ============================ 性别选择弹层 ============================

class _GenderSheet extends StatelessWidget {
  const _GenderSheet({required this.selectedLabel, required this.onSelected});
  final String? selectedLabel;
  final void Function(GenderOption) onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHeader(title: '性别'),
            const SizedBox(height: 16),
            // 与「常见目标」页共用的 5 个性别选项（kGenderOptions）
            ...kGenderOptions.map((o) => _SheetOptionTile(
                  title: o.label,
                  icon: o.icon,
                  selected: o.label == selectedLabel,
                  onTap: () => onSelected(o),
                )),
            const _SheetPrivacyNote(),
          ],
        ),
      ),
    );
  }
}

// ============================ 活动强度弹层 ============================

class _ActivitySheet extends StatelessWidget {
  const _ActivitySheet({required this.selected, required this.onSelected});
  final ActivityLevel selected;
  final void Function(ActivityLevel) onSelected;

  /// 3 个选项：(标题, 副标题, 对应 ActivityLevel, 图标)
  static const _options = <_ActivityOption>[
    _ActivityOption('低强度活动', '大多久坐不动的生活方式', ActivityLevel.low,
        Icons.chair_outlined),
    _ActivityOption('中等强度活动', '每周偶尔锻炼或长距离散步', ActivityLevel.medium,
        Icons.directions_run),
    _ActivityOption('高强度活动', '每周锻炼几次', ActivityLevel.high,
        Icons.fitness_center),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHeader(title: '每日活动'),
            const SizedBox(height: 16),
            ..._options.map((o) => _SheetOptionTile(
                  title: o.title,
                  subtitle: o.subtitle,
                  icon: o.icon,
                  selected: o.level == selected,
                  onTap: () => onSelected(o.level),
                )),
            const _SheetPrivacyNote(),
          ],
        ),
      ),
    );
  }
}

class _ActivityOption {
  const _ActivityOption(this.title, this.subtitle, this.level, this.icon);
  final String title;
  final String subtitle;
  final ActivityLevel level;
  final IconData icon;
}

// ============================ 天气选择弹层 ============================

class _TemperatureSheet extends StatelessWidget {
  const _TemperatureSheet({required this.selected, required this.onSelected});
  final GoalTemperature selected;
  final void Function(GoalTemperature) onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHeader(title: '天气'),
            const SizedBox(height: 16),
            ...GoalTemperature.values.map((t) => _SheetOptionTile(
                  title: t.label,
                  subtitle: t.description,
                  icon: _GoalInfoFormState._tempIcon(t),
                  selected: t == selected,
                  onTap: () => onSelected(t),
                )),
            const _SheetPrivacyNote(),
          ],
        ),
      ),
    );
  }
}

// ============================ 常见目标说明弹层 ============================

class _CommonGoalSheet extends StatelessWidget {
  const _CommonGoalSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Center(child: _SheetGrabber()),
            SizedBox(height: 12),
            Center(
              child: Text(
                '每日饮水目标',
                style: TextStyle(
                  color: Color(0xFF171A26),
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(height: 18),
            Text(
              '常见目标',
              style: TextStyle(
                color: Color(0xFF171A26),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '一般人的饮水量目标。',
              style: TextStyle(
                color: Color(0xFF3A3F52),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            SizedBox(height: 14),
            Text(
              '推荐目标',
              style: TextStyle(
                color: Color(0xFF171A26),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '根据你的性别、体重、活动和天气确定的饮水量目标。',
              style: TextStyle(
                color: Color(0xFF3A3F52),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            SizedBox(height: 20),
            Text(
              '饮水量目标是根据众所周知的建议含水量惯例来估算的。'
              '请咨询你的医生来确定特定的目标对你是否有益。',
              style: TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================ 自定义目标数字键盘弹层 ============================

class _CustomGoalSheet extends StatefulWidget {
  const _CustomGoalSheet({required this.initialMl, required this.onDone});
  final int initialMl;
  final ValueChanged<int> onDone;

  @override
  State<_CustomGoalSheet> createState() => _CustomGoalSheetState();
}

class _CustomGoalSheetState extends State<_CustomGoalSheet> {
  static const _navy = Color(0xFF2C3345);

  late String _input = widget.initialMl.toString();

  void _press(String digit) {
    if (_input.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() {
      _input = _input == '0' ? digit : '$_input$digit';
    });
  }

  void _backspace() {
    if (_input.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _input = _input.substring(0, _input.length - 1);
    });
  }

  void _submit() {
    final v = int.tryParse(_input);
    if (v == null || v <= 0) return;
    HapticFeedback.mediumImpact();
    widget.onDone(v.clamp(500, 5000));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final value = _input.isEmpty ? '0' : _input;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: const _SheetCloseButton(),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const Text(
                  'ml',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '自定义目标',
              style: TextStyle(color: _navy, fontSize: 14),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _input.isEmpty ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFD5D7DD),
                disabledForegroundColor: Colors.white,
                minimumSize: const Size(132, 52),
                elevation: 0,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700),
              ),
              child: const Text('完成'),
            ),
            const SizedBox(height: 22),
            _NumberKeypad(onDigit: _press, onBackspace: _backspace),
          ],
        ),
      ),
    );
  }
}

/// 数字键盘（1-9 + 0 + 退格），每次按键触发轻震动
class _NumberKeypad extends StatelessWidget {
  const _NumberKeypad({required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  static const _keys = <(String, String)>[
    ('1', 'ABC'), ('2', 'DEF'), ('3', 'GHI'),
    ('4', 'JKL'), ('5', 'MNO'), ('6', 'PQR'),
    ('7', 'PQRS'), ('8', 'TUV'), ('9', 'WXYZ'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < 3; row++) ...[
          Row(
            children: [
              for (var col = 0; col < 3; col++) ...[
                if (col > 0) const SizedBox(width: 8),
                Expanded(
                  child: _DigitKey(
                    digit: _keys[row * 3 + col].$1,
                    letters: _keys[row * 3 + col].$2,
                    onTap: () => onDigit(_keys[row * 3 + col].$1),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            const Expanded(child: SizedBox()),
            const SizedBox(width: 8),
            Expanded(
              child: _DigitKey(
                digit: '0',
                letters: '',
                onTap: () => onDigit('0'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: onBackspace,
                  borderRadius: BorderRadius.circular(10),
                  child: const SizedBox(
                    height: 56,
                    child: Icon(
                      Icons.backspace_outlined,
                      size: 22,
                      color: Color(0xFF2C3345),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DigitKey extends StatelessWidget {
  const _DigitKey({
    required this.digit,
    required this.letters,
    required this.onTap,
  });

  final String digit;
  final String letters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                digit,
                style: const TextStyle(
                  color: Color(0xFF171A26),
                  fontSize: 24,
                  height: 1.1,
                ),
              ),
              if (letters.isNotEmpty)
                Text(
                  letters,
                  style: const TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 9,
                    letterSpacing: 1.2,
                    height: 1.2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
