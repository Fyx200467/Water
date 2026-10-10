import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/providers.dart';
import '../../shared/models/beverage.dart';
import '../../shared/models/drink_entry.dart';
import '../../shared/models/user_profile.dart';
import '../home/providers/home_providers.dart';
import 'widgets/animal_silhouette.dart';

/// PRD §2.1 多步向导 onboarding（对标原版 WaterLlama 录屏流程）
///
/// 4 步：第一次饮水 / 智能提醒 / 目标计算 / 加载完成
/// 用 IndexedStack + _step 索引管理；顶部"跳过"可跳过当前步
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  /// 当前向导步索引：0=FirstDrink 1=Reminder 2=GoalCalc 3=Loading
  int _step = 0;

  // 目标计算入参（GoalCalc 与 Loading 共用）
  Gender? _gender; // 默认未选
  double _weight = 60; // 默认体重(kg)，未选时用此默认值参与计算
  bool _weightSelected = false; // 体重卡片是否已被用户点选过
  ActivityLevel _activity = ActivityLevel.medium; // 默认中等强度（已选中）
  int? _customGoal; // 用户自定义目标 ml

  // 品牌色规范
  static const _brandCyan = Color(0xFF4DB8D8);
  static const _textDark = Color(0xFF1C1C1E);
  static const _hintGray = Color(0xFF8E8E93);

  /// 当前预览目标（自定义优先；否则按现有数据用 UserProfile.create 计算）
  int get _previewGoal => _customGoal ??
      UserProfile.create(
        gender: _gender ?? Gender.male,
        weightKg: _weight,
        heightCm: 170,
        age: 25,
        activityLevel: _activity,
      ).dailyGoalMl;

  void _goNext() {
    if (_step < 3) setState(() => _step++);
  }

  /// 跳过当前步：行为等同于下一步（不强制本步交互）
  void _goSkip() {
    if (_step < 3) setState(() => _step++);
  }

  /// 保存第一次饮水记录（fire-and-forget，不阻塞向导推进）
  void _saveFirstDrink(double ml) {
    final entry = DrinkEntry.create(
      beverage: Beverage.presets.firstWhere(
        (b) => b.id == 'water_pure',
        orElse: () => Beverage.presets.first,
      ),
      volumeMl: ml.round(),
    );
    unawaited(
      ref.read(localStorageProvider.future).then((s) => s.insertDrinkEntry(entry)),
    );
  }

  /// 加载完成最后一步：保存 UserProfile 并跳转首页
  Future<void> _finishProfile() async {
    final profile = UserProfile.create(
      gender: _gender ?? Gender.male,
      weightKg: _weight,
      heightCm: 170,
      age: 25,
      activityLevel: _activity,
      customGoalMl: _customGoal,
    );
    await ref.read(profileProvider.notifier).save(profile);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    // 4 步全部预构建放进 IndexedStack，避免跨步切换丢失子组件状态
    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: _step,
        children: [
          _FirstDrinkScreen(
            onContinue: (ml) {
              _saveFirstDrink(ml);
              _goNext();
            },
            onSkip: _goSkip,
          ),
          _ReminderScreen(
            onContinue: _goNext,
            onSkip: _goSkip,
          ),
          _GoalCalcScreen(
            gender: _gender,
            weightSelected: _weightSelected,
            weightKg: _weight,
            activity: _activity,
            customGoal: _customGoal,
            previewGoal: _previewGoal,
            onGenderTap: () => _showGenderSheet(context),
            onWeightTap: () => _showWeightSheet(context),
            onActivityTap: () => _showActivitySheet(context),
            onTempTap: () => _showTempSheet(context),
            onCustomGoalTap: () => _showCustomGoalSheet(context),
            onContinue: _goNext,
            onSkip: _goSkip,
          ),
          _LoadingScreen(
            visible: _step == 3,
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
        selected: _gender,
        onSelected: (g) {
          setState(() => _gender = g);
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

  void _showWeightSheet(BuildContext context) {
    double temp = _weight;
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
              const Text('体重',
                  style: TextStyle(
                      color: _textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: temp,
                      min: 30,
                      max: 150,
                      divisions: 120,
                      label: '${temp.round()} kg',
                      onChanged: (v) => setSheet(() => temp = v),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text('${temp.round()} kg',
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: _textDark, fontSize: 16)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _weight = temp;
                          _weightSelected = true;
                        });
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

  void _showTempSheet(BuildContext context) {
    // 温度卡片仅展示选择 UI，不影响目标计算（UserProfile 不含温度参数）
    String? selected;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
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
              ...['热', '温', '凉'].map((t) => InkWell(
                    onTap: () => setSheet(() => selected = t),
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
                          Text(t,
                              style: const TextStyle(
                                  color: _textDark, fontSize: 16)),
                          const Spacer(),
                          Icon(
                            selected == t
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: selected == t ? _brandCyan : _hintGray,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  )),
              const SizedBox(height: 16),
              const Text('不会收集或共享你的个人信息',
                  style: TextStyle(color: _hintGray, fontSize: 12)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
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

// ============================ 第 1 步：第一次饮水 ============================

class _FirstDrinkScreen extends StatefulWidget {
  const _FirstDrinkScreen({required this.onContinue, required this.onSkip});
  final void Function(double ml) onContinue;
  final VoidCallback onSkip;

  @override
  State<_FirstDrinkScreen> createState() => _FirstDrinkScreenState();
}

class _FirstDrinkScreenState extends State<_FirstDrinkScreen>
    with SingleTickerProviderStateMixin {
  /// 液体高度比例（0.05-0.95），初始 35%
  double _waterLevel = 0.35;

  // 杯子尺寸与容量
  static const double _cupWidth = 160;
  static const double _cupHeight = 220;
  static const double _cupCapacityMl = 250;

  /// 持续晃动的波浪相位驱动
  late final AnimationController _wave;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  /// 拖拽调节：向上拖 dy 为负 → 水量增加；向下拖 → 水量减少
  void _onVerticalDragUpdate(DragUpdateDetails d) {
    setState(() {
      _waterLevel = (_waterLevel - d.delta.dy / _cupHeight).clamp(0.05, 0.95);
    });
  }

  int get _currentMl => (_waterLevel * _cupCapacityMl).round();

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
                onPressed: widget.onSkip,
                child: const Text('跳过',
                    style: TextStyle(color: Color(0xFF8E8E93))),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '添加你的第一次饮水',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF1C1C1E),
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            // 杯子区域（可拖拽）
            Expanded(
              child: Center(
                child: GestureDetector(
                  onVerticalDragStart: (_) {},
                  onVerticalDragUpdate: _onVerticalDragUpdate,
                  onVerticalDragEnd: (_) {},
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: _cupWidth + 60,
                    height: _cupHeight + 60,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 上箭头提示可向上拖
                        Positioned(
                          top: 0,
                          child: const Text(
                            '⌃',
                            style: TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        // 下箭头提示可向下拖
                        Positioned(
                          bottom: 0,
                          child: const Text(
                            '⌄',
                            style: TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        // 杯子 + 液体绘制
                        AnimatedBuilder(
                          animation: _wave,
                          builder: (ctx, _) => CustomPaint(
                            size: const Size(_cupWidth, _cupHeight),
                            painter: _CupPainter(
                              waterLevel: _waterLevel,
                              phase: _wave.value * math.pi * 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 实时水量显示
            Text(
              '$_currentMl ml',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF1C1C1E),
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '上下拖动杯子调整水量',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
            ),
            const SizedBox(height: 24),
            // 底部"+ 水"胶囊按钮
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => widget.onContinue(_currentMl.toDouble()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4DB8D8),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28)),
                  textStyle: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600),
                ),
                child: const Text('+ 水'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// 杯子 + 液体 CustomPainter
/// - 杯子：圆角矩形容器（深灰描边 + 玻璃高光）
/// - 液体：青色填充，顶部正弦波随 phase 晃动；裁剪到杯子形状内
class _CupPainter extends CustomPainter {
  _CupPainter({required this.waterLevel, required this.phase});
  final double waterLevel;
  final double phase;

  static const Color _liquidColor = Color(0xFF4DB8D8);
  static const Color _cupStroke = Color(0xFF1C1C1E);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 杯子轮廓（圆角矩形）
    final cupRect = Rect.fromLTWH(0, 0, w, h);
    final cupRRect =
        RRect.fromRectAndRadius(cupRect, const Radius.circular(24));

    // 1. 玻璃高光底
    final glassPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(cupRRect, glassPaint);

    // 2. 液体（裁剪到杯子内）
    final liquidHeight = h * waterLevel;
    final surfaceY = h - liquidHeight;
    const samples = 30;
    // 液体路径：左下 → 左上水面 → 沿正弦波到右上水面 → 右下 → 闭合
    final path = Path()
      ..moveTo(0, h)
      ..lineTo(0, surfaceY);
    for (var i = 1; i <= samples; i++) {
      final t = i / samples;
      final x = w * t;
      // 波浪：2.5 周期，振幅 4px
      final wave = math.sin(t * math.pi * 2.5 + phase) * 4;
      path.lineTo(x, surfaceY + wave);
    }
    path
      ..lineTo(w, h)
      ..close();

    canvas.save();
    canvas.clipRRect(cupRRect);
    canvas.drawPath(path, Paint()..color = _liquidColor);
    // 液体顶部高光线（增强水面感）
    final surfacePath = Path();
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final x = w * t;
      final wave = math.sin(t * math.pi * 2.5 + phase) * 4;
      if (i == 0) {
        surfacePath.moveTo(x, surfaceY + wave);
      } else {
        surfacePath.lineTo(x, surfaceY + wave);
      }
    }
    canvas.drawPath(
      surfacePath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();

    // 3. 杯子描边
    final strokePaint = Paint()
      ..color = _cupStroke.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRRect(cupRRect, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _CupPainter old) =>
      old.waterLevel != waterLevel || old.phase != phase;
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

// ============================ 第 3 步：目标计算 ============================

class _GoalCalcScreen extends StatelessWidget {
  const _GoalCalcScreen({
    required this.gender,
    required this.weightSelected,
    required this.weightKg,
    required this.activity,
    required this.customGoal,
    required this.previewGoal,
    required this.onGenderTap,
    required this.onWeightTap,
    required this.onActivityTap,
    required this.onTempTap,
    required this.onCustomGoalTap,
    required this.onContinue,
    required this.onSkip,
  });

  final Gender? gender;
  final bool weightSelected;
  final double weightKg;
  final ActivityLevel activity;
  final int? customGoal;
  final int previewGoal;
  final VoidCallback onGenderTap;
  final VoidCallback onWeightTap;
  final VoidCallback onActivityTap;
  final VoidCallback onTempTap;
  final VoidCallback onCustomGoalTap;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 青色渐变背景 + 半透明六边形装饰（铺满全屏）
        Positioned.fill(child: CustomPaint(painter: _HexagonBgPainter())),
        // 内容层
        SafeArea(
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
                        style: TextStyle(color: Colors.white70)),
                  ),
                ),
                const Spacer(),
                // 大字目标
                Text(
                  '$previewGoal ml',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 60,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text('常见目标',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                    SizedBox(width: 4),
                    Icon(Icons.info_outline, color: Colors.white70, size: 16),
                  ],
                ),
                const SizedBox(height: 32),
                const Text(
                  '计算你的目标',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                // 4 张可点击卡片（纵排）
                _GoalCard(
                  label: '性别',
                  value: gender == null ? '' : gender!.label,
                  selected: gender != null,
                  onTap: onGenderTap,
                ),
                _GoalCard(
                  label: '体重',
                  value: weightSelected ? '${weightKg.round()} kg' : '',
                  selected: weightSelected,
                  onTap: onWeightTap,
                ),
                _GoalCard(
                  label: activity.label,
                  value: activity.description,
                  selected: true,
                  onTap: onActivityTap,
                ),
                _GoalCard(
                  label: '温度',
                  value: '',
                  selected: false,
                  onTap: onTempTap,
                ),
                const SizedBox(height: 12),
                // 自定义目标文本链接
                Center(
                  child: TextButton(
                    onPressed: onCustomGoalTap,
                    child: const Text('自定义目标',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                ),
                const Spacer(),
                // 底部"继续"按钮（白底青字）
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: onContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF4DB8D8),
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
          ),
        ),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: selected
                  ? Border.all(color: const Color(0xFF4DB8D8), width: 2)
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value.isEmpty ? label : '$label · $value',
                    style: const TextStyle(
                      color: Color(0xFF1C1C1E),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF8E8E93)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 青色渐变背景 + 半透明六边形散布
class _HexagonBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 渐变背景
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF4DB8D8), Color(0xFF3A9BC9)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 半透明六边形散布（固定种子保证一致布局）
    final hexPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    final rng = math.Random(7);
    for (var i = 0; i < 14; i++) {
      final cx = rng.nextDouble() * size.width;
      final cy = rng.nextDouble() * size.height;
      final r = 18 + rng.nextDouble() * 28;
      canvas.drawPath(_hexagonPath(cx, cy, r), hexPaint);
    }
  }

  Path _hexagonPath(double cx, double cy, double r) {
    final p = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant _HexagonBgPainter old) => false;
}

// ============================ 第 4 步：加载完成 ============================

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
  const _GenderSheet({required this.selected, required this.onSelected});
  final Gender? selected;
  final void Function(Gender) onSelected;

  /// 5 个选项：(标签, 对应 Gender, 图标)
  /// 备注：原版 WaterLlama 将怀孕/母乳喂养归为女性变体，这里仅作展示标签，
  /// 实际保存时映射到 female/other，计算目标按性别修正系数处理。
  static const _options = <_GenderOption>[
    _GenderOption('男性', Gender.male, Icons.male),
    _GenderOption('女性', Gender.female, Icons.female),
    _GenderOption('怀孕', Gender.female, Icons.pregnant_woman),
    _GenderOption('母乳喂养', Gender.female, Icons.child_care),
    _GenderOption('不愿透露', Gender.other, Icons.no_accounts),
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
            const Text('性别',
                style: TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ..._options.map((o) => InkWell(
                  onTap: () => onSelected(o.gender),
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

class _GenderOption {
  const _GenderOption(this.label, this.gender, this.icon);
  final String label;
  final Gender gender;
  final IconData icon;
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
