import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/providers.dart';
import '../../shared/models/user_profile.dart';
import '../home/providers/home_providers.dart';
import '../settings/goal_screen.dart';
import 'widgets/animal_silhouette.dart';

/// PRD §2.1 多步向导 onboarding
///
/// 3 步：目标计算（用户初始化信息，不可跳过） / 智能提醒（可跳过） / 加载完成
/// 用 IndexedStack + _step 索引管理；「第一次饮水」步已按需求剔除
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  /// 当前向导步索引：0=GoalCalc 1=Reminder 2=Loading
  int _step = 0;

  // 目标计算入参（GoalCalc 与 Loading 共用）
  Gender? _gender; // 默认未选
  String? _genderLabel; // 性别展示标签（怀孕/母乳喂养等，与枚举分离）

  /// 当前性别展示值（未选时返回 null，选项卡仅显示「性别」）
  String? get _genderDisplayLabel => _gender == null ? null : _genderLabel;

  /// 体重展示值（固定 kg）
  String get _weightDisplay => '${_weight.round()}kg';
  double _weight = 60; // 默认体重(kg)，未选时用此默认值参与计算
  bool _weightSelected = false; // 体重卡片是否已被用户点选过
  ActivityLevel _activity = ActivityLevel.medium; // 默认中等强度（已选中）
  GoalTemperature _temp = GoalTemperature.mild; // 默认温和
  int? _customGoal; // 用户自定义目标 ml

  // 品牌色规范
  static const _brandCyan = Color(0xFF4DB8D8);
  static const _textDark = Color(0xFF1C1C1E);
  static const _hintGray = Color(0xFF8E8E93);

  /// 当前预览目标（自定义优先；否则推荐算法 + 温度修正，夹紧 [1500, 4500]）
  int get _previewGoal {
    if (_customGoal != null) return _customGoal!.clamp(500, 5000);
    final base = UserProfile.create(
      gender: _gender ?? Gender.male,
      weightKg: _weight,
      heightCm: 170,
      age: 25,
      activityLevel: _activity,
    ).dailyGoalMl;
    return (base + _temp.deltaMl).clamp(1500, 4500);
  }

  void _goNext() {
    if (_step < 2) setState(() => _step++);
  }

  /// 跳过当前步：行为等同于下一步（仅智能提醒页提供入口）
  void _goSkip() {
    if (_step < 2) setState(() => _step++);
  }

  /// 加载完成最后一步：保存 UserProfile（含温度修正与温度偏好）并跳转首页
  Future<void> _finishProfile() async {
    final profile = UserProfile.create(
      gender: _gender ?? Gender.male,
      weightKg: _weight,
      heightCm: 170,
      age: 25,
      activityLevel: _activity,
      customGoalMl: _previewGoal,
    );
    final storage = await ref.read(localStorageProvider.future);
    // 温度与性别展示标签持久化，与「常见目标」页共用同一 key
    await storage.prefs.setString('goal_temperature', _temp.name);
    if (_genderLabel != null) {
      await storage.prefs.setString('gender_display_label', _genderLabel!);
    }
    await ref.read(profileProvider.notifier).save(profile);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    // 3 步全部预构建放进 IndexedStack，避免跨步切换丢失子组件状态
    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: _step,
        children: [
          _GoalCalcScreen(
            genderLabel: _genderDisplayLabel,
            genderSelected: _gender != null,
            weightSelected: _weightSelected,
            weightDisplay: _weightSelected ? _weightDisplay : null,
            activity: _activity,
            temp: _temp,
            customGoal: _customGoal,
            previewGoal: _previewGoal,
            onGenderTap: () => _showGenderSheet(context),
            onWeightTap: () => _showWeightSheet(context),
            onActivityTap: () => _showActivitySheet(context),
            onTempTap: () => _showTempSheet(context),
            onCustomGoalTap: () => _showCustomGoalSheet(context),
            onContinue: _goNext,
          ),
          _ReminderScreen(
            onContinue: _goNext,
            onSkip: _goSkip,
          ),
          _LoadingScreen(
            visible: _step == 2,
            onDone: _finishProfile,
          ),
        ],
      ),
    );
  }

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
        selectedLabel: _genderLabel,
        onSelected: (o) {
          setState(() {
            _gender = o.gender;
            _genderLabel = o.label;
          });
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
        selected: _activity,
        onSelected: (a) {
          setState(() => _activity = a);
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
      builder: (_) => _WeightWheelSheet(
        initialKg: _weight,
        onDone: (kg) {
          setState(() {
            _weight = kg;
            _weightSelected = true;
          });
        },
      ),
    );
  }

  void _showTempSheet(BuildContext context) {
    // 温度选择影响目标计算（寒冷 -150 / 温和 0 / 炎热 +300），与「常见目标」页一致
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
              _SheetGrabber(),
              const Text('温度',
                  style: TextStyle(
                      color: _textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ...GoalTemperature.values.map((t) => InkWell(
                    onTap: () {
                      setState(() => _temp = t);
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
                            t == _temp
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: t == _temp ? _brandCyan : _hintGray,
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
    int temp = _customGoal ?? _previewGoal;
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
              _SheetGrabber(),
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
                      label: '$temp ml',
                      onChanged: (v) => setSheet(() => temp = v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text('$temp ml',
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
                      setState(() => _customGoal = null);
                      Navigator.pop(ctx);
                    },
                    child: const Text('使用推荐值'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() => _customGoal = temp);
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
}

/// 顶部小拖把（标准 Material sheet 视觉提示）
class _SheetGrabber extends StatelessWidget {
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

/// 滚轮体重选择弹层（对标原版：kg 数字轮，选中行深色大字 +
/// 浅灰高亮带 + 上下渐隐，底部「完成」胶囊随页面水色）
class _WeightWheelSheet extends StatefulWidget {
  const _WeightWheelSheet({required this.initialKg, required this.onDone});

  final double initialKg;
  final void Function(double kg) onDone;

  @override
  State<_WeightWheelSheet> createState() => _WeightWheelSheetState();
}

class _WeightWheelSheetState extends State<_WeightWheelSheet> {
  static const _sheetBg = Color(0xFFF7F6FB);
  static const _accentCyan = Color(0xFF4DB8D8); // 与信息录入页水色一致
  static const _inkDark = Color(0xFF171A26);
  static const _inkGray = Color(0xFF3A3F52);
  static const double _itemExtent = 56;

  static const int _kMin = 30, _kMax = 200; // kg 范围

  late int _numSel; // 数字轮当前下标
  late double _kg;
  late final FixedExtentScrollController _numCtrl;

  @override
  void initState() {
    super.initState();
    _kg = widget.initialKg.clamp(_kMin.toDouble(), _kMax.toDouble());
    _numSel = _kg.round() - _kMin;
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
      _kg = (_kMin + i).toDouble();
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
          const Text(
            '体重',
            style: TextStyle(
                color: _inkDark, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          // 滚轮区：高亮带垫底 + kg 数字轮 + 上下渐隐遮罩
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
              widget.onDone(_kg);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentCyan,
              foregroundColor: Colors.white,
              minimumSize: const Size(180, 54),
              elevation: 0,
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700),
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

// ============================ 第 1 步：目标计算（用户初始化信息，水下动画场景） ============================

/// 复用「常见目标」页的水下动画背景（冰晶缓旋浮动 + 气泡生灭），
/// 布局对标原版初始化页：白胶囊选项卡 + 底部白色「继续」按钮
class _GoalCalcScreen extends StatefulWidget {
  const _GoalCalcScreen({
    required this.genderLabel,
    required this.genderSelected,
    required this.weightSelected,
    required this.weightDisplay,
    required this.activity,
    required this.temp,
    required this.customGoal,
    required this.previewGoal,
    required this.onGenderTap,
    required this.onWeightTap,
    required this.onActivityTap,
    required this.onTempTap,
    required this.onCustomGoalTap,
    required this.onContinue,
  });

  /// 性别展示标签（怀孕/母乳喂养等），null = 未选择
  final String? genderLabel;

  /// 性别是否已被用户选择（展示标签可能为 null，不能作为判断依据）
  final bool genderSelected;

  final bool weightSelected;

  /// 体重展示值（如 "62kg"），null = 未选择（选项卡只显示箭头）
  final String? weightDisplay;
  final ActivityLevel activity;
  final GoalTemperature temp;
  final int? customGoal;
  final int previewGoal;
  final VoidCallback onGenderTap;
  final VoidCallback onWeightTap;
  final VoidCallback onActivityTap;
  final VoidCallback onTempTap;
  final VoidCallback onCustomGoalTap;
  final VoidCallback onContinue;

  @override
  State<_GoalCalcScreen> createState() => _GoalCalcScreenState();
}

class _GoalCalcScreenState extends State<_GoalCalcScreen>
    with SingleTickerProviderStateMixin {
  /// 驱动性别/体重胶囊颤动的循环控制器（与水下背景同周期 12s）
  late final AnimationController _anim;

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

  @override
  Widget build(BuildContext context) {
    // 性别与体重均已选择才允许继续下一步
    final canContinue = widget.genderSelected && widget.weightSelected;
    return Stack(
      children: [
        // 底层：水下动画背景（渐变水体 + 冰晶 + 气泡）
        const Positioned.fill(child: UnderwaterBackground()),
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
                      '${widget.previewGoal} ml',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 56,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text('常见目标',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 14)),
                        SizedBox(width: 4),
                        Icon(Icons.info_outline,
                            color: Colors.white70, size: 16),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '计算你的目标',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    // 4 张白胶囊选项卡（左深色标签 + 右蓝色值与箭头；
                    // 性别/体重带左右轻微颤动）
                    PillSway(
                      t: t,
                      phase: 0.0,
                      child: _OptionCapsule(
                        label: '性别',
                        value: widget.genderLabel,
                        onTap: widget.onGenderTap,
                      ),
                    ),
                    const SizedBox(height: 12),
                    PillSway(
                      t: t,
                      phase: math.pi,
                      child: _OptionCapsule(
                        label: '体重',
                        value: widget.weightDisplay,
                        onTap: widget.onWeightTap,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _OptionCapsule(
                      label: '运动强度',
                      value: _activityAmountLabel(widget.activity),
                      onTap: widget.onActivityTap,
                    ),
                    const SizedBox(height: 12),
                    _OptionCapsule(
                      label: '温度',
                      value: widget.temp.label,
                      onTap: widget.onTempTap,
                    ),
                    const SizedBox(height: 10),
                    // 自定义目标文本链接
                    Center(
                      child: TextButton(
                        onPressed: widget.onCustomGoalTap,
                        child: const Text('自定义目标',
                            style:
                                TextStyle(color: Colors.white, fontSize: 14)),
                      ),
                    ),
                    const Spacer(),
                    // 底部"继续"按钮（白底青字；性别与体重均已选择才可点击，
                    // 未选完时置灰不可点）
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed:
                            canContinue ? widget.onContinue : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canContinue
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.5),
                          foregroundColor: canContinue
                              ? const Color(0xFF4DB8D8)
                              : const Color(0xFF4DB8D8)
                                  .withValues(alpha: 0.4),
                          disabledBackgroundColor:
                              Colors.white.withValues(alpha: 0.5),
                          disabledForegroundColor: const Color(0xFF4DB8D8)
                              .withValues(alpha: 0.4),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28)),
                          textStyle: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                        child: const Text('继续'),
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF171A26),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (value != null) ...[
                Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _waterAccent,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              const Icon(Icons.chevron_right,
                  color: _waterAccent, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================ 第 2 步：智能提醒 ============================

class _ReminderScreen extends StatelessWidget {
  const _ReminderScreen({required this.onContinue, required this.onSkip});
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onSkip,
                child: const Text('跳过',
                    style: TextStyle(color: Color(0xFF8E8E93))),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '智能提醒',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF1C1C1E),
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '当你忘记喝水时的健康提醒',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            ),
            const SizedBox(height: 24),
            // 中央：羊驼 + 通知预览卡叠放
            Expanded(
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimalSilhouette(
                      animalId: 'llama',
                      fillRatio: 1.0,
                      accentColor: const Color(0xFF4DB8D8),
                      size: 240,
                    ),
                    const Positioned(
                      top: 0,
                      child: _NotificationCard(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 底部"提醒我喝水"深色胶囊按钮（点击直接下一步）
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1C1C1E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28)),
                  textStyle: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600),
                ),
                child: const Text('提醒我喝水'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// 通知预览卡片（模拟系统通知样式）
class _NotificationCard extends StatelessWidget {
  const _NotificationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF4DB8D8),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.water_drop,
                    color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              const Text(
                'WaterLlama',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
              ),
              const Spacer(),
              const Text(
                '20:30',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '还剩 1 杯。你可以做到！',
            style: TextStyle(
              color: Color(0xFF1C1C1E),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================ 第 3 步：加载完成 ============================

class _LoadingScreen extends StatefulWidget {
  const _LoadingScreen({required this.visible, required this.onDone});
  final bool visible;
  final VoidCallback onDone;

  @override
  State<_LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<_LoadingScreen>
    with SingleTickerProviderStateMixin {
  /// 旋转圆点动画驱动
  late final AnimationController _ctrl;

  /// 当前完成的步数（0=分析中 1=分析完成→个性化中 2=个性化完成→羊驼互动中）
  int _currentStep = 0;

  /// 三步文案
  static const _steps = <String>[
    '正在分析你的数据',
    '正在个性化目标',
    '正在与羊驼互动',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(); // 圆点持续旋转
  }

  @override
  void didUpdateWidget(covariant _LoadingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只在 visible 变为 true 时才开始倒计时（避免 IndexedStack 预构建即触发）
    if (widget.visible && !oldWidget.visible && !_done) {
      _startCountdown();
    }
  }

  bool _done = false;
  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _currentStep = 1);
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _currentStep = 2);
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_done) {
        _done = true;
        widget.onDone();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const Spacer(),
          // 羊驼脸 + 蓝色圆点环绕
          SizedBox(
            width: 220,
            height: 220,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (ctx, _) => CustomPaint(
                painter: _DotsPainter(progress: _ctrl.value),
                child: Center(
                  child: AnimalSilhouette(
                    animalId: 'llama',
                    fillRatio: 1.0,
                    accentColor: const Color(0xFF4DB8D8),
                    size: 110,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          // 三步进度条（横线 → 对勾）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        _StepIndicator(
                          done: i < _currentStep,
                          active: i == _currentStep,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _steps[i],
                          style: TextStyle(
                            color: i <= _currentStep
                                ? const Color(0xFF1C1C1E)
                                : const Color(0xFF8E8E93),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}

/// 单步指示器：未完成=横线 / 进行中=青色圆环 spinner / 已完成=对勾
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.done, required this.active});
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (done) {
      return Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          color: Color(0xFF4DB8D8),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 16),
      );
    }
    if (active) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4DB8D8)),
          backgroundColor: const Color(0xFFE5E5EA),
        ),
      );
    }
    // 未开始：横线
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      child: Container(
        width: 14,
        height: 2,
        color: const Color(0xFF8E8E93),
      ),
    );
  }
}

/// 旋转的蓝色圆点环绕（背景层，羊驼插画在前景）
class _DotsPainter extends CustomPainter {
  _DotsPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width / 2 - 8;
    const dotCount = 8;
    final baseAngle = progress * math.pi * 2;
    for (var i = 0; i < dotCount; i++) {
      final a = baseAngle + (i / dotCount) * math.pi * 2;
      final x = cx + radius * math.cos(a);
      final y = cy + radius * math.sin(a);
      // 透明度递减形成"尾迹"效果
      final alpha = (1.0 - i / dotCount).clamp(0.15, 1.0);
      canvas.drawCircle(
        Offset(x, y),
        4,
        Paint()..color = const Color(0xFF4DB8D8).withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => old.progress != progress;
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
            _SheetGrabber(),
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
            _SheetGrabber(),
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
