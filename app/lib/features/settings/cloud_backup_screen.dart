import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/storage/providers.dart';
import '../../core/sync/sync_service.dart';

/// 账号状态（当前为本地匿名身份，服务端接入后扩展为真实登录态）
class CloudBackupState {
  const CloudBackupState({
    required this.anonId,
    required this.nickname,
    this.lastBackupAt,
    this.cloudConnected = false,
    this.pendingCount = 0,
  });

  final String anonId;
  final String nickname;
  final DateTime? lastBackupAt;

  /// 已拿到服务端匿名身份（云同步可用）
  final bool cloudConnected;

  /// 本地待上行条数
  final int pendingCount;

  /// 是否已绑定正式账号（Apple / 微信）
  bool get isBound => false;

  /// 柠檬 ID：以 user- 开头的 UUID 形式展示本机标识
  String get lemonId {
    final h = anonId.padRight(32, '0');
    return 'user-${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20, 32)}';
  }
}

final cloudBackupStateProvider = FutureProvider<CloudBackupState>((ref) async {
  final storage = await ref.watch(localStorageProvider.future);
  return CloudBackupState(
    anonId: storage.accountAnonId,
    nickname: storage.accountNickname,
    lastBackupAt: storage.syncLastSyncAt ?? storage.accountLastBackupAt,
    cloudConnected: storage.hasSyncSession,
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
  static const _tabSelected = Color(0xFF33383E);
  static const _tabUnselected = Color(0xFFB4B9C0);
  static const _pink = Color(0xFFEF7A8B);
  static const _red = Color(0xFFE0533D);
  static const _appleDark = Color(0xFF2F3542);
  static const _wechatGreen = Color(0xFF52B556);
  static const _qqBlue = Color(0xFF2D3648);
  static const _divider = Color(0xFFF0F2F5);

  static const double _kTabItemW = 88;

  /// 登录按钮宽度占比（约为去掉白卡后内容宽度的 54%，与之前按钮的实际宽度一致）
  static const double _kLoginBtnWidthFactor = 0.54;

  final PageController _pageController = PageController();
  int _tab = 0;
  bool _agreed = true;
  bool _syncing = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cloudBackupStateProvider).valueOrNull;
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(height: topInset + 52),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    if (_tab != index) setState(() => _tab = index);
                  },
                  children: [
                    _centeredPage(_buildLoginTab(state), bottomInset),
                    _centeredPage(
                        _buildBasicInfoTab(context, ref, state), bottomInset),
                  ],
                ),
              ),
            ],
          ),
          // 标题
          Positioned(
            top: topInset + 12,
            left: 0,
            right: 0,
            child: const Center(
              child: Text(
                '账号信息',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                ),
              ),
            ),
          ),
          // 悬浮返回按钮（与设置页一致，不随内容滚动）
          Positioned(
            top: topInset + 6,
            left: 12,
            child: _buildBackButton(),
          ),
          // 底部悬浮 tab 栏
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset + 20,
            child: _buildTabBar(),
          ),
        ],
      ),
    );
  }

  // ==================== 页面内容容器 ====================

  /// 页面内容整体垂直居中：内容不足一屏时居中显示，超过一屏时可正常滚动
  Widget _centeredPage(List<Widget> children, double bottomInset) {
    const topPad = 6.0;
    final bottomPad = bottomInset + 110;
    return LayoutBuilder(
      builder: (context, cons) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, topPad, 16, bottomPad),
          child: ConstrainedBox(
            // 扣掉上下内边距后，内容在「可见区域」内垂直居中（避开悬浮 tab 栏）
            constraints:
                BoxConstraints(minHeight: cons.maxHeight - topPad - bottomPad),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        );
      },
    );
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
        child: const Icon(
          Icons.arrow_back_ios_new,
          size: 15,
          color: _textDark,
        ),
      ),
    );
  }

  // ==================== 底部悬浮 tab 栏 ====================

  Widget _buildTabBar() {
    const labels = ['登录', '基本信息'];
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: const Color(0xFFE7E7EA),
                ),
              _tabItem(labels[i], i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tabItem(String label, int index) {
    final selected = _tab == index;
    final color = selected ? _tabSelected : _tabUnselected;
    return SizedBox(
      width: _kTabItemW,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (selected) return;
          HapticFeedback.selectionClick();
          setState(() => _tab = index);
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== 登录页 ====================

  List<Widget> _buildLoginTab(CloudBackupState? state) {
    return [
      (state?.isBound ?? false) ? _buildBoundCard(state!) : _buildLoginActions(),
      if (!(state?.isBound ?? false)) ...[
        const SizedBox(height: 28),
        _buildAgreement(),
      ],
      const SizedBox(height: 26),
      _buildDataSyncCard(state),
    ];
  }

  /// 登录按钮组：直接铺在页面底色上，不再套白色卡片，保持简洁
  Widget _buildLoginActions() {
    return Column(
      children: [
        if (Platform.isIOS) ...[
          _loginButton(
            icon: Icons.apple,
            color: _appleDark,
            label: '通过 Apple 登录',
            widthFactor: _kLoginBtnWidthFactor,
          ),
          const SizedBox(height: 30),
        ],
        _loginButton(
          asset: 'assets/icons/login/qq.svg',
          color: _qqBlue,
          label: '通过 QQ 登录',
          widthFactor: _kLoginBtnWidthFactor,
        ),
        const SizedBox(height: 30),
        _loginButton(
          asset: 'assets/icons/login/wechat.svg',
          color: _wechatGreen,
          label: '通过微信登录',
          widthFactor: _kLoginBtnWidthFactor,
        ),
        const SizedBox(height: 18),
        const Text(
          '小建议：如果需要多设备同步数据，请尽量使用「微信登录」',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _loginButton({
    IconData? icon,
    String? asset,
    required Color color,
    required String label,
    double widthFactor = 1,
  }) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: _onLoginTap,
          child: SizedBox(
            height: 54,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // asset 优先：使用品牌 SVG 图标；否则回退到 Material 图标
                if (asset != null)
                  SvgPicture.asset(asset, width: 23, height: 23)
                else
                  Icon(icon, size: 20, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onLoginTap() {
    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先阅读并同意用户协议与隐私政策')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('登录服务接入中，下一步开放')),
    );
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
                        style: const TextStyle(color: _red)),
                    const TextSpan(text: '、'),
                    TextSpan(
                        text: '《隐私政策》',
                        style: const TextStyle(color: _red)),
                    const TextSpan(text: '和'),
                    TextSpan(
                        text: '《儿童个人信息保护规则》',
                        style: const TextStyle(color: _red)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 已登录：账号绑定列表 ====================

  Widget _buildBoundCard(CloudBackupState state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          _boundRow(
            icon: Icons.apple,
            iconColor: _appleDark,
            title: 'Apple账号',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: _pink,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '绑定',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          _boundRow(
            icon: Icons.forum_rounded,
            iconColor: _wechatGreen,
            title: '微信账号',
            trailing: Text(
              state.nickname,
              style: const TextStyle(fontSize: 13, color: _textSecondary),
            ),
          ),
          const Divider(height: 20, color: _divider),
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: _pink,
              side: const BorderSide(color: _pink, width: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
            ),
            child: const Text('退出登录', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _boundRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: const TextStyle(fontSize: 15, color: _textDark)),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildDataSyncCard(CloudBackupState? state) {
    final pending = state?.pendingCount ?? 0;
    final connected = state?.cloudConnected ?? false;
    final last = state?.lastBackupAt;
    final String status;
    if (_syncing) {
      status = '同步中…';
    } else if (!connected) {
      status = '待连接';
    } else if (pending > 0) {
      status = '待同步 $pending 条';
    } else if (last != null) {
      final t = last.toLocal();
      status = '已同步 ${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
    } else {
      status = '已连接';
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _syncing ? null : _runSync,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              SvgPicture.asset('assets/icons/menu/cloud_backup.svg',
                  width: 22, height: 22),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('数据同步',
                    style: TextStyle(fontSize: 15, color: _textDark)),
              ),
              Text(status,
                  style: TextStyle(
                    fontSize: 13,
                    color: pending > 0 ? _pink : _textSecondary,
                  )),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: Color(0xFFC7C7CC)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runSync() async {
    setState(() => _syncing = true);
    try {
      final storage = await ref.read(localStorageProvider.future);
      final result = await SyncService.syncNow(storage);
      ref.invalidate(cloudBackupStateProvider);
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

  // ==================== 基本信息页 ====================

  List<Widget> _buildBasicInfoTab(
      BuildContext context, WidgetRef ref, CloudBackupState? state) {
    return [
      _infoCard(
        child: _infoRow(
          title: '头像',
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('更换头像将在账号接入后开放')),
            );
          },
          trailing: Container(
            width: 42,
            height: 42,
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Color(0x14000000), blurRadius: 6),
              ],
            ),
            child: ClipOval(
              child: Container(
                color: const Color(0xFFEAF4FB),
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  'assets/images/characters/alpaca.svg',
                  width: 30,
                  height: 30,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _infoCard(
        child: _infoRow(
          title: '昵称',
          onTap: () => _editNickname(ref, state?.nickname ?? ''),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state?.nickname ?? '—',
                style: const TextStyle(fontSize: 14, color: _textSecondary),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: Color(0xFFC7C7CC)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      _infoCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            children: [
              const Text('吨吨ID',
                  style: TextStyle(fontSize: 15, color: _textDark)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  state?.lemonId ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style:
                      const TextStyle(fontSize: 11, color: _textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _infoCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: child,
    );
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
          Text(title,
              style: const TextStyle(fontSize: 15, color: _textDark)),
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
    ref.invalidate(cloudBackupStateProvider);
  }
}
