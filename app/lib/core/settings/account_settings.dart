import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 账号级偏好（跟随账号上云）的键集合，与云同步 settings 表的 key 一一对应。
///
/// 这些偏好属于「人」而不是「设备」：换设备登录后单位、目标温度、角色、
/// 自定义饮品都应保持一致；游客则落在本机游客桶里，互不串数据。
class AccountSettingKeys {
  AccountSettingKeys._();

  static const String preferredUnit = 'preferred_unit';
  static const String goalTemperature = 'goal_temperature';
  static const String genderDisplayLabel = 'gender_display_label';
  static const String currentCharacter = 'current_character_id';
  static const String characterCollected = 'character_collected_ids';
  static const String customBeverages = 'custom_beverages';

  /// 全部账号级偏好键（升级时把老版本全局 key 迁进当前归属桶）
  static const List<String> all = [
    preferredUnit,
    goalTemperature,
    genderDisplayLabel,
    currentCharacter,
    characterCollected,
    customBeverages,
  ];
}

/// 云端偏好被应用到本机（同步拉取 / 冲突覆盖）后 +1。
///
/// 按当前账号读取偏好的 provider 监听它重新加载；与会话纪元不同，它不会
/// 连带重载饮水记录，避免一次偏好同步就整页刷新。
final accountSettingsRevisionProvider = StateProvider<int>((ref) => 0);
