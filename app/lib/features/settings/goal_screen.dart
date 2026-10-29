import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/providers.dart';
import '../../shared/models/user_profile.dart';
import '../../shared/widgets/goal_info_form.dart';
import '../../shared/widgets/underwater_scene.dart';
import '../home/providers/home_providers.dart';

/// 设置页「我的饮水目标」。
///
/// 直接复用 onboarding 第 1 步的信息录入页（[GoalInfoForm]），保持两处
/// 视觉与目标计算口径完全一致；这里只负责初始值回填与改动落库。
class GoalScreen extends ConsumerStatefulWidget {
  const GoalScreen({super.key});

  @override
  ConsumerState<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends ConsumerState<GoalScreen> {
  /// 温度持久化 key（与 onboarding 共用）
  static const _kTempKey = 'goal_temperature';

  /// 性别展示标签持久化 key（与 onboarding 共用）
  static const _kGenderLabelKey = 'gender_display_label';

  late GoalInfoValues _values;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider);
    _values = GoalInfoValues(
      gender: profile?.gender,
      genderLabel: profile == null
          ? null
          : defaultGenderLabel(profile.gender),
      weightKg: profile?.weightKg ?? 60,
      heightCm: profile?.heightCm ?? 170,
      activityLevel: profile?.activityLevel ?? ActivityLevel.medium,
      temperature: GoalTemperature.mild,
      customGoalMl: profile?.dailyGoalMl,
      weightSelected: profile != null,
      age: profile?.age ?? 25,
    );
    _loadPrefs();
  }

  /// 回填持久化的温度偏好与性别展示标签
  Future<void> _loadPrefs() async {
    final storage = await ref.read(localStorageProvider.future);
    final tempName = storage.prefs.getString(_kTempKey);
    final label = storage.prefs.getString(_kGenderLabelKey);
    if (!mounted) return;
    setState(() {
      _values = _values.copyWith(
        temperature: GoalTemperature.values.firstWhere(
          (t) => t.name == tempName,
          orElse: () => _values.temperature,
        ),
        genderLabel: label,
      );
    });
  }

  Future<void> _onChanged(GoalInfoValues next) async {
    setState(() => _values = next);
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(_kTempKey, next.temperature.name);
    final label = next.genderLabel;
    if (label != null) {
      await storage.prefs.setString(_kGenderLabelKey, label);
    }
    if (!mounted) return;
    final profile = ref.read(profileProvider);
    final updated = profile == null
        ? UserProfile.create(
            gender: next.gender ?? Gender.male,
            weightKg: next.weightKg,
            heightCm: next.heightCm,
            age: next.age,
            activityLevel: next.activityLevel,
            customGoalMl: next.previewGoal,
          )
        : profile.copyWith(
            gender: next.gender ?? profile.gender,
            weightKg: next.weightKg,
            heightCm: next.heightCm,
            activityLevel: next.activityLevel,
            dailyGoalMl: next.previewGoal,
          );
    await ref.read(profileProvider.notifier).save(updated);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            GoalInfoForm(
              values: _values,
              onChanged: _onChanged,
              continueLabel: '完成',
              onContinue: () => Navigator.of(context).pop(),
            ),
            // 左上角返回（白底场景用浅色圆钮 + 深色箭头）
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 8),
                child: Material(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: const CircleBorder(),
                  elevation: 1.5,
                  shadowColor: const Color(0xFF2C3E50).withValues(alpha: 0.18),
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    customBorder: const CircleBorder(),
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        size: 17,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
