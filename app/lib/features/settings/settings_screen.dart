import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notification/notification_service.dart';
import '../../core/storage/providers.dart';
import '../../shared/models/user_profile.dart';
import '../home/providers/home_providers.dart';
import '../reminder/reminder_providers.dart';
import '../stats/providers/stats_providers.dart';

/// PRD §2.8 权益与设置：资料 / 目标 / 提醒 / 音效 / 外观 / 清除数据
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _messageCtrl;

  @override
  void initState() {
    super.initState();
    _messageCtrl = TextEditingController(
      text: ref.read(reminderProvider).message,
    );
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider);
    final reminder = ref.watch(reminderProvider);
    final sound = ref.watch(soundEnabledProvider);
    final themeMode = ref.watch(themeModeProvider);

    if (profile == null) {
      // 已被清除数据等情况触发重定向
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ---------- 个人资料 ----------
          _sectionTitle(theme, '个人资料'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    '${profile.gender.label} · ${profile.weightKg.round()}kg'
                    ' · ${profile.heightCm.round()}cm · ${profile.age}岁',
                  ),
                  subtitle: Text(profile.activityLevel.description),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editProfile(profile),
                ),
              ],
            ),
          ),

          // ---------- 每日目标 ----------
          _sectionTitle(theme, '每日饮水目标'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('目标饮水量', style: theme.textTheme.titleMedium),
                      Text(
                        '${profile.dailyGoalMl} ml',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                  Slider(
                    value: profile.dailyGoalMl.toDouble(),
                    min: 1000,
                    max: 5000,
                    divisions: 80,
                    label: '${profile.dailyGoalMl} ml',
                    onChanged: (v) => ref
                        .read(profileProvider.notifier)
                        .updateGoal(v.round()),
                  ),
                ],
              ),
            ),
          ),

          // ---------- 喝水提醒 ----------
          _sectionTitle(theme, '喝水提醒'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('每日定时提醒'),
                    subtitle: const Text('到点推送通知，小动物喊你喝水'),
                    value: reminder.enabled,
                    onChanged: _toggleReminder,
                  ),
                  if (reminder.enabled) ...[
                    const Divider(),
                    const SizedBox(height: 8),
                    Text('提醒时间', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in reminder.times)
                          InputChip(
                            label: Text(t),
                            onDeleted: () => _removeTime(t),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: const Text('添加'),
                          onPressed: _addTime,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _messageCtrl,
                      decoration: InputDecoration(
                        labelText: '提醒文案',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.check),
                          tooltip: '保存文案',
                          onPressed: _saveMessage,
                        ),
                      ),
                      onSubmitted: (_) => _saveMessage(),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('免打扰时段'),
                      subtitle: Text(
                        reminder.dndEnabled
                            ? '${reminder.dndStart ?? '22:00'} - ${reminder.dndEnd ?? '07:00'} 内不提醒'
                            : '关闭中',
                      ),
                      value: reminder.dndEnabled,
                      onChanged: (v) async {
                        var next = reminder.copyWith(dndEnabled: v);
                        // 首次开启时给默认窗口
                        if (v && (next.dndStart == null || next.dndEnd == null)) {
                          next = next.copyWith(dndStart: '22:00', dndEnd: '07:00');
                        }
                        await ref.read(reminderProvider.notifier).update(next);
                      },
                    ),
                    if (reminder.dndEnabled)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _pickDnd(isStart: true),
                              child: Text('开始 ${reminder.dndStart ?? '22:00'}'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _pickDnd(isStart: false),
                              child: Text('结束 ${reminder.dndEnd ?? '07:00'}'),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),

          // ---------- 通用 ----------
          _sectionTitle(theme, '通用'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.music_note_outlined),
                  title: const Text('喝水音效'),
                  value: sound,
                  onChanged: (v) =>
                      ref.read(soundEnabledProvider.notifier).set(v),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.palette_outlined, size: 20),
                          const SizedBox(width: 16),
                          Text('外观', style: theme.textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('跟随系统'),
                            icon: Icon(Icons.settings_suggest_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('浅色'),
                            icon: Icon(Icons.light_mode_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('深色'),
                            icon: Icon(Icons.dark_mode_outlined),
                          ),
                        ],
                        selected: {themeMode},
                        onSelectionChanged: (s) => ref
                            .read(themeModeProvider.notifier)
                            .set(s.first),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ---------- 数据 ----------
          _sectionTitle(theme, '数据'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('清除全部数据',
                  style: TextStyle(color: Colors.redAccent)),
              subtitle: const Text('删除饮水记录、档案与所有设置，不可恢复'),
              onTap: _confirmClearAll,
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              '喝水养成 v1.0.0 · V1.0 本地版',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(text, style: theme.textTheme.titleLarge),
      );

  // ---------------- 提醒相关 ----------------

  Future<void> _toggleReminder(bool v) async {
    if (v) {
      final granted = await NotificationService.requestPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未获得通知权限，请到系统设置中开启')),
        );
        return;
      }
    }
    final cur = ref.read(reminderProvider);
    await ref.read(reminderProvider.notifier).update(cur.copyWith(enabled: v));
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _parseTod(String s) {
    final p = s.split(':');
    return TimeOfDay(
      hour: int.tryParse(p.isNotEmpty ? p[0] : '') ?? 22,
      minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
    );
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked == null || !mounted) return;
    final cur = ref.read(reminderProvider);
    final t = _fmt(picked);
    if (cur.times.contains(t)) return;
    final times = [...cur.times, t]..sort();
    await ref.read(reminderProvider.notifier).update(cur.copyWith(times: times));
  }

  Future<void> _removeTime(String t) async {
    final cur = ref.read(reminderProvider);
    await ref.read(reminderProvider.notifier).update(
          cur.copyWith(times: cur.times.where((x) => x != t).toList()),
        );
  }

  Future<void> _saveMessage() async {
    final msg = _messageCtrl.text.trim();
    final cur = ref.read(reminderProvider);
    if (msg.isEmpty || msg == cur.message) return;
    await ref.read(reminderProvider.notifier).update(cur.copyWith(message: msg));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提醒文案已保存')),
      );
    }
  }

  Future<void> _pickDnd({required bool isStart}) async {
    final cur = ref.read(reminderProvider);
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTod(
        isStart ? (cur.dndStart ?? '22:00') : (cur.dndEnd ?? '07:00'),
      ),
    );
    if (picked == null) return;
    final t = _fmt(picked);
    await ref.read(reminderProvider.notifier).update(
          isStart ? cur.copyWith(dndStart: t) : cur.copyWith(dndEnd: t),
        );
  }

  // ---------------- 资料编辑 ----------------

  void _editProfile(UserProfile profile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProfileEditSheet(profile: profile),
    );
  }

  // ---------------- 清除数据 ----------------

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部数据？'),
        content: const Text('将删除所有饮水记录、个人档案、会员状态与设置，操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await NotificationService.cancelAll();
    final storage = await ref.read(localStorageProvider.future);
    await storage.clearAllData();

    // 重置内存态（保留主题偏好）
    ref.invalidate(profileProvider);
    ref.invalidate(memberProvider);
    ref.invalidate(todayEntriesProvider);
    ref.invalidate(dailyProgressProvider);
    ref.invalidate(dailyAnimalProvider);
    ref.invalidate(reminderProvider);
    ref.invalidate(soundEnabledProvider);
    ref.invalidate(last7DaysProvider);
    ref.invalidate(monthDataProvider);
    ref.invalidate(dayEntriesForProvider);
    ref.invalidate(streakProvider);

    if (mounted) context.go('/onboarding');
  }
}

/// 资料编辑底部弹层（复用 onboarding 的表单形态）
class _ProfileEditSheet extends ConsumerStatefulWidget {
  const _ProfileEditSheet({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends ConsumerState<_ProfileEditSheet> {
  late Gender _gender = widget.profile.gender;
  late double _weight = widget.profile.weightKg;
  late double _height = widget.profile.heightCm;
  late int _age = widget.profile.age;
  late ActivityLevel _activity = widget.profile.activityLevel;
  bool _saving = false;

  int get _previewGoal => UserProfile.create(
        gender: _gender,
        weightKg: _weight,
        heightCm: _height,
        age: _age,
        activityLevel: _activity,
      ).dailyGoalMl;

  Future<void> _save() async {
    setState(() => _saving = true);
    // 体重/身高/年龄变化时重算推荐目标；原目标与旧推荐一致则跟随新推荐
    final oldRecommended = UserProfile.create(
      gender: widget.profile.gender,
      weightKg: widget.profile.weightKg,
      heightCm: widget.profile.heightCm,
      age: widget.profile.age,
      activityLevel: widget.profile.activityLevel,
    ).dailyGoalMl;
    final goal = widget.profile.dailyGoalMl == oldRecommended
        ? _previewGoal
        : widget.profile.dailyGoalMl;
    await ref.read(profileProvider.notifier).save(
          widget.profile.copyWith(
            gender: _gender,
            weightKg: _weight,
            heightCm: _height,
            age: _age,
            activityLevel: _activity,
            dailyGoalMl: goal,
          ),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('编辑个人资料', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),

            SegmentedButton<Gender>(
              segments: Gender.values
                  .map((g) => ButtonSegment(value: g, label: Text(g.label)))
                  .toList(),
              selected: {_gender},
              onSelectionChanged: (s) => setState(() => _gender = s.first),
            ),
            const SizedBox(height: 16),

            _sliderRow('年龄', _age.toDouble(), 10, 100, 90,
                '$_age 岁', (v) => setState(() => _age = v.round())),
            _sliderRow('体重', _weight, 30, 150, 120,
                '${_weight.round()} kg', (v) => setState(() => _weight = v)),
            _sliderRow('身高', _height, 120, 220, 100,
                '${_height.round()} cm', (v) => setState(() => _height = v)),

            ...ActivityLevel.values.map(
              (a) => RadioListTile<ActivityLevel>(
                contentPadding: EdgeInsets.zero,
                value: a,
                groupValue: _activity,
                title: Text(a.label),
                subtitle: Text(a.description),
                onChanged: (v) => setState(() => _activity = v ?? _activity),
              ),
            ),

            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('推荐目标', style: theme.textTheme.titleMedium),
                    Text(
                      '$_previewGoal ml',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('保存'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sliderRow(
    String label,
    double value,
    double min,
    double max,
    int divisions,
    String text,
    ValueChanged<double> onChanged,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(width: 56, child: Text(label, style: theme.textTheme.titleMedium)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            label: text,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 84,
          child: Text(text, textAlign: TextAlign.end),
        ),
      ],
    );
  }
}
