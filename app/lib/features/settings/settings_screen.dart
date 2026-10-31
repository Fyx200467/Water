import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/notification/notification_service.dart';
import '../../core/storage/providers.dart';
import '../../core/sync/session_watch.dart';
import '../../core/sync/sync_api.dart';
import '../../shared/models/preferred_unit.dart';
import '../../shared/widgets/account_avatar.dart';
import '../characters/character_art.dart';
import '../characters/character_catalog.dart';
import '../characters/character_screen.dart';
import '../characters/current_character_provider.dart';
import '../drink/providers/custom_beverage_provider.dart';
import 'feedback_screen.dart';
import '../challenges/challenge_service.dart' show challengeRevisionProvider;
import '../home/providers/home_providers.dart';
import '../membership/membership_provider.dart';
import '../membership/membership_screen.dart';
import '../reminder/reminder_providers.dart';
import '../stats/providers/stats_providers.dart';
import 'app_icon_screen.dart';
import 'app_prefs_screen.dart';
import 'calorie_screen.dart';
import 'cloud_backup_screen.dart';
import 'health_sync_screen.dart';
import 'legal_screen.dart';
import 'reset_time_screen.dart';
import 'settings_flags.dart';
import 'widget_settings_screen.dart';

/// PRD §2.8 设置页 — 对标原版 WaterLlama App 设计
///
/// 布局（自上而下）：
/// 1. 悬浮返回按钮（无标题行，页面内容铺满屏幕顶部）
/// 2. 提醒卡片（浅青绿）
/// 3. 每日目标卡片（渐变青绿 + 红色角标）
/// 4. 推广卡片（薄荷绿 + 羊驼插画）
/// 5. 功能分组（饮料 / 小组件 / App图标）
/// 6. 偏好分组（重置时间 / 卡路里 / 单位 / App声音动画 / 健康同步 / 手表）
/// 7. 云备份
/// 8. 帮助与支持（语言 / 社区入口暂时隐藏）
/// 9. 底部 footer（条款和隐私 / 版本号）
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // ---- 设计规范色板 ----
  static const _bgColor = Color(0xFFF2F2F7);
  static const _textPrimary = Color(0xFF1C1C1E);
  static const _textSecondary = Color(0xFF8E8E93);
  static const _arrowColor = Color(0xFFC7C7CC);
  static const _separatorColor = Color(0xFFE5E5EA);
  static const _cardRadius = 14.0;

  @override
  void initState() {
    super.initState();
    SettingsFlags.instance.ensureLoaded();
    _loadSelectedAppIcon();
  }

  /// 载入当前选中的 App 图标 id（供「App 图标」行小图标动态显示；
  /// 进入选择页换图标后由 selectedAppIcon 通知实时刷新）
  Future<void> _loadSelectedAppIcon() async {
    final storage = await ref.read(localStorageProvider.future);
    selectedAppIcon.value ??=
        storage.prefs.getString(kAppIconSelectionKey) ?? kDefaultAppIconId;
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final reminder = ref.watch(reminderProvider);
    final currentChar = ref.watch(effectiveCurrentCharacterProvider);

    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 内容铺满整个屏幕顶部（状态栏区域同为页面底色），返回按钮悬浮
    // 在页面之上、不随列表滚动（无标题行，无右上角「最新变化」）
    final topInset = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _bgColor,
        body: Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(16, topInset + 56, 16, 40),
              children: [
                // ---- 卡片0：账号信息 ----
                _buildAccountCard(
                  ref.watch(cloudBackupStateProvider).valueOrNull,
                ),
                const SizedBox(height: 12),
                // ---- 卡片1/2：提醒 + 饮水目标（左右并排） ----
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildReminderCard(reminder)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildGoalCard()),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ---- 分组1：功能 ----
                _buildSection('功能', [
                  // 「角色」行：左侧小头像显示当前角色，点击进入角色选择页
                  _settingRow(
                    leading: CharacterArt(
                      animalId: currentChar,
                      unlocked: true,
                      size: 30,
                      filePath: ref
                          .watch(characterCatalogProvider)
                          .valueOrNull
                          ?.uploadedFilePaths[currentChar],
                    ),
                    title: '角色',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CharacterScreen(),
                      ),
                    ),
                  ),
                  _settingRow(
                    iconAsset: 'edit_drink.svg',
                    title: '添加/编辑饮料',
                    onTap: () => context.push('/drink/manage'),
                  ),
                  _settingRow(
                    iconAsset: 'widget.svg',
                    title: '小组件',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WidgetSettingsScreen(),
                      ),
                    ),
                  ),
                  // 「App 图标」行：左侧小图标动态显示当前选中的桌面图标
                  ListenableBuilder(
                    listenable: selectedAppIcon,
                    builder: (ctx, _) => _settingRow(
                      leading: const AppIconPreview(size: 30),
                      title: 'App 图标',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AppIconScreen(),
                        ),
                      ),
                    ),
                  ),
                  // 「消消乐」行：进入饮品三消小游戏
                  _settingRow(
                    iconAsset: 'match3.svg',
                    title: '消消乐',
                    onTap: () => context.push('/game/match3'),
                  ),
                ]),
                const SizedBox(height: 28),

                // ---- 分组2：偏好 ----
                _buildSection('偏好', [
                  ListenableBuilder(
                    listenable: SettingsFlags.instance,
                    builder: (ctx, _) => _settingRow(
                      iconAsset: 'reset_time.svg',
                      title: '一天中的重置时间',
                      trailingText: SettingsFlags.instance.resetLabel,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ResetTimeScreen(),
                        ),
                      ),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: SettingsFlags.instance,
                    builder: (ctx, _) => _settingRow(
                      iconAsset: 'calories.svg',
                      title: '卡路里',
                      trailingText: SettingsFlags.instance.trackCalories
                          ? '开'
                          : '关',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CalorieScreen(),
                        ),
                      ),
                    ),
                  ),
                  _settingRow(
                    iconAsset: 'measure_unit.svg',
                    title: '测量单位',
                    trailingText: ref.watch(preferredUnitProvider).symbol,
                    onTap: () => _showUnitPicker(),
                  ),
                  _settingRow(
                    iconAsset: 'app_sound.svg',
                    title: 'App、声音、动画',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AppPrefsScreen()),
                    ),
                  ),
                  // 「健康」同步与手表联动仅 iOS 提供；Android 不展示
                  if (Platform.isIOS) ...[
                    _settingRow(
                      iconAsset: 'health.svg',
                      title: '"健康"同步',
                      trailingText:
                          ref.watch(healthSyncEnabledProvider).valueOrNull ==
                              true
                          ? '已连接'
                          : '连接',
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const HealthSyncScreen(),
                          ),
                        );
                        ref.invalidate(healthSyncEnabledProvider);
                      },
                    ),
                    _settingRow(iconAsset: 'watch.svg', title: '手表'),
                  ],
                ]),
                const SizedBox(height: 28),

                // ---- 分组4：帮助（语言 / 吨吨社区入口暂时隐藏） ----
                _buildSection('', [
                  _settingRow(
                    iconAsset: 'help.svg',
                    title: '帮助与支持',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FeedbackScreen()),
                    ),
                  ),
                ]),
                const SizedBox(height: 28),

                // ---- 分组5：清除数据（保留入口） ----
                _buildSection('', [
                  _settingRow(
                    iconAsset: 'delete.svg',
                    title: '清除全部数据',
                    showArrow: false,
                    isDestructive: true,
                    onTap: _confirmClearAll,
                  ),
                ]),
                const SizedBox(height: 28),

                // ---- 底部 footer ----
                _buildFooter(),
              ],
            ),
            Positioned(top: topInset + 6, left: 12, child: _buildBackButton()),
          ],
        ),
      ),
    );
  }

  // ==================== 悬浮返回按钮 ====================

  /// 圆形浅灰返回按钮（浮在页面内容之上，不随列表滚动）
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
          color: _textPrimary,
        ),
      ),
    );
  }

  // ==================== 卡片0：账号信息 ====================

  /// 头像 + 昵称 + 分隔线下的会员入口（按菜单页原型排版）
  Widget _buildAccountCard(CloudBackupState? state) {
    final m = ref.watch(membershipProvider);
    final loggedIn = state?.isLoggedIn ?? false;
    final nickname = state?.nickname ?? '未登录';
    const gold = Color(0xFFD9A13B);
    // 整卡不再套一层 GestureDetector：上半区进账号页，昵称改名，
    // 会员行单独进会员页，避免嵌套手势同时触发「打开弹窗 + 跳转页面」
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 26, 14, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CloudBackupScreen()),
            ),
            child: Row(
              children: [
                // 头像：未登录为灰色用户图标，登录后为上传头像 / 默认插画
                AccountAvatar(
                  size: 72,
                  loggedIn: loggedIn,
                  avatarPath: state?.avatarPath,
                  padding: 2,
                  background: loggedIn
                      ? const Color(0xFFDCEFFD)
                      : const Color(0xFFF2F2F7),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 昵称只做展示，修改入口放到账号信息页
                      Text(
                        nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _accountSubtitle(state),
                        style: TextStyle(
                          color: (state?.pendingCount ?? 0) > 0
                              ? const Color(0xFFEF7A8B)
                              : _textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: _arrowColor, size: 22),
              ],
            ),
          ),
          // 分隔线：细线且两端向内收，不与卡片信息同宽
          const Padding(
            padding: EdgeInsets.only(top: 26, bottom: 24),
            child: Divider(
              height: 1,
              thickness: 0.6,
              indent: 32,
              endIndent: 32,
              color: Color(0xFFDDDDE3),
            ),
          ),
          // 会员入口：未开通展示开通文案，已开通展示有效期
          GestureDetector(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MembershipScreen())),
            child: Row(
              children: [
                // 会员图标直接展示，不套方块底
                SvgPicture.asset(
                  'assets/icons/menu/member.svg',
                  width: 20,
                  height: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    m.isMember ? '吨吨会员 · ${m.statusLabel}' : '开通吨吨会员，积分限时兑换',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: m.isMember ? gold : _textPrimary,
                      fontSize: 14,
                      fontWeight: m.isMember
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: _arrowColor, size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 账号卡副标题：常驻同步状态提示（未登录时不展示同步信息）
  String _accountSubtitle(CloudBackupState? state) {
    if (state == null || !state.isLoggedIn) return '吨吨账户、云同步等';
    final pending = state.pendingCount;
    if (pending > 0) return '待同步 $pending 条记录，点此处理';
    final last = state.lastBackupAt?.toLocal();
    if (last != null) {
      final hh = last.hour.toString().padLeft(2, '0');
      final mm = last.minute.toString().padLeft(2, '0');
      return '已同步至云端 · 上次 $hh:$mm';
    }
    return '吨吨账户、云同步等';
  }

  // ==================== 卡片1/2：提醒 · 饮水目标（左右并排） ====================

  /// 提醒卡：浅青底 + 图标 + 文案
  Widget _buildReminderCard(ReminderSettings reminder) {
    return _buildQuickCard(
      iconAsset: 'assets/icons/menu/reminder.svg',
      // 闹钟图标在原画布中留白较多，放大 1.5 倍后与目标图标视觉大小一致
      iconScale: 1.5,
      caption: '当你忘记喝水时提醒你',
      background: const Color(0xFFD8F3F7),
      textColor: const Color(0xFF4C5A60),
      onTap: () => context.push('/settings/reminder'),
    );
  }

  /// 饮水目标卡：青底白字 + 白色图标
  Widget _buildGoalCard() {
    return _buildQuickCard(
      iconAsset: 'assets/icons/menu/goal.svg',
      caption: '我的饮水目标',
      background: const Color(0xFF1BC5DE),
      textColor: Colors.white,
      whiteIcon: true,
      onTap: () => context.push('/settings/goal'),
    );
  }

  /// 并排小卡片统一样式：图标距卡片顶部约 20%，文字紧跟图标下方
  /// （只做水平居中，两张卡文字起始位置一致）
  Widget _buildQuickCard({
    required String iconAsset,
    required String caption,
    required Color background,
    required Color textColor,
    required VoidCallback onTap,
    bool whiteIcon = false,
    double iconScale = 1,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SizedBox(
          // 内容区高度：112；图标上留白 20%，文字距卡片底部约 10%
          height: 112,
          child: Column(
            children: [
              const SizedBox(height: 22),
              Transform.scale(
                scale: iconScale,
                child: SvgPicture.asset(
                  iconAsset,
                  width: 40,
                  height: 40,
                  colorFilter: whiteIcon
                      ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
                      : null,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 32,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Text(
                    caption,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== iOS 分组列表 ====================

  Widget _buildSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title,
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_cardRadius),
          ),
          child: Column(children: _insertDividers(rows)),
        ),
      ],
    );
  }

  /// 在行之间插入缩进的分隔线（iOS grouped 风格）
  List<Widget> _insertDividers(List<Widget> rows) {
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      out.add(rows[i]);
      if (i < rows.length - 1) {
        out.add(
          const Padding(
            padding: EdgeInsets.only(left: 60),
            child: Divider(height: 1, thickness: 0.5, color: _separatorColor),
          ),
        );
      }
    }
    return out;
  }

  /// 菜单页彩色 SVG 图标（图标自带配色，26×26 直接渲染，无底色块）
  Widget _menuIcon(String asset) =>
      SvgPicture.asset('assets/icons/menu/$asset', width: 26, height: 26);

  /// 通用设置行：左图标(带圆角背景) + 标题 + 右侧值/箭头
  ///
  /// 图标三选一优先级：leading（自定义组件，如 App 图标动态预览）>
  /// iconAsset（菜单页彩色 SVG）> icon+iconBg（Material 图标 + 底色块）
  Widget _settingRow({
    IconData? icon,
    Color? iconBg,
    Color? iconColor,
    String? iconAsset,
    Widget? leading,
    required String title,
    String? trailingText,
    Widget? trailing,
    bool showArrow = true,
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap ?? () => _showSnack('功能开发中'),
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            if (leading != null)
              leading
            else if (iconAsset != null)
              _menuIcon(iconAsset)
            else
              // 图标背景块
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconBg ?? _textSecondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor ?? Colors.white, size: 18),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isDestructive ? Colors.redAccent : _textPrimary,
                  fontSize: 16,
                ),
              ),
            ),
            if (trailingText != null)
              Text(
                trailingText,
                style: const TextStyle(color: _textSecondary, fontSize: 15),
              ),
            if (trailing != null) trailing,
            if (showArrow)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.chevron_right, color: _arrowColor, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  // ==================== 底部 footer ====================

  Widget _buildFooter() {
    return Column(
      children: [
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const LegalScreen())),
          child: const Text(
            '条款和隐私',
            style: TextStyle(color: _textSecondary, fontSize: 12),
          ),
        ),
        GestureDetector(
          onLongPress: _showApiBaseDialog,
          behavior: HitTestBehavior.opaque,
          child: const Text(
            '1.0.0 (1)',
            style: TextStyle(color: _arrowColor, fontSize: 11),
          ),
        ),
      ],
    );
  }

  // ==================== 弹层入口 ====================

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  /// 开发入口：长按版本号修改接口地址（内网穿透调试用）
  Future<void> _showApiBaseDialog() async {
    final controller = TextEditingController(text: SyncApi.baseUrl);
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('接口地址'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://example.ngrok.io',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '内网穿透域名变化后改这里即可，无需重新打包；'
              '粘贴带 /api/v1 的地址会自动取域名部分',
              style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (input == null || !mounted) return;
    final normalized = SyncApi.normalize(input);
    if (normalized == null) {
      _showSnack('地址格式不正确');
      return;
    }
    SyncApi.configure(normalized);
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(SyncApi.prefsKey, normalized);
    ref.invalidate(membershipPlansProvider);
    if (!mounted) return;
    _showSnack('接口地址已更新：$normalized');
  }

  /// 测量单位弹层（对标原版：「你使用什么单位」+ 两个青色胶囊按钮）
  void _showUnitPicker() {
    final selected = ref.read(preferredUnitProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '你使用什么单位',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 26),
              for (final u in PreferredUnit.values) ...[
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: () {
                      ref.read(preferredUnitProvider.notifier).select(u);
                      // 单位切换后桌面小组件文案立即跟随（ml ↔ oz）
                      ref.read(widgetSettingsProvider.notifier).refreshWidget();
                      Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF35B5D6),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          u.label == 'ml（毫升）' ? 'ml (毫升)' : u.label,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (u == selected) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check_rounded, size: 20),
                        ],
                      ],
                    ),
                  ),
                ),
                if (u != PreferredUnit.values.last) const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 清除全部数据（保留原逻辑） ====================

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部数据？'),
        content: const Text('将删除所有饮水记录、个人档案与设置，操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // 通知取消容错：个别 ROM 上插件初始化/取消可能抛异常，
    // 不能让通知失败阻断数据清除（真机上已出现过「点了没反应」）
    try {
      await NotificationService.cancelAll();
    } catch (_) {}
    final storage = await ref.read(localStorageProvider.future);
    await storage.clearAllData();
    // 已登录时清除数据会同时清掉会话：断开实时通道并复位账号权益
    SessionWatch.stop();
    await ref.read(membershipProvider.notifier).reset();
    await ref.read(currentCharacterProvider.notifier).select('sheep');

    // 重置内存态（保留主题偏好）
    ref.invalidate(profileProvider);
    ref.invalidate(todayEntriesProvider);
    ref.invalidate(dailyProgressProvider);
    ref.invalidate(dailyAnimalProvider);
    ref.invalidate(reminderProvider);
    ref.invalidate(last7DaysProvider);
    ref.invalidate(monthDataProvider);
    ref.invalidate(dayEntriesForProvider);
    ref.invalidate(streakProvider);
    ref.invalidate(checkinDaysProvider);
    ref.invalidate(customBeveragesProvider);
    ref.invalidate(bestCheckinDaysProvider);
    // 静态单例内存缓存同步复位：设置标志 + 限时挑战参加状态
    SettingsFlags.instance.resetToDefaults();
    // 挑战参加状态随数据一并清除：让挑战页重新按空状态计算
    ref.read(challengeRevisionProvider.notifier).state++;

    // 同步桌面小组件：全部清零（此时 profile 已失效，目标显示回退由原生缺省处理）
    await syncWidgetFromSettings(
      ref.read,
      todayMl: 0,
      goalMl: 0,
      streakDays: 0,
    );

    if (mounted) context.go('/onboarding');
  }
}
