import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/storage/providers.dart';
import '../../core/widget/home_widget_sync.dart';
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
// 7. 手表示意 + 说明文案
//
// 原则：本页只做小组件的「样式」设置（外观/内容），不提供添加/
// 启停小组件等开关类功能——组件的添加与管理一律在系统桌面完成
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
    // 设置变化即时刷新桌面小组件（饮料格/主题色/徽章与预览卡保持一致）
    syncWidgetFromSettings(ref.read);
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

  // ---------------- 预览卡 ----------------

  Widget _previewCard(WidgetSettingsState s) {
    final progress = ref.watch(dailyProgressProvider);
    final checkin = ref.watch(checkinDaysProvider).asData?.value ?? 0;
    final currentChar = ref.watch(currentCharacterProvider);

    // 左上大字：当日饮水总量（实时绑定，与桌面小组件 goal_label 同源）
    final volume = _goalLabel(progress.totalEffectiveMl);
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
    // 波浪液面动画）；「彩色字符层」开启时液体跟随主题色，否则品牌青
    // （灰色剪影为组件内置 EBEBEB，与首页角色底色一致）
    final liquidColor = widgetLiquidColor(s);
    Widget character(double size) => AnimalSilhouette(
          animalId: currentChar,
          fillRatio: fraction,
          accentColor: liquidColor,
          solidFillColor: liquidColor,
          size: size,
        );

    // 全宽卡，角色居中偏右，饮料格右侧竖排（唯一固定样式，对标竞品
    // 「柠檬喝水」：单一布局强制不变，跨厂商/iOS 观感一致）
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
                Text(volume,
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

  /// 预览卡内单个饮料格：容量/名称 + 灰底圆角容器
  Widget _widgetDrinkTile(Beverage b, WidgetSettingsState s) {
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
        // 唯一固定样式：3 个饮料位（饮料 1/2/3）
        _drinkRow('饮料 1', s.drink1, s.vol1,
            (id, ml) => _mutate((x) => x.copyWith(drink1: id, vol1: ml))),
        const SizedBox(height: 10),
        _drinkRow('饮料 2', s.drink2, s.vol2,
            (id, ml) => _mutate((x) => x.copyWith(drink2: id, vol2: ml))),
        const SizedBox(height: 10),
        _drinkRow('饮料 3', s.drink3, s.vol3,
            (id, ml) => _mutate((x) => x.copyWith(drink3: id, vol3: ml))),
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

  /// 饮料选择弹层：两步（先选饮品，再选容量）
  Future<void> _pickDrink(
      Beverage current, void Function(String, int) onPicked) async {
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
                            trailing: const Icon(Icons.chevron_right,
                                color: Color(0xFFC7C7CC)),
                            onTap: () {
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

// ============================================================
// 桌面小组件数据组装（与预览卡同构）
// ============================================================

/// Provider 泛型读取签名：兼容 Ref.read / WidgetRef.read 的 tear-off
typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// 桌面小组件液体波浪动画帧数：一次渲染 16 个相位帧（0..15/16）写盘，
/// 小组件内 ViewFlipper 在 launcher 进程内自动轮播（100ms/帧 ≈ 10fps，
/// 周期 1.6s，与 App 内 1400ms 波浪周期观感一致且平滑）—— 动画不依赖
/// App 存活，退后台/被杀后桌面液体仍持续流动
const int kWidgetFrameCount = 16;

/// 渲染防并发：连续快速录入时合并请求，正在渲染期间的新请求只置
/// pending 标记，结束后补渲一次（避免两个 16 帧循环交错冲突）
bool _framesRendering = false;
bool _framesPending = false;

/// 离屏渲染 8 帧波浪相位角色并推送小组件刷新（与 App 内同款
/// AnimalSilhouette：灰剪影 + 液体填充/达标全彩）。
/// 相位只影响液体波面：0% 灰剪影 / 达标全彩时 8 帧画面一致，
/// 轮播无可见变化、无额外开销
Future<void> renderWidgetCharacterFrames(
  Reader read, {
  Color liquidColor = const Color(0xFF4DB8D8),
}) async {
  if (_framesRendering) {
    _framesPending = true;
    return;
  }
  _framesRendering = true;
  try {
    await _renderFramesOnce(read, liquidColor: liquidColor);
  } finally {
    _framesRendering = false;
  }
  if (_framesPending) {
    _framesPending = false;
    return renderWidgetCharacterFrames(read, liquidColor: liquidColor);
  }
}

Future<void> _renderFramesOnce(
  Reader read, {
  required Color liquidColor,
}) async {
  try {
    final progress = read(dailyProgressProvider);
    final characterId = read(currentCharacterProvider);
    for (var i = 0; i < kWidgetFrameCount; i++) {
      final key = 'character_frame_$i';
      var path = await HomeWidget.renderFlutterWidget(
        AnimalSilhouette(
          animalId: characterId,
          fillRatio: progress.progress.clamp(0.0, 1.0),
          accentColor: liquidColor,
          solidFillColor: liquidColor,
          size: 128,
          phase: i / kWidgetFrameCount,
          fullArt: progress.isComplete,
        ),
        key: key,
        logicalSize: const ui.Size(128, 128),
        pixelRatio: 3,
      );
      path ??= await HomeWidget.getWidgetData<String>(key);
      if (path != null && path.isNotEmpty) {
        // 先写全 8 帧文件，末尾统一 updateWidget：launcher 解码发生在
        // RemoteViews 应用时，不会读到半写图像
        await HomeWidget.saveWidgetData<String>(key, path);
      }
    }
    await HomeWidget.updateWidget(
      name: 'WaterLlamaWidgetProvider',
      androidName: 'WaterLlamaWidgetProvider',
    );
  } catch (_) {
    // 帧渲染失败静默跳过（下次数据变化同步时自动补上）
  }
}

/// 同步防交错：连续快速改设置时合并请求（渲染/写键交错会产生脏数据）
bool _syncBusy = false;
bool _syncPending = false;

/// 组装小组件数据并刷新：饮料格/主题色/徽章/格底色来自小组件设置
/// （与预览卡同构）；今日合计/目标/连续天数默认读当前状态，
/// 可用参数覆盖（清除数据等重置场景）
Future<void> syncWidgetFromSettings(
  Reader read, {
  int? todayMl,
  int? goalMl,
  int? streakDays,
}) async {
  if (_syncBusy) {
    _syncPending = true;
    return;
  }
  _syncBusy = true;
  try {
    await _syncWidgetFromSettingsOnce(read,
        todayMl: todayMl, goalMl: goalMl, streakDays: streakDays);
  } finally {
    _syncBusy = false;
  }
  if (_syncPending) {
    _syncPending = false;
    return syncWidgetFromSettings(read);
  }
}

/// 液体填充色：「彩色字符层」开启且有非白主题色时液体跟随主题色，
/// 否则保持品牌青（预览卡与桌面帧同规则）
Color widgetLiquidColor(WidgetSettingsState s) {
  final colorful =
      s.colorIndex != 0 || (s.colorIndex == -1 && s.customColor != null);
  if (s.colorfulCharacter && colorful) return s.themeColor;
  return const Color(0xFF4DB8D8);
}

Future<void> _syncWidgetFromSettingsOnce(
  Reader read, {
  int? todayMl,
  int? goalMl,
  int? streakDays,
}) async {
  try {
    final s = read(widgetSettingsProvider);
    final progress = read(dailyProgressProvider);
    // 数据文本/饮料格先行推送（不等帧渲染，录入后桌面数字即时更新）
    final slots = [(s.drink1, s.vol1), (s.drink2, s.vol2), (s.drink3, s.vol3)];
    final customs = read(customBeveragesProvider);
    final all = [...Beverage.presets, ...customs];
    final drinks = <WidgetDrinkData>[];
    for (final (id, vol) in slots) {
      final b = all.firstWhere((x) => x.id == id, orElse: () => all.first);
      drinks.add(WidgetDrinkData(
          ml: vol, name: b.name, iconFile: await _rasterizeDrinkIcon(b)));
    }
    // 主题色：选了非白色（含自定义色）才染底，白/未选保持默认白底；
    // 「遵循深色模式规则」开启且系统处于深色时强制深色底白字
    final colorful =
        s.colorIndex != 0 || (s.colorIndex == -1 && s.customColor != null);
    final systemDark = WidgetsBinding
            .instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final themeColor = s.followDarkMode && systemDark
        ? const Color(0xFF1C1C22)
        : (colorful ? s.themeColor : null);
    await syncHomeWidget(
      todayMl: todayMl ?? progress.totalEffectiveMl,
      goalMl: goalMl ?? progress.goalMl,
      streakDays: streakDays ?? read(checkinDaysProvider).asData?.value ?? 0,
      themeColor: themeColor,
      showStreak: s.streakBadge,
      tileColor: s.colorfulButtons
          ? (themeColor ?? s.themeColor).toARGB32()
          : -1,
      drinks: drinks,
    );
    // 角色动画帧随后渲染补推（与 App 内首页同款 AnimalSilhouette 8 帧
    // 波浪相位，ViewFlipper 轮播实现持续动画；液体色按彩色字符层规则）
    await renderWidgetCharacterFrames(read, liquidColor: widgetLiquidColor(s));
  } catch (_) {
    // 小组件同步失败不影响主流程
  }
}

/// 光栅化饮品图标为 PNG（RemoteViews 不支持 SVG；规则与预览卡 _drinkThumb
/// 一致：容器剪影按包围盒 92% 居中 + srcIn 染色，预设插画 contain 不染色）
Future<File?> _rasterizeDrinkIcon(Beverage b, {int dim = 96}) async {
  try {
    final String assetPath;
    final Color? tint;
    if (isSvgContainer(b.containerId)) {
      assetPath = svgContainerAsset(b.containerId!);
      tint = b.color;
    } else {
      final illustId = b.id.startsWith('custom_')
          ? (b.templateId ?? Beverage.fallbackIllustration(b.category))
          : b.id;
      assetPath = 'assets/images/drinks/$illustId.svg';
      tint = null;
    }
    final info = await vg.loadPicture(SvgAssetLoader(assetPath), null);
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    final box = Offset.zero & Size.square(dim.toDouble());
    if (tint == null) {
      // 预设插画：contain 等比居中
      final s = math.min(dim / info.size.width, dim / info.size.height);
      canvas.translate(
        dim / 2 - info.size.width / 2 * s,
        dim / 2 - info.size.height / 2 * s,
      );
      canvas.scale(s);
      canvas.drawPicture(info.picture);
    } else {
      // 容器剪影：图形包围盒 92% 等比居中（与 SvgContainerIcon 同规则）再整体染色
      canvas.saveLayer(box, ui.Paint());
      final m =
          await loadSvgArtMetrics(b.containerId!, info.picture, info.size);
      final bounds = m?.bounds;
      if (bounds == null || bounds.width <= 0 || bounds.height <= 0) {
        canvas.scale(dim / info.size.width, dim / info.size.height);
        canvas.drawPicture(info.picture);
      } else {
        const targetFactor = 0.92;
        final s = math.min(
          dim * targetFactor / bounds.width,
          dim * targetFactor / bounds.height,
        );
        canvas.translate(
          dim / 2 - (bounds.left + bounds.width / 2) * s,
          dim / 2 - (bounds.top + bounds.height / 2) * s,
        );
        canvas.scale(s);
        canvas.drawPicture(info.picture);
      }
      canvas.drawRect(
        box,
        ui.Paint()
          ..color = tint
          ..blendMode = BlendMode.srcIn,
      );
      canvas.restore();
    }
    final image = await rec.endRecording().toImage(dim, dim);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    info.picture.dispose();
    if (data == null) return null;
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}home_widget'
        '${Platform.pathSeparator}icon_${b.id}.png');
    await file.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List());
    return file;
  } catch (_) {
    return null;
  }
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
