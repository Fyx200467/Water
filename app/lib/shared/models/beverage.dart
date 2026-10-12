import 'package:flutter/material.dart';

/// PRD §2.3 饮品分类 + 水分折算比例
enum BeverageCategory {
  water('纯水', 1.00, Color(0xFF6AD7E0), Icons.water_drop),
  tea('茶水类', 0.90, Color(0xFF8BC34A), Icons.emoji_food_beverage),
  coffee('咖啡类', 0.70, Color(0xFF795548), Icons.coffee),
  milk('奶茶 / 果汁 / 牛奶', 0.80, Color(0xFFFFC107), Icons.local_drink),
  soda('碳酸饮料', 0.90, Color(0xFFC9364F), Icons.local_drink),
  soup('汤粥类', 0.85, Color(0xFFFF8A65), Icons.soup_kitchen),
  alcohol('酒类', 0.00, Color(0xFFE57373), Icons.wine_bar);

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
  });

  final String id;
  final BeverageCategory category;
  final String name;
  final int defaultMl;
  final IconData icon;
  final bool memberOnly;

  /// 液体颜色（对标原版每种饮品独立配色），为空时回退到分类色
  final Color? liquidColor;

  /// 显示用颜色：优先使用液体色，否则分类色
  Color get color => liquidColor ?? category.color;

  /// 实际有效水分 = 容量 × 折算比例
  /// 酒类按 PRD §2.3 不贡献目标进度
  int effectiveMl(int volumeMl) => (volumeMl * category.hydrationRatio).round();

  static const List<Beverage> presets = [
    Beverage(id: 'water_pure', category: BeverageCategory.water, name: '纯净水', defaultMl: 250),
    Beverage(id: 'tea', category: BeverageCategory.tea, name: '茶', defaultMl: 250),
    Beverage(id: 'coffee', category: BeverageCategory.coffee, name: '咖啡', defaultMl: 250, liquidColor: Color(0xFF6B3E2E)),
    Beverage(id: 'milk_milk', category: BeverageCategory.milk, name: '牛奶', defaultMl: 250, liquidColor: Color(0xFFC8CDD0)),
    Beverage(id: 'milk_tea', category: BeverageCategory.milk, name: '奶茶', defaultMl: 500, memberOnly: true, liquidColor: Color(0xFFA8723C)),
    Beverage(id: 'milk_juice', category: BeverageCategory.milk, name: '果汁', defaultMl: 300, liquidColor: Color(0xFFFFB300)),
    Beverage(id: 'soda', category: BeverageCategory.soda, name: '碳酸饮料', defaultMl: 330, liquidColor: Color(0xFFC9364F)),
    Beverage(id: 'soup_porridge', category: BeverageCategory.soup, name: '白粥', defaultMl: 300, liquidColor: Color(0xFFF0D9A8)),
    Beverage(id: 'soup_chicken', category: BeverageCategory.soup, name: '鸡汤', defaultMl: 250, liquidColor: Color(0xFFFFB300)),
    Beverage(id: 'alcohol_beer', category: BeverageCategory.alcohol, name: '啤酒', defaultMl: 500, memberOnly: true, liquidColor: Color(0xFFFFC107)),
    Beverage(id: 'alcohol_wine', category: BeverageCategory.alcohol, name: '红酒', defaultMl: 150, memberOnly: true, liquidColor: Color(0xFFA62034)),
    Beverage(id: 'alcohol_spirits', category: BeverageCategory.alcohol, name: '白酒', defaultMl: 100, memberOnly: true, liquidColor: Color(0xFFE3E8EC)),
  ];

  /// PRD §2.3 内置预设容量
  static const List<int> presetVolumes = [100, 200, 300, 500, 1000];
}
