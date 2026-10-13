import 'package:flutter/material.dart';

/// PRD §2.3 饮品分类 + 水分折算比例
enum BeverageCategory {
  water('纯水', 1.00, Color(0xFF6AD7E0), Icons.water_drop),
  tea('茶水类', 0.90, Color(0xFF8BC34A), Icons.emoji_food_beverage),
  coffee('咖啡类', 0.70, Color(0xFF795548), Icons.coffee),
  milk('奶茶 / 果汁 / 牛奶', 0.80, Color(0xFFFFC107), Icons.local_drink),
  soda('碳酸饮料', 0.90, Color(0xFFC9364F), Icons.local_drink),
  soup('汤粥类', 0.85, Color(0xFFFF8A65), Icons.soup_kitchen),
  alcohol('酒类', 0.65, Color(0xFFE57373), Icons.wine_bar);

  const BeverageCategory(this.label, this.hydrationRatio, this.color, this.icon);
  final String label;
  final double hydrationRatio; // 有效水分折算比例
  final Color color;
  final IconData icon;
}

/// 单条饮品（可由后端动态下发，PRD §3.2）
class Beverage {
  const Beverage({
    required this.id,
    required this.category,
    required this.name,
    required this.defaultMl,
    this.icon = Icons.local_drink,
    this.memberOnly = false,
    this.liquidColor,
    this.hydrationRatio,
    this.templateId,
    this.animation,
    this.containerId,
    this.calories,
    this.caffeineMg,
    this.alcoholPercent,
  });

  final String id;
  final BeverageCategory category;
  final String name;
  final int defaultMl;
  final IconData icon;
  final bool memberOnly;

  /// 液体颜色（对标原版每种饮品独立配色），为空时回退到分类色
  final Color? liquidColor;

  /// 单品折算比例覆盖（负值为脱水，如啤酒 -40% 白酒 -318% 红酒 -95%），为空时用分类比例
  final double? hydrationRatio;

  /// 自定义饮品的模板插画 id（预览/图标沿用该模板的 SVG artwork）
  final String? templateId;

  /// 液体动画：'bubbles' 气泡 / 'micro' 微气泡 / 'ice' 冰块 / 'rice' 悬浮米粒 / 'none' 无；为空时按模板推断（汤粥→米粒，其余→气泡）
  final String? animation;

  /// 自定义饮品的容器图标形状 id（container_shapes.dart 目录），为空时沿用模板插画
  final String? containerId;

  /// 附加营养信息（自定义饮品编辑页维护）
  final int? calories;
  final int? caffeineMg;
  final int? alcoholPercent;

  /// 动画生效值：单品设置优先，否则按分类推断
  String get effectiveAnimation =>
      animation ??
      (category == BeverageCategory.soup ? 'rice' : 'bubbles');

  /// 分类 → 默认插画 id（无专属 artwork 时回退）
  static String fallbackIllustration(BeverageCategory c) => switch (c) {
        BeverageCategory.water => 'water_pure',
        BeverageCategory.tea => 'tea',
        BeverageCategory.coffee => 'coffee',
        BeverageCategory.milk => 'milk_milk',
        BeverageCategory.soda => 'soda',
        BeverageCategory.soup => 'soup_chicken',
        BeverageCategory.alcohol => 'alcohol_beer',
      };

  /// 显示用颜色：优先使用液体色，否则分类色
  Color get color => liquidColor ?? category.color;

  /// 容量档位：水 5 档；其他饮品统一 3 档（自定义量会永久覆盖其中一档）
  List<int> get volumes => category == BeverageCategory.water
      ? const [100, 200, 300, 500, 1000]
      : const [250, 330, 500];

  /// 实际生效的折算比例：单品覆盖优先，否则用分类比例
  double get effectiveRatio => hydrationRatio ?? category.hydrationRatio;

  /// 实际有效水分 = 容量 × 折算比例（负值为脱水，从当日总量中扣减）
  int effectiveMl(int volumeMl) => (volumeMl * effectiveRatio).round();

  static const List<Beverage> presets = [
    Beverage(id: 'water_pure', category: BeverageCategory.water, name: '纯净水', defaultMl: 250),
    Beverage(id: 'tea', category: BeverageCategory.tea, name: '茶', defaultMl: 250),
    Beverage(id: 'coffee', category: BeverageCategory.coffee, name: '咖啡', defaultMl: 250, liquidColor: Color(0xFF6B3E2E)),
    Beverage(id: 'milk_milk', category: BeverageCategory.milk, name: '牛奶', defaultMl: 250, liquidColor: Color(0xFFC8CDD0)),
    Beverage(id: 'milk_tea', category: BeverageCategory.milk, name: '奶茶', defaultMl: 500, memberOnly: true, liquidColor: Color(0xFFA8723C)),
    Beverage(id: 'milk_juice', category: BeverageCategory.milk, name: '果汁', defaultMl: 300, liquidColor: Color(0xFFFFB300)),
    Beverage(id: 'soda', category: BeverageCategory.soda, name: '碳酸饮料', defaultMl: 330, liquidColor: Color(0xFFC9364F)),
    Beverage(id: 'soup_porridge', category: BeverageCategory.soup, name: '白粥', defaultMl: 300, liquidColor: Color(0xFFF5EFE2)),
    Beverage(id: 'soup_chicken', category: BeverageCategory.soup, name: '鸡汤', defaultMl: 250, liquidColor: Color(0xFFFFB300)),
    Beverage(id: 'alcohol_beer', category: BeverageCategory.alcohol, name: '啤酒', defaultMl: 500, memberOnly: true, liquidColor: Color(0xFFFFC107), hydrationRatio: -0.40),
    Beverage(id: 'alcohol_wine', category: BeverageCategory.alcohol, name: '红酒', defaultMl: 150, memberOnly: true, liquidColor: Color(0xFFA62034), hydrationRatio: -0.95),
    Beverage(id: 'alcohol_spirits', category: BeverageCategory.alcohol, name: '白酒', defaultMl: 100, memberOnly: true, liquidColor: Color(0xFFE3E8EC), hydrationRatio: -3.18),
  ];

  /// PRD §2.3 内置预设容量
  static const List<int> presetVolumes = [100, 200, 300, 500, 1000];
}
