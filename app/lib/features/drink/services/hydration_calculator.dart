import '../../../shared/models/beverage.dart';
import '../../../shared/models/drink_entry.dart';

/// PRD §2.3 折算工具
/// PRD §2.1 当日总进度算法
class HydrationCalculator {
  HydrationCalculator._();

  /// 计算当日已喝"有效水分"
  static int sumEffective(List<DrinkEntry> entries) {
    return entries.fold<int>(0, (s, e) => s + e.effectiveMl);
  }

  /// 计算当日"原始总摄入"
  static int sumVolume(List<DrinkEntry> entries) {
    return entries.fold<int>(0, (s, e) => s + e.volumeMl);
  }

  /// 进度百分比 [0, 1]
  static double progress(List<DrinkEntry> entries, int goalMl) {
    if (goalMl <= 0) return 0;
    final v = sumEffective(entries);
    final p = v / goalMl;
    if (p < 0) return 0;
    if (p > 1) return 1;
    return p;
  }

  /// 剩余水量
  static int remaining(List<DrinkEntry> entries, int goalMl) {
    final v = sumEffective(entries);
    final r = goalMl - v;
    return r < 0 ? 0 : r;
  }

  /// 饮品折算预览
  static int previewEffectiveMl(Beverage beverage, int volumeMl) {
    return beverage.effectiveMl(volumeMl);
  }
}
