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

  // ---- 精美插画补充素材（D:\User_FYX\精美插画，按文件夹分类接入）----

  // 蔬果
  'pineapple': CharacterInfo(id: 'pineapple', displayName: '菠萝'),
  'strawberry': CharacterInfo(id: 'strawberry', displayName: '草莓'),
  'cherries': CharacterInfo(id: 'cherries', displayName: '车厘子'),
  'orange': CharacterInfo(id: 'orange', displayName: '橙子'),
  'orange_smile': CharacterInfo(id: 'orange_smile', displayName: '橙子微笑'),
  'blueberry_kid': CharacterInfo(id: 'blueberry_kid', displayName: '蓝莓小子'),
  'avocado': CharacterInfo(id: 'avocado', displayName: '牛油果'),
  'avocado_watermelon': CharacterInfo(id: 'avocado_watermelon', displayName: '牛油果和西瓜'),
  'persimmon': CharacterInfo(id: 'persimmon', displayName: '柿子'),
  'watermelon_smile': CharacterInfo(id: 'watermelon_smile', displayName: '西瓜笑脸'),
  'cherry': CharacterInfo(id: 'cherry', displayName: '樱桃'),
  'cherry_pair': CharacterInfo(id: 'cherry_pair', displayName: '一对樱桃'),

  // 人物
  'person_04': CharacterInfo(id: 'person_04', displayName: '人物 04'),
  'person_06': CharacterInfo(id: 'person_06', displayName: '人物 06'),
  'person_07': CharacterInfo(id: 'person_07', displayName: '人物 07'),
  'person_11': CharacterInfo(id: 'person_11', displayName: '人物 11'),
  'person_15': CharacterInfo(id: 'person_15', displayName: '人物 15'),
  'zannet_01': CharacterInfo(id: 'zannet_01', displayName: '人物 01'),
  'zannet_02': CharacterInfo(id: 'zannet_02', displayName: '人物 02'),
  'zannet_04': CharacterInfo(id: 'zannet_04', displayName: '人物 03'),
  'zannet_07': CharacterInfo(id: 'zannet_07', displayName: '人物 05'),
  'zannet_11': CharacterInfo(id: 'zannet_11', displayName: '人物 08'),
  'raise_cup': CharacterInfo(id: 'raise_cup', displayName: '举杯'),
  'cartoon_person': CharacterInfo(id: 'cartoon_person', displayName: '卡通人物'),
  'eating_pizza': CharacterInfo(id: 'eating_pizza', displayName: '吃披萨'),
  'sofa_snacks': CharacterInfo(id: 'sofa_snacks', displayName: '沙发零食'),
  'sofa_drink': CharacterInfo(id: 'sofa_drink', displayName: '沙发饮料'),
  'delivery_rider': CharacterInfo(id: 'delivery_rider', displayName: '外卖员'),
  'bride': CharacterInfo(id: 'bride', displayName: '新娘'),
  'discussion': CharacterInfo(id: 'discussion', displayName: '讨论'),
  'shopping_girl': CharacterInfo(id: 'shopping_girl', displayName: '购物女孩'),

  // 像素
  'pixel_rabbit': CharacterInfo(id: 'pixel_rabbit', displayName: '像素兔子'),
  'pixel_dog': CharacterInfo(id: 'pixel_dog', displayName: '像素小狗'),
  'pixel_pig': CharacterInfo(id: 'pixel_pig', displayName: '像素小猪'),
  'pixel_cat': CharacterInfo(id: 'pixel_cat', displayName: '像素小猫'),
  'pixel_chick': CharacterInfo(id: 'pixel_chick', displayName: '像素小鸡'),
  'pixel_polar_bear': CharacterInfo(id: 'pixel_polar_bear', displayName: '像素白熊'),
  'pixel_tiger': CharacterInfo(id: 'pixel_tiger', displayName: '像素老虎'),
  'pixel_frog': CharacterInfo(id: 'pixel_frog', displayName: '像素青蛙'),

  // 可爱
  'excited': CharacterInfo(id: 'excited', displayName: '兴奋'),
  'comfort': CharacterInfo(id: 'comfort', displayName: '安慰'),
  'greeting': CharacterInfo(id: 'greeting', displayName: '打招呼'),
  'inspired': CharacterInfo(id: 'inspired', displayName: '振奋'),
  'joyful': CharacterInfo(id: 'joyful', displayName: '欢快'),
  'delighted': CharacterInfo(id: 'delighted', displayName: '欣喜'),
  'pensive': CharacterInfo(id: 'pensive', displayName: '沉思'),
  'content': CharacterInfo(id: 'content', displayName: '满足'),

  // 家
  'orange_cat': CharacterInfo(id: 'orange_cat', displayName: '乖橘猫'),
  'silly_dog': CharacterInfo(id: 'silly_dog', displayName: '大傻狗狗'),
  'pet': CharacterInfo(id: 'pet', displayName: '宠物'),
  'corgi': CharacterInfo(id: 'corgi', displayName: '小柯基'),
  'poodle': CharacterInfo(id: 'poodle', displayName: '小贵宾'),
  'homesick_rabbit': CharacterInfo(id: 'homesick_rabbit', displayName: '想家兔兔'),
  'sleepy_cat': CharacterInfo(id: 'sleepy_cat', displayName: '瞌睡喵'),
  'longtail_cat': CharacterInfo(id: 'longtail_cat', displayName: '长尾巴猫咪'),

  // 抽象
  'envelope': CharacterInfo(id: 'envelope', displayName: '信封'),
  'star': CharacterInfo(id: 'star', displayName: '星星'),
  'abstract_cup': CharacterInfo(id: 'abstract_cup', displayName: '抽象杯子'),
  'camera': CharacterInfo(id: 'camera', displayName: '相机'),
  'daily_icons': CharacterInfo(id: 'daily_icons', displayName: '日常图标'),
  'shopping_bag': CharacterInfo(id: 'shopping_bag', displayName: '购物袋'),

  // 杯子
  'cola_bottle': CharacterInfo(id: 'cola_bottle', displayName: '可乐瓶子'),
  'coffee_cup': CharacterInfo(id: 'coffee_cup', displayName: '咖啡杯'),
  'baby_bottle': CharacterInfo(id: 'baby_bottle', displayName: '奶瓶'),
  'cup': CharacterInfo(id: 'cup', displayName: '杯子'),
  'bottle': CharacterInfo(id: 'bottle', displayName: '瓶子'),

  // 植物
  'flower_bunch': CharacterInfo(id: 'flower_bunch', displayName: '一小撮花'),
  'little_flower': CharacterInfo(id: 'little_flower', displayName: '一朵小花'),
  'big_leaf_plant': CharacterInfo(id: 'big_leaf_plant', displayName: '大叶植物'),
  'little_thing': CharacterInfo(id: 'little_thing', displayName: '小之物'),
  'potted_big_leaf': CharacterInfo(id: 'potted_big_leaf', displayName: '大叶盆栽'),
  'green_cactus': CharacterInfo(id: 'green_cactus', displayName: '绿色仙人球'),
  'mushroom_baby': CharacterInfo(id: 'mushroom_baby', displayName: '蘑菇宝宝'),
};

/// 9 个收集分类：每日收纳全部原始插画，其余分类按素材来源分组
final characterCategories = <CharacterCategory>[
  // 1. 每日：全部 41 个原始插画角色，主页角色切换池
  CharacterCategory(
    id: 'daily',
    name: '每日',
    color: const Color(0xFF5AC8FA),
    characterIds: const [
      'alpaca', 'pony', 'rabbit', 'fox', 'polar_bear',
      'red_squirrel', 'hedgehog', 'beaver', 'otter', 'duck',
      'parrot', 'turtle', 'husky', 'rooster', 'chameleon',
      'gecko', 'swan', 'goat_kid', 'otter_kid', 'goat',
      'mole', 'zebra', 'hippo', 'dolphin',
      'turkey', 'leopard', 'sheep', 'ram', 'skunk',
      'firefly2', 'firefly', 'snake', 'hummingbird', 'bat',
      'panther', 'boar', 'pheasant', 'fish', 'whale',
      'bird', 'lobster',
    ],
  ),
  // 2. 可爱（精美插画）
  CharacterCategory(
    id: 'cute',
    name: '可爱',
    color: const Color(0xFF5AC8FA),
    characterIds: const [
      'excited', 'comfort', 'greeting', 'inspired',
      'joyful', 'delighted', 'pensive', 'content',
    ],
  ),
  // 3. 像素（精美插画）
  CharacterCategory(
    id: 'pixel',
    name: '像素',
    color: const Color(0xFF8E8E93),
    characterIds: const [
      'pixel_rabbit', 'pixel_dog', 'pixel_pig', 'pixel_cat',
      'pixel_chick', 'pixel_polar_bear', 'pixel_tiger', 'pixel_frog',
    ],
  ),
  // 4. 人（精美插画）
  CharacterCategory(
    id: 'people',
    name: '人',
    color: const Color(0xFFE0528C),
    characterIds: const [
      'person_04', 'person_06', 'person_07', 'person_11', 'person_15',
      'zannet_01', 'zannet_02', 'zannet_04', 'zannet_07', 'zannet_11',
      'raise_cup', 'cartoon_person', 'eating_pizza', 'sofa_snacks',
      'sofa_drink', 'delivery_rider',
      'bride', 'discussion', 'shopping_girl',
    ],
  ),
  // 5. 抽象（精美插画）
  CharacterCategory(
    id: 'abstract',
    name: '抽象',
    color: const Color(0xFF6B6FD7),
    characterIds: const [
      'envelope', 'star', 'abstract_cup', 'camera',
      'daily_icons', 'shopping_bag',
    ],
  ),
  // 6. 家（精美插画）
  CharacterCategory(
    id: 'home',
    name: '家',
    color: const Color(0xFF34C759),
    characterIds: const [
      'orange_cat', 'silly_dog', 'pet', 'corgi', 'poodle',
      'homesick_rabbit', 'sleepy_cat', 'longtail_cat',
    ],
  ),
  // 7. 蔬果（精美插画）
  CharacterCategory(
    id: 'fruits',
    name: '蔬果',
    color: const Color(0xFFFF9500),
    characterIds: const [
      'pineapple', 'strawberry', 'cherries', 'orange',
      'orange_smile', 'blueberry_kid', 'avocado', 'avocado_watermelon',
      'persimmon', 'watermelon_smile', 'cherry', 'cherry_pair',
    ],
  ),
  // 8. 杯子（精美插画）
  CharacterCategory(
    id: 'cups',
    name: '杯子',
    color: const Color(0xFF007AFF),
    characterIds: const [
      'cola_bottle', 'coffee_cup', 'baby_bottle', 'cup', 'bottle',
    ],
  ),
  // 9. 植物（精美插画）
  CharacterCategory(
    id: 'plants',
    name: '植物',
    color: const Color(0xFF34C759),
    characterIds: const [
      'flower_bunch', 'little_flower', 'big_leaf_plant', 'little_thing',
      'potted_big_leaf', 'green_cactus', 'mushroom_baby',
    ],
  ),
];

/// 默认已解锁的角色 ID（业务规则：只有羊驼卢娜默认点亮）
const defaultUnlockedIds = <String>{'alpaca'};

/// 全部角色总数（用于"已收集 X 个，共 Y 个"）
int get totalCharacterCount => characters.length;
