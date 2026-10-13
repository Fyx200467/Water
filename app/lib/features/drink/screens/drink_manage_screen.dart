import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/beverage.dart';
import '../../../shared/widgets/drink_illustration.dart';
import '../providers/custom_beverage_provider.dart';
import '../widgets/container_shapes.dart';
import 'drink_edit_screen.dart';

/// 添加或编辑饮品页（对标原版「饮料」页：品类胶囊筛选 + 灰底卡片列表）
///
/// 结构：
/// 1. 顶栏：左返回圆钮 + 居中标题「饮料」+ 右上青色「+添加」胶囊
/// 2. 品类胶囊（Wrap 多行）：点选后下方列表只展示该品类饮品，
///    选中胶囊渲染为该品类颜色（「所有」选中为深灰黑，对标原版）
/// 3. 列表：灰底圆角卡片，右侧显示「进水量」折算百分比；自定义饮品可点击编辑
/// 4. 底部：查看折算说明的青色文字链接
class DrinkManageScreen extends ConsumerStatefulWidget {
  const DrinkManageScreen({super.key});

  @override
  ConsumerState<DrinkManageScreen> createState() => _DrinkManageScreenState();
}

class _DrinkManageScreenState extends ConsumerState<DrinkManageScreen> {
  static const _brandCyan = Color(0xFF4DB8D8);
  static const _textDark = Color(0xFF1C1C1E);
  static const _hintGray = Color(0xFF8E8E93);

  /// 当前筛选品类（null = 所有）
  BeverageCategory? _filter;

  /// 品类胶囊短标签（对标原版：茶 / 咖啡 / 酒精…）
  String _chipLabel(BeverageCategory c) => switch (c) {
        BeverageCategory.water => '水',
        BeverageCategory.tea => '茶',
        BeverageCategory.coffee => '咖啡',
        BeverageCategory.milk => '奶茶·果汁·牛奶',
        BeverageCategory.soda => '碳酸饮料',
        BeverageCategory.soup => '汤粥',
        BeverageCategory.alcohol => '酒精',
      };

  @override
  Widget build(BuildContext context) {
    final customs = ref.watch(customBeveragesProvider);
    final homeDrinks = ref.watch(homeDrinksProvider);
    // 列表按持久化顺序渲染（拖拽/掉落结果即时反映；未登记的新饮品追加到末尾）
    final raw = [...Beverage.presets, ...customs];
    final byId = {for (final b in raw) b.id: b};
    final ordered = [
      for (final id in orderedAllIds(homeDrinks, raw))
        if (byId[id] != null) byId[id]!,
    ];
    final shown = _filter == null
        ? ordered
        : ordered.where((b) => b.category == _filter).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ---- 顶栏：返回 / 标题 / +添加 ----
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Row(
                  children: [
                    // 返回圆钮（浅灰圆底）
                    _CircleButton(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back_ios_new,
                          size: 18, color: _textDark),
                    ),
                    const Expanded(
                      child: Text(
                        '饮料',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _textDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    // 右上「+添加」青色胶囊（对标原版）
                    GestureDetector(
                      onTap: _showAddSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: _brandCyan,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.add, size: 15, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              '添加',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 3),
                            Icon(Icons.local_cafe,
                                size: 14, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ---- 品类胶囊（点选筛选；选中渲染为品类色） ----
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _CategoryChip(
                      label: '所有 ${raw.length}',
                      selected: _filter == null,
                      selectedColor: _textDark,
                      onTap: () => setState(() => _filter = null),
                    ),
                    for (final c in BeverageCategory.values)
                      _CategoryChip(
                        label: _chipLabel(c),
                        selected: _filter == c,
                        selectedColor: c.color,
                        onTap: () => setState(() => _filter = c),
                      ),
                  ],
                ),
              ),
              // ---- 列表头：进水量（右对齐小标签，对标原版） ----
              Padding(
                padding: const EdgeInsets.only(right: 76, top: 10, bottom: 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '进水量',
                    style: TextStyle(
                      color: _hintGray.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              // ---- 饮品卡片列表（按品类筛选；长按箭头图形拖拽排序，开关控制首页展示）
              // ---- 列表末尾追加「查看饮料对进水量有何影响」链接，随内容滚动、被饮品撑开 ----
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '该品类暂无饮品，点击右上「添加」创建',
                              style: TextStyle(color: _hintGray, fontSize: 14),
                            ),
                            const SizedBox(height: 16),
                            _ratioLink(),
                          ],
                        ),
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
                        itemCount: shown.length + 1,
                        onReorder: (oldIndex, newIndex) =>
                            _onReorder(oldIndex, newIndex, shown, raw),
                        proxyDecorator: (child, index, animation) =>
                            _dragProxy(child, animation),
                        itemBuilder: (ctx, i) {
                          // 末尾条目：折算说明链接（非饮品，不参与排序）
                          if (i == shown.length) {
                            return Container(
                              key: const ValueKey('ratio_footer'),
                              padding: const EdgeInsets.only(top: 4, bottom: 24),
                              child: _ratioLink(),
                            );
                          }
                          final b = shown[i];
                          final isCustom = b.id.startsWith('custom_');
                          final isWater = b.id == 'water_pure';
                          final visible = homeDrinks.isVisible(b.id);
                          return Container(
                            key: ValueKey(b.id),
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _DrinkCard(
                                    beverage: b,
                                    isCustom: isCustom,
                                    visible: visible,
                                    isWater: isWater,
                                    onToggle: isWater
                                        ? null
                                        : () => ref
                                            .read(homeDrinksProvider.notifier)
                                            .setVisible(b.id, !visible),
                                    onTap: isCustom
                                        ? () => _showEditSheet(b)
                                        : () => _showSnack(
                                            '内置饮品暂不支持编辑，可添加自定义饮品'),
                                  ),
                                ),
                                // 卡片外右侧整体箭头图形：长按浮起后上下拖动排序
                                // （水仅展示图形与其它饮品对称，不可拖动、位置固定）
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: isWater
                                      ? const _DragHandle()
                                      : ReorderableDelayedDragStartListener(
                                          index: i,
                                          child: const _DragHandle(),
                                        ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 「查看饮料对进水量有何影响 >」青色文字链接（点击弹出折算说明弹层）
  Widget _ratioLink() {
    return TextButton(
      onPressed: _showRatioDialog,
      child: const Text(
        '查看饮料对进水量\n有何影响 >',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _brandCyan,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1200)),
    );
  }

  // ---------------- 长按拖拽排序 ----------------

  /// 拖拽结束：计算新顺序（水强制置顶）并持久化；首页饮品栏实时同步
  void _onReorder(
    int oldIndex,
    int newIndex,
    List<Beverage> shown,
    List<Beverage> all,
  ) {
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    final ids = shown.map((b) => b.id).toList();
    final moved = ids.removeAt(oldIndex);
    if (moved == 'water_pure') return; // 水不参与排序（无把手，兜底）
    ids.insert(newIndex, moved);
    // 水始终置顶（仅「所有」筛选时水在列表中）
    if (ids.contains('water_pure') && ids.first != 'water_pure') {
      ids.remove('water_pure');
      ids.insert(0, 'water_pure');
    }
    ref.read(homeDrinksProvider.notifier).reorderShown(ids, all);
  }

  /// 拖拽代理：长按浮起时卡片轻微放大 + 投影
  Widget _dragProxy(Widget child, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (ctx, child) {
        final t = Curves.easeInOut.transform(animation.value);
        return Transform.scale(
          scale: 1.0 + 0.05 * t,
          child: Material(
            color: Colors.transparent,
            elevation: 8 * t,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(20),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  /// 折算说明弹层（各品类有效水分比例 + 单品特殊比例）
  void _showRatioDialog() {
    final overrides =
        Beverage.presets.where((b) => b.hydrationRatio != null).toList();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('饮料对进水量的影响',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in BeverageCategory.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(c.icon, size: 18, color: c.color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.label,
                        style: const TextStyle(
                            color: _textDark,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      overrides.any((b) => b.category == c)
                          ? '单品各异'
                          : '${(c.hydrationRatio * 100).round()}%',
                      style: TextStyle(
                        color: overrides.any((b) => b.category == c)
                            ? _hintGray
                            : c.color,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            if (overrides.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Divider(height: 1),
              const SizedBox(height: 4),
              for (final b in overrides)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(b.icon, size: 16, color: b.color),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          b.name,
                          style: const TextStyle(
                              color: _textDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${(b.effectiveRatio * 100).round()}%',
                        style: TextStyle(
                          color: b.color,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了',
                style: TextStyle(color: _brandCyan)),
          ),
        ],
      ),
    );
  }

  // ---------------- 添加 / 编辑（对标原版的全屏编辑页） ----------------

  Future<void> _showAddSheet() => Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const DrinkEditScreen()),
      );

  Future<void> _showEditSheet(Beverage b) => Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => DrinkEditScreen(existing: b)),
      );

}

// ============================================================
// 组件
// ============================================================

/// 顶部返回圆钮（浅灰圆底）
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF2F2F5),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// 品类筛选胶囊：未选中浅灰底，选中渲染为指定颜色（品类色/深灰黑）
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? selectedColor : const Color(0xFFF2F2F5),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF6B6B70),
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// 饮品卡片：灰底圆角，图标 + 名称 + 副标题，右侧进水量百分比 + 首页展示开关
class _DrinkCard extends StatelessWidget {
  const _DrinkCard({
    required this.beverage,
    required this.isCustom,
    required this.visible,
    required this.isWater,
    required this.onTap,
    this.onToggle,
  });
  final Beverage beverage;
  final bool isCustom;
  final bool visible;
  final bool isWater;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final b = beverage;
    final percent = (b.effectiveRatio * 100).round();
    return Material(
      color: const Color(0xFFF5F5F7),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              // 图标：自定义饮品用所选容器形状，内置用饮品插画
              isCustom && b.containerId != null
                  ? CustomPaint(
                      size: const Size(38, 40),
                      painter: ContainerShapePainter(
                        id: b.containerId!,
                        color: b.color,
                      ),
                    )
                  : isCustom
                      ? Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: b.color.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: DrinkIllustration(
                              beverageId: b.templateId ??
                                  Beverage.fallbackIllustration(b.category),
                              color: b.color,
                              size: 26,
                            ),
                          ),
                        )
                      : DrinkIllustration(
                          beverageId: b.id,
                          color: b.color,
                          size: 42,
                        ),
              const SizedBox(width: 14),
              // 名称 + 副标题
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1C1C1E),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${b.category.label} · ${b.defaultMl}ml',
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // 进水量百分比
              Text(
                '$percent%',
                style: TextStyle(
                  color: percent >= 0 ? const Color(0xFF8E8E93) : b.color,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              // 首页展示开关（iOS 风格：开青色/关浅灰；水无开关）
              if (!isWater) ...[
                const SizedBox(width: 10),
                Transform.scale(
                  scale: 0.82,
                  child: Switch(
                    value: visible,
                    onChanged: onToggle == null
                        ? null
                        : (_) => onToggle!(),
                    activeTrackColor: const Color(0xFF35B5D6),
                    activeThumbColor: Colors.white,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: const Color(0xFFE5E5EA),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片外右侧整体箭头图形（上箭头+下箭头组成一个整体）：
/// 长按后卡片浮起，上下拖动排序（水无此图形，固定最前）
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.keyboard_arrow_up, size: 24, color: Color(0xFFC7C7CC)),
          // 负偏移让两个箭头叠合成一个紧凑的整体图形
          Transform.translate(
            offset: const Offset(0, -10),
            child: const Icon(Icons.keyboard_arrow_down,
                size: 24, color: Color(0xFFC7C7CC)),
          ),
        ],
      ),
    );
  }
}
