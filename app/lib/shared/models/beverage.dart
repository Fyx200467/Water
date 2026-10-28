import 'package:flutter/material.dart';

/// PRD §2.3 饮品分类 + 水分折算比例
enum BeverageCategory {
  water('纯水', 1.00, Color(0xFF00BFDC), Icons.water_drop),
  tea('茶水类', 0.90, Color(0xFF8BC34A), Icons.emoji_food_beverage),
  coffee('咖啡类', 0.70, Color(0xFF795548), Icons.coffee),
  milk('牛奶', 0.80, Color(0xFF90A4AE), Icons.local_drink),
  milkTea('奶茶', 0.80, Color(0xFFA8723C), Icons.local_cafe),
  juice('果汁', 0.80, Color(0xFFFFB300), Icons.local_bar),
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
    this.liquidColor,
    this.hydrationRatio,
    this.templateId,
    this.animation,
    this.containerId,
    this.memberOnly = false,
    this.categoryKey,
    this.categoryName,
    this.categoryAccent,
    this.calories,
    this.caffeineMg,
    this.alcoholPercent,
  });

  final String id;
  final BeverageCategory category;
  final String name;
  final int defaultMl;
  final IconData icon;

  /// 液体颜色（对标原版每种饮品独立配色），为空时回退到分类色
  final Color? liquidColor;

  /// 单品折算比例覆盖（负值为脱水，如啤酒 -40% 白酒 -318% 红酒 -95%），为空时用分类比例
  final double? hydrationRatio;

  /// 自定义饮品的模板插画 id（预览/图标沿用该模板的 SVG artwork）
  final String? templateId;

  /// 液体动画：'bubbles' 气泡 / 'micro' 微气泡 / 'ice' 冰块 / 'rice' 悬浮米粒 / 'none' 无；为空时按模板推断（汤粥→米粒，其余→气泡）
  final String? animation;

  /// 容器图标 id（'svg:<文件名>' 对应 assets/images/containers/ 下的 SVG 剪影），为空时沿用模板插画
  final String? containerId;

  /// 会员专属：后台可配置，非会员不可记录
  final bool memberOnly;

  /// 后台分类 code / 显示名 / 分类色（后台「饮品分类」维护）。
  /// 为空时回退到本地枚举（内置预设与用户自定义饮品）。
  final String? categoryKey;
  final String? categoryName;
  final Color? categoryAccent;

  /// 分类 code（后台新增分类可能不在枚举内）
  String get categoryCode => categoryKey ?? category.name;

  /// 分类显示名（App 饮品页胶囊与卡片副标题使用）
  String get categoryLabel => categoryName ?? category.label;

  /// 分类色（筛选胶囊选中色）
  Color get categoryColor => categoryAccent ?? category.color;

  /// 当前身份是否无权使用（非会员 + 会员专属）
  bool lockedFor(bool isMember) => memberOnly && !isMember;

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
        BeverageCategory.milkTea => 'milk_tea',
        BeverageCategory.juice => 'milk_juice',
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

  // 预设营养值初始化规则（与营养选项卡页计算口径一致）：
  // 卡路里/咖啡因按每 250ml（8 盎司）计；酒精按 ABV 档位代表值
  // （淡酒 3 / 微量 4 / 低度 5 / 中度 10 / 烈 20，见 drink_nutrient_screen）
  // 用户自绘容器图标（assets/images/containers/<id>_user.svg 单色剪影，
  // 首页饮品格 / 加量页容器走 SvgContainerIcon 液体填充渲染，12 款预设全覆盖）
  static const List<Beverage> presets = [
    Beverage(id: 'water_pure', category: BeverageCategory.water, name: '纯净水', defaultMl: 250, containerId: 'svg:water_pure_user'),
    // 红茶基底：47mg 咖啡因（选项卡说明示例），无糖无卡路里
    Beverage(id: 'tea', category: BeverageCategory.tea, name: '茶', defaultMl: 250, caffeineMg: 47, containerId: 'svg:tea_user'),
    // 黑咖啡：约 5 卡 + 95mg 咖啡因
    Beverage(id: 'coffee', category: BeverageCategory.coffee, name: '咖啡', defaultMl: 250, liquidColor: Color(0xFF6B3E2E), calories: 5, caffeineMg: 95, containerId: 'svg:coffee_user'),
    // 全脂牛奶：约 155 卡，不含咖啡因
    Beverage(id: 'milk_milk', category: BeverageCategory.milk, name: '牛奶', defaultMl: 250, liquidColor: Color(0xFFC8CDD0), calories: 155, containerId: 'svg:milk_milk_user'),
    // 含糖奶茶：约 170 卡 + 45mg 咖啡因（茶汤基底）
    Beverage(id: 'milk_tea', category: BeverageCategory.milkTea, name: '奶茶', defaultMl: 500, liquidColor: Color(0xFFA8723C), calories: 170, caffeineMg: 45, containerId: 'svg:milk_tea_user'),
    // 鲜榨果汁：约 110 卡
    Beverage(id: 'milk_juice', category: BeverageCategory.juice, name: '果汁', defaultMl: 300, liquidColor: Color(0xFFFFB300), calories: 110, containerId: 'svg:milk_juice_user'),
    // 可乐类碳酸饮料：100 卡（选项卡说明示例）+ 25mg 咖啡因
    Beverage(id: 'soda', category: BeverageCategory.soda, name: '碳酸饮料', defaultMl: 330, liquidColor: Color(0xFFC9364F), calories: 100, caffeineMg: 25, containerId: 'svg:soda_user'),
    // 米粥：约 80 卡
    Beverage(id: 'soup_porridge', category: BeverageCategory.soup, name: '白粥', defaultMl: 300, liquidColor: Color(0xFFF5EFE2), calories: 80, containerId: 'svg:soup_porridge_user'),
    // 清炖鸡汤：约 35 卡
    Beverage(id: 'soup_chicken', category: BeverageCategory.soup, name: '鸡汤', defaultMl: 250, liquidColor: Color(0xFFFFB300), calories: 35, containerId: 'svg:soup_chicken_user'),
    // 啤酒 1-4% ABV（选项卡淡酒档示例「低度啤酒」）：约 110 卡
    Beverage(id: 'alcohol_beer', category: BeverageCategory.alcohol, name: '啤酒', defaultMl: 500, liquidColor: Color(0xFFFFC107), hydrationRatio: -0.40, calories: 110, alcoholPercent: 3, containerId: 'svg:alcohol_beer_user'),
    // 红酒 12-13% ABV → 中度档：约 200 卡
    Beverage(id: 'alcohol_wine', category: BeverageCategory.alcohol, name: '红酒', defaultMl: 150, liquidColor: Color(0xFFA62034), hydrationRatio: -0.95, calories: 200, alcoholPercent: 10, containerId: 'svg:alcohol_wine_user'),
    // 白酒 40%+ ABV → 烈档：约 550 卡（纯酒精热量折算每 250ml）
    Beverage(id: 'alcohol_spirits', category: BeverageCategory.alcohol, name: '白酒', defaultMl: 100, liquidColor: Color(0xFFE3E8EC), hydrationRatio: -3.18, calories: 550, alcoholPercent: 20, containerId: 'svg:alcohol_spirits_user'),
  ];

  /// PRD §2.3 内置预设容量
  static const List<int> presetVolumes = [100, 200, 300, 500, 1000];
}
