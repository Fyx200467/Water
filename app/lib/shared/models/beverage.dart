import 'package:flutter/material.dart';

/// PRD §2.3 饮品分类 + 水分折算比例
enum BeverageCategory {
  water('纯水 / 矿泉水', 1.00, Color(0xFF6AD7E0), Icons.water_drop),
  tea('茶水类', 0.90, Color(0xFF8BC34A), Icons.emoji_food_beverage),
  coffee('咖啡类', 0.70, Color(0xFF795548), Icons.coffee),
  milk('奶茶 / 果汁 / 牛奶', 0.80, Color(0xFFFFC107), Icons.local_drink),
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
  });

  final String id;
  final BeverageCategory category;
  final String name;
  final int defaultMl;
  final IconData icon;
  final bool memberOnly;

  /// 实际有效水分 = 容量 × 折算比例
  /// 酒类按 PRD §2.3 不贡献目标进度
  int effectiveMl(int volumeMl) => (volumeMl * category.hydrationRatio).round();

  static const List<Beverage> presets = [
    Beverage(id: 'water_pure', category: BeverageCategory.water, name: '纯净水', defaultMl: 250),
    Beverage(id: 'water_mineral', category: BeverageCategory.water, name: '矿泉水', defaultMl: 330),
    Beverage(id: 'water_cold', category: BeverageCategory.water, name: '凉白开', defaultMl: 250),
    Beverage(id: 'tea_green', category: BeverageCategory.tea, name: '绿茶', defaultMl: 250),
    Beverage(id: 'tea_black', category: BeverageCategory.tea, name: '红茶', defaultMl: 250),
    Beverage(id: 'tea_herbal', category: BeverageCategory.tea, name: '花茶', defaultMl: 250),
    Beverage(id: 'coffee_americano', category: BeverageCategory.coffee, name: '美式', defaultMl: 250),
    Beverage(id: 'coffee_latte', category: BeverageCategory.coffee, name: '拿铁', defaultMl: 350),
    Beverage(id: 'milk_milk', category: BeverageCategory.milk, name: '牛奶', defaultMl: 250),
    Beverage(id: 'milk_tea', category: BeverageCategory.milk, name: '奶茶', defaultMl: 500, memberOnly: true),
    Beverage(id: 'milk_juice', category: BeverageCategory.milk, name: '果汁', defaultMl: 300),
    Beverage(id: 'soup_porridge', category: BeverageCategory.soup, name: '白粥', defaultMl: 300),
    Beverage(id: 'soup_chicken', category: BeverageCategory.soup, name: '鸡汤', defaultMl: 250),
    Beverage(id: 'alcohol_beer', category: BeverageCategory.alcohol, name: '啤酒', defaultMl: 500, memberOnly: true),
    Beverage(id: 'alcohol_wine', category: BeverageCategory.alcohol, name: '红酒', defaultMl: 150, memberOnly: true),
  ];

  /// PRD §2.3 内置预设容量
  static const List<int> presetVolumes = [100, 200, 300, 500, 1000];
}
