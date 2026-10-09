import 'package:flutter_test/flutter_test.dart';
import 'package:water_llama/features/drink/services/hydration_calculator.dart';
import 'package:water_llama/shared/models/beverage.dart';
import 'package:water_llama/shared/models/drink_entry.dart';
import 'package:water_llama/shared/models/user_profile.dart';

void main() {
  group('PRD §2.1 饮水目标算法', () {
    test('男性 65kg / 170cm / 25岁 / 中等活动量', () {
      final p = UserProfile.create(
        gender: Gender.male,
        weightKg: 65,
        heightCm: 170,
        age: 25,
        activityLevel: ActivityLevel.medium,
      );
      // 65*35 + 350 - 0 (height<=175) = 2625 -> 取整到 50ml 倍数 -> 2650
      expect(p.dailyGoalMl, 2650);
    });

    test('女性 50kg / 165cm / 30岁 / 低活动量', () {
      final p = UserProfile.create(
        gender: Gender.female,
        weightKg: 50,
        heightCm: 165,
        age: 30,
        activityLevel: ActivityLevel.low,
      );
      // 50*35 *0.9 = 1575 -> 1600 (50ml 倍数向上)
      expect(p.dailyGoalMl, 1600);
    });

    test('男性 90kg / 180cm / 40岁 / 高活动量（封顶 4000）', () {
      final p = UserProfile.create(
        gender: Gender.male,
        weightKg: 90,
        heightCm: 180,
        age: 40,
        activityLevel: ActivityLevel.high,
      );
      // 90*35 + 700 + 200 = 4250 -> clamp 4000
      expect(p.dailyGoalMl, 4000);
    });

    test('女性 45kg / 150cm / 70岁 / 低活动量（封底 1500）', () {
      final p = UserProfile.create(
        gender: Gender.female,
        weightKg: 45,
        heightCm: 150,
        age: 70,
        activityLevel: ActivityLevel.low,
      );
      // 45*35 *0.9 - 200 = 1217.5 -> 50ml 倍数 -> 1200 -> clamp 1500
      expect(p.dailyGoalMl, 1500);
    });

    test('自定义目标覆盖算法结果', () {
      final p = UserProfile.create(
        gender: Gender.male,
        weightKg: 65,
        heightCm: 170,
        age: 25,
        activityLevel: ActivityLevel.medium,
        customGoalMl: 1800,
      );
      expect(p.dailyGoalMl, 1800);
    });
  });

  group('PRD §2.3 饮品折算', () {
    test('纯水 250ml -> 250ml', () {
      final b = Beverage.presets.firstWhere((e) => e.id == 'water_pure');
      expect(b.effectiveMl(250), 250);
    });

    test('咖啡 250ml -> 175ml (70%)', () {
      final b = Beverage.presets.firstWhere((e) => e.id == 'coffee_americano');
      expect(b.effectiveMl(250), 175);
    });

    test('奶茶 500ml -> 400ml (80%)', () {
      final b = Beverage.presets.firstWhere((e) => e.id == 'milk_tea');
      expect(b.effectiveMl(500), 400);
    });

    test('啤酒 500ml -> 0ml (酒类不计进度)', () {
      final b = Beverage.presets.firstWhere((e) => e.id == 'alcohol_beer');
      expect(b.effectiveMl(500), 0);
    });

    test('当日进度聚合', () {
      final entries = [
        DrinkEntry.create(
          beverage: Beverage.presets.firstWhere((e) => e.id == 'water_pure'),
          volumeMl: 250,
        ),
        DrinkEntry.create(
          beverage: Beverage.presets.firstWhere((e) => e.id == 'coffee_latte'),
          volumeMl: 350,
        ),
      ];
      // 250 + 350*0.7 = 250+245 = 495
      expect(HydrationCalculator.sumEffective(entries), 495);
      expect(HydrationCalculator.sumVolume(entries), 600);
      expect(HydrationCalculator.progress(entries, 1000), 0.495);
      expect(HydrationCalculator.remaining(entries, 1000), 505);
    });
  });
}
