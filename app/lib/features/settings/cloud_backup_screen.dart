import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/storage/providers.dart';
import '../../core/sync/profile_sync.dart';
import '../../core/sync/sync_api.dart';
import '../../core/sync/sync_service.dart';
import '../../shared/widgets/account_avatar.dart';
import '../home/providers/home_providers.dart';
import '../membership/membership_provider.dart';
import '../stats/providers/stats_providers.dart';

/// 账号状态（未登录 = 本地模式；登录后才允许云同步）
class CloudBackupState {
  const CloudBackupState({
    required this.anonId,
    required this.nickname,
    this.email,
    this.userId,
    this.avatarPath,
    this.lastBackupAt,
    this.pendingCount = 0,
  });

  final String anonId;
  final String nickname;

  /// 已登录账号邮箱，为空表示本地模式
  final String? email;

  /// 服务端用户 ID（登录后才有）
  final String? userId;

  /// 本机自定义头像路径（相册 / 拍照后落盘）
  final String? avatarPath;

  final DateTime? lastBackupAt;

  /// 本地待上行条数
  final int pendingCount;

  bool get isLoggedIn => (email ?? '').isNotEmpty && (userId ?? '').isNotEmpty;

  /// 吨吨ID：登录后展示服务端用户 ID（唯一标识），未登录不展示
  String get displayId => isLoggedIn ? userId! : '登录后生成';
}

final cloudBackupStateProvider = FutureProvider<CloudBackupState>((ref) async {
  final storage = await ref.watch(localStorageProvider.future);
  return CloudBackupState(
    anonId: storage.accountAnonId,
    // 退出登录后不再展示上一个账号的昵称
    nickname: storage.hasAccountSession ? storage.accountNickname : '未登录',
    email: storage.accountEmail,
    userId: storage.syncUserId,
    avatarPath: storage.accountAvatarPath,
    lastBackupAt: storage.syncLastSyncAt ?? storage.accountLastBackupAt,
    pendingCount: await storage.countPendingSyncEntries(),
  );
});

/// 「账号信息」页：登录 / 基本信息 两页，左右滑动切换
class CloudBackupScreen extends ConsumerStatefulWidget {
  const CloudBackupScreen({super.key});

  @override
  ConsumerState<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends ConsumerState<CloudBackupScreen> {
  static const _bg = Color(0xFFF5F6F8);
  static const _textDark = Color(0xFF1C1C1E);
  static const _textSecondary = Color(0xFF9A9AA0);
  static const _pink = Color(0xFFEF7A8B);
  static const _red = Color(0xFFE0533D);
  static const _divider = Color(0xFFF0F2F5);

  /// 登录按钮宽度占比（约为去掉白卡后内容宽度的 54%，与之前按钮的实际宽度一致）
  static const double _kLoginBtnWidthFactor = 0.54;

  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _pwdCtrl = TextEditingController();
  bool _agreed = true;
  bool _syncing = false;
  bool _busy = false;
  bool _registerMode = false;
  bool _autoSync = true;

  @override
  void initState() {
    super.initState();
    _loadAutoSync();
  }

  Future<void> _loadAutoSync() async {
    final storage = await ref.read(localStorageProvider.future);
    if (!mounted) return;
    setState(() => _autoSync = storage.autoSyncEnabled);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cloudBackupStateProvider).valueOrNull;
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final loggedIn = state?.isLoggedIn ?? false;
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              topInset + 62,
              20,
              bottomInset + 28,
            ),
            children: [
              // 顶部当前头像（圆形，水平居中，点击可上传）
              Center(child: _buildAvatar(state)),
              const SizedBox(height: 26),
              _buildAccountCard(state),
              if (!loggedIn) ...[
                const SizedBox(height: 22),
                _buildLoginForm(),
                const SizedBox(height: 18),
                _buildAgreement(),
              ],
              const SizedBox(height: 18),
              _buildDataSyncCard(state),
            ],
          ),
          // 悬浮返回按钮（不随内容滚动）
          Positioned(top: topInset + 6, left: 12, child: _buildBackButton()),
        ],
      ),
    );
  }

  /// 顶部当前头像：未登录展示「未登录」图标；
  /// 已登录统一为「白色圆环 + 内部头像」，白环加在头像外侧，
  /// 不缩小、不裁切内部的照片 / 默认头像。
  Widget _buildAvatar(CloudBackupState? state) {
    final loggedIn = state?.isLoggedIn ?? false;
    final path = state?.avatarPath;
    return GestureDetector(
      onTap: () => _pickAvatar(loggedIn),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (loggedIn)
            Container(
              width: 120,
              height: 120,
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Color(0x14000000), blurRadius: 10),
                ],
              ),
              child: AccountAvatar(
                size: 100,
                loggedIn: true,
                avatarPath: path,
                padding: 2,
                background: const Color(0xFFEAF4FB),
              ),
            )
          else
            const AccountAvatar(size: 100, loggedIn: false),
          if (loggedIn)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: _pink,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.photo_camera_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 头像上传 ====================

  /// 登录后点击头像 → 拍照 / 从相册选择 / 恢复默认头像。
  /// 未登录时头像即「未登录」图标，不提供编辑入口。
  Future<void> _pickAvatar(bool loggedIn) async {
    if (!loggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('登录后可设置头像')));
      return;
    }
    final hasCustom =
        (ref.read(cloudBackupStateProvider).valueOrNull?.avatarPath ?? '')
            .isNotEmpty;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: _pink),
              title: const Text('拍照'),
              onTap: () => Navigator.of(ctx).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: _pink),
              title: const Text('从相册选择'),
              onTap: () => Navigator.of(ctx).pop('gallery'),
            ),
            if (hasCustom)
              ListTile(
                leading: const Icon(
                  Icons.restart_alt_rounded,
                  color: _textSecondary,
                ),
                title: const Text('恢复默认头像'),
                onTap: () => Navigator.of(ctx).pop('reset'),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'reset') {
      await _resetAvatar();
    } else {
      await _pickFromSource(
        action == 'camera' ? ImageSource.camera : ImageSource.gallery,
      );
    }
  }

  /// 取图后复制到应用私有目录并记录路径（只保存一份，替换时删旧图）
  Future<void> _pickFromSource(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 88,
      );
      if (picked == null) return;
      final storage = await ref.read(localStorageProvider.future);
      final appDir = await getApplicationDocumentsDirectory();
      final avatarDir = Directory(p.join(appDir.path, 'avatars'));
      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }
      final ext = p.extension(picked.path).isEmpty
          ? '.jpg'
          : p.extension(picked.path);
      final dest = File(
        p.join(
          avatarDir.path,
          'avatar_${DateTime.now().millisecondsSinceEpoch}$ext',
        ),
      );
      await dest.writeAsBytes(await picked.readAsBytes(), flush: true);
      final old = storage.accountAvatarPath;
      await storage.setAccountAvatarPath(dest.path);
      if (old != null && old != dest.path) {
        try {
          final f = File(old);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      ref.invalidate(cloudBackupStateProvider);
      // 登录状态下立即上传，换设备登录即可看到同一头像
      final token = storage.syncToken;
      if (token != null && token.isNotEmpty) {
        await ProfileSync.uploadLocal(storage, token, dest.path);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('头像已更新')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('头像设置失败：$e')));
    }
  }

  /// 清除本机自定义头像，回到默认插画（后续第三方登录头像也走这条清空路径）
  Future<void> _resetAvatar() async {
    final storage = await ref.read(localStorageProvider.future);
    final old = storage.accountAvatarPath;
    await storage.setAccountAvatarPath(null);
    if (old != null) {
      try {
        final f = File(old);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    // 同步清除服务端头像，避免其他设备登录后又把旧头像拉回来
    final token = storage.syncToken;
    if (token != null && token.isNotEmpty) {
      try {
        await SyncApi.deleteAvatar(token);
        await storage.setAccountAvatarRemoteUrl(null);
      } catch (_) {}
    }
    ref.invalidate(cloudBackupStateProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已恢复默认头像')));
  }

  // ==================== 悬浮返回按钮 ====================

  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: Color(0xFFE5E5EA),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.arrow_back_ios_new, size: 15, color: _textDark),
      ),
    );
  }

  // ==================== 账号信息卡（昵称 / 登录账号 / 吨吨ID） ====================

  Widget _buildAccountCard(CloudBackupState? state) {
    final loggedIn = state?.isLoggedIn ?? false;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          _infoRow(
            title: '昵称',
            onTap: loggedIn
                ? () => _editNickname(ref, state?.nickname ?? '')
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    state?.nickname ?? '未登录',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: _textSecondary),
                  ),
                ),
                if (loggedIn) ...[
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: Color(0xFFC7C7CC),
                  ),
                ],
              ],
            ),
          ),
          _infoRow(
            title: '登录账号',
            trailing: Text(
              (state?.email ?? '').isEmpty ? '未登录' : state!.email!,
              style: const TextStyle(fontSize: 13, color: _textSecondary),
            ),
          ),
          _infoRow(
            title: '吨吨ID',
            trailing: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(
                state?.displayId ?? '登录后生成',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, color: _textSecondary),
              ),
            ),
          ),
          if (loggedIn) ...[
            const Padding(
              padding: EdgeInsets.only(top: 10, bottom: 14),
              child: Divider(
                height: 1,
                thickness: 0.6,
                indent: 40,
                endIndent: 40,
                color: _divider,
              ),
            ),
            OutlinedButton(
              onPressed: _onSignOut,
              style: OutlinedButton.styleFrom(
                foregroundColor: _pink,
                side: const BorderSide(color: _pink, width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 34,
                  vertical: 11,
                ),
              ),
              child: const Text('退出登录', style: TextStyle(fontSize: 14)),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== 登录页 ====================

  /// 登录表单：邮箱 + 密码（暂代第三方登录，后续可平滑替换为微信/Apple）
  Widget _buildLoginForm() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: '邮箱',
                  border: InputBorder.none,
                ),
              ),
              const Divider(height: 1, color: _divider),
              TextField(
                controller: _pwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: '密码（至少 8 位）',
                  border: InputBorder.none,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FractionallySizedBox(
          widthFactor: _kLoginBtnWidthFactor,
          child: Material(
            color: _pink,
            borderRadius: BorderRadius.circular(15),
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: _busy ? null : _onSubmit,
              child: SizedBox(
                height: 54,
                child: Center(
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _registerMode ? '注册并登录' : '登录',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => setState(() => _registerMode = !_registerMode),
          child: Text(
            _registerMode ? '已有账号？去登录' : '没有账号？立即注册',
            style: const TextStyle(color: _textSecondary, fontSize: 13),
          ),
        ),
        const Text(
          '不登录也能正常记录，但数据只保存在本机；登录后才会同步到云端。',
          textAlign: TextAlign.center,
          style: TextStyle(color: _textSecondary, fontSize: 13, height: 1.5),
        ),
      ],
    );
  }

  Future<void> _onSubmit() async {
    if (!_agreed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先阅读并同意用户协议与隐私政策')));
      return;
    }
    final email = _emailCtrl.text.trim();
    final password = _pwdCtrl.text;
    if (!email.contains('@') || email.length < 5) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效的邮箱地址')));
      return;
    }
    if (password.length < 8) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('密码至少 8 位')));
      return;
    }
    setState(() => _busy = true);
    try {
      final storage = await ref.read(localStorageProvider.future);
      if (_registerMode) {
        await SyncService.signUp(storage, email, password);
      } else {
        await SyncService.signIn(storage, email, password);
      }
      final result = await SyncService.syncNow(storage);
      ref.invalidate(cloudBackupStateProvider);
      // 拉下来的历史数据要立刻回显：刷新首页与统计缓存
      ref.invalidate(todayEntriesProvider);
      ref.invalidate(yearEntriesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.failed
                ? '登录成功，但同步失败：${result.message}'
                : '已登录，同步完成（上行 ${result.pushed} 条，下行 ${result.pulled} 条）',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '登录失败：${e is SyncApiException ? e.message : '无法连接服务器'}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildAgreement() {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _agreed = !_agreed),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                _agreed
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 19,
                color: _agreed ? _textSecondary : const Color(0xFFC7C7CC),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 13,
                    color: _textSecondary,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: '我已阅读并同意'),
                    TextSpan(
                      text: '《服务协议》',
                      style: const TextStyle(color: _red),
                    ),
                    const TextSpan(text: '、'),
                    TextSpan(
                      text: '《隐私政策》',
                      style: const TextStyle(color: _red),
                    ),
                    const TextSpan(text: '和'),
                    TextSpan(
                      text: '《儿童个人信息保护规则》',
                      style: const TextStyle(color: _red),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text(
          '退出后将隐藏本机中该账号的数据，重新登录会恢复显示；'
          '未同步的记录仍保留在本机，重新登录该账号后继续同步。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final storage = await ref.read(localStorageProvider.future);
    await SyncService.signOut(storage);
    // 会员属于账号权益：退出登录后立刻清掉本地会员状态与权益
    await ref.read(membershipProvider.notifier).reset();
    ref.invalidate(cloudBackupStateProvider);
    // 身体数据/目标已恢复为登录前的游客档案
    ref.invalidate(profileProvider);
    // 记录按账号归属：退出后立刻刷新为游客视图，不再显示账号数据
    ref.invalidate(todayEntriesProvider);
    ref.invalidate(yearEntriesProvider);
    if (!mounted) return;
    setState(() {
      _emailCtrl.clear();
      _pwdCtrl.clear();
      _registerMode = false;
    });
  }

  Widget _buildDataSyncCard(CloudBackupState? state) {
    final pending = state?.pendingCount ?? 0;
    final connected = state?.isLoggedIn ?? false;
    final last = state?.lastBackupAt;
    final String status;
    if (!connected) {
      status = '登录后自动同步';
    } else if (!_autoSync) {
      status = '已关闭';
    } else if (_syncing) {
      status = '同步中…';
    } else if (pending > 0) {
      status = '待同步 $pending 条';
    } else if (last != null) {
      final t = last.toLocal();
      status =
          '已同步 ${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
    } else {
      status = '已开启';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/icons/menu/cloud_backup.svg',
            width: 22,
            height: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '数据同步',
                  style: TextStyle(fontSize: 15, color: _textDark),
                ),
                const SizedBox(height: 3),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    color: pending > 0 && connected && _autoSync
                        ? _pink
                        : _textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _autoSync && connected,
            onChanged: connected ? _toggleAutoSync : null,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF4DB8D8),
          ),
        ],
      ),
    );
  }

  /// 开关：开启后数据变动 / 冷启动 / 回前台自动同步（无感）
  Future<void> _toggleAutoSync(bool on) async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.setAutoSyncEnabled(on);
    if (!mounted) return;
    setState(() => _autoSync = on);
    if (on) await _runSync();
  }

  Future<void> _runSync() async {
    setState(() => _syncing = true);
    try {
      final storage = await ref.read(localStorageProvider.future);
      final result = await SyncService.syncNow(storage);
      ref.invalidate(cloudBackupStateProvider);
      // 拉下来的历史数据要立刻回显：刷新首页与统计缓存
      ref.invalidate(todayEntriesProvider);
      ref.invalidate(yearEntriesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.failed
                ? '同步失败：${result.message}'
                : '已同步：上行 ${result.pushed} 条，下行 ${result.pulled} 条',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Widget _infoRow({
    required String title,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 15, color: _textDark)),
          const SizedBox(width: 12),
          const Spacer(),
          trailing,
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }

  // ==================== 交互 ====================

  Future<void> _editNickname(WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改昵称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '请输入昵称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final storage = await ref.read(localStorageProvider.future);
    await storage.setAccountNickname(name);
    if (storage.hasAccountSession) {
      try {
        await SyncApi.updateNickname(storage.syncToken!, name);
      } catch (_) {
        // 离线时仅改本地，服务端下次联网不影响本地展示
      }
    }
    ref.invalidate(cloudBackupStateProvider);
  }
}
