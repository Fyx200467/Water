part of 'history_screen.dart';

/// 柱状图数据（valueLabel 仅当前柱显示在柱顶）
class _BarData {
  const _BarData({
    required this.label,
    required this.value,
    this.valueLabel,
    this.highlighted = false,
  });
  final String label;
  final int value;
  final String? valueLabel;
  final bool highlighted;
}

/// 「各饮品摄入量」面板的单品聚合（周期内按饮品名累加）
class _BeverageTotal {
  _BeverageTotal({required this.name, required this.category});
  final String name;
  final BeverageCategory category;
  int volumeMl = 0; // 总摄入量（实际喝入容量）
  int effectiveMl = 0; // 水份（有效进水量）
  int calories = 0; // 热量（按饮品每份 kcal × 容量折算）
}
