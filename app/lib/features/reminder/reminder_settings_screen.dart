import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notification/notification_service.dart';
import 'reminder_providers.dart';

/// 提醒设置全屏页面 — 对标竞品简洁布局
///
/// 布局（自上而下）：
/// 1. 顶部导航：圆形浅灰返回按钮 + 标题「提醒」
/// 2. 提醒卡：合并单卡（顶部间隔提醒铃铛行 + 其下方「选择删除」行 +
///    各时间行 + 底部添加更多时间）
/// 3. 高级设置卡（达到目标停止/进度标题/激励标题/饮水事实/
///    自定义信息/快速添加/贴纸）
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
  static const _cardRadius = 16.0;
  static const _bellIconColor = Color(0xFF8CB6F0);
  static const _dangerRed = Color(0xFFFF3B30);

  /// 定时提醒是否处于删除模式（「选择删除」→「完成」）
  bool _deleteMode = false;

  @override
  Widget build(BuildContext context) {
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
                    // ---- 提醒卡（间隔行 + 选择删除 + 时间行合并单卡） ----
                    _buildReminderCard(),
                    const SizedBox(height: 20),
                    // ---- 高级设置 ----
                    _buildAdvancedSettings(),
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

  // ==================== 区块：定时提醒（合并单卡） ====================

  /// 合并提醒卡：顶部间隔提醒铃铛行 + 各时间行 + 底部「添加更多时间」，
  /// 行距参考竞品（舒展），行间细分隔线
  Widget _buildReminderCard() {
    final reminder = ref.watch(reminderProvider);
    final times = reminder.times;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Column(
        children: [
          _intervalRow(),
          const Padding(
            padding: EdgeInsets.only(left: 52),
            child:
                Divider(height: 1, thickness: 0.5, color: _separatorColor),
          ),
          _deleteToggleRow(),
          const Padding(
            padding: EdgeInsets.only(left: 52),
            child:
                Divider(height: 1, thickness: 0.5, color: _separatorColor),
          ),
          for (var i = 0; i < times.length; i++) ...[
            _timeRow(reminder, times[i]),
            if (i < times.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 52),
                child: Divider(
                    height: 1, thickness: 0.5, color: _separatorColor),
              ),
          ],
          if (times.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Text(
                '暂无定时提醒，点击下方添加',
                style: TextStyle(color: _textSecondary, fontSize: 14),
              ),
            ),
          _addTimeRow(),
        ],
      ),
    );
  }

  /// 间隔提醒行：🔔 每隔 N分钟 提醒一次 + 开关
  /// 点行（非开关）弹出间隔选择底部弹层
  Widget _intervalRow() {
    final interval = ref.watch(notificationIntervalMinutesProvider);
    final enabled = ref.watch(intervalEnabledProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 30, 14, 15),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_none_rounded,
            color: _bellIconColor,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showIntervalPicker,
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 16,
                  ),
                  children: [
                    const TextSpan(text: '每隔 '),
                    TextSpan(
                      text: '$interval分钟',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const TextSpan(text: ' 提醒一次'),
                  ],
                ),
              ),
            ),
          ),
          _IosSwitch(
            value: enabled,
            onChanged: (v) async {
              if (v) await _ensureNotificationPermission();
              await ref.read(intervalEnabledProvider.notifier).set(v);
              await ref.read(reminderProvider.notifier).rescheduleNow();
            },
          ),
        ],
      ),
    );
  }

  /// 间隔选择底部弹层：滑块 15~180 分钟（步长 15）+ 完成按钮
  void _showIntervalPicker() {
    var value = ref.read(notificationIntervalMinutesProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '提醒间隔',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$value 分钟',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _brandCyan,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Slider(
                    value: value.clamp(15, 180).toDouble(),
                    min: 15,
                    max: 180,
                    divisions: 11,
                    activeColor: _brandCyan,
                    onChanged: (v) {
                      setSheet(() => value = v.round());
                    },
                    onChangeEnd: (v) async {
                      await ref
                          .read(notificationIntervalMinutesProvider.notifier)
                          .set(v.round());
                      await ref
                          .read(reminderProvider.notifier)
                          .rescheduleNow();
                    },
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _brandCyan,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(sheetCtx),
                    child: const Text(
                      '完成',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 删除模式入口行：右对齐「选择删除 / 完成」（位于间隔行下方）
  Widget _deleteToggleRow() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _deleteMode = !_deleteMode),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Row(
          children: [
            const Spacer(),
            Text(
              _deleteMode ? '完成' : '选择删除',
              style: TextStyle(
                color: _deleteMode ? _brandCyan : _textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeRow(ReminderSettings reminder, String time) {
    final disabled = reminder.disabledTimes.contains(time);
    return InkWell(
      onTap: () => _deleteMode
          ? _removeTime(time)
          : _editTime(time, disabled: disabled),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 14, 18),
        child: Row(
          children: [
            const Icon(Icons.access_time_rounded,
                color: _textPrimary, size: 22),
            const SizedBox(width: 14),
            Text(
              time,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (_deleteMode)
              // 固定 26 高与开关一致，避免切换删除模式时行高变化导致跳动
              const SizedBox(
                height: 26,
                child: Center(
                  child:
                      Icon(Icons.do_not_disturb_on, color: _dangerRed),
                ),
              )
            else
              _IosSwitch(
                value: !disabled,
                onChanged: (v) => _toggleTime(time, enable: v),
              ),
          ],
        ),
      ),
    );
  }

  /// 卡片底部「⊕ 添加更多时间」
  Widget _addTimeRow() {
    return InkWell(
      onTap: _addTime,
      borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(_cardRadius)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _textPrimary, width: 1.4),
              ),
              child: const Icon(Icons.add, size: 17, color: _textPrimary),
            ),
            const SizedBox(width: 10),
            const Text(
              '添加更多时间',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
          _advancedSwitchRow(
            icon: Icons.emoji_events_outlined,
            title: '达到目标时停止',
            subtitle: '饮水目标完成 100% 后停止发送提醒',
            provider: stopAtGoalEnabledProvider,
          ),
          _advancedSwitchRow(
            icon: Icons.water_drop_outlined,
            title: '饮水进度标题',
            subtitle: '在通知标题中显示剩余水量。例如：剩余 800ml',
            provider: progressTitleEnabledProvider,
          ),
          _advancedSwitchRow(
            icon: Icons.thumb_up_alt_outlined,
            title: '激励性标题',
            subtitle: '在提醒标题中显示鼓励性信息。例如：你做到了！',
            provider: motivationalTitleEnabledProvider,
          ),
          _advancedSwitchRow(
            icon: Icons.description_outlined,
            title: '饮水事实',
            subtitle: '每次提醒都包含有关适当饮水益处的有趣事实',
            provider: waterFactsEnabledProvider,
          ),
          _advancedRow(
            icon: Icons.edit_outlined,
            title: '自定义信息',
            subtitle: '提醒中的个人自定义文本',
            trailingText: '无',
          ),
          _advancedQuickAddRow(),
          _advancedStickerRow(),
        ]),
      ),
    );
  }

  /// 带箭头的高级设置行
  Widget _advancedRow({
    required IconData icon,
    required String title,
    required String subtitle,
    String? trailingText,
    bool enabled = true,
  }) {
    return InkWell(
      onTap: enabled ? () => _showSnack('功能开发中') : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 36),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 36),
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
          _IosSwitch(
            value: value,
            onChanged: (v) async {
              await ref.read(provider.notifier).set(v);
            },
          ),
        ],
      ),
    );
  }

  /// 快速添加行（开关 + 5 个杯子容量按钮）
  Widget _advancedQuickAddRow() {
    const cupSizes = [120, 250, 330, 500, 1000];
    final enabled = ref.watch(quickAddEnabledProvider);
    final cupMl = ref.watch(quickAddCupMlProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 36),
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
              _IosSwitch(
                value: enabled,
                onChanged: (v) async {
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
                for (final ml in cupSizes)
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

  /// 贴纸行（仅开关，无预览说明）
  Widget _advancedStickerRow() {
    final enabled = ref.watch(stickersEnabledProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 36),
      child: Row(
        children: [
          const Icon(Icons.sentiment_satisfied_outlined,
              color: _textPrimary, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '贴纸',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
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
          _IosSwitch(
            value: enabled,
            onChanged: (v) async {
              await ref.read(stickersEnabledProvider.notifier).set(v);
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

  // ==================== 提醒逻辑 ====================

  /// 确保通知权限（Android 13+ 首次开启任一提醒时申请）
  Future<void> _ensureNotificationPermission() async {
    final granted = await NotificationService.requestPermission();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未获得通知权限，请到系统设置中开启')),
      );
    }
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  /// 单行开关：关闭 → 加入 disabledTimes；开启 → 移出
  Future<void> _toggleTime(String time, {required bool enable}) async {
    HapticFeedback.selectionClick();
    if (enable) await _ensureNotificationPermission();
    final cur = ref.read(reminderProvider);
    final next = enable
        ? cur.copyWith(
            disabledTimes:
                cur.disabledTimes.where((x) => x != time).toList())
        : cur.copyWith(disabledTimes: [...cur.disabledTimes, time]);
    await ref.read(reminderProvider.notifier).update(next);
  }

  /// 编辑时间行（选新时刻替换旧值，保留其开关状态）
  Future<void> _editTime(String oldTime, {required bool disabled}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTod(oldTime),
    );
    if (picked == null || !mounted) return;
    final t = _fmt(picked);
    final cur = ref.read(reminderProvider);
    if (t == oldTime || cur.times.contains(t)) return;
    await ref.read(reminderProvider.notifier).update(
          cur.copyWith(
            times: cur.times.map((x) => x == oldTime ? t : x).toList()
              ..sort(),
            disabledTimes: disabled
                ? cur.disabledTimes
                    .map((x) => x == oldTime ? t : x)
                    .toList()
                : cur.disabledTimes,
          ),
        );
  }

  /// 添加定时提醒时间
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

  /// 删除定时提醒时间（删除模式下点击行触发）
  Future<void> _removeTime(String t) async {
    HapticFeedback.selectionClick();
    final cur = ref.read(reminderProvider);
    await ref.read(reminderProvider.notifier).update(
          cur.copyWith(
            times: cur.times.where((x) => x != t).toList(),
            disabledTimes:
                cur.disabledTimes.where((x) => x != t).toList(),
          ),
        );
  }

  TimeOfDay _parseTod(String s) {
    final p = s.split(':');
    return TimeOfDay(
      hour: int.tryParse(p.isNotEmpty ? p[0] : '') ?? 10,
      minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
    );
  }
}

/// 统一 iOS 风格开关（全页所有开关共用，视觉完全一致）
///
/// Material 自带 Switch 自带不可去除的内边距（约 8px 水平留白），
/// 不同行内显得宽窄不一、右缘对不齐。此组件固定 44×26 轨道 +
/// 22 圆钮，无隐藏边距；onChanged 为 null 时呈现禁用态（灰轨）
/// 且不可点。
class _IosSwitch extends StatelessWidget {
  const _IosSwitch({required this.value, this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// 开启轨道色（用户指定 #1BC5DE）
  static const _trackOn = Color(0xFF1BC5DE);

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    return GestureDetector(
      onTap: disabled
          ? null
          : () {
              HapticFeedback.selectionClick();
              onChanged!(!value);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: !value
              ? const Color(0xFFE9E9EB)
              : (disabled
                  ? _trackOn.withValues(alpha: 0.35)
                  : _trackOn),
          borderRadius: BorderRadius.circular(13),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

