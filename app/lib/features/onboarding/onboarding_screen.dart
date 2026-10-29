import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notification/notification_service.dart';
import '../../core/storage/providers.dart';
import '../../shared/models/user_profile.dart';
import '../../shared/widgets/goal_info_form.dart';
import '../home/providers/home_providers.dart';
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

  /// 信息录入值（与设置页「我的饮水目标」共用同一份表单模型）
  GoalInfoValues _values = const GoalInfoValues();

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
      gender: _values.gender ?? Gender.male,
      weightKg: _values.weightKg,
      heightCm: _values.heightCm,
      age: 25,
      activityLevel: _values.activityLevel,
      customGoalMl: _values.previewGoal,
    );
    final storage = await ref.read(localStorageProvider.future);
    // 温度与性别展示标签持久化，与「我的饮水目标」页共用同一 key
    await storage.prefs.setString('goal_temperature', _values.temperature.name);
    final label = _values.genderLabel;
    if (label != null) {
      await storage.prefs.setString('gender_display_label', label);
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
            // 信息录入页与设置页「我的饮水目标」共用同一套 UI
            GoalInfoForm(
              values: _values,
              onChanged: (v) => setState(() => _values = v),
              continueLabel: '继续',
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
                      animalId: 'sheep',
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
                onPressed: () {
                  // 「提醒我喝水」即开启提醒：在此申请系统通知权限
                  // （iOS 必须先授权，否则排定的提醒不会弹出）
                  NotificationService.requestPermission();
                  onContinue();
                },
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
              // 应用默认图标：浅灰底板 + 青色水滴
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F7),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.water_drop,
                    color: Color(0xFF72E3F0), size: 18),
              ),
              const SizedBox(width: 8),
              const Text(
                'Drink some water',
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
                    animalId: 'sheep',
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
