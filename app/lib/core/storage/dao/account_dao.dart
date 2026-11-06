import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'dao_keys.dart';
import 'dao_shared.dart';

/// 账号资料、头像、昵称、云备份与同步会话（SharedPreferences）
class AccountDao {
  AccountDao(this.prefs);

  final SharedPreferences prefs;

  String? get syncUserId => prefs.getString(StorageKeys.syncUserId);

  String? get syncToken => prefs.getString(StorageKeys.syncToken);

  /// 已登录账号的邮箱；为空表示本地模式（不同步）
  String? get accountEmail {
    final v = prefs.getString(StorageKeys.accountEmail);
    return (v == null || v.isEmpty) ? null : v;
  }

  String get _cursorKey =>
      '${StorageKeys.syncCursorPrefix}${ownerSuffix(syncUserId ?? '')}';

  int get syncCursor => prefs.getInt(_cursorKey) ?? 0;

  DateTime? get syncLastSyncAt {
    final s = prefs.getString(StorageKeys.syncLastAt);
    return s == null ? null : DateTime.tryParse(s);
  }

  String? get syncLastError {
    final s = prefs.getString(StorageKeys.syncLastError);
    return (s == null || s.isEmpty) ? null : s;
  }

  bool get hasSyncSession =>
      (syncUserId ?? '').isNotEmpty && (syncToken ?? '').isNotEmpty;

  /// 已登录正式账号：以「有 userId + token」为准，
  /// 邮箱只是某一种登录方式，解绑后不应把用户踢下线
  bool get hasAccountSession => hasSyncSession;

  Future<void> setSyncSession(
    String userId,
    String token, {
    String? email,
  }) async {
    await prefs.setString(StorageKeys.syncUserId, userId);
    await prefs.setString(StorageKeys.syncToken, token);
    if (email != null) await prefs.setString(StorageKeys.accountEmail, email);
  }

  /// 退出登录：清掉账号与令牌。记录本身保留在本地，但带有所属账号，
  /// 退出后不再属于当前（游客）视图，因此不会显示；重新登录该账号会恢复。
  Future<void> clearSyncSession() async {
    final last = syncUserId;
    if (last != null && last.isNotEmpty) {
      await prefs.setString(StorageKeys.lastUserId, last);
    }
    await prefs.remove(StorageKeys.syncUserId);
    await prefs.remove(StorageKeys.syncToken);
    await prefs.remove(StorageKeys.accountEmail);
    // 游标不随会话清除：重新登录同一账号时继续增量拉取
  }

  Future<void> setSyncCursor(int cursor) async {
    await prefs.setInt(_cursorKey, cursor);
  }

  /// 重新读取磁盘偏好：小组件后台录入在独立 isolate（Android 上还有纯
  /// 原生侧）写库/写偏好，主进程内存中的 prefs 缓存会滞后；回前台时
  /// 先 reload 再查数据，避免读到旧值
  Future<void> reloadPrefs() async {
    try {
      await prefs.reload();
    } catch (_) {
      // 读取失败沿用当前缓存
    }
  }

  /// 解绑邮箱后清掉本机记录的邮箱展示，会话仍保留
  Future<void> clearAccountEmail() async {
    await prefs.remove(StorageKeys.accountEmail);
  }

  Future<void> setSyncLastSyncAt(DateTime at) async {
    await prefs.setString(StorageKeys.syncLastAt, at.toIso8601String());
  }

  /// 记录/清除最近一次同步失败原因（null 或空串表示清除）
  Future<void> setSyncLastError(String? message) async {
    if (message == null || message.isEmpty) {
      await prefs.remove(StorageKeys.syncLastError);
    } else {
      await prefs.setString(StorageKeys.syncLastError, message);
    }
  }

  /// 头像按账号存放：切换账号不会看到上一个账号的头像；
  /// 未登录时读游客 key（实际不会设置，界面显示「未登录」图标）。
  String get _avatarKey {
    final uid = syncUserId;
    return (uid == null || uid.isEmpty)
        ? StorageKeys.accountAvatar
        : '${StorageKeys.accountAvatar}_$uid';
  }

  /// 本机自定义头像路径（相册 / 拍照保存到应用目录后的绝对路径）。
  /// 未设置时返回 null，由界面回退到默认头像；
  /// 后续接入 QQ / 微信登录时，第三方头像也可以先落盘再写入这里。
  String? get accountAvatarPath {
    final v = prefs.getString(_avatarKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setAccountAvatarPath(String? path) async {
    final key = _avatarKey;
    if (path == null || path.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, path);
    }
  }

  String get _accountUid {
    final uid = syncUserId;
    return (uid == null || uid.isEmpty) ? 'guest' : uid;
  }

  /// 服务端头像地址（/static/avatars/...），用于判断本机是否需要重新下载
  String? get accountAvatarRemoteUrl {
    final v =
        prefs.getString('${StorageKeys.accountAvatarRemote}_$_accountUid');
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setAccountAvatarRemoteUrl(String? url) async {
    final key = '${StorageKeys.accountAvatarRemote}_$_accountUid';
    if (url == null || url.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, url);
    }
  }

  /// 本机头像改动（换了新图或恢复默认）尚未成功同步到服务端。
  /// 仅靠「远端地址是否变化」判断会漏掉替换头像上传失败、离线恢复默认
  /// 这两类情况，导致改动永远补传不上去。
  bool get avatarDirty =>
      prefs.getBool('${StorageKeys.avatarDirty}_$_accountUid') ?? false;

  Future<void> markAvatarDirty() =>
      prefs.setBool('${StorageKeys.avatarDirty}_$_accountUid', true);

  Future<void> clearAvatarDirty() =>
      prefs.remove('${StorageKeys.avatarDirty}_$_accountUid');

  /// 上次与服务端对齐的档案签名（性别/体重/身高/年龄/活动量/目标），
  /// 避免每轮同步重复 PATCH；为空表示该账号尚未与服务端对齐
  String? get lastPushedProfileSignature {
    final v = prefs.getString('${StorageKeys.pushedProfile}_$_accountUid');
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setLastPushedProfileSignature(String signature) async {
    await prefs.setString(
      '${StorageKeys.pushedProfile}_$_accountUid',
      signature,
    );
  }

  Future<void> clearLastPushedProfileSignature() async {
    await prefs.remove('${StorageKeys.pushedProfile}_$_accountUid');
  }

  /// 已经弹过「申请未通过」提示的订单 ID，避免重复打扰
  String? get lastRejectedNoticeOrderId {
    final v =
        prefs.getString('${StorageKeys.rejectedOrderNotice}_$_accountUid');
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setLastRejectedNoticeOrderId(String orderId) async {
    await prefs.setString(
      '${StorageKeys.rejectedOrderNotice}_$_accountUid',
      orderId,
    );
  }

  /// 无感同步开关：开启后在数据变动 / 冷启动 / 回前台时自动同步
  bool get autoSyncEnabled => prefs.getBool(StorageKeys.autoSync) ?? true;

  Future<void> setAutoSyncEnabled(bool on) async {
    await prefs.setBool(StorageKeys.autoSync, on);
  }

  /// 本机匿名标识：首次读取时生成并复用。
  /// 仅用于服务端识别设备，卸载后随之丢失（匿名身份不保证跨重装恢复）。
  String get accountAnonId {
    final existing = prefs.getString(StorageKeys.accountAnonId);
    if (existing != null && existing.isNotEmpty) return existing;
    final rnd = math.Random();
    const chars = '0123456789abcdef';
    final id = List.generate(32, (_) => chars[rnd.nextInt(16)]).join();
    prefs.setString(StorageKeys.accountAnonId, id);
    return id;
  }

  /// 本机昵称：未登录时也允许修改，登录后由服务端同步
  String get accountNickname {
    final n = prefs.getString(StorageKeys.accountNickname);
    return (n == null || n.trim().isEmpty) ? '喝水羊驼' : n;
  }

  Future<void> setAccountNickname(String name) async {
    await prefs.setString(StorageKeys.accountNickname, name.trim());
  }

  /// 本机改过昵称但还没上行成功：同步时以本地为准推送，避免被云端覆盖
  bool get nicknameDirty => prefs.getBool(StorageKeys.nicknameDirty) ?? false;

  Future<void> markNicknameDirty() async {
    await prefs.setBool(StorageKeys.nicknameDirty, true);
  }

  Future<void> clearNicknameDirty() async {
    await prefs.remove(StorageKeys.nicknameDirty);
  }

  /// 登录前快照游客昵称，退出账号后恢复
  Future<void> saveGuestNicknameSnapshot() async {
    await prefs.setString(StorageKeys.guestNickname, accountNickname);
  }

  Future<void> restoreGuestNickname() async {
    final snapshot = prefs.getString(StorageKeys.guestNickname);
    if (snapshot == null || snapshot.isEmpty) {
      await prefs.remove(StorageKeys.accountNickname);
    } else {
      await prefs.setString(StorageKeys.accountNickname, snapshot);
    }
    await prefs.remove(StorageKeys.guestNickname);
  }

  DateTime? get accountLastBackupAt {
    final s = prefs.getString(StorageKeys.accountLastBackup);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> setAccountLastBackupAt(DateTime at) async {
    await prefs.setString(
      StorageKeys.accountLastBackup,
      at.toIso8601String(),
    );
  }
}
