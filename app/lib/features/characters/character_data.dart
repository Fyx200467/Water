import 'package:flutter/material.dart';

/// 角色数据：41 个动物角色 + 12 个收集分类
///
/// 资源位于 `assets/images/characters/<animalId>.svg`，由 iconfont 提供。
/// 业务规则：
/// - 默认只有羊驼卢娜是已解锁状态（非会员主页角色固定）
/// - 用户每日完成饮水目标后，可解锁一个新角色（次日点亮）
/// - 主页角色切换需要会员资格，非会员只有羊驼卢娜
class CharacterCategory {
  const CharacterCategory({
    required this.id,
    required this.name,
    required this.color,
    this.subtitle,
    required this.characterIds,
  });

  final String id;
  final String name;
  final Color color;
  final String? subtitle;
  final List<String> characterIds;
}

class CharacterInfo {
  const CharacterInfo({
    required this.id,
    required this.displayName,
  });

  final String id;
  final String displayName;
}

/// 41 个角色信息（id ↔ 中文名映射，按 iconfont 原始文件名命名）
final characters = <String, CharacterInfo>{
  'turtle': CharacterInfo(id: 'turtle', displayName: '乌龟'),
  'husky': CharacterInfo(id: 'husky', displayName: '二哈'),
  'rabbit': CharacterInfo(id: 'rabbit', displayName: '兔子'),
  'rooster': CharacterInfo(id: 'rooster', displayName: '公鸡'),
  'hedgehog': CharacterInfo(id: 'hedgehog', displayName: '刺猬'),
  'chameleon': CharacterInfo(id: 'chameleon', displayName: '变色龙'),
  'gecko': CharacterInfo(id: 'gecko', displayName: '壁虎'),
  'swan': CharacterInfo(id: 'swan', displayName: '天鹅'),
  'goat_kid': CharacterInfo(id: 'goat_kid', displayName: '小山羊'),
  'otter_kid': CharacterInfo(id: 'otter_kid', displayName: '小海獭'),
  'pony': CharacterInfo(id: 'pony', displayName: '小马'),
  'goat': CharacterInfo(id: 'goat', displayName: '山羊'),
  'mole': CharacterInfo(id: 'mole', displayName: '打地鼠'),
  'zebra': CharacterInfo(id: 'zebra', displayName: '斑马'),
  'beaver': CharacterInfo(id: 'beaver', displayName: '河狸'),
  'hippo': CharacterInfo(id: 'hippo', displayName: '河马'),
  'otter': CharacterInfo(id: 'otter', displayName: '海獭'),
  'dolphin': CharacterInfo(id: 'dolphin', displayName: '海豚'),
  'turkey': CharacterInfo(id: 'turkey', displayName: '火鸡'),
  'leopard': CharacterInfo(id: 'leopard', displayName: '灰豹'),
  'fox': CharacterInfo(id: 'fox', displayName: '狐'),
  'polar_bear': CharacterInfo(id: 'polar_bear', displayName: '白熊'),
  'red_squirrel': CharacterInfo(id: 'red_squirrel', displayName: '红松鼠'),
  'sheep': CharacterInfo(id: 'sheep', displayName: '绵羊'),
  'ram': CharacterInfo(id: 'ram', displayName: '羊'),
  'alpaca': CharacterInfo(id: 'alpaca', displayName: '羊驼'),
  'skunk': CharacterInfo(id: 'skunk', displayName: '臭鼬'),
  'firefly2': CharacterInfo(id: 'firefly2', displayName: '萤火虫'),
  'firefly': CharacterInfo(id: 'firefly', displayName: '萤火虫'),
  'snake': CharacterInfo(id: 'snake', displayName: '蛇'),
  'hummingbird': CharacterInfo(id: 'hummingbird', displayName: '蜂鸟'),
  'bat': CharacterInfo(id: 'bat', displayName: '蝙蝠'),
  'panther': CharacterInfo(id: 'panther', displayName: '豹子'),
  'boar': CharacterInfo(id: 'boar', displayName: '野猪'),
  'pheasant': CharacterInfo(id: 'pheasant', displayName: '野鸡'),
  'fish': CharacterInfo(id: 'fish', displayName: '鱼'),
  'whale': CharacterInfo(id: 'whale', displayName: '鲸鱼'),
  'bird': CharacterInfo(id: 'bird', displayName: '鸟'),
  'duck': CharacterInfo(id: 'duck', displayName: '鸭鸭'),
  'parrot': CharacterInfo(id: 'parrot', displayName: '鹦鹉'),
  'lobster': CharacterInfo(id: 'lobster', displayName: '龙虾'),
};

/// 12 个收集分类（对标原版 WaterLlama 角色页结构）
final characterCategories = <CharacterCategory>[
  // 1. 每日：默认已点亮的角色，主页角色切换池
  CharacterCategory(
    id: 'daily',
    name: '每日',
    color: const Color(0xFF5AC8FA),
    characterIds: const [
      'alpaca', 'pony', 'rabbit', 'fox', 'polar_bear',
      'red_squirrel', 'hedgehog', 'beaver', 'otter', 'duck',
      'parrot',
    ],
  ),
  // 2. 可爱
  CharacterCategory(
    id: 'cute',
    name: '可爱',
    color: const Color(0xFF5AC8FA),
    characterIds: const [
      'hummingbird', 'bird', 'parrot', 'duck', 'swan',
      'rabbit', 'fox', 'polar_bear', 'hedgehog', 'red_squirrel',
      'otter_kid',
    ],
  ),
  // 3. 挑战
  CharacterCategory(
    id: 'challenge',
    name: '挑战',
    color: const Color(0xFF1C1C1E),
    subtitle: '开始并完成全部挑战，收集挑战角色！',
    characterIds: const [
      'leopard', 'panther', 'husky', 'boar', 'snake',
      'bat', 'lobster', 'fish', 'whale',
    ],
  ),
  // 4. 节假日挑战
  CharacterCategory(
    id: 'holiday',
    name: '节假日挑战',
    color: const Color(0xFF1C1C1E),
    subtitle: '全年节假日期间的限时挑战。',
    characterIds: const [
      'turkey', 'pheasant', 'rooster', 'goat', 'goat_kid',
      'ram', 'sheep', 'alpaca', 'pony', 'rabbit',
    ],
  ),
  // 5. 支持者（会员专属）
  CharacterCategory(
    id: 'supporter',
    name: '支持者',
    color: const Color(0xFF5AC8FA),
    subtitle: '成为支持者! 作为你的感谢，你可以解锁一个独特的角色。',
    characterIds: const [
      'alpaca', 'pony', 'fox', 'polar_bear', 'husky',
    ],
  ),
  // 6. 像素
  CharacterCategory(
    id: 'pixel',
    name: '像素',
    color: const Color(0xFF8E8E93),
    characterIds: const [
      'turtle', 'fish', 'whale', 'lobster', 'snake',
      'bat', 'hummingbird', 'bird', 'parrot', 'duck',
      'firefly',
    ],
  ),
  // 7. 人（拟人化动物占位）
  CharacterCategory(
    id: 'people',
    name: '人',
    color: const Color(0xFFE0528C),
    characterIds: const [
      'mole', 'beaver', 'otter', 'otter_kid', 'rabbit',
      'fox', 'husky', 'boar', 'pheasant',
    ],
  ),
  // 8. 抽象
  CharacterCategory(
    id: 'abstract',
    name: '抽象',
    color: const Color(0xFF6B6FD7),
    characterIds: const [
      'firefly', 'firefly2', 'hummingbird', 'bat', 'bird',
      'fish', 'whale', 'snake', 'lobster',
    ],
  ),
  // 9. 家（家庭宠物）
  CharacterCategory(
    id: 'home',
    name: '家',
    color: const Color(0xFF34C759),
    characterIds: const [
      'rabbit', 'husky', 'fox', 'hedgehog', 'turtle',
      'parrot', 'bird', 'duck', 'mole',
    ],
  ),
  // 10. 乡村（农场动物）
  CharacterCategory(
    id: 'farm',
    name: '乡村',
    color: const Color(0xFFA8845A),
    characterIds: const [
      'goat', 'goat_kid', 'sheep', 'ram', 'alpaca',
      'turkey', 'pheasant', 'rooster', 'boar',
    ],
  ),
  // 11. 杯子
  CharacterCategory(
    id: 'cups',
    name: '杯子',
    color: const Color(0xFF007AFF),
    characterIds: const [
      'whale', 'fish', 'dolphin', 'lobster', 'turtle',
      'duck', 'swan', 'otter', 'otter_kid', 'beaver',
      'snake',
    ],
  ),
  // 12. 植物
  CharacterCategory(
    id: 'plants',
    name: '植物',
    color: const Color(0xFF34C759),
    characterIds: const [
      'bird', 'hummingbird', 'parrot', 'rabbit', 'fox',
      'beaver', 'mole', 'hedgehog', 'red_squirrel', 'bat',
      'firefly', 'firefly2', 'snake',
    ],
  ),
];

/// 默认已解锁的角色 ID（业务规则：只有羊驼卢娜默认点亮）
const defaultUnlockedIds = <String>{'alpaca'};

/// 全部角色总数（用于"已收集 X 个，共 Y 个"）
int get totalCharacterCount => characters.length;
