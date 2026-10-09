import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/user_profile.dart';
import '../home/providers/home_providers.dart';

/// PRD §2.1 初始化表单：性别 / 体重 / 身高 / 活动量
/// PRD §2.1 自动申请通知权限（通知服务 V1 stub，M3 接入）
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  Gender _gender = Gender.male;
  double _weight = 65;
  double _height = 170;
  int _age = 25;
  ActivityLevel _activity = ActivityLevel.medium;
  int? _customGoal;
  bool _saving = false;

  int get _previewGoal => _customGoal ??
      UserProfile.create(
        gender: _gender,
        weightKg: _weight,
        heightCm: _height,
        age: _age,
        activityLevel: _activity,
      ).dailyGoalMl;

  Future<void> _finish() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final profile = UserProfile.create(
      gender: _gender,
      weightKg: _weight,
      heightCm: _height,
      age: _age,
      activityLevel: _activity,
      customGoalMl: _customGoal,
    );
    await ref.read(profileProvider.notifier).save(profile);
    // PRD §2.1 首次启动申请通知权限 — M3 实现，此处占位
    if (mounted) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('初始化你的资料')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                '我们会根据你的身体数据自动生成每日饮水量目标',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              // 性别
              Text('性别', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              SegmentedButton<Gender>(
                segments: Gender.values
                    .map((g) => ButtonSegment(value: g, label: Text(g.label)))
                    .toList(),
                selected: {_gender},
                onSelectionChanged: (s) => setState(() => _gender = s.first),
              ),
              const SizedBox(height: 24),

              // 年龄
              Text('年龄', style: theme.textTheme.titleLarge),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _age.toDouble(),
                      min: 10,
                      max: 100,
                      divisions: 90,
                      label: '$_age 岁',
                      onChanged: (v) => setState(() => _age = v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text('$_age 岁',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.end),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 体重
              Text('体重', style: theme.textTheme.titleLarge),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _weight,
                      min: 30,
                      max: 150,
                      divisions: 120,
                      label: '${_weight.round()} kg',
                      onChanged: (v) => setState(() => _weight = v),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text('${_weight.round()} kg',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.end),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 身高
              Text('身高', style: theme.textTheme.titleLarge),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _height,
                      min: 120,
                      max: 220,
                      divisions: 100,
                      label: '${_height.round()} cm',
                      onChanged: (v) => setState(() => _height = v),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text('${_height.round()} cm',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.end),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 活动量
              Text('日常活动量', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              ...ActivityLevel.values.map((a) => RadioListTile<ActivityLevel>(
                    value: a,
                    groupValue: _activity,
                    title: Text(a.label),
                    subtitle: Text(a.description),
                    onChanged: (v) => setState(() => _activity = v ?? _activity),
                  )),

              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('每日饮水目标', style: theme.textTheme.titleLarge),
                      Text(
                        '$_previewGoal ml',
                        style: theme.textTheme.displayMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.edit),
                label: Text(_customGoal == null ? '自定义目标' : '恢复推荐值'),
                onPressed: () => _showCustomGoalSheet(context),
              ),

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _finish,
                child: _saving
                    ? const SizedBox(
                        height: 24, width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('开始养成'),
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
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20, 20, 20,
              20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('自定义每日目标',
                    style: Theme.of(ctx).textTheme.titleLarge),
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
                        onChanged: (v) => setSheetState(() => temp = v.round()),
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: Text('$temp ml',
                          style: Theme.of(ctx).textTheme.titleLarge,
                          textAlign: TextAlign.end),
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
                    // Expanded 提供有界宽度：全局主题 minimumSize 依赖父级约束，
                    // Row 的无界宽度会强制按钮 minWidth=Infinity 导致布局崩溃
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() => _customGoal = temp);
                          Navigator.pop(ctx);
                        },
                        child: const Text('确定'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
