import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notification/notification_service.dart';
import '../../core/storage/providers.dart';
import '../../shared/models/preferred_unit.dart';
import '../../shared/models/user_profile.dart';
import '../../shared/widgets/drink_illustration.dart';
import '../home/providers/home_providers.dart';
import '../reminder/reminder_providers.dart';
import '../stats/providers/stats_providers.dart';

/// PRD §2.8 设置页 — 对标原版 WaterLlama App 设计
///
/// 布局（自上而下）：
/// 1. 顶部导航：返回按钮 + "最新变化"
/// 2. 提醒卡片（浅青绿）
/// 3. 每日目标卡片（渐变青绿 + 红色角标）
/// 4. 推广卡片（薄荷绿 + 羊驼插画）
/// 5. 功能分组（饮料 / 小组件 / App图标）
/// 6. 偏好分组（重置时间 / 卡路里 / 单位 / App声音动画 / 健康同步 / Watch）
/// 7. iCloud 备份
/// 8. 语言 / 帮助与支持
/// 9. 社区
/// 10. 分享 CTA
/// 11. "我们的 App" 推荐区
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
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final reminder = ref.watch(reminderProvider);

    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _bgColor,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                  children: [
                    // ---- 卡片1：提醒 ----
                    _buildReminderCard(reminder),
                    const SizedBox(height: 12),
                    // ---- 卡片2：每日目标 ----
                    _buildGoalCard(profile),
                    const SizedBox(height: 28),

                    // ---- 分组1：功能 ----
                    _buildSection(
                      '功能',
                      [
                        _settingRow(
                          icon: Icons.local_drink,
                          iconBg: const Color(0xFFA8E6CF),
                          iconColor: const Color(0xFF2E7D32),
                          title: '添加/编辑饮料',
                          onTap: () => context.push('/drink/manage'),
                        ),
                        _settingRow(
                          icon: Icons.dashboard,
                          iconBg: const Color(0xFFB4D7F0),
                          iconColor: const Color(0xFF1976D2),
                          title: '小组件',
                        ),
                        _settingRow(
                          icon: Icons.pets,
                          iconBg: const Color(0xFFFFE082),
                          iconColor: const Color(0xFF5D4037),
                          title: 'App 图标',
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // ---- 分组2：偏好 ----
                    _buildSection(
                      '偏好',
                      [
                        _settingRow(
                          icon: Icons.restart_alt,
                          iconBg: const Color(0xFFFFB6C1),
                          iconColor: const Color(0xFFAD1457),
                          title: '一天中的重置时间',
                          trailingText: '00:00',
                        ),
                        _settingRow(
                          icon: Icons.local_fire_department,
                          iconBg: const Color(0xFFFFD93D),
                          iconColor: const Color(0xFFE65100),
                          title: '卡路里',
                          trailingText: '关',
                        ),
                        _settingRow(
                          icon: Icons.straighten,
                          iconBg: const Color(0xFFFFF3B0),
                          iconColor: const Color(0xFFF57F17),
                          title: '测量单位',
                          trailingText:
                              ref.watch(preferredUnitProvider).symbol,
                          onTap: () => _showUnitPicker(),
                        ),
                        _settingRow(
                          icon: Icons.tune,
                          iconBg: const Color(0xFFD4BBFF),
                          iconColor: const Color(0xFF6A1B9A),
                          title: 'App、声音、动画',
                          onTap: () => _showPreferencesSheet(),
                        ),
                        _settingRow(
                          icon: Icons.favorite,
                          iconBg: const Color(0xFFFF2D55),
                          iconColor: Colors.white,
                          title: 'Apple"健康"同步',
                          trailingText: '连接',
                        ),
                        _settingRow(
                          icon: Icons.watch,
                          iconBg: const Color(0xFFFFCCAA),
                          iconColor: const Color(0xFFD84315),
                          title: 'Apple Watch',
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // ---- 分组3：iCloud ----
                    _buildSection(
                      '',
                      [
                        _settingRow(
                          icon: Icons.cloud,
                          iconBg: const Color(0xFF5AC8FA),
                          iconColor: Colors.white,
                          title: 'iCloud 备份',
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // ---- 分组4：语言 / 帮助 ----
                    _buildSection(
                      '',
                      [
                        _settingRow(
                          icon: Icons.language,
                          iconBg: const Color(0xFFFF9500),
                          iconColor: Colors.white,
                          title: '语言',
                          trailingText: '简体中文',
                        ),
                        _settingRow(
                          icon: Icons.question_answer_rounded,
                          iconBg: const Color(0xFF8E8E93),
                          iconColor: Colors.white,
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
                          icon: Icons.delete_outline,
                          iconBg: Colors.redAccent,
                          iconColor: Colors.white,
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
                          icon: Icons.groups,
                          iconBg: const Color(0xFFAF52DE),
                          iconColor: Colors.white,
                          title: '社交媒体上的喝水羊驼社区',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ---- CTA 分享按钮 ----
                    _buildShareButton(),
                    const SizedBox(height: 32),

                    // ---- "我们的 App" 推荐区 ----
                    _buildOurAppsSection(),
                    const SizedBox(height: 24),

                    // ---- 底部 footer ----
                    _buildFooter(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 顶部导航 ====================

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左上：圆形浅灰背景返回按钮
          GestureDetector(
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
          ),
          // 右上："最新变化" 文字按钮
          TextButton(
            onPressed: () => _showSnack('最新变化'),
            child: const Text(
              '最新变化',
              style: TextStyle(color: _textSecondary, fontSize: 14),
            ),
          ),
        ],
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
            // 蓝色闹钟插画
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: Color(0xFF4FC3F7),
                shape: BoxShape.circle,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.alarm, color: Colors.white, size: 22),
                  Text(
                    '09:00',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
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
                        '${profile.dailyGoalMl}ml',
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
          // 右上角红色圆形角标
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text(
                '1',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
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

  /// 通用设置行：左图标(带圆角背景) + 标题 + 右侧值/箭头
  Widget _settingRow({
    required IconData icon,
    required Color iconBg,
    Color? iconColor,
    required String title,
    String? trailingText,
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
            // 图标背景块
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconBg,
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

  // ==================== "我们的 App" 推荐区 ====================

  Widget _buildOurAppsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '我们的 App',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    child: const DrinkIllustration(
                      beverageId: 'llama',
                      size: 48,
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
                      '卡路里羊驼',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '拍张照片，用 AI 跟踪卡路里。个人的减肥、'
                      '维持体重或增重计划。1,000 多个5星好评。',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: const [
                        Icon(Icons.apple, size: 14, color: _textSecondary),
                        SizedBox(width: 4),
                        Text(
                          '今日 App',
                          style: TextStyle(
                            color: _textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '· 100+ 个国家/地区',
                          style: TextStyle(
                            color: _textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
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
          onPressed: () => _showSnack('恢复购买'),
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
        const Text(
          '1.0.0 (1)',
          style: TextStyle(color: _arrowColor, fontSize: 11),
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

  void _showPreferencesSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _PreferencesSheet(),
    );
  }

  void _showUnitPicker() {
    final cur = ref.read(preferredUnitProvider);
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('测量单位'),
        children: [
          for (final u in PreferredUnit.values)
            RadioListTile<PreferredUnit>(
              value: u,
              groupValue: cur,
              title: Text(u.label),
              onChanged: (v) {
                if (v != null) {
                  ref.read(preferredUnitProvider.notifier).select(v);
                }
                Navigator.pop(ctx);
              },
            ),
        ],
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
          '将删除所有饮水记录、个人档案、会员状态与设置，操作不可恢复。',
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

    await NotificationService.cancelAll();
    final storage = await ref.read(localStorageProvider.future);
    await storage.clearAllData();

    // 重置内存态（保留主题偏好）
    ref.invalidate(profileProvider);
    ref.invalidate(memberProvider);
    ref.invalidate(todayEntriesProvider);
    ref.invalidate(dailyProgressProvider);
    ref.invalidate(dailyAnimalProvider);
    ref.invalidate(reminderProvider);
    ref.invalidate(soundEnabledProvider);
    ref.invalidate(last7DaysProvider);
    ref.invalidate(monthDataProvider);
    ref.invalidate(dayEntriesForProvider);
    ref.invalidate(streakProvider);
    ref.invalidate(checkinDaysProvider);

    if (mounted) context.go('/onboarding');
  }
}

// ============================================================
// App/声音/动画 偏好底部弹层（音效 + 外观主题）
// ============================================================

class _PreferencesSheet extends ConsumerWidget {
  const _PreferencesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sound = ref.watch(soundEnabledProvider);
    final themeMode = ref.watch(themeModeProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 拖拽指示器
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFD1D1D6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('App、声音、动画', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.music_note_outlined),
            title: const Text('喝水音效'),
            value: sound,
            onChanged: (v) =>
                ref.read(soundEnabledProvider.notifier).set(v),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
            child: Row(
              children: [
                const Icon(Icons.palette_outlined, size: 20),
                const SizedBox(width: 16),
                Text('外观', style: theme.textTheme.titleMedium),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('跟随系统'),
                icon: Icon(Icons.settings_suggest_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('浅色'),
                icon: Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('深色'),
                icon: Icon(Icons.dark_mode_outlined),
              ),
            ],
            selected: {themeMode},
            onSelectionChanged: (s) =>
                ref.read(themeModeProvider.notifier).set(s.first),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
