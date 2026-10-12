import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notification/notification_service.dart';
import '../../shared/widgets/drink_illustration.dart';
import 'reminder_providers.dart';

/// 提醒设置全屏页面 — 对标原版 WaterLlama App
///
/// 布局（自上而下）：
/// 1. 顶部导航：圆形浅灰返回按钮
/// 2. 主卡片"饮水提醒"：标题 + 开/关 + iOS 开关
/// 3. （开关开启时）Tab 选项框：智能提醒 / 自定义提醒
/// 4. 当前 Tab 配置面板（智能：间隔+时间+星期+声音；自定义：时间chips+文案+免打扰）
/// 5. 高级设置卡片组（延后/达到目标停止/进度标题/激励标题/事实/自定义信息/快速添加/贴纸）
/// 6. 分组"其他通知"：5 个子卡片
class ReminderSettingsScreen extends ConsumerStatefulWidget {
  const ReminderSettingsScreen({super.key});

  @override
  ConsumerState<ReminderSettingsScreen> createState() =>
      _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState
    extends ConsumerState<ReminderSettingsScreen> {
  // ---- 设计规范色板 ----
  static const _bgColor = Color(0xFFF2F2F7);
  static const _textPrimary = Color(0xFF1C1C1E);
  static const _textSecondary = Color(0xFF8E8E93);
  static const _arrowColor = Color(0xFFC7C7CC);
  static const _separatorColor = Color(0xFFE5E5EA);
  static const _brandCyan = Color(0xFF5AC8FA);
  static const _cardRadius = 14.0;

  static const _weekdays = ['日', '一', '二', '三', '四', '五', '六'];
  static const _cupSizes = [120, 250, 330, 500, 1000];
  static const _sounds = <String, String>{
    'bamboo': '竹子',
    'glass': '玻璃',
    'bike': '自行车',
    'conga': '康加鼓',
    'submarine': '潜水艇',
  };

  late final TextEditingController _messageCtrl;

  @override
  void initState() {
    super.initState();
    _messageCtrl = TextEditingController(
      text: ref.read(reminderProvider).message,
    );
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reminder = ref.watch(reminderProvider);

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
                    // ---- 主卡片：饮水提醒 ----
                    _buildMainReminderCard(reminder),
                    if (reminder.enabled) ...[
                      const SizedBox(height: 12),
                      _buildTabSelector(),
                      const SizedBox(height: 12),
                      _buildCurrentPanel(reminder),
                      const SizedBox(height: 20),
                      _buildAdvancedSettings(),
                    ],
                    const SizedBox(height: 28),

                    // ---- 分组：其他通知 ----
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Text(
                        '其他通知',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _buildOtherNotificationsGroup(),
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
        children: [
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
          const SizedBox(width: 12),
          const Text(
            '提醒',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 主卡片：饮水提醒 ====================

  Widget _buildMainReminderCard(ReminderSettings reminder) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '饮水提醒',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            reminder.enabled ? '开' : '关',
            style: const TextStyle(color: _textSecondary, fontSize: 15),
          ),
          const SizedBox(width: 8),
          _iosSwitch(
            value: reminder.enabled,
            onChanged: _toggleReminder,
          ),
        ],
      ),
    );
  }

  // ==================== Tab 选项框 ====================

  Widget _buildTabSelector() {
    final mode = ref.watch(reminderModeProvider);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEFEFF2),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _tabItem(
              label: '智能提醒',
              selected: mode == 'smart',
              onTap: () => ref.read(reminderModeProvider.notifier).set('smart'),
            ),
          ),
          Expanded(
            child: _tabItem(
              label: '自定义提醒',
              selected: mode == 'custom',
              onTap: () =>
                  ref.read(reminderModeProvider.notifier).set('custom'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabItem({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _brandCyan : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.check, color: Colors.white, size: 16),
              ),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : _textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 当前 Tab 面板 ====================

  Widget _buildCurrentPanel(ReminderSettings reminder) {
    final mode = ref.watch(reminderModeProvider);
    return mode == 'smart'
        ? _buildSmartPanel(reminder)
        : _buildCustomPanel(reminder);
  }

  // ==================== 智能提醒面板 ====================

  Widget _buildSmartPanel(ReminderSettings reminder) {
    final interval = ref.watch(notificationIntervalMinutesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 白色圆角卡片：通知间隔 + 时间设置
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '通知间隔',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              // 小时数显示
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${interval ~/ 60}',
                    style: const TextStyle(
                      color: _brandCyan,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '小时',
                    style: TextStyle(color: _textSecondary, fontSize: 14),
                  ),
                  const Spacer(),
                  Text(
                    '${interval % 60}',
                    style: const TextStyle(
                      color: _brandCyan,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '分钟',
                    style: TextStyle(color: _textSecondary, fontSize: 14),
                  ),
                ],
              ),
              // 小时滑块（1-8 小时）
              Slider(
                value: (interval ~/ 60).clamp(1, 8).toDouble(),
                min: 1,
                max: 8,
                divisions: 7,
                activeColor: _brandCyan,
                onChanged: (v) {
                  final h = v.round();
                  final m = interval % 60;
                  ref
                      .read(notificationIntervalMinutesProvider.notifier)
                      .set(h * 60 + m);
                },
              ),
              // 分钟滑块（0/15/30/45）
              Slider(
                value: (interval % 60).toDouble(),
                min: 0,
                max: 45,
                divisions: 3,
                activeColor: _brandCyan,
                onChanged: (v) {
                  final m = v.round();
                  final h = interval ~/ 60;
                  ref
                      .read(notificationIntervalMinutesProvider.notifier)
                      .set(h * 60 + m);
                },
              ),
              const SizedBox(height: 8),
              // 时间设置行
              _timeRow(
                '开始时间',
                reminder.dndStart ?? '08:00',
                onTap: () => _pickTime(isStart: true),
              ),
              const Divider(height: 1, color: _separatorColor),
              _timeRow(
                '结束时间',
                reminder.dndEnd ?? '22:00',
                onTap: () => _pickTime(isStart: false),
              ),
              const SizedBox(height: 12),
              // 说明 + 灯泡
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: const Text(
                      '智能提醒：仅在你忘记喝水时才发送通知',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _brandCyan.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lightbulb,
                      color: _brandCyan,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 星期几选择器
        _buildWeekdaySelector(),
        const SizedBox(height: 12),

        // 声音选择器
        _buildSoundSelector(),
      ],
    );
  }

  Widget _timeRow(String label, String value, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                color: _brandCyan,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right,
              color: _arrowColor,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 星期几选择器 ====================

  Widget _buildWeekdaySelector() {
    final days = ref.watch(reminderWeekdaysProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '星期几',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                _weekdayButton(i, days[i]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weekdayButton(int index, bool selected) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        ref.read(reminderWeekdaysProvider.notifier).toggle(index);
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: selected ? _brandCyan : const Color(0xFFEFEFF2),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          _weekdays[index],
          style: TextStyle(
            color: selected ? Colors.white : _textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ==================== 声音选择器 ====================

  Widget _buildSoundSelector() {
    final selectedSound = ref.watch(reminderSoundProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '声音',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _sounds.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final entry = _sounds.entries.elementAt(i);
                final id = entry.key;
                final name = entry.value;
                final selected = id == selectedSound;
                final locked = id != 'bamboo';
                return _soundItem(
                  name: name,
                  selected: selected,
                  locked: locked,
                  onTap: () {
                    if (locked) {
                      _showSnack('会员功能开发中');
                      return;
                    }
                    ref
                        .read(reminderSoundProvider.notifier)
                        .set(id);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _soundItem({
    required String name,
    required bool selected,
    required bool locked,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: selected
                        ? _brandCyan
                        : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.music_note,
                    color: selected ? Colors.white : _textSecondary,
                    size: 24,
                  ),
                ),
                if (selected)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                if (locked)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock,
                        size: 10,
                        color: _textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              name,
              style: TextStyle(
                color: selected ? _brandCyan : _textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 自定义提醒面板 ====================

  Widget _buildCustomPanel(ReminderSettings reminder) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '提醒时间',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in reminder.times)
                InputChip(
                  label: Text(t),
                  onDeleted: () => _removeTime(t),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
                onPressed: _addTime,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 自定义提醒文案
          TextField(
            controller: _messageCtrl,
            decoration: InputDecoration(
              labelText: '提醒文案',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check),
                tooltip: '保存文案',
                onPressed: _saveMessage,
              ),
            ),
            onSubmitted: (_) => _saveMessage(),
          ),
          const SizedBox(height: 16),

          // 免打扰时段
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('免打扰时段'),
            subtitle: Text(
              reminder.dndEnabled
                  ? '${reminder.dndStart ?? '22:00'} - '
                      '${reminder.dndEnd ?? '07:00'} 内不提醒'
                  : '关闭中',
            ),
            value: reminder.dndEnabled,
            activeTrackColor: _brandCyan.withValues(alpha: 0.5),
            activeThumbColor: _brandCyan,
            onChanged: (v) async {
              HapticFeedback.selectionClick();
              var next = reminder.copyWith(dndEnabled: v);
              if (v && (next.dndStart == null || next.dndEnd == null)) {
                next = next.copyWith(dndStart: '22:00', dndEnd: '07:00');
              }
              await ref.read(reminderProvider.notifier).update(next);
            },
          ),
          if (reminder.dndEnabled)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDnd(isStart: true),
                    child: Text('开始 ${reminder.dndStart ?? '22:00'}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDnd(isStart: false),
                    child: Text('结束 ${reminder.dndEnd ?? '07:00'}'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ==================== 高级设置卡片组 ====================

  Widget _buildAdvancedSettings() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Column(
        children: _insertDividers([
          // 1. 延后（锁定）
          _advancedRow(
            icon: Icons.history,
            title: '延后',
            subtitle: '长按通知可将你的提醒延后',
            locked: true,
            trailingText: '无',
          ),
          // 2. 达到目标时停止
          _advancedSwitchRow(
            icon: Icons.emoji_events_outlined,
            title: '达到目标时停止',
            subtitle: '饮水目标完成 100% 后停止发送提醒',
            provider: stopAtGoalEnabledProvider,
          ),
          // 3. 饮水进度标题
          _advancedSwitchRow(
            icon: Icons.water_drop_outlined,
            title: '饮水进度标题',
            subtitle: '在通知标题中显示剩余水量。例如：剩余 800ml',
            provider: progressTitleEnabledProvider,
          ),
          // 4. 激励性标题
          _advancedSwitchRow(
            icon: Icons.thumb_up_alt_outlined,
            title: '激励性标题',
            subtitle: '在提醒标题中显示鼓励性信息。例如：你做到了！',
            provider: motivationalTitleEnabledProvider,
          ),
          // 5. 饮水事实
          _advancedSwitchRow(
            icon: Icons.description_outlined,
            title: '饮水事实',
            subtitle: '每次提醒都包含有关适当饮水益处的有趣事实',
            provider: waterFactsEnabledProvider,
          ),
          // 6. 自定义信息（锁定）
          _advancedRow(
            icon: Icons.edit_outlined,
            title: '自定义信息',
            subtitle: '提醒中的个人自定义文本',
            locked: true,
            trailingText: '无',
          ),
          // 7. 快速添加
          _advancedQuickAddRow(),
          // 8. 贴纸
          _advancedStickerRow(),
        ]),
      ),
    );
  }

  /// 锁定/带箭头的高级设置行
  Widget _advancedRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool locked,
    String? trailingText,
  }) {
    return InkWell(
      onTap: locked
          ? () => _showSnack('会员功能开发中')
          : () => _showSnack('功能开发中'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: _textPrimary, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 16,
                        ),
                      ),
                      if (locked) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.lock,
                          size: 12,
                          color: _textSecondary,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (trailingText != null)
              Text(
                trailingText,
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 15,
                ),
              ),
            const Icon(
              Icons.chevron_right,
              color: _arrowColor,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  /// 带开关的高级设置行
  Widget _advancedSwitchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required StateNotifierProvider<NotificationToggleNotifier, bool> provider,
  }) {
    final value = ref.watch(provider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: _textPrimary, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _iosSwitch(
            value: value,
            onChanged: (v) async {
              HapticFeedback.selectionClick();
              await ref.read(provider.notifier).set(v);
            },
          ),
        ],
      ),
    );
  }

  /// 快速添加行（开关 + 5 个杯子容量按钮）
  Widget _advancedQuickAddRow() {
    final enabled = ref.watch(quickAddEnabledProvider);
    final cupMl = ref.watch(quickAddCupMlProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.touch_app_outlined,
                  color: _textPrimary, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '快速添加',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '长按通知即可快速饮水。设置你的杯子尺寸：',
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
              _iosSwitch(
                value: enabled,
                onChanged: (v) async {
                  HapticFeedback.selectionClick();
                  await ref.read(quickAddEnabledProvider.notifier).set(v);
                },
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ml in _cupSizes)
                  _cupButton(
                    ml: ml,
                    selected: ml == cupMl,
                    onTap: () => ref
                        .read(quickAddCupMlProvider.notifier)
                        .set(ml),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cupButton({
    required int ml,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _brandCyan : const Color(0xFFEFEFF2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '${ml}ml',
          style: TextStyle(
            color: selected ? Colors.white : _textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// 贴纸行（开关 + 羊驼贴纸预览）
  Widget _advancedStickerRow() {
    final enabled = ref.watch(stickersEnabledProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sentiment_satisfied_outlined,
                  color: _textPrimary, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      '贴纸',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '在通知中显示有趣的随机喝水羊驼贴纸',
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
              _iosSwitch(
                value: enabled,
                onChanged: (v) async {
                  HapticFeedback.selectionClick();
                  await ref.read(stickersEnabledProvider.notifier).set(v);
                },
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const DrinkIllustration(
                  beverageId: 'llama',
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: const Text(
                    '羊驼贴纸将在通知中随机出现 🦙',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ==================== 分组：其他通知（5 个子卡片） ====================

  Widget _buildOtherNotificationsGroup() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Column(
        children: _insertDividers([
          _notificationToggleRow(
            icon: Icons.event_note_outlined,
            title: '你的进度回顾',
            subtitle: '饮水回顾生成后立即通知：每周、按月、按年',
            provider: progressReviewEnabledProvider,
          ),
          _notificationToggleRow(
            icon: Icons.celebration_outlined,
            title: '节假日',
            subtitle: '在固定假日和一些有趣的节日（如国家羊驼日）期间，'
                '鼓励你多喝水的通知。',
            provider: holidayEnabledProvider,
          ),
          _notificationToggleRow(
            icon: Icons.flag_outlined,
            title: '限时挑战',
            subtitle: '限时挑战当天的通知',
            provider: challengeEnabledProvider,
          ),
          _notificationToggleRow(
            icon: Icons.nights_stay_outlined,
            title: '饮水提示',
            provider: drinkTipEnabledProvider,
          ),
          _notificationToggleRow(
            icon: Icons.notifications_active_outlined,
            title: '特别优惠',
            provider: specialOfferEnabledProvider,
          ),
        ]),
      ),
    );
  }

  /// 通知开关行：左线框图标(无背景) + 标题/说明 + 右 iOS 开关
  Widget _notificationToggleRow({
    required IconData icon,
    Color iconColor = const Color(0xFF1C1C1E),
    required String title,
    String? subtitle,
    required StateNotifierProvider<NotificationToggleNotifier, bool> provider,
  }) {
    final value = ref.watch(provider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 16,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _iosSwitch(
            value: value,
            onChanged: (v) async {
              HapticFeedback.selectionClick();
              await ref.read(provider.notifier).set(v);
            },
          ),
        ],
      ),
    );
  }

  // ==================== 通用辅助 ====================

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  /// iOS 风格开关（开启色 #5AC8FA 蓝青色）
  Widget _iosSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Switch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: _brandCyan.withValues(alpha: 0.5),
      activeThumbColor: _brandCyan,
    );
  }

  /// 在行之间插入缩进分隔线（iOS grouped 风格）
  List<Widget> _insertDividers(List<Widget> rows) {
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      out.add(rows[i]);
      if (i < rows.length - 1) {
        out.add(const Padding(
          padding: EdgeInsets.only(left: 52),
          child: Divider(height: 1, thickness: 0.5, color: _separatorColor),
        ));
      }
    }
    return out;
  }

  // ==================== 提醒逻辑（全部保留） ====================

  Future<void> _toggleReminder(bool v) async {
    HapticFeedback.selectionClick();
    if (v) {
      final granted = await NotificationService.requestPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未获得通知权限，请到系统设置中开启')),
        );
        return;
      }
    }
    final cur = ref.read(reminderProvider);
    await ref
        .read(reminderProvider.notifier)
        .update(cur.copyWith(enabled: v));
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _parseTod(String s) {
    final p = s.split(':');
    return TimeOfDay(
      hour: int.tryParse(p.isNotEmpty ? p[0] : '') ?? 22,
      minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
    );
  }

  /// 智能提醒面板的开始/结束时间选择
  Future<void> _pickTime({required bool isStart}) async {
    final cur = ref.read(reminderProvider);
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTod(
        isStart ? (cur.dndStart ?? '08:00') : (cur.dndEnd ?? '22:00'),
      ),
    );
    if (picked == null || !mounted) return;
    final t = _fmt(picked);
    await ref.read(reminderProvider.notifier).update(
          isStart ? cur.copyWith(dndStart: t) : cur.copyWith(dndEnd: t),
        );
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked == null || !mounted) return;
    final cur = ref.read(reminderProvider);
    final t = _fmt(picked);
    if (cur.times.contains(t)) return;
    final times = [...cur.times, t]..sort();
    await ref
        .read(reminderProvider.notifier)
        .update(cur.copyWith(times: times));
  }

  Future<void> _removeTime(String t) async {
    final cur = ref.read(reminderProvider);
    await ref.read(reminderProvider.notifier).update(
          cur.copyWith(times: cur.times.where((x) => x != t).toList()),
        );
  }

  Future<void> _saveMessage() async {
    final msg = _messageCtrl.text.trim();
    final cur = ref.read(reminderProvider);
    if (msg.isEmpty || msg == cur.message) return;
    await ref
        .read(reminderProvider.notifier)
        .update(cur.copyWith(message: msg));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提醒文案已保存')),
      );
    }
  }

  Future<void> _pickDnd({required bool isStart}) async {
    final cur = ref.read(reminderProvider);
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTod(
        isStart ? (cur.dndStart ?? '22:00') : (cur.dndEnd ?? '07:00'),
      ),
    );
    if (picked == null || !mounted) return;
    final t = _fmt(picked);
    await ref.read(reminderProvider.notifier).update(
          isStart
              ? cur.copyWith(dndStart: t)
              : cur.copyWith(dndEnd: t),
        );
  }
}
