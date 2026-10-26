/// 饮水量单位偏好
enum PreferredUnit { ml, oz }

extension PreferredUnitX on PreferredUnit {
  String get label => switch (this) {
        PreferredUnit.ml => 'ml（毫升）',
        PreferredUnit.oz => '盎司',
      };
  String get symbol => switch (this) {
        PreferredUnit.ml => 'ml',
        PreferredUnit.oz => 'oz',
      };

  /// ml ↔ oz 转换（1 oz ≈ 29.5735 ml）
  double toMl(double value) =>
      this == PreferredUnit.ml ? value : value * 29.5735;
  double fromMl(double ml) =>
      this == PreferredUnit.ml ? ml : ml / 29.5735;
}

/// 全局当前单位（由 PreferredUnitNotifier 启动/切换时同步）。
///
/// 存储与计算恒用 ml，这里只负责「显示层」换算；通知、桌面小组件、
/// Chart Painter 等拿不到 WidgetRef 的地方也统一走这套格式化。
class UnitFormat {
  UnitFormat._();

  static PreferredUnit unit = PreferredUnit.ml;

  /// 330 → '330 ml' / '11.2 oz'；[compact] 时去掉空格（330ml / 11.2oz）
  static String volume(num ml, {bool compact = false}) {
    final v = unit.fromMl(ml.toDouble());
    final s = unit == PreferredUnit.ml ? v.round().toString() : _oneDecimal(v);
    return compact ? '$s${unit.symbol}' : '$s ${unit.symbol}';
  }

  /// 大容量智能单位：ml 模式 ≥1000 显示「升」，oz 模式统一 oz
  static String smart(num ml) {
    if (unit == PreferredUnit.ml) {
      if (ml >= 1000) return '${(ml / 1000).toStringAsFixed(1)}升';
      return '${ml.round()} ml';
    }
    return volume(ml);
  }

  /// 只返回数值文本（不含单位），供输入框回显
  static String number(num ml) {
    final v = unit.fromMl(ml.toDouble());
    return unit == PreferredUnit.ml ? v.round().toString() : _oneDecimal(v);
  }

  static String _oneDecimal(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
}
