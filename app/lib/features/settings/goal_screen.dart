import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/providers.dart';
import '../../shared/models/user_profile.dart';
import '../characters/character_art.dart';
import '../characters/character_catalog.dart';
import '../characters/current_character_provider.dart';
import '../home/providers/home_providers.dart';

/// 常见目标信息录入页（对标原版 WaterLlama「常见目标」水下场景）
///
/// 整页是水下世界，全部动画由单个 12s 循环控制器驱动（t = 0~1 循环，
/// 所有正弦项使用整数倍频率保证循环首尾无缝）：
/// 1. 顶部水面：白色波浪边界持续晃动（两层不同相位/振幅的波形叠加）
/// 2. 角色：以当前选中角色在水下来回游动（端点处掉头翻转 + 轻微起伏摇摆）
/// 3. 气泡：随机位置自然升起、自然放大淡出消失，循环往复
/// 4. 冰晶六边形块：贴屏幕两侧分布，缓慢旋转 + 上下轻微浮动
/// 5. 性别 / 体重两个选项胶囊：左右轻微颤动
///
/// 功能：性别 / 体重 / 活动强度 / 温度 四项选择即时联动顶部大字目标量
/// 并即时保存；底部「自定义目标」可直接输入覆盖推荐值。

// ---- 设计规范色板（取自原版效果图，供本页与水下背景组件共用） ----
const Color _waterTop = Color(0xFF4FBFDC);
const Color _waterBottom = Color(0xFF37A3C6);

class GoalScreen extends ConsumerStatefulWidget {
  const GoalScreen({super.key});

  @override
  ConsumerState<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends ConsumerState<GoalScreen>
    with SingleTickerProviderStateMixin {
  // ---- 设计规范色板 ----
  static const _pillColor = Color(0x33FFFFFF); // 半透明白胶囊
  static const _iconCircleColor = Color(0x40FFFFFF);

  /// 全场景动画控制器（12s 无限循环）
  late final AnimationController _anim;

  // ---- 用户选择（进入时从档案初始化） ----
  late Gender _gender;

  /// 性别展示标签（怀孕/母乳喂养等），与计算用 Gender 枚举分离并持久化
  late String _genderLabel;
  late double _weight;
  late ActivityLevel _activity;
  GoalTemperature _temp = GoalTemperature.mild;
  int? _customGoal;

  /// 温度持久化 key
  static const _kTempKey = 'goal_temperature';

  /// 性别展示标签持久化 key（与初始化页共用）
  static const _kGenderLabelKey = 'gender_display_label';

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider);
    _gender = profile?.gender ?? Gender.male;
    _genderLabel = defaultGenderLabel(_gender);
    _weight = profile?.weightKg ?? 60;
    _activity = profile?.activityLevel ?? ActivityLevel.low;
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _loadPrefs();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// 加载持久化的温度偏好与性别展示标签
  Future<void> _loadPrefs() async {
    final storage = await ref.read(localStorageProvider.future);
    final name = storage.prefs.getString(_kTempKey);
    final label = storage.prefs.getString(_kGenderLabelKey);
    if (!mounted) return;
    setState(() {
      if (name != null) {
        _temp = GoalTemperature.values.firstWhere(
          (t) => t.name == name,
          orElse: () => GoalTemperature.mild,
        );
      }
      if (label != null) _genderLabel = label;
    });
  }

  // ---- 目标计算与持久化 ----

  /// 当前目标量：自定义值优先；否则按档案算法 + 温度修正
  int get _goal {
    if (_customGoal != null) return _customGoal!.clamp(500, 5000);
    final profile = ref.read(profileProvider);
    final base = UserProfile.create(
      gender: _gender,
      weightKg: _weight,
      heightCm: profile?.heightCm ?? 170,
      age: profile?.age ?? 25,
      activityLevel: _activity,
    ).dailyGoalMl;
    return (base + _temp.deltaMl).clamp(1500, 4500);
  }

  /// 任一选项变化 → 覆盖目标并即时保存档案（自定义值随之失效）
  Future<void> _persist() async {
    final profile = ref.read(profileProvider);
    if (profile == null) return;
    await ref.read(profileProvider.notifier).save(
          profile.copyWith(
            gender: _gender,
            weightKg: _weight,
            activityLevel: _activity,
            dailyGoalMl: _goal,
          ),
        );
  }

  Future<void> _selectGender(GenderOption option) async {
    setState(() {
      _gender = option.gender;
      _genderLabel = option.label;
      _customGoal = null;
    });
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(_kGenderLabelKey, option.label);
    await _persist();
  }

  Future<void> _selectWeight(double kg) async {
    setState(() {
      _weight = kg;
      _customGoal = null;
    });
    await _persist();
  }

  Future<void> _selectActivity(ActivityLevel a) async {
    setState(() {
      _activity = a;
      _customGoal = null;
    });
    await _persist();
  }

  Future<void> _selectTemp(GoalTemperature t) async {
    setState(() {
      _temp = t;
      _customGoal = null;
    });
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(_kTempKey, t.name);
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final currentChar = ref.watch(currentCharacterProvider);
    final catalogAsync = ref.watch(characterCatalogProvider);
    final filePath = catalogAsync.value?.uploadedFilePaths[currentChar];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            final t = _anim.value;
            return Stack(
              children: [
                // 底层：可复用水下背景（渐变水体 + 冰晶 + 气泡，自带动画）
                const Positioned.fill(child: UnderwaterBackground()),
                // 主内容列
                Positioned.fill(
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        SizedBox(height: 46),
                        // 游动的角色（与首页选中角色统一）
                        _SwimmingCharacter(
                          t: t,
                          animalId: currentChar,
                          filePath: filePath,
                        ),
                        const SizedBox(height: 18),
                        // 标题：常见目标 ⓘ
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Text(
                              '常见目标',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.info_outline,
                                color: Colors.white70, size: 15),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // 目标大字（实时联动）
                        Text(
                          '${_goal}ml',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '计算你的目标',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 30),
                        // 四个选项胶囊
                        PillSway(
                          t: t,
                          phase: 0.0,
                          child: _OptionPill(
                            label: '性别',
                            value: _genderLabel,
                            icon: Icons.transgender,
                            onTap: _pickGender,
                          ),
                        ),
                        const SizedBox(height: 14),
                        PillSway(
                          t: t,
                          phase: math.pi,
                          child: _OptionPill(
                            label: '体重',
                            value: '${_weight.round()}kg',
                            icon: Icons.scale,
                            onTap: _pickWeight,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _OptionPill(
                          label: _activityLabel,
                          icon: Icons.directions_run,
                          onTap: _pickActivity,
                        ),
                        const SizedBox(height: 14),
                        _OptionPill(
                          label: _temp.label,
                          icon: Icons.thermostat,
                          onTap: _pickTemp,
                        ),
                        const Spacer(),
                        // 自定义目标入口
                        TextButton(
                          onPressed: _editCustomGoal,
                          child: const Text(
                            '自定义目标',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                // 顶部白色水面（含晃动波形 + 泡沫层）
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: topInset + 26,
                  child: _WaterSurface(t: t, baseHeight: topInset + 26),
                ),
                // 返回按钮（浮于水面之下的青色区域）
                Positioned(
                  top: topInset + 34,
                  left: 16,
                  child: _BackButton(onTap: () => Navigator.pop(context)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---- 选项弹层 ----

  String get _activityLabel => switch (_activity) {
        ActivityLevel.low => '低强度活动',
        ActivityLevel.medium => '中等强度活动',
        ActivityLevel.high => '高强度活动',
      };

  /// 当前选中项在共用性别选项中的匹配（优先按持久化标签，其次按枚举）
  GenderOption get _matchedGenderOption {
    for (final o in kGenderOptions) {
      if (o.label == _genderLabel) return o;
    }
    for (final o in kGenderOptions) {
      if (o.gender == _gender) return o;
    }
    return kGenderOptions.first;
  }

  Future<void> _pickGender() => _showPickerSheet<GenderOption>(
        title: '性别',
        options: kGenderOptions,
        current: _matchedGenderOption,
        label: (o) => o.label,
        onSelect: _selectGender,
      );

  Future<void> _pickActivity() => _showPickerSheet<ActivityLevel>(
        title: '日常活动量',
        options: ActivityLevel.values,
        current: _activity,
        label: (a) => a.label,
        subtitle: (a) => a.description,
        onSelect: _selectActivity,
      );

  Future<void> _pickTemp() => _showPickerSheet<GoalTemperature>(
        title: '今日气温',
        options: GoalTemperature.values,
        current: _temp,
        label: (t) => t.label,
        subtitle: (t) => t.description,
        onSelect: _selectTemp,
      );

  /// 通用选择弹层（白色底部弹层 + 选中项打勾）
  Future<void> _showPickerSheet<T>({
    required String title,
    required List<T> options,
    required T current,
    required String Function(T) label,
    String Function(T)? subtitle,
    required Future<void> Function(T) onSelect,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E),
                ),
              ),
            ),
            for (final option in options)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(
                  label(option),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                subtitle: subtitle == null
                    ? null
                    : Text(
                        subtitle(option),
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF8E8E93)),
                      ),
                trailing: option == current
                    ? const Icon(Icons.check_circle,
                        color: Color(0xFF3BB3DB))
                    : const Icon(Icons.radio_button_unchecked,
                        color: Color(0xFFC7C7CC)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await onSelect(option);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// 体重滑杆弹层（拖动实时预览目标量，松手保存）
  Future<void> _pickWeight() {
    var v = _weight;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '体重',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${v.round()}',
                      style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF3BB3DB),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'kg',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: v,
                  min: 30,
                  max: 150,
                  divisions: 120,
                  activeColor: const Color(0xFF3BB3DB),
                  onChanged: (nv) => setSheet(() => v = nv),
                  onChangeEnd: (nv) => _selectWeight(nv),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    '推荐目标 ${_previewGoalWith(weight: v)}ml',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 以指定体重预览目标量（不落库，仅弹层内展示）
  int _previewGoalWith({required double weight}) {
    final profile = ref.read(profileProvider);
    final base = UserProfile.create(
      gender: _gender,
      weightKg: weight,
      heightCm: profile?.heightCm ?? 170,
      age: profile?.age ?? 25,
      activityLevel: _activity,
    ).dailyGoalMl;
    return (base + _temp.deltaMl).clamp(1500, 4500);
  }

  /// 自定义目标输入弹层（覆盖推荐值，500~5000ml）
  Future<void> _editCustomGoal() async {
    final ctrl = TextEditingController(text: '$_goal');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('自定义目标', textAlign: TextAlign.center),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(
            suffixText: 'ml',
            helperText: '范围 500 ~ 5000 ml',
          ),
          onSubmitted: (v) {
            final n = int.tryParse(v);
            if (n != null) Navigator.pop(ctx, n.clamp(500, 5000));
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF8E8E93))),
          ),
          ElevatedButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text);
              if (n != null) Navigator.pop(ctx, n.clamp(500, 5000));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3BB3DB),
              foregroundColor: Colors.white,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    final profile = ref.read(profileProvider);
    if (profile == null) return;
    setState(() => _customGoal = result);
    await ref
        .read(profileProvider.notifier)
        .save(profile.copyWith(dailyGoalMl: _customGoal));
  }
}

// ============================================================
// 性别选项（初始化页与常见目标页共用，怀孕/母乳喂养按女性修正计算）
// ============================================================

/// 性别选项：展示标签与计算用 Gender 枚举分离（怀孕/母乳喂养 → female）
class GenderOption {
  const GenderOption(this.label, this.gender, this.icon);
  final String label;
  final Gender gender;
  final IconData icon;
}

/// 两页共用的 5 个性别选项
const List<GenderOption> kGenderOptions = <GenderOption>[
  GenderOption('男性', Gender.male, Icons.male),
  GenderOption('女性', Gender.female, Icons.female),
  GenderOption('怀孕', Gender.female, Icons.pregnant_woman),
  GenderOption('母乳喂养', Gender.female, Icons.child_care),
  GenderOption('不愿透露', Gender.other, Icons.no_accounts),
];

/// 无持久化标签时按 Gender 枚举回退的展示标签
String defaultGenderLabel(Gender g) => switch (g) {
      Gender.male => '男性',
      Gender.female => '女性',
      Gender.other => '不愿透露',
    };

// ============================================================
// 目标温度（气温修正：寒冷 -150 / 温和 0 / 炎热 +300）
// ============================================================

enum GoalTemperature {
  cold('寒冷', -150, '天冷出汗少，目标相应降低'),
  mild('温和', 0, '常温天气，无需修正'),
  hot('炎热', 300, '天热出汗多，需要补充更多水分');

  const GoalTemperature(this.label, this.deltaMl, this.description);
  final String label;
  final int deltaMl;
  final String description;
}

// ============================================================
// 可复用水下背景（渐变水体 + 冰晶 + 气泡，供初始化页共用）
// ============================================================

/// 自带循环动画的水下背景层：青色渐变 + 两侧缓旋冰晶 + 升起气泡
class UnderwaterBackground extends StatefulWidget {
  const UnderwaterBackground({super.key});

  @override
  State<UnderwaterBackground> createState() => _UnderwaterBackgroundState();
}

class _UnderwaterBackgroundState extends State<UnderwaterBackground>
    with SingleTickerProviderStateMixin {
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final t = _anim.value;
        return Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_waterTop, _waterBottom],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: IceCubesPainter(t: t)),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: BubblesPainter(t: t)),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================
// 动画组件
// ============================================================

/// 左右轻微颤动包裹器（性别/体重选项胶囊专用）
class PillSway extends StatelessWidget {
  const PillSway({
    super.key,
    required this.t,
    required this.phase,
    required this.child,
  });

  /// 循环进度 0~1
  final double t;
  final double phase;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dx = math.sin(2 * math.pi * t + phase) * 2.4;
    return Transform.translate(offset: Offset(dx, 0), child: child);
  }
}

/// 选项胶囊：左标签（+当前值）+ 右侧图标圆钮
class _OptionPill extends StatelessWidget {
  const _OptionPill({
    required this.label,
    required this.icon,
    required this.onTap,
    this.value,
  });

  final String label;
  final String? value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 44),
      child: Material(
        color: _GoalScreenState._pillColor,
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            height: 58,
            padding: const EdgeInsets.fromLTRB(24, 0, 12, 0),
            child: Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    value!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const Spacer(),
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: _GoalScreenState._iconCircleColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 19),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 来回游动的角色：水平往返（端点掉头翻转）+ 上下起伏 + 轻微摇摆
class _SwimmingCharacter extends StatelessWidget {
  const _SwimmingCharacter({
    required this.t,
    required this.animalId,
    required this.filePath,
  });

  final double t;
  final String animalId;
  final String? filePath;

  @override
  Widget build(BuildContext context) {
    // 水平往返：x = sin(2πt)·38；导数 cos 决定朝向（端点处掉头）
    final x = math.sin(2 * math.pi * t) * 38;
    final facingRight = math.cos(2 * math.pi * t) >= 0;
    // 起伏（2 倍频）+ 摇摆
    final y = math.sin(4 * math.pi * t + 0.8) * 5;
    final rot = math.sin(2 * math.pi * t + 0.4) * 0.06;

    return Transform.translate(
      offset: Offset(x, y),
      child: Transform.rotate(
        angle: rot,
        child: Transform.flip(
          flipX: !facingRight,
          child: CharacterArt(
            animalId: animalId,
            unlocked: true,
            size: 92,
            filePath: filePath,
          ),
        ),
      ),
    );
  }
}

/// 顶部白色水面：白色区域下缘为两层相位/振幅不同的晃动波形
class _WaterSurface extends StatelessWidget {
  const _WaterSurface({required this.t, required this.baseHeight});

  final double t;
  final double baseHeight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, baseHeight),
      painter: _WaterSurfacePainter(t: t, baseHeight: baseHeight),
    );
  }
}

class _WaterSurfacePainter extends CustomPainter {
  _WaterSurfacePainter({required this.t, required this.baseHeight});

  final double t;
  final double baseHeight;

  /// 以整数倍频率保证 12s 循环首尾无缝
  Path _wave(double w, double phase, double amp, double baseY, double cycles) {
    final path = Path()..moveTo(0, 0);
    for (double x = 0; x <= w + 4; x += 4) {
      final y = baseY +
          math.sin(x / w * 2 * math.pi * cycles + phase) * amp +
          math.sin(2 * math.pi * t) * 2; // 整体水面缓慢呼吸
      path.lineTo(x, y);
    }
    return path
      ..lineTo(w, 0)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    // 后层泡沫（半透明白，振幅更大、频率更高）
    final foamPaint = Paint()..color = const Color(0x59FFFFFF);
    canvas.drawPath(
      _wave(w, 2 * math.pi * t * 3 + 1.2, 8, baseHeight - 6, 3),
      foamPaint,
    );
    // 前层水面（纯白，主体）
    final mainPaint = Paint()..color = Colors.white;
    canvas.drawPath(
      _wave(w, 2 * math.pi * t * 2, 6, baseHeight - 16, 2),
      mainPaint,
    );
  }

  @override
  bool shouldRepaint(_WaterSurfacePainter old) =>
      old.t != t || old.baseHeight != baseHeight;
}

/// 气泡层：随机分布的气泡自然升起、放大、淡出消失
class BubblesPainter extends CustomPainter {
  BubblesPainter({required this.t});

  final double t;

  static final List<_BubbleSpec> _specs = () {
    final rnd = math.Random(11);
    return List.generate(10, (i) {
      return _BubbleSpec(
        xFrac: 0.06 + rnd.nextDouble() * 0.88,
        size: 4 + rnd.nextDouble() * 9,
        phase: rnd.nextDouble(),
        speed: 0.6 + rnd.nextDouble() * 0.7,
        sway: 4 + rnd.nextDouble() * 8,
      );
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final yStart = h * 0.96;
    final yEnd = h * 0.24;
    for (final s in _specs) {
      // 每个气泡独立周期：local 0→1 = 升起全程
      final local = (t * s.speed + s.phase) % 1.0;
      final y = yStart + (yEnd - yStart) * local;
      final x = s.xFrac * size.width +
          math.sin(local * 3 * math.pi + s.phase * 7) * s.sway;
      final r = s.size * (0.7 + local * 0.5); // 上升过程缓慢放大
      // 自然出现又自然消失：透明度按正弦半波包络
      final opacity = math.sin(math.pi * local) * 0.55;
      final paint = Paint()
        ..color = Colors.white.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawCircle(Offset(x, y), r, paint);
      // 高光小点
      canvas.drawCircle(
        Offset(x - r * 0.35, y - r * 0.35),
        r * 0.22,
        Paint()..color = Colors.white.withOpacity(opacity),
      );
    }
  }

  @override
  bool shouldRepaint(BubblesPainter old) => old.t != t;
}

class _BubbleSpec {
  const _BubbleSpec({
    required this.xFrac,
    required this.size,
    required this.phase,
    required this.speed,
    required this.sway,
  });

  final double xFrac;
  final double size;
  final double phase;
  final double speed;
  final double sway;
}

/// 冰晶六边形层：屏幕两侧分布，缓慢旋转 + 上下轻微浮动
class IceCubesPainter extends CustomPainter {
  IceCubesPainter({required this.t});

  final double t;

  static final List<_CubeSpec> _specs = () {
    final rnd = math.Random(7);
    return List.generate(9, (i) {
      final isLeft = i % 2 == 0;
      return _CubeSpec(
        isLeft: isLeft,
        yFrac: 0.18 + rnd.nextDouble() * 0.72,
        size: 30 + rnd.nextDouble() * 62,
        edgeFrac: 0.10 + rnd.nextDouble() * 0.16,
        rotSpeed: (i % 3 - 1).toDouble(), // -1 / 0 / 1 圈每循环（0=仅浮动）
        phase: rnd.nextDouble(),
        bright: rnd.nextBool(),
        opacity: 0.10 + rnd.nextDouble() * 0.10,
      );
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in _specs) {
      final cy = s.yFrac * size.height +
          math.sin(2 * math.pi * (t + s.phase)) * 9; // 上下轻微浮动
      final cx = s.isLeft
          ? -s.size * (0.5 - s.edgeFrac)
          : size.width + s.size * (0.5 - s.edgeFrac);
      final rotation = 2 * math.pi * (t * s.rotSpeed + s.phase);
      final paint = Paint()
        ..color = s.bright
            ? Colors.white.withOpacity(s.opacity)
            : const Color(0xFF1B7A99).withOpacity(s.opacity * 0.9);
      _drawHexagon(canvas, Offset(cx, cy), s.size * 0.5, rotation, paint);
    }
  }

  void _drawHexagon(
      Canvas canvas, Offset center, double r, double rotation, Paint paint) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = rotation + math.pi / 6 + i * math.pi / 3;
      final p = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(IceCubesPainter old) => old.t != t;
}

class _CubeSpec {
  const _CubeSpec({
    required this.isLeft,
    required this.yFrac,
    required this.size,
    required this.edgeFrac,
    required this.rotSpeed,
    required this.phase,
    required this.bright,
    required this.opacity,
  });

  final bool isLeft;
  final double yFrac;
  final double size;

  /// 贴边嵌入比例（越大越多部分露出）
  final double edgeFrac;
  final double rotSpeed;
  final double phase;
  final bool bright;
  final double opacity;
}

/// 左上角返回按钮（半透明白圆钮）
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x33FFFFFF),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.arrow_back_ios_new,
            size: 17,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
