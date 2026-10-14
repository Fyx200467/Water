import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/providers.dart';
import '../characters/current_character_provider.dart';
import '../drink/providers/custom_beverage_provider.dart';
import '../drink/widgets/svg_container.dart';
import '../../shared/models/beverage.dart';
import '../../shared/widgets/drink_illustration.dart';
import '../home/providers/home_providers.dart';
import '../onboarding/widgets/animal_silhouette.dart';
import '../stats/providers/stats_providers.dart';

// ============================================================
// 小组件设置页（对标原版 WaterLlama「小组件」页）
//
// 结构：
// 1. 返回圆钮 + 居中大标题「小组件」
// 2. 中/小 分段选择器（深色选中胶囊）
// 3. 小组件预览卡（目标 + 灰色角色剪影 + 连续徽章 + 饮料格）
// 4. 颜色主题卡（20 色圆形色板 + 自定义 + 按钮）
// 5. 饮料 1/2/3 选择行（弹层选饮品 + 容量）
// 6. 开关组：彩色饮料按钮 / 彩色字符层 / 遵循深色模式规则 /
//    跳过日间模式 / 连续徽章
// 7. 如何添加小组件行（说明弹层）
// 8. 手表示意 + 说明文案
// ============================================================

/// 小组件设置状态（持久化到 SharedPreferences）
class WidgetSettingsState {
  const WidgetSettingsState({
    this.colorIndex = 0,
    this.customColor,
    this.drink1 = 'milk_juice',
    this.vol1 = 250,
    this.drink2 = 'milk_juice',
    this.vol2 = 250,
    this.drink3 = 'soda',
    this.vol3 = 330,
    this.colorfulButtons = false,
    this.colorfulCharacter = true,
    this.followDarkMode = true,
    this.skipDayMode = true,
    this.streakBadge = true,
    this.mediumSize = true,
  });

  final int colorIndex; // 色板下标，-1 = 自定义色
  final int? customColor; // 自定义色 ARGB（colorIndex == -1 时生效）
  final String drink1;
  final int vol1;
  final String drink2;
  final int vol2;
  final String drink3;
  final int vol3;
  final bool colorfulButtons; // 彩色饮料按钮
  final bool colorfulCharacter; // 彩色字符层
  final bool followDarkMode; // 遵循深色模式规则
  final bool skipDayMode; // 跳过日间模式
  final bool streakBadge; // 连续徽章
  final bool mediumSize; // 中 / 小 分段

  Color get themeColor => colorIndex >= 0
      ? widgetPalette[colorIndex]
      : Color(customColor ?? 0xFFFFFFFF);

  WidgetSettingsState copyWith({
    int? colorIndex,
    int? customColor,
    String? drink1,
    int? vol1,
    String? drink2,
    int? vol2,
    String? drink3,
    int? vol3,
    bool? colorfulButtons,
    bool? colorfulCharacter,
    bool? followDarkMode,
    bool? skipDayMode,
    bool? streakBadge,
    bool? mediumSize,
  }) =>
      WidgetSettingsState(
        colorIndex: colorIndex ?? this.colorIndex,
        customColor: customColor ?? this.customColor,
        drink1: drink1 ?? this.drink1,
        vol1: vol1 ?? this.vol1,
        drink2: drink2 ?? this.drink2,
        vol2: vol2 ?? this.vol2,
        drink3: drink3 ?? this.drink3,
        vol3: vol3 ?? this.vol3,
        colorfulButtons: colorfulButtons ?? this.colorfulButtons,
        colorfulCharacter: colorfulCharacter ?? this.colorfulCharacter,
        followDarkMode: followDarkMode ?? this.followDarkMode,
        skipDayMode: skipDayMode ?? this.skipDayMode,
        streakBadge: streakBadge ?? this.streakBadge,
        mediumSize: mediumSize ?? this.mediumSize,
      );

  Map<String, dynamic> _toMap() => {
        'colorIndex': colorIndex,
        if (customColor != null) 'customColor': customColor,
        'drink1': drink1, 'vol1': vol1,
        'drink2': drink2, 'vol2': vol2,
        'drink3': drink3, 'vol3': vol3,
        'colorfulButtons': colorfulButtons,
        'colorfulCharacter': colorfulCharacter,
        'followDarkMode': followDarkMode,
        'skipDayMode': skipDayMode,
        'streakBadge': streakBadge,
        'mediumSize': mediumSize,
      };

  static WidgetSettingsState _fromMap(Map<String, dynamic> m) =>
      WidgetSettingsState(
        colorIndex: (m['colorIndex'] as num?)?.toInt() ?? 0,
        customColor: (m['customColor'] as num?)?.toInt(),
        drink1: m['drink1'] as String? ?? 'milk_juice',
        vol1: (m['vol1'] as num?)?.toInt() ?? 250,
        drink2: m['drink2'] as String? ?? 'milk_juice',
        vol2: (m['vol2'] as num?)?.toInt() ?? 250,
        drink3: m['drink3'] as String? ?? 'soda',
        vol3: (m['vol3'] as num?)?.toInt() ?? 330,
        colorfulButtons: m['colorfulButtons'] as bool? ?? false,
        colorfulCharacter: m['colorfulCharacter'] as bool? ?? true,
        followDarkMode: m['followDarkMode'] as bool? ?? true,
        skipDayMode: m['skipDayMode'] as bool? ?? true,
        streakBadge: m['streakBadge'] as bool? ?? true,
        mediumSize: m['mediumSize'] as bool? ?? true,
      );
}

class WidgetSettingsNotifier extends StateNotifier<WidgetSettingsState> {
  WidgetSettingsNotifier(this.ref) : super(const WidgetSettingsState()) {
    _load();
  }

  final Ref ref;

  static const _kKey = 'widget_settings';

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final raw = storage.prefs.getString(_kKey);
    if (raw == null || raw.isEmpty || !mounted) return;
    try {
      state = WidgetSettingsState._fromMap(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // 数据异常保持默认
    }
  }

  Future<void> update(WidgetSettingsState next) async {
    state = next;
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(_kKey, jsonEncode(state._toMap()));
  }
}

/// 色板（对标原版 5 列 × 4 行）
const List<Color> widgetPalette = [
  Color(0xFFFFFFFF), Color(0xFFF2F2F4), Color(0xFFF5ECDC), Color(0xFF5D4037), Color(0xFF141414),
  Color(0xFFADE1F5), Color(0xFFBBD7F0), Color(0xFFC6E5C5), Color(0xFFA8E6CF), Color(0xFF43A047),
  Color(0xFFFFE45C), Color(0xFFFFB35C), Color(0xFFF48FB1), Color(0xFFE5605C), Color(0xFF8E2436),
  Color(0xFFF8BBD0), Color(0xFFD3C7F2), Color(0xFF7C4DFF), Color(0xFF1E44B8), Color(0xFF64748B),
];

final widgetSettingsProvider =
    StateNotifierProvider<WidgetSettingsNotifier, WidgetSettingsState>((ref) {
  return WidgetSettingsNotifier(ref);
});

// ============================================================
// 页面
// ============================================================

class WidgetSettingsScreen extends ConsumerStatefulWidget {
  const WidgetSettingsScreen({super.key});

  @override
  ConsumerState<WidgetSettingsScreen> createState() =>
      _WidgetSettingsScreenState();
}

class _WidgetSettingsScreenState extends ConsumerState<WidgetSettingsScreen> {
  static const _textDark = Color(0xFF1C1C1E);
  static const _textGray = Color(0xFF9E9EA4);
  static const _cardBg = Color(0xFFF6F6F8);
  static const _switchCyan = Color(0xFF35B5D6);

  Future<void> _mutate(WidgetSettingsState Function(WidgetSettingsState) fn) =>
      ref.read(widgetSettingsProvider.notifier).update(
            fn(ref.read(widgetSettingsProvider)),
          );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(widgetSettingsProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _backButton(),
                const SizedBox(height: 6),
                const Center(
                  child: Text('小组件',
                      style: TextStyle(
                          color: _textDark,
                          fontSize: 28,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 18),
                _segmented(s),
                const SizedBox(height: 14),
                _previewCard(s),
                const SizedBox(height: 14),
                _paletteCard(s),
                const SizedBox(height: 18),
                ..._drinkRows(s),
                _sectionDivider(),
                _toggleCard(
                  title: '彩色饮料按钮',
                  subtitle: '饮料按钮的颜色将与小组件的颜色主题保持一致',
                  value: s.colorfulButtons,
                  onChanged: (v) => _mutate((x) => x.copyWith(colorfulButtons: v)),
                ),
                const SizedBox(height: 10),
                _toggleCard(
                  title: '彩色字符层',
                  subtitle: '角色饮料图层的颜色将与小组件的色彩主题保持一致',
                  value: s.colorfulCharacter,
                  onChanged: (v) => _mutate((x) => x.copyWith(colorfulCharacter: v)),
                ),
                const SizedBox(height: 10),
                _toggleCard(
                  title: '遵循深色模式规则',
                  subtitle: '当你的设备启用深色模式时，将深色应用于主屏幕小组件',
                  value: s.followDarkMode,
                  onChanged: (v) => _mutate((x) => x.copyWith(followDarkMode: v)),
                ),
                const SizedBox(height: 10),
                _toggleCard(
                  title: '跳过日间模式',
                  subtitle: '如果你一整天都不加水，第二天的部件会显示一个鼓励的图示。',
                  value: s.skipDayMode,
                  onChanged: (v) => _mutate((x) => x.copyWith(skipDayMode: v)),
                ),
                _sectionDivider(),
                _toggleCard(
                  title: '连续徽章',
                  value: s.streakBadge,
                  onChanged: (v) => _mutate((x) => x.copyWith(streakBadge: v)),
                ),
                const SizedBox(height: 10),
                _helpRow(),
                _sectionDivider(),
                _watchMock(),
                const SizedBox(height: 10),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '你为主屏幕小组件选择的饮料对手表小组件也适用。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _textGray, fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- 顶部 ----------------

  Widget _backButton() => Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(),
          customBorder: const CircleBorder(),
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFE9E9EC),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chevron_left,
                color: Color(0xFF5A5A60), size: 28),
          ),
        ),
      );

  /// 中/小 分段选择器（深色选中胶囊，平滑切换）
  Widget _segmented(WidgetSettingsState s) => Container(
        height: 46,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F1F4),
          borderRadius: BorderRadius.circular(23),
        ),
        child: Row(
          children: [
            _segment('中', s.mediumSize, () => _mutate((x) => x.copyWith(mediumSize: true))),
            _segment('小', !s.mediumSize, () => _mutate((x) => x.copyWith(mediumSize: false))),
          ],
        ),
      );

  Widget _segment(String label, bool selected, VoidCallback onTap) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF232B36) : Colors.transparent,
              borderRadius: BorderRadius.circular(19),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : _textDark,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );

  // ---------------- 预览卡 ----------------

  Widget _previewCard(WidgetSettingsState s) {
    final progress = ref.watch(dailyProgressProvider);
    final checkin = ref.watch(checkinDaysProvider).asData?.value ?? 0;
    final currentChar = ref.watch(currentCharacterProvider);

    final goal = _goalLabel(progress.goalMl);
    final percent = (progress.progress * 100).round();
    final fraction = progress.progress.clamp(0.0, 1.0).toDouble();
    // 选择了非默认白色主题时，预览卡背景染主题色
    final colorful =
        s.colorIndex != 0 || (s.colorIndex == -1 && s.customColor != null);
    final themeColor = s.themeColor;
    final cardColor = colorful ? themeColor : Colors.white;
    // 深色主题上文字/徽章用白色，浅色主题用深色
    final onCard =
        themeColor.computeLuminance() > 0.55 ? _textDark : Colors.white;
    // 角色液体填充：直接复用首页同款 AnimalSilhouette（灰剪影 +
    // 波浪液面动画）；液体固定品牌青水色，不随小组件主题色变化
    // （灰色剪影为组件内置 EBEBEB，与首页角色底色一致）
    Widget character(double size) => AnimalSilhouette(
          animalId: currentChar,
          fillRatio: fraction,
          accentColor: const Color(0xFF4DB8D8),
          solidFillColor: const Color(0xFF4DB8D8),
          size: size,
        );

    if (!s.mediumSize) {
      // 小：居中正方形卡（对标原版），单饮料半透明圆格（右下）
      final b = _findBeverage(s.drink1);
      return Center(
        child: Container(
          width: 188,
          height: 188,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFECECEF)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 目标（左上）
              Positioned(
                left: 2,
                top: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(goal,
                        style: TextStyle(
                            color: onCard,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    Text('$percent%',
                        style: TextStyle(
                            color: onCard.withValues(alpha: 0.65),
                            fontSize: 11)),
                  ],
                ),
              ),
              // 角色（大剪影，居右下）
              Positioned(
                right: 0,
                bottom: 0,
                child: character(142),
              ),
              // 连续徽章（左下，半透明白）
              if (s.streakBadge)
                Positioned(
                  left: 0,
                  bottom: 6,
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Text('$checkin',
                        style: TextStyle(
                            color: onCard,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              // 饮料圆格（右下，半透明白 + 图标 + 容量）
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                          width: 24,
                          height: 24,
                          child: Center(child: _drinkThumb(b, 22))),
                      const SizedBox(height: 2),
                      Text('${s.volOf(b)}ml',
                          style: TextStyle(
                              color: onCard,
                              fontSize: 9,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 中：全宽卡，角色居中偏右，饮料格右侧竖排
    final drinks = [
      _findBeverage(s.drink1),
      _findBeverage(s.drink2),
      _findBeverage(s.drink3),
    ];
    return Container(
      height: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFECECEF)),
      ),
      child: Stack(
        children: [
          // 目标（左上）
          Positioned(
            left: 4,
            top: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(goal,
                    style: TextStyle(
                        color: onCard,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                Text('$percent%',
                    style:
                        TextStyle(color: onCard.withValues(alpha: 0.65), fontSize: 12)),
              ],
            ),
          ),
          // 角色（居中偏右）
          Positioned(
            left: 64,
            bottom: 0,
            child: character(122),
          ),
          // 连续徽章（左下，压在角色上）
          if (s.streakBadge)
            Positioned(
              left: 2,
              bottom: 12,
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFEFEFF2)),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 8,
                        offset: Offset(0, 2)),
                  ],
                ),
                child: Text('$checkin',
                    style: const TextStyle(
                        color: _textDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          // 饮料格（右侧竖排）
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final b in drinks) _widgetDrinkTile(b, s),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Beverage _findBeverage(String id) {
    final customs = ref.read(customBeveragesProvider);
    final all = [...Beverage.presets, ...customs];
    return all.firstWhere((b) => b.id == id, orElse: () => all.first);
  }

  /// 预览卡内单个饮料格：容量/名称 + 灰底圆角容器 + 会员锁角标
  Widget _widgetDrinkTile(Beverage b, WidgetSettingsState s) {
    final isMember = ref.watch(memberProvider).isValid;
    final locked = b.memberOnly && !isMember;
    final tileColor = s.colorfulButtons ? s.themeColor : const Color(0xFFF1F1F4);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${s.volOf(b)}ml',
                style: const TextStyle(
                    color: _textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 1),
            Text(b.name,
                style: const TextStyle(color: _textGray, fontSize: 11)),
          ],
        ),
        const SizedBox(width: 10),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: tileColor,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: _drinkThumb(b, 36),
            ),
            if (locked)
              Positioned(
                left: -5,
                top: -5,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                      color: Color(0xFF3C3C43), shape: BoxShape.circle),
                  child: const Icon(Icons.lock,
                      color: Colors.white, size: 10),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _drinkThumb(Beverage b, double size) {
    if (isSvgContainer(b.containerId)) {
      return SvgContainerIcon(
          containerId: b.containerId!, color: b.color, size: size);
    }
    final illustId = b.id.startsWith('custom_')
        ? (b.templateId ?? Beverage.fallbackIllustration(b.category))
        : b.id;
    return DrinkIllustration(beverageId: illustId, color: b.color, size: size);
  }

  /// 目标容量显示：整千显示「N升」，其余千位以上一位小数，小目标直接 ml
  String _goalLabel(int ml) {
    if (ml >= 1000) {
      final liters = ml / 1000;
      return liters == liters.roundToDouble()
          ? '${liters.toStringAsFixed(0)}升'
          : '${liters.toStringAsFixed(1)}升';
    }
    return '${ml}ml';
  }

  // ---------------- 色板卡 ----------------

  Widget _paletteCard(WidgetSettingsState s) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 5,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1,
            children: [
              for (var i = 0; i < widgetPalette.length; i++)
                _swatch(
                  widgetPalette[i],
                  selected: s.colorIndex == i,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(child: SizedBox()),
              Container(
                width: 52,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE4E4E8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: 10),
          // 自定义色预览或提示
          if (s.colorIndex == -1 && s.customColor != null)
            _swatch(Color(s.customColor!),
                selected: true, custom: true)
          else
            const Text('自定义',
                style: TextStyle(color: Color(0xFFB4B4BA), fontSize: 13)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: _pickCustomColor,
              customBorder: const CircleBorder(),
              child: Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: Color(0xFFE7E7EB),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add,
                    color: Color(0xFF9A9AA0), size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _swatch(Color c, {required bool selected, bool custom = false}) =>
      GestureDetector(
        onTap: custom
            ? _pickCustomColor
            : () => _mutate(
                (x) => x.copyWith(colorIndex: widgetPalette.indexOf(c))),
        child: Center(
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? const Color(0xFF3F4753)
                    : const Color(0x14000000),
                width: selected ? 2.5 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: selected
                ? Icon(Icons.check,
                    color: c.computeLuminance() > 0.5
                        ? const Color(0xFF2B313B)
                        : Colors.white,
                    size: 24)
                : null,
          ),
        ),
      );

  // ---------------- 饮料选择行 ----------------

  List<Widget> _drinkRows(WidgetSettingsState s) => [
        // 小组件只有 1 个饮料位（标题「饮料」），中组件有 3 个（饮料 1/2/3）
        _drinkRow(s.mediumSize ? '饮料 1' : '饮料', s.drink1, s.vol1,
            (id, ml) => _mutate((x) => x.copyWith(drink1: id, vol1: ml))),
        if (s.mediumSize) ...[
          const SizedBox(height: 10),
          _drinkRow('饮料 2', s.drink2, s.vol2,
              (id, ml) => _mutate((x) => x.copyWith(drink2: id, vol2: ml))),
          const SizedBox(height: 10),
          _drinkRow('饮料 3', s.drink3, s.vol3,
              (id, ml) => _mutate((x) => x.copyWith(drink3: id, vol3: ml))),
        ],
      ];

  Widget _drinkRow(
      String title, String drinkId, int ml,
      void Function(String id, int ml) onPicked) {
    final b = _findBeverage(drinkId);
    return InkWell(
      onTap: () => _pickDrink(b, onPicked),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Text(title,
                style: const TextStyle(
                    color: _textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${b.name}, ${ml}ml',
                style: const TextStyle(color: Color(0xFFB0B0B6), fontSize: 15)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right,
                color: Color(0xFFC7C7CC), size: 22),
          ],
        ),
      ),
    );
  }

  /// 饮料选择弹层：两步（先选饮品，再选容量），会员专属饮品带锁
  Future<void> _pickDrink(
      Beverage current, void Function(String, int) onPicked) async {
    final isMember = ref.read(memberProvider).isValid;
    final customs = ref.read(customBeveragesProvider);
    final all = [...Beverage.presets, ...customs];
    Beverage? picked;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          if (picked == null) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.7,
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    const Text('选择饮品',
                        style: TextStyle(
                            color: _textDark,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: all.length,
                        itemBuilder: (ctx, i) {
                          final b = all[i];
                          final locked = b.memberOnly && !isMember;
                          return ListTile(
                            leading: SizedBox(
                                width: 40,
                                height: 40,
                                child: Center(child: _drinkThumb(b, 32))),
                            title: Text(b.name,
                                style: const TextStyle(
                                    color: _textDark,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                            trailing: locked
                                ? const Icon(Icons.lock,
                                    color: Color(0xFFB0B0B6), size: 18)
                                : const Icon(Icons.chevron_right,
                                    color: Color(0xFFC7C7CC)),
                            onTap: () {
                              if (locked) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('该饮品为会员专属，开通会员后可选')),
                                );
                                return;
                              }
                              if (b.category == BeverageCategory.water ||
                                  b.volumes.length == 1) {
                                Navigator.pop(ctx);
                                onPicked(b.id, b.defaultMl);
                                return;
                              }
                              setSheet(() => picked = b);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          // 第二步：容量选择
          final b = picked!;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('选择${b.name}容量',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: _textDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final v in b.volumes)
                        ChoiceChip(
                          label: Text('$v ml'),
                          selected: v == b.defaultMl,
                          onSelected: (_) {
                            Navigator.pop(ctx);
                            onPicked(b.id, v);
                          },
                          selectedColor: const Color(0xFFD7F0F6),
                          labelStyle: const TextStyle(color: _textDark),
                          shape: const StadiumBorder(
                              side: BorderSide(color: Color(0xFFE2E2E6))),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------- 通用行 ----------------

  Widget _sectionDivider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Container(
            width: 52,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFECECEF),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );

  Widget _toggleCard({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: _textDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(
                            color: _textGray, fontSize: 13, height: 1.45)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Transform.scale(
              scale: 0.82,
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: _switchCyan,
                activeThumbColor: Colors.white,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFE5E5EA),
              ),
            ),
          ],
        ),
      );

  Widget _helpRow() => InkWell(
        onTap: _showHelpSheet,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Text('如何添加小组件',
                  style: TextStyle(
                      color: _textDark,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              const Icon(Icons.chevron_right,
                  color: Color(0xFFC7C7CC), size: 22),
            ],
          ),
        ),
      );

  void _showHelpSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text('如何添加小组件',
                    style: TextStyle(
                        color: _textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 16),
              ...const [
                Text('1. 长按主屏幕空白区域，进入编辑模式',
                    style: TextStyle(color: _textDark, fontSize: 14, height: 1.8)),
                Text('2. 点击左上角「+」搜索喝水羊驼',
                    style: TextStyle(color: _textDark, fontSize: 14, height: 1.8)),
                Text('3. 选择「中」或「小」尺寸',
                    style: TextStyle(color: _textDark, fontSize: 14, height: 1.8)),
                Text('4. 点击「添加小组件」完成',
                    style: TextStyle(color: _textDark, fontSize: 14, height: 1.8)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- 自定义颜色 ----------------

  Future<void> _pickCustomColor() async {
    Color color = ref.read(widgetSettingsProvider).customColor != null
        ? Color(ref.read(widgetSettingsProvider).customColor!)
        : const Color(0xFF4DB8D8);
    final hsl = HSLColor.fromColor(color);
    double hue = hsl.hue, sat = hsl.saturation, light = hsl.lightness;
    Color fromHSL() =>
        HSLColor.fromAHSL(1, hue, sat.clamp(0.0, 1.0), light.clamp(0.0, 1.0))
            .toColor();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                      color: color, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(height: 18),
              _hSlider('色相', hue, 0, 360, [
                for (var i = 0; i <= 6; i++)
                  HSLColor.fromAHSL(1, i * 60.0, 1, 0.5).toColor(),
              ], (v) => setSheet(() { hue = v; color = fromHSL(); })),
              _hSlider('饱和度', sat, 0, 1, [
                Colors.black,
                HSLColor.fromAHSL(1, hue, 1, 0.5).toColor(),
              ], (v) => setSheet(() { sat = v; color = fromHSL(); })),
              _hSlider('亮度', light, 0, 1, [
                Colors.black,
                Colors.white,
              ], (v) => setSheet(() { light = v; color = fromHSL(); })),
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4DB8D8),
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
    );
    if (ok == true) {
      await _mutate((x) => x.copyWith(
          colorIndex: -1, customColor: color.toARGB32()));
    }
  }

  Widget _hSlider(String label, double value, double min, double max,
      List<Color> trackColors, ValueChanged<double> onChanged) {
    // 滑轨底色由调用方传入渐变色组（色相=彩虹，饱和=黑-主色，亮度=黑-白），
    // Slider 自身轨道透明只保留拇指圆点
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: _textGray, fontSize: 12)),
          SizedBox(
            height: 36,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: LinearGradient(colors: trackColors),
                    ),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 1,
                    trackShape: const RectangularSliderTrackShape(),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 9, elevation: 2),
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    activeColor: Colors.transparent,
                    inactiveColor: Colors.transparent,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 手表示意 ----------------

  Widget _watchMock() => SizedBox(
        height: 290,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 表带（上下两段）
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 66,
                  decoration: const BoxDecoration(
                    color: Color(0xFF161618),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(34)),
                  ),
                ),
                const SizedBox(height: 148),
                Container(
                  width: 96,
                  height: 66,
                  decoration: const BoxDecoration(
                    color: Color(0xFF161618),
                    borderRadius:
                        BorderRadius.vertical(bottom: Radius.circular(34)),
                  ),
                ),
              ],
            ),
            // 表壳 + 屏幕
            Container(
              width: 152,
              height: 184,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFF0E0E10),
                borderRadius: BorderRadius.circular(46),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(38),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3A4A6B), Color(0xFF14161F)],
                  ),
                ),
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: 18),
                child: const Column(
                  children: [
                    Text('WED\nJUL',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Color(0xFF9AE0F0),
                            fontSize: 11,
                            height: 1.2,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            // 悬浮小组件卡（8oz/12oz/6oz + 28oz 进度）
            Positioned(
              bottom: 42,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF7FB),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x1E000000),
                        blurRadius: 10,
                        offset: Offset(0, 3)),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _watchBubble('8oz', const Color(0xFF7FD6EE)),
                        const SizedBox(width: 8),
                        _watchBubble('12oz', const Color(0xFFFFC966)),
                        const SizedBox(width: 8),
                        _watchBubble('6oz', const Color(0xFFE5605C)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('28oz',
                            style: TextStyle(
                                color: _textDark,
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        Container(
                          width: 110,
                          height: 7,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: 78,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  Color(0xFF7FD6EE),
                                  Color(0xFFFFC966),
                                  Color(0xFFE5605C),
                                ]),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _watchBubble(String label, Color color) => Column(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(
                  color: _textDark,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
        ],
      );
}

// StateNotifier 内访问 storage 的辅助（避开构造参数改动）
extension _WidgetSettingsVol on WidgetSettingsState {
  int volOf(Beverage b) {
    // 预览格显示的容量：与所选饮料对应的 vol 字段
    if (b.id == drink1) return vol1;
    if (b.id == drink2) return vol2;
    if (b.id == drink3) return vol3;
    return b.defaultMl;
  }
}
