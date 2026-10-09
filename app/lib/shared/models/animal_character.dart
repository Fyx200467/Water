import 'package:flutter/material.dart';

/// PRD §2.2 当日动物形象
/// 内置几个简单自绘形象，避免美术依赖；可后续替换 Lottie/PNG
@immutable
class AnimalCharacter {
  const AnimalCharacter({
    required this.id,
    required this.name,
    required this.primaryColor,
    required this.bodyColor,
    required this.memberOnly,
  });

  final String id;
  final String name;
  final Color primaryColor;
  final Color bodyColor;
  final bool memberOnly;

  static const List<AnimalCharacter> all = [
    AnimalCharacter(
      id: 'llama',
      name: '小羊驼',
      primaryColor: Color(0xFFE8D5C4),
      bodyColor: Color(0xFFFFFFFF),
      memberOnly: false,
    ),
    AnimalCharacter(
      id: 'panda',
      name: '熊猫',
      primaryColor: Color(0xFF2C2C2C),
      bodyColor: Color(0xFFFFFFFF),
      memberOnly: false,
    ),
    AnimalCharacter(
      id: 'frog',
      name: '青蛙',
      primaryColor: Color(0xFF6FA8DC),
      bodyColor: Color(0xFF8BC34A),
      memberOnly: false,
    ),
    AnimalCharacter(
      id: 'penguin',
      name: '企鹅',
      primaryColor: Color(0xFF1A1A1A),
      bodyColor: Color(0xFFFFFFFF),
      memberOnly: true,
    ),
    AnimalCharacter(
      id: 'fox',
      name: '小狐狸',
      primaryColor: Color(0xFFE67E22),
      bodyColor: Color(0xFFFFF3E0),
      memberOnly: true,
    ),
  ];

  static List<AnimalCharacter> availableFor({required bool isMember}) {
    return all.where((a) => !a.memberOnly || isMember).toList();
  }
}
