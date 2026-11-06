/// 本地存储键常量（自 LocalStorage 拆出，键名与取值保持不变）
class StorageKeys {
  StorageKeys._();

  static const String dbName = 'water_llama.db';
  static const int dbVersion = 6;

  static const String profile = 'user_profile';
  static const String dailyAnimalPrefix = 'daily_animal_id_';
  static const String lastResetDay = 'last_reset_day';
  static const String entriesPrefix = 'entries_';
  static const String welcomeSeen = 'welcome_seen';

  static const String settingsPrefix = 'account_settings_';
  static const String settingsPushedPrefix = 'account_settings_pushed_';
  static const String settingsMigrated = 'account_settings_migrated_v1';

  static const String pointsLegacyKey = 'points_state';
  static const String pointsMigrated = 'points_bucket_migrated_v1';

  static const String syncUserId = 'sync_user_id';
  static const String syncToken = 'sync_token';
  static const String syncCursorPrefix = 'sync_cursor_';
  static const String syncCursorLegacy = 'sync_cursor';
  static const String syncLastAt = 'sync_last_at';
  static const String syncLastError = 'sync_last_error';
  static const String accountEmail = 'account_email';

  static const String healthEnabled = 'health_sync_enabled';
  static const String healthLastSync = 'health_sync_last_at';

  static const String match3Level = 'match3_level';
  static const String defenseLevel = 'defense_level';

  static const String accountAnonId = 'account_anon_id';
  static const String accountNickname = 'account_nickname';
  static const String accountLastBackup = 'account_last_backup_at';
  static const String accountAvatar = 'account_avatar_path';
  static const String lastUserId = 'last_account_user_id';
  static const String autoSync = 'cloud_auto_sync';
  static const String accountAvatarRemote = 'account_avatar_remote_url';
  static const String pushedProfile = 'account_pushed_profile';
  static const String guestProfile = 'guest_profile_snapshot';
  static const String rejectedOrderNotice = 'account_rejected_order_notice';
  static const String avatarDirty = 'account_avatar_dirty';
  static const String nicknameDirty = 'account_nickname_dirty';
  static const String guestNickname = 'guest_nickname_snapshot';
}
