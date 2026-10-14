import 'package:flutter/material.dart';

import '../../../shared/widgets/drink_illustration.dart';
import '../widgets/liquid_preview.dart';
import '../widgets/svg_container.dart';

/// 营养选项滚轮页（对标原版卡路里 / 咖啡因 / 酒精三个选项卡全屏页）：
/// 整页可滚动 = 动态液体预览 + 居中大标题 + 主题色滚轮选择器 + 说明文字，
/// 底部悬浮「取消 / 应用」胶囊。应用返回选定值（int?），取消返回 null 不改动状态。
///
/// 返回值语义：
/// - 卡路里：null = 无，数值 = 每 250ml 卡数
/// - 咖啡因：null = 无，数值 = 每 250ml 咖啡因 mg 数
/// - 酒精：null = 无，数值 = 档位代表酒精度（ABV %）
enum NutrientTab { calories, caffeine, alcohol }

class DrinkNutrientScreen extends StatefulWidget {
  const DrinkNutrientScreen({
    super.key,
    required this.tab,
    required this.color,
    required this.liquidColor,
    required this.animationKey,
    this.containerId,
    this.templateId,
    this.initial,
  });

  final NutrientTab tab;

  /// 滚轮主题色（卡路里橙 / 咖啡因棕 / 酒精紫）
  final Color color;

  // 顶部预览参数：SVG 容器动态液体，老数据无容器时回退模板插画
  final String? containerId;
  final String? templateId;
  final Color liquidColor;
  final String animationKey;

  /// 初始值（与返回值同语义；null = 无）
  final int? initial;

  @override
  State<DrinkNutrientScreen> createState() => _DrinkNutrientScreenState();
}

class _DrinkNutrientScreenState extends State<DrinkNutrientScreen> {
  static const _textDark = Color(0xFF1C1C1E);
  static const _explainDark = Color(0xFF333333);
  static const _pillGray = Color(0xFFF4F4F6);
  static const _pillTextGray = Color(0xFF6D6D72);
  static const _pillDark = Color(0xFF1F2733);

  static const _itemExtent = 66.0;

  /// 酒精五档（标签与代表 ABV% 按档位区间一一对应；反查按区间映射回档位）
  static const _alcoholLabels = <String>[
    '无',
    '淡酒 1-4% 酒精度为',
    '微量 4-5% 酒精度为',
    '低度 5-6% 酒精度为',
    '中度 6-15% 酒精度为',
    '烈 15%+ 酒精度为',
  ];
  static const _alcoholValues = <int?>[null, 3, 4, 5, 10, 20];

  static int _alcoholIndexFor(int? v) {
    if (v == null) return 0;
    if (v < 4) return 1;
    if (v < 5) return 2;
    if (v < 6) return 3;
    if (v < 15) return 4;
    return 5;
  }

  late final FixedExtentScrollController _ctrl;
  late int _index;

  int get _itemCount => switch (widget.tab) {
        NutrientTab.calories => 1001,
        NutrientTab.caffeine => 201,
        NutrientTab.alcohol => _alcoholLabels.length,
      };

  String _label(int i) => switch (widget.tab) {
        NutrientTab.calories => i == 0 ? '无' : '$i',
        NutrientTab.caffeine => i == 0 ? '无' : '${i}mg',
        NutrientTab.alcohol => _alcoholLabels[i],
      };

  /// 选中字号基数：数字页大、酒精分类文本略小（保证长文本单行）
  double get _baseFontSize => widget.tab == NutrientTab.alcohol ? 20.0 : 24.0;

  String get _title => switch (widget.tab) {
        NutrientTab.calories => '卡路里',
        NutrientTab.caffeine => '咖啡因',
        NutrientTab.alcohol => '酒精',
      };

  /// 说明文字（对标原版逐字抄录）
  String get _explanation => switch (widget.tab) {
        NutrientTab.calories =>
          '对于含有卡路里的饮料，卡路里含量以每 8 盎司（250 毫升）计算。\n例如：碳酸饮料 - 100 卡路里，这意味着你每喝 8 盎司（250 毫升）汽水就会含有 100 卡路里。',
        NutrientTab.caffeine =>
          '对于含咖啡因的饮料，按每 250ml（8盎司）中的咖啡因含量（毫克）计算。\n例如：红茶 - 47 毫克咖啡因，这意味着你每喝下 250ml（8 盎司）就会摄入 47 毫克咖啡因。',
        NutrientTab.alcohol =>
          '按照通用体系，酒精摄入量通过计算你所饮用的标准杯数来测定。\n酒精浓度按酒中含乙醇的体积百分比 (ABV) 进行分类。\n\n'
              '淡酒 1-4% 酒精度为\n例如：低度啤酒\n1 标准杯 = 12 盎司（355 毫升）\n\n'
              '微量 4-5% 酒精度为\n例如：莫吉托, 金汤力\n1 标准杯 = 8 盎司（250 毫升）\n\n'
              '低度 5-6% 酒精度为\n例如：代基里鸡尾酒, 含羞草鸡尾酒\n1 标准杯 = 5 盎司（150 毫升）\n\n'
              '中度 6-15% 酒精度为\n示例：啤酒、葡萄酒\n1 标准杯 = 4 盎司（125 毫升）\n\n'
              '烈 15%+ 酒精度为\n示例：杜松子酒、威士忌\n1 标准杯 = 1.5 盎司（50 毫升）',
      };

  @override
  void initState() {
    super.initState();
    _index = switch (widget.tab) {
      NutrientTab.calories => (widget.initial ?? 0).clamp(0, 1000),
      NutrientTab.caffeine => (widget.initial ?? 0).clamp(0, 200),
      NutrientTab.alcohol => _alcoholIndexFor(widget.initial),
    };
    _ctrl = FixedExtentScrollController(initialItem: _index);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 应用：按选项卡返回选定值（0 = 无 → null）
  int? get _result => switch (widget.tab) {
        NutrientTab.calories => _index == 0 ? null : _index,
        NutrientTab.caffeine => _index == 0 ? null : _index,
        NutrientTab.alcohol => _alcoholValues[_index],
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              // 底部留白避开悬浮胶囊；酒精页长文案可整页滚动（对标原版）
              padding: const EdgeInsets.only(bottom: 120),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 205,
                    child: Center(child: _buildPreview()),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _title,
                    style: const TextStyle(
                      color: _textDark,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildWheel(),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      _explanation,
                      style: const TextStyle(
                        color: _explainDark,
                        fontSize: 15,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _pill('取消', _pillGray, _pillTextGray,
                    () => Navigator.pop(context)),
                const SizedBox(width: 14),
                _pill('应用', _pillDark, Colors.white,
                    () => Navigator.pop(context, _result)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部预览：SVG 容器动态液体；老数据无容器时回退模板插画
  Widget _buildPreview() {
    final id = widget.containerId;
    if (id != null && isSvgContainer(id)) {
      return LiquidPreview(
        containerId: id,
        color: widget.liquidColor,
        animation: widget.animationKey,
        width: 150,
        height: 195,
      );
    }
    final tid = widget.templateId;
    if (tid != null) {
      return DrinkIllustration(
        beverageId: tid,
        color: widget.liquidColor,
        size: 150,
      );
    }
    return const SizedBox(width: 150, height: 195);
  }

  /// 滚轮：主题色浅底圆角高亮条置底 + 随滚动连续缩放/淡出的选项行
  Widget _buildWheel() {
    return SizedBox(
      height: _itemExtent * 3,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: _itemExtent - 4,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: _ctrl,
            itemExtent: _itemExtent,
            perspective: 0.0001, // 近似平面滚轮，无 3D 卷曲（对标原版）
            diameterRatio: 50,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (i) => _index = i,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: _itemCount,
              builder: (context, index) => _WheelItem(
                controller: _ctrl,
                index: index,
                label: _label(index),
                color: widget.color,
                itemExtent: _itemExtent,
                baseFontSize: _baseFontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color background, Color foreground,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// 滚轮选项行：逐项监听滚轮位置，按与中心距离连续缩放字号与透明度，
/// 选中行主题色加粗最大，相邻行淡色略小
class _WheelItem extends StatelessWidget {
  const _WheelItem({
    required this.controller,
    required this.index,
    required this.label,
    required this.color,
    required this.itemExtent,
    required this.baseFontSize,
  });

  final FixedExtentScrollController controller;
  final int index;
  final String label;
  final Color color;
  final double itemExtent;
  final double baseFontSize;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final center = controller.hasClients
            ? controller.offset / itemExtent
            : controller.initialItem.toDouble();
        final dist = ((index - center).abs()).clamp(0.0, 1.0).toDouble();
        final sel = 1.0 - dist;
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Opacity(
              opacity: 0.32 + 0.68 * sel,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: baseFontSize + 6 * sel,
                  fontWeight: sel > 0.5 ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
