import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:water_llama/features/challenges/challenge_catalog.dart';
import 'package:water_llama/shared/models/beverage.dart';

void main() {
  group('挑战卡服务端字段解析', () {
    test('后台下发的 camelCase 字段完整映射到 HabitData', () {
      final data = HabitData.fromJson({
        'id': 'uuid-1',
        'title': '测试的\n新卡',
        'subtitle': '副标题',
        'bgColor': '#123abc',
        'asset': '/static/preset/characters/rabbit.svg',
        'intro': '挑战介绍',
        'benefits': [
          ['💧', '补水'],
          {'emoji': '🍃', 'text': '对象格式兼容'},
        ],
        'todo': '要做的事',
        'days': 30,
        'rewardPoints': 600,
        'forbiddenLabels': ['奶茶'],
        'forbiddenKeywords': ['咖啡'],
        'forbiddenCategories': ['coffee', 'milkTea'],
      });

      expect(data.id, 'uuid-1');
      expect(data.title, '测试的\n新卡');
      expect(data.bg, const Color(0xFF123ABC));
      expect(data.days, 30);
      expect(data.rewardPoints, 600);
      expect(data.benefits.length, 2);
      expect(data.benefits.last.$2, '对象格式兼容');
      expect(data.forbiddenCategories, contains(BeverageCategory.coffee));
      expect(data.forbiddenCategories, contains(BeverageCategory.milkTea));
      expect(data.forbiddenKeywords, ['咖啡']);
    });

    test('缺省与越界字段按客户端规则回退', () {
      final data = HabitData.fromJson({
        'title': '只有标题',
        'days': 0,
        'rewardPoints': 5000,
        'bgColor': 'not-a-color',
      });

      expect(data.days, 1);
      expect(data.rewardPoints, 1000);
      expect(data.bg, const Color(0xFF3FA65C));
      expect(data.forbiddenCategories, isEmpty);
      expect(data.benefits, isEmpty);
    });

    test('禁止标签同样参与饮品命中判定（不只是展示文案）', () {
      final data = HabitData.fromJson({
        'title': '标签命中',
        'forbiddenLabels': ['鸡尾酒'],
      });

      expect(data.forbids(BeverageCategory.soda, '鸡尾酒'), isTrue);
      expect(data.forbids(BeverageCategory.soda, '苏打水'), isFalse);
    });
  });
}
