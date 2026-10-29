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
  static const _textDark = Color(0xFF1C1C1E);
  static const _hintGray = Color(0xFF8E8E93);

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

  /// 身高录入：与体重同款数字滚轮（cm）
  void _showHeightSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF7F6FB),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _NumberWheelSheet(
        title: '身高',
        min: 120,
        max: 220,
        initial: widget.values.heightCm,
        onDone: (cm) => _update(widget.values.copyWith(
          heightCm: cm,
          clearCustomGoal: true,
        )),
      ),
    );
  }

  void _showTempSheet(BuildContext context) {
    // 温度选择影响目标计算（寒冷 -150 / 温和 0 / 炎热 +300）
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetGrabber(),
              const Text('温度',
                  style: TextStyle(
                      color: _textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ...GoalTemperature.values.map((t) => InkWell(
                    onTap: () {
                      _update(widget.values.copyWith(
                        temperature: t,
                        clearCustomGoal: true,
                      ));
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                              color: Color(0xFFE5E5EA), width: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.label,
                                  style: const TextStyle(
                                      color: _textDark,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 2),
                              Text(t.description,
                                  style: const TextStyle(
                                      color: _hintGray, fontSize: 13)),
                            ],
                          ),
                          const Spacer(),
                          Icon(
                            t == widget.values.temperature
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: t == widget.values.temperature
                                ? _brandCyan
                                : _hintGray,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  )),
              const SizedBox(height: 16),
              const Text('不会收集或共享你的个人信息',
                  style: TextStyle(color: _hintGray, fontSize: 12)),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showCustomGoalSheet(BuildContext context) {
    final values = widget.values;
    int temp = values.customGoalMl ?? values.previewGoal;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetGrabber(),
              const Text('自定义目标',
                  style: TextStyle(
                      color: _textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: temp.toDouble(),
                      min: 1000,
                      max: 5000,
                      divisions: 80,
                      label: UnitFormat.volume(temp),
                      onChanged: (v) => setSheet(() => temp = v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text(UnitFormat.volume(temp),
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                            color: _textDark,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      _update(widget.values.copyWith(clearCustomGoal: true));
                      Navigator.pop(ctx);
                    },
                    child: const Text('使用推荐值'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _update(widget.values.copyWith(customGoalMl: temp));
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brandCyan,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                      child: const Text('确定'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('常见目标',
                            style:
                                TextStyle(color: _brandCyan, fontSize: 14)),
                        SizedBox(width: 4),
                        Icon(Icons.info_outline, color: _brandCyan, size: 16),
                      ],
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
                    // 5 张白胶囊选项卡（性别/体重/身高带左右轻微颤动）
                    PillSway(
                      t: t,
                      phase: 0.0,
                      child: _OptionCapsule(
                        label: '性别',
                        value: values.gender == null ? null : values.genderLabel,
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
                        onTap: () => _showWeightSheet(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    PillSway(
                      t: t,
                      phase: math.pi / 2,
                      child: _OptionCapsule(
                        label: '身高',
                        value: '${values.heightCm.round()}cm',
                        onTap: () => _showHeightSheet(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _OptionCapsule(
                      label: '运动强度',
                      value: _activityAmountLabel(values.activityLevel),
                      onTap: () => _showActivitySheet(context),
                    ),
                    const SizedBox(height: 12),
                    _OptionCapsule(
                      label: '温度',
                      value: values.temperature.label,
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

/// 白胶囊选项卡（对标原版：白色全圆角行卡 + 左深色粗体标签 +
/// 右侧水色值与箭头贴右对齐；value 为 null 时只显示箭头）
class _OptionCapsule extends StatelessWidget {
  const _OptionCapsule({
    required this.label,
    required this.onTap,
    this.value,
  });
  final String label;
  final String? value;
  final VoidCallback onTap;

  /// 值/箭头颜色：跟随信息录入页的水下背景色
  static const _waterAccent = Color(0xFF4DB8D8);

  @override
  Widget build(BuildContext context) {
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
                    Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFF171A26),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (value != null)
                      Flexible(
                        child: Text(
                          value!,
                          maxLines: 1,
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _waterAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right,
                        color: _waterAccent, size: 20),
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

// ============================ 性别选择弹层 ============================

class _GenderSheet extends StatelessWidget {
  const _GenderSheet({required this.selectedLabel, required this.onSelected});
  final String? selectedLabel;
  final void Function(GenderOption) onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetGrabber(),
            const Text('性别',
                style: TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            // 与「常见目标」页共用的 5 个性别选项（kGenderOptions）
            ...kGenderOptions.map((o) => InkWell(
                  onTap: () => onSelected(o),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom:
                            BorderSide(color: Color(0xFFE5E5EA), width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(o.label,
                            style: const TextStyle(
                                color: Color(0xFF1C1C1E), fontSize: 16)),
                        const Spacer(),
                        Icon(o.icon, color: const Color(0xFF8E8E93)),
                        const SizedBox(width: 12),
                        Icon(
                          o.label == selectedLabel
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: o.label == selectedLabel
                              ? const Color(0xFF4DB8D8)
                              : const Color(0xFF8E8E93),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                )),
            const SizedBox(height: 16),
            const Text('不会收集或共享你的个人信息',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
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
    _ActivityOption('低强度活动', '久坐不动', ActivityLevel.low, Icons.chair),
    _ActivityOption('中等强度活动', '偶尔锻炼', ActivityLevel.medium,
        Icons.directions_run),
    _ActivityOption('高强度活动', '每周几次', ActivityLevel.high,
        Icons.fitness_center),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetGrabber(),
            const Text('日常活动量',
                style: TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ..._options.map((o) => InkWell(
                  onTap: () => onSelected(o.level),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom:
                            BorderSide(color: Color(0xFFE5E5EA), width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.title,
                                style: const TextStyle(
                                    color: Color(0xFF1C1C1E),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text(o.subtitle,
                                style: const TextStyle(
                                    color: Color(0xFF8E8E93), fontSize: 13)),
                          ],
                        ),
                        const Spacer(),
                        Icon(o.icon, color: const Color(0xFF8E8E93)),
                      ],
                    ),
                  ),
                )),
            const SizedBox(height: 16),
            const Text('不会收集或共享你的个人信息',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
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
