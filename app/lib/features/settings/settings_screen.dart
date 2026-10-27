import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/notification/notification_service.dart';
import '../../core/storage/providers.dart';
import '../../core/sync/sync_api.dart';
import '../../shared/models/preferred_unit.dart';
import '../../shared/models/user_profile.dart';
import '../drink/providers/custom_beverage_provider.dart';
import '../home/challenge_sheet.dart' show challengeJoined;
import '../home/providers/home_providers.dart';
import '../reminder/reminder_providers.dart';
import '../stats/providers/stats_providers.dart';
import 'app_icon_screen.dart';
import 'app_prefs_screen.dart';
import 'calorie_screen.dart';
import 'cloud_backup_screen.dart';
import 'health_sync_screen.dart';
import 'reset_time_screen.dart';
import 'settings_flags.dart';
import 'widget_settings_screen.dart';
import '../membership/membership_provider.dart';
import '../membership/membership_screen.dart';

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
/// 8. 语言 / 帮助与支持
/// 9. 社区
/// 10. 分享 CTA
/// 11. "我们的网站" 推荐区
/// 12. 底部 footer（恢复购买 / 条款 / 版本号）
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // ---- 设计规范色板 ----
  static const _bgColor = Color(0xFFF2F2F7);
  static const _brandCyan = Color(0xFF4DB8D8);
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
                      ref
                              .watch(cloudBackupStateProvider)
                              .valueOrNull
                              ?.nickname ??
                          '喝水羊驼',
                    ),
                    const SizedBox(height: 12),
                    // ---- 卡片1：提醒 ----
                    _buildReminderCard(reminder),
                    const SizedBox(height: 12),
                    // ---- 卡片2：每日目标 ----
                    _buildGoalCard(profile),
                    const SizedBox(height: 12),
                    // ---- 卡片3：会员 ----
                    _buildMembershipCard(),
                    const SizedBox(height: 28),

                    // ---- 分组1：功能 ----
                    _buildSection(
                      '功能',
                      [
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
                                builder: (_) => const WidgetSettingsScreen()),
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
                                  builder: (_) => const AppIconScreen()),
                            ),
                          ),
                        ),
                        // 「水滴发射」行：一键切换首页饮品栏（弧线弹弓 / 经典直线）
                        ListenableBuilder(
                          listenable: SettingsFlags.instance,
                          builder: (ctx, _) => _settingRow(
                            iconAsset: 'launch.svg',
                            title: '水滴发射',
                            showArrow: false,
                            onTap: () => SettingsFlags.instance
                                .save(funPlay: !SettingsFlags.instance.funPlay),
                            trailing: Switch(
                              value: SettingsFlags.instance.funPlay,
                              activeThumbColor: const Color(0xFF4DB8D8),
                              onChanged: (v) =>
                                  SettingsFlags.instance.save(funPlay: v),
                            ),
                          ),
                        ),
                        // 「消消乐」行：进入饮品三消小游戏
                        _settingRow(
                          iconAsset: 'match3.svg',
                          title: '消消乐',
                          onTap: () => context.push('/game/match3'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // ---- 分组2：偏好 ----
                    _buildSection(
                      '偏好',
                      [
                        ListenableBuilder(
                          listenable: SettingsFlags.instance,
                          builder: (ctx, _) => _settingRow(
                            iconAsset: 'reset_time.svg',
                            title: '一天中的重置时间',
                            trailingText: SettingsFlags.instance.resetLabel,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const ResetTimeScreen()),
                            ),
                          ),
                        ),
                        ListenableBuilder(
                          listenable: SettingsFlags.instance,
                          builder: (ctx, _) => _settingRow(
                            iconAsset: 'calories.svg',
                            title: '卡路里',
                            trailingText:
                                SettingsFlags.instance.trackCalories
                                    ? '开'
                                    : '关',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const CalorieScreen()),
                            ),
                          ),
                        ),
                        _settingRow(
                          iconAsset: 'measure_unit.svg',
                          title: '测量单位',
                          trailingText:
                              ref.watch(preferredUnitProvider).symbol,
                          onTap: () => _showUnitPicker(),
                        ),
                        _settingRow(
                          iconAsset: 'app_sound.svg',
                          title: 'App、声音、动画',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AppPrefsScreen()),
                          ),
                        ),
                        // 「健康」同步与手表联动仅 iOS 提供；Android 不展示
                        if (Platform.isIOS) ...[
                          _settingRow(
                            iconAsset: 'health.svg',
                            title: '"健康"同步',
                            trailingText: ref
                                        .watch(healthSyncEnabledProvider)
                                        .valueOrNull ==
                                    true
                                ? '已连接'
                                : '连接',
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const HealthSyncScreen()),
                              );
                              ref.invalidate(healthSyncEnabledProvider);
                            },
                          ),
                          _settingRow(
                            iconAsset: 'watch.svg',
                            title: '手表',
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 28),

                    // ---- 分组4：语言 / 帮助 ----
                    _buildSection(
                      '',
                      [
                        _settingRow(
                          iconAsset: 'language.svg',
                          title: '语言',
                          trailingText: '简体中文',
                        ),
                        _settingRow(
                          iconAsset: 'help.svg',
                          title: '帮助与支持',
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // ---- 分组5：清除数据（保留入口） ----
                    _buildSection(
                      '',
                      [
                        _settingRow(
                          iconAsset: 'delete.svg',
                          title: '清除全部数据',
                          showArrow: false,
                          isDestructive: true,
                          onTap: _confirmClearAll,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // ---- 分组6：社区 ----
                    _buildSection(
                      '',
                      [
                        _settingRow(
                          iconAsset: 'social.svg',
                          title: '社交媒体上的喝水羊驼社区',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ---- CTA 分享按钮 ----
                    _buildShareButton(),
                    const SizedBox(height: 32),

                    // ---- "我们的网站" 推荐区 ----
                    _buildOurAppsSection(),
                    const SizedBox(height: 24),

                    // ---- 底部 footer ----
                    _buildFooter(),
                  ],
                ),
            Positioned(
              top: topInset + 6,
              left: 12,
              child: _buildBackButton(),
            ),
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

  // ==================== 卡片3：会员 ====================

  Widget _buildMembershipCard() {
    final m = ref.watch(membershipProvider);
    const gold = Color(0xFFD9A13B);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MembershipScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: m.isMember
                ? const [Color(0xFFFFF3DC), Color(0xFFFFE7BE)]
                : const [Color(0xFFEAF7FB), Color(0xFFDDF1F8)],
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Icon(Icons.workspace_premium,
                size: 30, color: m.isMember ? gold : const Color(0xFF3BB3DB)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.isMember ? '吨吨会员' : '开通吨吨会员',
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    m.isMember
                        ? m.statusLabel
                        : '解锁全部动物、饮品与专属小组件',
                    style: const TextStyle(
                      color: Color(0xFF7C7C82),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              m.isMember ? '管理' : '去开通',
              style: TextStyle(
                color: m.isMember ? gold : const Color(0xFF3BB3DB),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Icon(Icons.chevron_right,
                color: _arrowColor, size: 20),
          ],
        ),
      ),
    );
  }

  // ==================== 卡片0：账号信息 ====================

  /// 头像 + 昵称（含会员角标），点击进入账号信息页
  Widget _buildAccountCard(String nickname) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CloudBackupScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(2.5),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: Container(
                  color: const Color(0xFFEAF4FB),
                  alignment: Alignment.center,
                  child: SvgPicture.asset(
                    'assets/images/characters/alpaca.svg',
                    width: 46,
                    height: 46,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Row(
                children: [
                  Text(
                    nickname,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  if (ref.watch(membershipProvider).isMember) ...[
                    const SizedBox(width: 6),
                    SvgPicture.asset('assets/icons/menu/crown.svg',
                        width: 17, height: 17),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: _arrowColor, size: 22),
          ],
        ),
      ),
    );
  }

  // ==================== 卡片1：提醒 ====================

  Widget _buildReminderCard(ReminderSettings reminder) {
    return GestureDetector(
      onTap: () => context.push('/settings/reminder'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F6F6),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '提醒',
                    style: TextStyle(
                      color: _brandCyan,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '当你忘记喝水时的健康提醒'
                    '${reminder.enabled ? ' · 已开启' : ''}',
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            // 提醒图标（自带青色圆底的完整插画，替代原蓝色闹钟圆）
            SvgPicture.asset('assets/icons/menu/reminder.svg',
                width: 58, height: 58),
          ],
        ),
      ),
    );
  }

  // ==================== 卡片2：每日目标 ====================

  Widget _buildGoalCard(UserProfile profile) {
    return GestureDetector(
      onTap: () => context.push('/settings/goal'),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 12, 22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4DD0E1), Color(0xFF26C6DA)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        UnitFormat.volume(profile.dailyGoalMl, compact: true),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 46,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '常见目标',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '更改体重、日常活动或天气',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.white70,
                  size: 28,
                ),
              ],
            ),
          ),
        ],
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
          child: Column(
            children: _insertDividers(rows),
          ),
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
        out.add(const Padding(
          padding: EdgeInsets.only(left: 60),
          child: Divider(height: 1, thickness: 0.5, color: _separatorColor),
        ));
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
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 15,
                ),
              ),
            if (trailing != null) trailing,
            if (showArrow)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.chevron_right,
                  color: _arrowColor,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==================== 分享 CTA ====================

  Widget _buildShareButton() {
    return GestureDetector(
      onTap: () => _showSnack('分享功能开发中'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF5AC8FA), Color(0xFF34C759)],
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.celebration, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              '让你的朋友保持充足的水分',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== "我们的网站" 推荐区 ====================

  Widget _buildOurAppsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '我们的网站',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // App 图标 + "新" 标签
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SvgPicture.asset(
                      'assets/icons/menu/ai.svg',
                      width: 40,
                      height: 40,
                    ),
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        '新',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '鲲穹Ai工具箱',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '探索 AI 智能「懂你所言、答你所问、创你所需、解你所难、教你所学」',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // "立即获取" 按钮
              Align(
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: () => _showSnack('功能开发中'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '立即获取',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== 底部 footer ====================

  Widget _buildFooter() {
    return Column(
      children: [
        TextButton(
          onPressed: () async {
            bool ok;
            try {
              ok = await ref.read(membershipProvider.notifier).restore();
            } catch (_) {
              if (!mounted) return;
              _showSnack('恢复购买需要联网，请检查网络后重试');
              return;
            }
            if (!mounted) return;
            if (ok) {
              _showSnack('会员权益已恢复');
            } else {
              // 没有本地记录：引导到会员中心（正式版由服务端凭据恢复）
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MembershipScreen()),
              );
            }
          },
          child: const Text(
            '恢复购买',
            style: TextStyle(color: _textSecondary, fontSize: 14),
          ),
        ),
        TextButton(
          onPressed: () => _showSnack('条款和隐私'),
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
              const Text('你使用什么单位',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
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
                          borderRadius: BorderRadius.circular(26)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(u.label == 'ml（毫升）' ? 'ml (毫升)' : u.label,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800)),
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
        content: const Text(
          '将删除所有饮水记录、个人档案与设置，操作不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
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
    challengeJoined.value = false;

    // 同步桌面小组件：全部清零（此时 profile 已失效，目标显示回退由原生缺省处理）
    await syncWidgetFromSettings(ref.read, todayMl: 0, goalMl: 0, streakDays: 0);

    if (mounted) context.go('/onboarding');
  }
}
