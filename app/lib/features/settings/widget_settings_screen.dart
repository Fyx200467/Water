import 'dart:async';
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
import '../../core/time/logical_day.dart';
import '../../core/widget/home_widget_sync.dart';
import '../characters/current_character_provider.dart';
import '../membership/membership_provider.dart';
import '../membership/membership_screen.dart';
import '../drink/providers/beverage_catalog_provider.dart';
import '../drink/providers/custom_beverage_provider.dart';
import '../drink/widgets/svg_container.dart';
import '../../shared/models/beverage.dart';
import '../../shared/models/preferred_unit.dart';
import '../../shared/widgets/drink_illustration.dart';
import '../home/providers/home_providers.dart';
import '../onboarding/widgets/animal_silhouette.dart';
import 'settings_flags.dart';
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
// 6. 开关组：彩色饮料按钮 / 彩色字符层 / 连续徽章
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
    this.drink1 = 'water_pure',
    this.vol1 = 250,
    this.drink2 = 'milk_juice',
    this.vol2 = 300,
    this.drink3 = 'soda',
    this.vol3 = 330,
    this.colorfulButtons = true,
    this.colorfulCharacter = false,
    this.followDarkMode = false,
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
  final bool followDarkMode; // 遵循深色模式规则（系统深色时强制深色底）
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
        'streakBadge': streakBadge,
      };

  static WidgetSettingsState _fromMap(Map<String, dynamic> m) =>
      WidgetSettingsState(
        colorIndex: (m['colorIndex'] as num?)?.toInt() ?? 0,
        customColor: (m['customColor'] as num?)?.toInt(),
        drink1: m['drink1'] as String? ?? 'water_pure',
        vol1: (m['vol1'] as num?)?.toInt() ?? 250,
        drink2: m['drink2'] as String? ?? 'milk_juice',
        vol2: (m['vol2'] as num?)?.toInt() ?? 300,
        drink3: m['drink3'] as String? ?? 'soda',
        vol3: (m['vol3'] as num?)?.toInt() ?? 330,
        colorfulButtons: m['colorfulButtons'] as bool? ?? true,
        colorfulCharacter: m['colorfulCharacter'] as bool? ?? false,
        followDarkMode: m['followDarkMode'] as bool? ?? false,
        streakBadge: m['streakBadge'] as bool? ?? true,
      );
}

class WidgetSettingsNotifier extends StateNotifier<WidgetSettingsState> {
  WidgetSettingsNotifier(this.ref) : super(const WidgetSettingsState()) {
    loaded = _load();
  }

  final Ref ref;

  static const _kKey = 'widget_settings';

  /// 磁盘加载完成信号：加载完成前 state 是默认值（milk_juice 等），
  /// 冷启动小组件同步必须先等它，否则会把默认饮料格推上桌面
  late final Future<void> loaded;

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

  /// 外部数据（自定义饮品增删改）变更后主动刷新桌面小组件。
  /// 走 notifier 的 ref（Provider 级生命周期），避免页面销毁后
  /// 继续使用已释放的 WidgetRef
  Future<void> refreshWidget() => syncWidgetFromSettings(ref.read);
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
    ref.watch(preferredUnitProvider);
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
                  title: '遵循深色模式',
                  subtitle: '系统处于深色模式时，小组件背景自动切换为深色',
                  value: s.followDarkMode,
                  onChanged: (v) => _mutate((x) => x.copyWith(followDarkMode: v)),
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
    // 预览卡底色：与桌面推送同规则（含「遵循深色模式规则」的深色强制，
    // 详见 effectiveWidgetThemeColor 注释），保证 App 内所见 = 桌面所见
    final themeColor = effectiveWidgetThemeColor(s);
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
      (_findBeverage(s.drink1), s.vol1),
      (_findBeverage(s.drink2), s.vol2),
      (_findBeverage(s.drink3), s.vol3),
    ];
    return Container(
      height: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: themeColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: themeColor.computeLuminance() > 0.55
                ? const Color(0xFFECECEF)
                : Colors.transparent),
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
                for (final (b, vol) in drinks) _widgetDrinkTile(b, vol, s),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Beverage _findBeverage(String id) {
    final all = ref.read(beverageLibraryProvider);
    return all.firstWhere((b) => b.id == id, orElse: () => all.first);
  }

  /// 预览卡内单个饮料格：容量/名称 + 灰底圆角容器（容量按槽位取，
  /// 文案与桌面同一套 tileMlLabel：1000→1L、1500→1.5L）
  Widget _widgetDrinkTile(Beverage b, int vol, WidgetSettingsState s) {
    // 格底/文字深浅与桌面同规则：彩色按钮染「实际生效底色」（含深色
    // 强制）；容量/名称落在卡面上，深浅随卡面亮度（桌面 dark_text 同源）
    final themeColor = effectiveWidgetThemeColor(s);
    final onDark = themeColor.computeLuminance() <= 0.55;
    final tileColor = s.colorfulButtons ? themeColor : const Color(0xFFF1F1F4);
    final textMain = onDark ? Colors.white : _textDark;
    final textSub = onDark ? const Color(0xB3FFFFFF) : _textGray;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(tileMlLabel(vol),
                style: TextStyle(
                    color: textMain,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 1),
            Text(b.name, style: TextStyle(color: textSub, fontSize: 11)),
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
    if (hasContainerIcon(b.containerId)) {
      return SvgContainerIcon(
          containerId: b.containerId!,
          color: b.color,
          fillRatio: 0.9, // 液体风格：液体占杯身 90%（全局统一）
          size: size);
    }
    final illustId = b.id.startsWith('custom_') ||
            !Beverage.presets.any((p) => p.id == b.id)
        ? (b.templateId ?? Beverage.fallbackIllustration(b.category))
        : b.id;
    return DrinkIllustration(beverageId: illustId, color: b.color, size: size);
  }

  /// 目标容量显示（跟随全局测量单位）
  String _goalLabel(int ml) => UnitFormat.smart(ml);

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
            Text('${b.name}, ${UnitFormat.volume(ml, compact: true)}',
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
    final all = ref.read(beverageLibraryProvider);
    final isMember = ref.read(membershipProvider).isMember;
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
                            trailing: b.lockedFor(isMember)
                                ? const Icon(Icons.lock,
                                    size: 16, color: Color(0xFFB98A2E))
                                : const Icon(Icons.chevron_right,
                                    color: Color(0xFFC7C7CC)),
                            onTap: () async {
                              if (b.lockedFor(isMember)) {
                                final unlocked = await ensureMember(context, ref,
                                    feature: '会员专属饮品「${b.name}」');
                                if (!unlocked || !ctx.mounted) return;
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
                          label: Text(UnitFormat.volume(v, compact: true)),
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
    // 会员权益：自定义主题色属于「专属小组件」
    if (!await ensureMember(context, ref, feature: '专属小组件')) return;
    if (!mounted) return;
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
    // 补渲必须重读当前设置：渲染期间用户可能改了主题色/彩色字符层，
    // 复用本次入参的 liquidColor 会把旧色帧再推上桌面
    return renderWidgetCharacterFrames(read,
        liquidColor: widgetLiquidColor(read(widgetSettingsProvider)));
  }
}

Future<void> _renderFramesOnce(
  Reader read, {
  required Color liquidColor,
}) async {
  final progress = read(dailyProgressProvider);
  final characterId = read(currentCharacterProvider);
  // 帧签名：同角色 + 同液体色 + 同填充档位（0.5% 步进）+ 同达标态时
  // 16 帧画面完全一致，直接复用已有帧跳过渲染——设置页连续开关
  // （徽章/彩色按钮等不影响画面的项）只剩数据推送，桌面即时刷新
  final sig = '$characterId|${liquidColor.toARGB32().toSigned(32)}|'
      '${(progress.progress.clamp(0.0, 1.0) * 200).round()}|${progress.isComplete}';
  final savedSig = await HomeWidget.getWidgetData<String>('character_frames_sig');
  if (savedSig == sig) return;
  var rendered = 0;
  try {
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
        // 100dp 角色在 2x 屏上约 260px，2 倍像素足够清晰；16/176 帧都要
        // 逐张渲染，3 倍会让「改液体色」等十几秒才上桌（用户以为没生效）
        logicalSize: const ui.Size(128, 128),
        pixelRatio: 2,
      );
      path ??= await HomeWidget.getWidgetData<String>(key);
      if (path != null && path.isNotEmpty) {
        await HomeWidget.saveWidgetData<String>(key, path);
        rendered++;
        if (i == 0) {
          // 新液体色先上桌：其余 15 帧暂用第 0 帧占位并立即刷新，
          // 之后逐帧回填相位（桌面同一时间只有一种液色，不会闪旧色）
          for (var j = 1; j < kWidgetFrameCount; j++) {
            await HomeWidget.saveWidgetData<String>('character_frame_$j', path);
          }
          await HomeWidget.updateWidget(
            name: 'WaterLlamaWidgetProvider',
            androidName: 'WaterLlamaWidgetProvider',
          );
        }
      }
    }
  } catch (_) {
    // 帧渲染失败静默跳过（下次数据变化同步时自动补上）
  }
  // 签名只在**真的渲出多帧**时才落盘：headless 引擎（小组件后台录入）
  // 无 implicitView，渲染必抛错——此前无条件写签名会让此后所有同步都
  // 命中「签名未变」直接跳过，动画帧永久停在旧画面
  if (rendered >= 2) {
    await HomeWidget.saveWidgetData<String>('character_frames_sig', sig);
  }
  // updateWidget 必须无条件执行：小组件后台录入跑在 headless 引擎里，
  // 帧渲染必然抛错（无 implicitView），若 updateWidget 放在 try 内则
  // 会被跳过——数据虽已写入但桌面 RemoteViews 不重绘，数字永远不更新
  await HomeWidget.updateWidget(
    name: 'WaterLlamaWidgetProvider',
    androidName: 'WaterLlamaWidgetProvider',
  );
  // 等级帧最后维护（数字/动画先行上桌，不被 88 张渲染阻塞；
  // 签名未变秒回，仅首装/角色或液体色变化时重渲）
  try {
    await _renderLevelFrames(read,
        characterId: characterId, liquidColor: liquidColor);
  } catch (_) {
    // 静默：等级帧缺失时原生点按退回旧单帧/无液面更新，下次同步补上
  }
}

/// 静态填充等级帧：0..100% 每 10% 一档 × 16 个波浪相位共 176 张。
/// 原生快捷录入（QuickAddReceiver）跑在 vivo 冻结窗口内、无法执行 Dart
/// 渲染——点按后由原生按新百分比就近取档，16 相位 1:1 写入动画帧槽位，
/// ViewFlipper 以同款 100ms/帧 轮播：动画流畅不中断、液面即时到新档位；
/// 下次 Dart 同步重渲当前填充态动画自动恢复。
/// 角色/液体色不变则复用（签名比对，避免每次同步重渲）
Future<void> _renderLevelFrames(
  Reader read, {
  required String characterId,
  required Color liquidColor,
}) async {
  final sig = '$characterId|${liquidColor.toARGB32().toSigned(32)}|v3';
  final saved = await HomeWidget.getWidgetData<String>('character_levels_sig');
  if (saved == sig) return;
  var rendered = 0;
  for (var pct = 0; pct <= 100; pct += 10) {
    for (var phase = 0; phase < 16; phase++) {
      final key = 'character_level_${pct}_$phase';
      var path = await HomeWidget.renderFlutterWidget(
        AnimalSilhouette(
          animalId: characterId,
          fillRatio: pct / 100,
          accentColor: liquidColor,
          solidFillColor: liquidColor,
          size: 128,
          phase: phase / 16,
          fullArt: pct >= 100,
        ),
        key: key,
        logicalSize: const ui.Size(128, 128),
        pixelRatio: 2, // 与动画帧同倍率：176 帧逐张渲染，3 倍会慢一倍以上
      );
      path ??= await HomeWidget.getWidgetData<String>(key);
      if (path != null && path.isNotEmpty) {
        await HomeWidget.saveWidgetData<String>(key, path);
        rendered++;
      }
    }
  }
  // 与动画帧同理：只有真正渲出绝大部分档位才落签名，否则 headless
  // 引擎下的失败会被签名「记住」导致等级帧永久缺失
  if (rendered >= 160) {
    await HomeWidget.saveWidgetData<String>('character_levels_sig', sig);
  }
}

/// 同步防交错：连续快速改设置时合并请求（渲染/写键交错会产生脏数据）
bool _syncBusy = false;
bool _syncPending = false;

/// 组装小组件数据并刷新：饮料格/主题色/徽章/格底色来自小组件设置
/// （与预览卡同构）；今日合计/目标/连续天数默认读当前状态，
/// 可用参数覆盖（清除数据等重置场景）
///
/// 响应速度关键：数据推送（数字/颜色/饮料格）走同步锁串行执行，
/// 完成后立即 updateWidget 上桌；角色动画帧渲染（16/176 帧，可达数秒）
/// 不占用锁、后台执行——连续调整设置时每次数据都即时上桌，帧由
/// renderWidgetCharacterFrames 自身的 pending 机制合并补渲
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
  unawaited(renderWidgetCharacterFrames(read,
      liquidColor: widgetLiquidColor(read(widgetSettingsProvider))));
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

/// 小组件卡面实际生效底色：预览卡与桌面推送同规则——
/// 「遵循深色模式规则」开启且系统处于深色时**强制深色底**（无论所选
/// 主题色为何），否则选了非白主题色时染主题色、默认白底。
/// 此前只有桌面推送做深色强制、预览卡直接用所选色，系统深色模式下
/// 出现「App 内改颜色、桌面永远不变」的观感错位
Color effectiveWidgetThemeColor(WidgetSettingsState s, {bool? systemDark}) {
  final dark = systemDark ??
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
  if (s.followDarkMode && dark) return const Color(0xFF1C1C22);
  final colorful =
      s.colorIndex != 0 || (s.colorIndex == -1 && s.customColor != null);
  return colorful ? s.themeColor : const Color(0xFFFFFFFF);
}

Future<void> _syncWidgetFromSettingsOnce(
  Reader read, {
  int? todayMl,
  int? goalMl,
  int? streakDays,
}) async {
  try {
    // 冷启动竞态防护：等小组件设置与自定义饮品都从磁盘加载完成再读
    // （此前 1s 定时器同步可能跑在加载前，用默认饮料格覆盖桌面）
    await read(widgetSettingsProvider.notifier).loaded;
    await read(customBeveragesProvider.notifier).loaded;
    // 用户档案加载完成再判初始化态（磁盘异步读，完成前 state 为 null，
    // 不等会把已初始化误判为未初始化 → 小组件被错误锁录入）
    await read(profileProvider.notifier).loaded;
    final s = read(widgetSettingsProvider);
    final progress = read(dailyProgressProvider);
    // 未完成初始化引导（无用户档案）→ 小组件只展示不可录入：
    // 录入数值强制 0 + 原生闸门键 false（详见 syncHomeWidget 注释）
    final recordEnabled = read(profileProvider) != null;
    // 数据文本/饮料格先行推送（不等帧渲染，录入后桌面数字即时更新）
    final slots = [(s.drink1, s.vol1), (s.drink2, s.vol2), (s.drink3, s.vol3)];
    final all = read(beverageLibraryProvider);
    final beverages = [
      for (final (id, _) in slots)
        all.firstWhere((x) => x.id == id, orElse: () => all.first)
    ];
    // 三格图标并行光栅化（命中缓存时近乎零开销）
    final icons =
        await Future.wait([for (final b in beverages) _rasterizeDrinkIcon(b)]);
    final drinks = <WidgetDrinkData>[
      for (var i = 0; i < slots.length; i++)
        WidgetDrinkData(
            ml: slots[i].$2,
            name: beverages[i].name,
            id: slots[i].$1, // 原生点按队列随条目携带，补录不认错饮品
            // 折算后水量：原生点按累加/百分比用它，与 App 内 sumEffective 口径一致
            effectiveMl: beverages[i].effectiveMl(slots[i].$2),
            iconFile: icons[i]),
    ];
    // 连续徽章：streak 已把「今天」纳入当且仅当今天已有记录；原生点按
    // 首笔时按 anchor 判断该 +1 还是断签重置（避免隔天没喝水也照样 +1）
    final streakAsync = read(checkinDaysProvider);
    final streak = streakDays ?? streakAsync.asData?.value ?? 0;
    final today = LogicalDay.today();
    final hasTodayEntry =
        read(todayEntriesProvider).any((e) => LogicalDay.sameDay(e.drankAt, today));
    // streak 还没算出来时不要下发 anchor：否则会把「昨天有记录」误写成
    // 空 → 原生点按把连续天数重置为 1
    final streakKnown = streakDays != null || streakAsync.hasValue;
    final streakAnchor = !streakKnown
        ? null
        : hasTodayEntry
            ? LogicalDay.keyString(today)
            : (streak > 0
                ? LogicalDay.keyString(today.subtract(const Duration(days: 1)))
                : '');
    // 主题色：与预览卡同规则（「遵循深色模式规则」+ 系统深色 → 强制
    // 深色底，详见 effectiveWidgetThemeColor 注释）。恒定有值：默认
    // 白底也显式推白色，行为与 -1 相同且省去空值分支
    final themeColor = effectiveWidgetThemeColor(s);
    await syncHomeWidget(
      todayMl: todayMl ?? progress.totalEffectiveMl,
      goalMl: goalMl ?? progress.goalMl,
      streakDays: streak,
      themeColor: themeColor,
      showStreak: s.streakBadge,
      // 必须转有符号 32 位：白色 0xFFFFFFFF 按无符号存进去原生只会读成
      // -1，而 -1 曾是「默认灰底」哨兵 → 白底主题下彩色按钮永远不生效
      tileColor: s.colorfulButtons ? themeColor.toARGB32().toSigned(32) : -2,
      drinks: drinks,
      recordEnabled: recordEnabled,
      resetMinutes: LogicalDay.resetMinutes,
      streakAnchor: streakAnchor,
      widgetSounds: SettingsFlags.instance.widgetSounds,
    );
    // 角色动画帧由 syncWidgetFromSettings 在数据推送完成后异步补推
    // （不阻塞数据同步锁，见其函数注释）
  } catch (_) {
    // 小组件同步失败不影响主流程
  }
}

/// 饮品图标 PNG 缓存：id → (签名, 文件)。签名 = 容器/插画 id + 液体色，
/// 未变化且文件仍在时直接复用，避免每次同步重复 SVG 解析 + 光栅化
/// （设置页每次调整都要推 3 张图标，无缓存时显著拖慢上桌速度）
final Map<String, (String, File)> _drinkIconCache = {};

/// 光栅化饮品图标为 PNG（RemoteViews 不支持 SVG；规则与预览卡 _drinkThumb
/// 一致：容器剪影按包围盒 92% 居中 + srcIn 染色，预设插画 contain 不染色）
Future<File?> _rasterizeDrinkIcon(Beverage b, {int dim = 96}) async {
  // 云端图标需联网、桌面图标光栅化不动网络：统一回退到分类插画
  final illustId = b.id.startsWith('custom_') ||
          !Beverage.presets.any((p) => p.id == b.id)
      ? (b.templateId ?? Beverage.fallbackIllustration(b.category))
      : b.id;
  final sig = isSvgContainer(b.containerId)
      ? '${b.containerId}|${b.color.toARGB32().toSigned(32)}'
      : 'illust|$illustId';
  final cached = _drinkIconCache[b.id];
  if (cached != null && cached.$1 == sig && cached.$2.existsSync()) {
    return cached.$2;
  }
  try {
    final String assetPath;
    final Color? tint;
    if (isSvgContainer(b.containerId)) {
      assetPath = svgContainerAsset(b.containerId!);
      tint = b.color;
    } else {
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
      // 变换只作用于剪影绘制：srcIn 染色矩形必须在恒等坐标系铺满整个
      // saveLayer（box 尺寸是缩放后的 viewBox 单位，若带着 92% 缩放画，
      // 矩形只落在 viewBox 左上角、剪影完全染不上色 → 黑色剪影）
      canvas.saveLayer(box, ui.Paint());
      canvas.save();
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
      canvas.restore();
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
    _drinkIconCache[b.id] = (sig, file);
    return file;
  } catch (_) {
    return null;
  }
}

// StateNotifier 内访问 storage 的辅助（避开构造参数改动）
