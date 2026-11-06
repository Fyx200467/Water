import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widget/home_widget_sync.dart';
import '../characters/current_character_provider.dart';
import '../membership/membership_provider.dart';
import '../membership/membership_screen.dart';
import '../drink/providers/beverage_catalog_provider.dart';
import '../drink/widgets/svg_container.dart';
import '../../shared/models/beverage.dart';
import '../../shared/models/preferred_unit.dart';
import '../../shared/widgets/app_back_button.dart';
import '../../shared/widgets/app_switch.dart';
import '../../shared/widgets/drink_illustration.dart';
import '../home/providers/home_providers.dart';
import '../onboarding/widgets/animal_silhouette.dart';
import '../stats/providers/stats_providers.dart';
import '../../../core/widget/widget_settings_provider.dart';

export '../../../core/widget/widget_settings_provider.dart';
export '../../../app/widget_sync_service.dart';

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

  Widget _backButton() => const Align(
        alignment: Alignment.centerLeft,
        child: AppBackButton(),
      );

  // ---------------- 预览卡 ----------------

  Widget _previewCard(WidgetSettingsState s) {
    final progress = ref.watch(dailyProgressProvider);
    final checkin = ref.watch(checkinDaysProvider).asData?.value ?? 0;
    final currentChar = ref.watch(effectiveCurrentCharacterProvider);

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
            AppSwitch(value: value, onChanged: onChanged),
          ],
        ),
      );

  // ---------------- 自定义颜色 ----------------

  Future<void> _pickCustomColor() async {
    // 自定义主题色对所有用户开放（「专属小组件」已不再作为会员权益）
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
