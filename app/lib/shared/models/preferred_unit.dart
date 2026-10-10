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
