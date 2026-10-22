import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/notification/notification_service.dart';
import '../drink/services/hydration_calculator.dart';
import '../home/providers/home_providers.dart';
import 'reminder_providers.dart';

/// 提醒设置全屏页面 — 对标竞品简洁布局
///
/// 布局（自上而下）：
/// 1. 悬浮返回按钮（圆形浅灰，浮在页面之上不随内容滚动，无标题文字）；
///    页面内容铺满整个屏幕顶部（状态栏区域同为页面底色）
/// 2. 「饮水提醒」总开关卡（高度与高级设置行一致；关闭即取消全部提醒）
/// 3. 选项卡卡组：两个圆角顶选项卡贴在浅青面板顶部（选中=青色+白圈勾+
///    白字，未选中=浅灰+灰勾+灰字），点击直接切换内容（无滑动动画）——
///    智能页 = 通知间隔小时/分钟双滑块 + 开始/结束时间 + 提示行；
///    自定义页 = 07:00~22:00 整点时间网格 +「新建」按钮
/// 4. 星期几圆形选项（周日开头，横向滚动）
/// 5. 高级设置卡（达到目标停止/进度标题/激励标题/饮水事实/
///    自定义信息/快速添加/贴纸）
class ReminderSettingsScreen extends ConsumerStatefulWidget {
  const ReminderSettingsScreen({super.key});

  @override
  ConsumerState<ReminderSettingsScreen> createState() =>
      _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState
    extends ConsumerState<ReminderSettingsScreen>
    with WidgetsBindingObserver {
  // ---- 设计规范色板 ----
  static const _bgColor = Color(0xFFF2F2F7);
  static const _textPrimary = Color(0xFF1C1C1E);
  static const _textSecondary = Color(0xFF8E8E93);
  static const _arrowColor = Color(0xFFC7C7CC);
  static const _separatorColor = Color(0xFFE5E5EA);
  static const _cardRadius = 16.0;

  /// 选项卡/面板强调青（与页面开关开启色一致）
  static const _accent = Color(0xFF1BC5DE);

  /// 选项卡内容面板浅青底
  static const _panelBg = Color(0xFFE9F7FB);

  /// 当前选项卡：0 = 智能提醒，1 = 自定义提醒
  int _tab = 0;

  /// 通知间隔滑块拖动中的临时值（null = 未在拖动，显示持久化值）
  int? _dragHours;
  int? _dragMinutes;

  /// 系统通知权限是否开启（未开启时在状态卡提示）
  bool _notifAllowed = true;

  /// 通知样式预览的随机种子与随机角色卡
  int _previewSeed = 0;
  String? _previewChar;

  void _switchTab(int t) {
    if (t == _tab) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = t);
  }

  @override
  void initState() {
    super.initState();
    // 兼容旧数据：间隔可选范围为 0~4 小时、分钟 15~60（15~300 分钟），
    // 越界旧值在进入页面时归一到最近的合法档位
    final cur = ref.read(notificationIntervalMinutesProvider);
    final (h, m) = _decodeInterval(cur);
    final normalized = (h * 60 + m).clamp(15, 300);
    if (normalized != cur || !ref.read(intervalEnabledProvider)) {
      Future.microtask(() async {
        await ref.read(intervalEnabledProvider.notifier).set(true);
        await ref
            .read(notificationIntervalMinutesProvider.notifier)
            .set(normalized);
        await ref.read(reminderProvider.notifier).rescheduleNow();
      });
    }
    _previewSeed = DateTime.now().minute * 60 + DateTime.now().second;
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_refreshStatus);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置开关通知权限后返回 App，立即刷新提示状态
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  /// 刷新系统通知权限状态 + 预览随机角色卡（不阻塞首帧）
  Future<void> _refreshStatus() async {
    final allowed = await NotificationService.notificationsEnabled();
    final card = await NotificationService.randomCharacterAsset();
    if (!mounted) return;
    setState(() {
      _notifAllowed = allowed;
      _previewChar = card;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 内容铺满整个屏幕顶部（状态栏区域同为页面底色，不用 SafeArea
    // 顶部留白），返回按钮悬浮在页面之上、不随列表滚动
    final topInset = MediaQuery.of(context).padding.top;
    // 饮水提醒总开关：关闭时隐藏下方选项卡卡组与星期几区块
    final masterOn = ref.watch(reminderProvider).enabled;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _bgColor,
        body: Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(16, topInset + 56, 16, 40),
              children: [
                // ---- 饮水提醒总开关卡 ----
                _buildMasterCard(),
                // 总开关开启：卡组 + 星期几；关闭：大留白 + 「其他通知」
                // 小节标题（间距结构参考竞品关闭态截图）
                if (masterOn) ...[
                  const SizedBox(height: 16),
                  // ---- 选项卡卡组：智能提醒 / 自定义提醒 ----
                  _buildTabbedCard(),
                  const SizedBox(height: 24),
                  // ---- 星期几 ----
                  _buildWeekdaySection(),
                  const SizedBox(height: 20),
                  // ---- 通知状态（权限 / 下次提醒） ----
                  _buildStatusCard(),
                  const SizedBox(height: 28),
                  // ---- 通知样式预览 ----
                  _buildNotificationPreview(),
                  const SizedBox(height: 32),
                ] else ...[
                  const SizedBox(height: 44),
                  const Text(
                    '其他通知',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                // ---- 高级设置 ----
                _buildAdvancedSettings(),
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

  /// 圆形浅灰返回按钮（浮在页面内容之上，无标题行）
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

  // ==================== 区块：饮水提醒总开关 + 选项卡卡组 ====================

  /// 「饮水提醒」总开关卡：控制智能提醒/自定义提醒卡组与星期几区块的
  /// 显隐（关闭时一并隐藏且取消全部已排提醒）
  Widget _buildMasterCard() {
    final enabled = ref.watch(reminderProvider).enabled;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            const Text(
              '饮水提醒',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              enabled ? '开' : '关',
              style: TextStyle(
                color: enabled ? _accent : _textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            _IosSwitch(
              value: enabled,
              onChanged: (v) async {
                if (v) await _ensureNotificationPermission();
                final cur = ref.read(reminderProvider);
                await ref
                    .read(reminderProvider.notifier)
                    .update(cur.copyWith(enabled: v));
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 选项卡 + 内容面板：两个圆角顶选项卡贴在浅青面板顶部——
  /// 选中 = 青色块 + 白圈勾 + 白字，未选中 = 浅灰块 + 灰圈勾 + 灰字；
  /// 面板顶部 3px 青色描边条（未选中选项卡底部露出），切换无动画
  Widget _buildTabbedCard() {
    return Column(
      children: [
        Row(
          children: [
            _tabBlock('智能提醒', 0),
            _tabBlock('自定义提醒', 1),
          ],
        ),
        Container(height: 3, color: _accent),
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: _panelBg,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
          child: _tab == 0 ? _smartPanel() : _customPanel(),
        ),
      ],
    );
  }

  Widget _tabBlock(String label, int index) {
    final selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _switchTab(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _accent : const Color(0xFFF1F1F3),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? Colors.white : const Color(0xFFDFDFE3),
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 19,
                  color: selected ? _accent : Colors.white,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFFAEAEB4),
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 智能提醒面板：通知间隔（小时/分钟双滑块）+ 开始/结束时间 + 提示行
  Widget _smartPanel() {
    final interval = ref.watch(notificationIntervalMinutesProvider);
    final startMin = ref.watch(reminderWindowStartProvider);
    final endMin = ref.watch(reminderWindowEndProvider);
    // 分钟档位为 15~60：整小时值（如 120 分钟）显示为 1 小时 60 分钟
    final (dh, dm) = _decodeInterval(interval);
    final hours = _dragHours ?? dh;
    final minutes = _dragMinutes ?? dm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        const Text(
          '通知间隔',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '$hours小时',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _accent,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        _slider(
          value: hours.toDouble(),
          min: 0,
          max: 4,
          divisions: 4,
          onChanged: (v) => setState(() => _dragHours = v.round()),
          onChangeEnd: (_) => _commitInterval(hours, minutes),
        ),
        Text(
          '$minutes分钟',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _accent,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        _slider(
          value: minutes.toDouble(),
          min: 15,
          max: 60,
          divisions: 9,
          onChanged: (v) => setState(() => _dragMinutes = v.round()),
          onChangeEnd: (_) => _commitInterval(hours, minutes),
        ),
        const SizedBox(height: 10),
        _windowRow('开始时间', startMin),
        const SizedBox(height: 12),
        _windowRow('结束时间', endMin),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Text(
                '智能提醒：30 分钟内喝过水会跳过该次，当天达标后停止发送',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Color(0xFFD3F0F8),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.tips_and_updates_outlined,
                size: 22,
                color: _accent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 间隔滑块（浅青细线轨道 + 刻度 + 白色圆钮，按手指位置跟手拖动）
  Widget _slider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return _TickSlider(
      value: value.clamp(min, max).toDouble(),
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
      onChangeEnd: () => onChangeEnd(value),
    );
  }

  /// 总分钟数 → 小时/分钟双滑块档位（分钟固定落在 15~60，整小时用 60 表示）
  (int, int) _decodeInterval(int total) {
    var h = (total ~/ 60).clamp(0, 5);
    var m = total % 60;
    if (m == 0 && h > 0) {
      m = 60;
      h -= 1;
    }
    return (h.clamp(0, 4), m.clamp(15, 60));
  }

  /// 滑块拖动结束：写回间隔（0~4 小时 + 15~60 分钟，即 15~300 分钟）
  Future<void> _commitInterval(int hours, int minutes) async {
    final h = hours.clamp(0, 4);
    final m = minutes.clamp(15, 60);
    var total = h * 60 + m;
    if (total < 15) total = 15;
    if (total > 300) total = 300;
    await ref.read(intervalEnabledProvider.notifier).set(true);
    await ref.read(notificationIntervalMinutesProvider.notifier).set(total);
    await ref.read(reminderProvider.notifier).rescheduleNow();
    if (!mounted) return;
    // 等新值真正写回后再交还绘制权，否则文字会短暂回落到旧值
    setState(() {
      if (_dragHours == h) _dragHours = null;
      if (_dragMinutes == m) _dragMinutes = null;
    });
  }

  /// 开始/结束时间行：白色圆角行 + 青色时间值，点击弹时间选择器
  Widget _windowRow(String title, int minutes) {
    return InkWell(
      onTap: () => _pickWindowTime(title == '开始时间', minutes),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              _fmtMinutes(minutes),
              style: const TextStyle(
                color: _accent,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: _arrowColor, size: 20),
          ],
        ),
      ),
    );
  }

  String _fmtMinutes(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  /// 选择窗口时间（开始/结束），校验开始 < 结束后持久化并重排
  Future<void> _pickWindowTime(bool isStart, int currentMin) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: currentMin ~/ 60, minute: currentMin % 60),
    );
    if (picked == null || !mounted) return;
    final v = picked.hour * 60 + picked.minute;
    final start = ref.read(reminderWindowStartProvider);
    final end = ref.read(reminderWindowEndProvider);
    if (isStart ? v >= end : v <= start) {
      _showSnack('开始时间需要早于结束时间');
      return;
    }
    final target = isStart
        ? reminderWindowStartProvider
        : reminderWindowEndProvider;
    await ref.read(target.notifier).set(v);
    await ref.read(reminderProvider.notifier).rescheduleNow();
  }

  /// 自定义提醒面板：整点时间网格（07:00~22:00 两列）+「新建」按钮
  Widget _customPanel() {
    final reminder = ref.watch(reminderProvider);
    final slots = <String>[
      for (var h = 7; h <= 22; h++) '${h.toString().padLeft(2, '0')}:00',
      // 添加过或曾经关闭过的非整点时间都要保留在网格中，
      // 否则关闭某个自定义时间后它会从列表中消失、无法再打开
      ...({...reminder.times, ...reminder.disabledTimes}
          .where((t) => !_isHourlySlot(t))
          .toList()
        ..sort()),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        const Text(
          '每次通知的时间',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.5,
          padding: EdgeInsets.zero,
          children: [
            for (final t in slots) _gridSlot(reminder, t),
          ],
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _addCustomTime,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(26),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, color: Colors.white, size: 20),
                const Text(
                  ' 新建',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 是否为 07:00~22:00 的整点槽位
  bool _isHourlySlot(String t) {
    final p = t.split(':');
    if (p.length != 2) return false;
    final h = int.tryParse(p[0]);
    return h != null && p[1] == '00' && h >= 7 && h <= 22;
  }

  /// 网格时间格：开启 = 白底深字青开关；关闭 = 浅青底灰字灰开关；
  /// 非整点自定义时间支持长按删除
  Widget _gridSlot(ReminderSettings reminder, String time) {
    // 开关状态 = 是否真实参与排程（times 中存在且未被单独关闭），
    // 否则会出现"显示开、实际不提醒"的假开启
    final on = reminder.times.contains(time) &&
        !reminder.disabledTimes.contains(time);
    final deletable = !_isHourlySlot(time);
    return GestureDetector(
      onLongPress: deletable ? () => _deleteCustomSlot(time) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: on ? Colors.white : const Color(0xFFF0FAFC),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                time,
                style: TextStyle(
                  color: on ? _textPrimary : const Color(0xFF9FA0A6),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _IosSwitch(
              value: on,
              onChanged: (v) => _toggleSlot(time, enable: v),
            ),
          ],
        ),
      ),
    );
  }

  /// 网格时间开关：开启 → 加入调度时间；关闭 → 移入 disabledTimes
  Future<void> _toggleSlot(String time, {required bool enable}) async {
    if (enable) await _ensureNotificationPermission();
    final cur = ref.read(reminderProvider);
    var times = [...cur.times];
    var disabled = [...cur.disabledTimes];
    if (enable) {
      if (!times.contains(time)) {
        times.add(time);
        times.sort();
      }
      disabled.remove(time);
    } else {
      // 关闭即从排程时间中移除，界面开关才能反映真实状态
      times.remove(time);
      if (!disabled.contains(time)) disabled.add(time);
    }
    await ref
        .read(reminderProvider.notifier)
        .update(cur.copyWith(times: times, disabledTimes: disabled));
  }

  /// 「新建」自定义提醒时间：时间选择器 → 加入时间列表
  ///（非整点时间会以额外槽位展示在网格中，长按可删除）
  Future<void> _addCustomTime() async {
    await _ensureNotificationPermission();
    if (!mounted) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: '选择提醒时间',
    );
    if (picked == null || !mounted) return;
    final t =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    final cur = ref.read(reminderProvider);
    // 已存在的时间（无论是开启还是已单独关闭）都不能重复新建
    if (cur.times.contains(t) || cur.disabledTimes.contains(t)) {
      _showSnack('该时间已存在');
      return;
    }
    final times = [...cur.times, t]..sort();
    await ref
        .read(reminderProvider.notifier)
        .update(cur.copyWith(times: times));
    // 今天该时刻已过：只会从明天开始生效，必须明确告知
    final now = DateTime.now();
    if (picked.hour * 60 + picked.minute < now.hour * 60 + now.minute) {
      _showSnack('今天 $t 已过，将从明天开始提醒');
    }
  }

  /// 删除非整点自定义时间（同时清理其单独关闭记录），update 内自动重排
  Future<void> _deleteCustomSlot(String time) async {
    HapticFeedback.mediumImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Text(
          '删除 $time 的提醒？',
          style: const TextStyle(color: _textPrimary, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消',
                style: TextStyle(color: _textSecondary, fontSize: 15)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除',
                style: TextStyle(
                    color: Color(0xFFC9364F),
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final cur = ref.read(reminderProvider);
    await ref.read(reminderProvider.notifier).update(cur.copyWith(
          times: cur.times.where((t) => t != time).toList(),
          disabledTimes: cur.disabledTimes.where((t) => t != time).toList(),
        ));
  }

  /// 自定义信息行右侧摘要：未设置显示「无」，过长截断
  String _customPreview() {
    final msg = ref.watch(customMessageProvider).trim();
    if (msg.isEmpty) return '无';
    return msg.length > 8 ? '${msg.substring(0, 8)}…' : msg;
  }

  /// 编辑自定义信息：输入弹窗 → 保存并重排（空串 = 清除）
  Future<void> _editCustomMessage() async {
    final ctrl =
        TextEditingController(text: ref.read(customMessageProvider));
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '自定义信息',
          style: TextStyle(
              color: _textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          style: const TextStyle(color: _textPrimary, fontSize: 15),
          decoration: const InputDecoration(
            hintText: '例如：开会前记得喝水哦',
            hintStyle: TextStyle(color: _textSecondary, fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消',
                style: TextStyle(color: _textSecondary, fontSize: 15)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存',
                style: TextStyle(
                    color: _accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    await ref.read(customMessageProvider.notifier).set(ctrl.text.trim());
    await ref.read(reminderProvider.notifier).rescheduleNow();
  }

  // ==================== 区块：星期几 ====================

  /// 星期几区块：分隔线 + 标题 + 圆形星期选项（周日开头，横向滚动）
  Widget _buildWeekdaySection() {
    final days = ref.watch(reminderWeekdaysProvider);
    const labels = {
      1: '周一', 2: '周二', 3: '周三', 4: '周四',
      5: '周五', 6: '周六', 7: '周日',
    };
    return Column(
      children: [
        const Divider(height: 1, thickness: 1, color: Color(0xFFE3E3E8)),
        const SizedBox(height: 20),
        const Text(
          '星期几',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '点按切换该天是否提醒',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFAEAEB4), fontSize: 12),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final d in const [7, 1, 2, 3, 4, 5, 6]) ...[
                _weekdayChip(d, labels[d]!, days.contains(d)),
                if (d != 6) const SizedBox(width: 12),
              ],
            ],
          ),
        ),
        if (days.isEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            '未选择任何星期，将不会收到提醒',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFC9364F), fontSize: 12),
          ),
        ],
      ],
    );
  }

  /// 通知状态卡：系统通知权限未开启时的提示 + 下一次提醒时间
  ///（「下次提醒」与真实排程共用同一套槽位计算，口径完全一致）
  Widget _buildStatusCard() {
    final next = _nextReminder();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Column(
        children: [
          if (!_notifAllowed) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.notifications_off_outlined,
                      color: Color(0xFFC9364F), size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '系统通知权限未开启，提醒不会弹出。请到 系统设置 → 应用 → 通知 中允许。',
                      style: TextStyle(
                        color: Color(0xFFC9364F),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _enableNotifications,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        '去开启',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5, color: _separatorColor),
          ],
          SizedBox(
            height: 52,
            child: Row(
              children: [
                const Text(
                  '下次提醒',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  _fmtNext(next),
                  style: TextStyle(
                    color: next == null ? _textSecondary : _accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 计算下一次提醒（今天/明天 + 时刻；无排程显示暂无）
  DateTime? _nextReminder() {
    final s = ref.watch(reminderProvider);
    final entries = ref.watch(todayEntriesProvider);
    final goalMl = ref.watch(profileProvider)?.dailyGoalMl ?? 2000;
    return NotificationService.nextSlotAt(
      enabled: s.enabled,
      times: s.activeTimes,
      intervalMinutes: ref.watch(intervalEnabledProvider)
          ? ref.watch(notificationIntervalMinutesProvider)
          : null,
      windowStartMin: ref.watch(reminderWindowStartProvider),
      windowEndMin: ref.watch(reminderWindowEndProvider),
      weekdays: ref.watch(reminderWeekdaysProvider),
      todayDrinkMinutes: [
        for (final e in entries) e.drankAt.hour * 60 + e.drankAt.minute,
      ],
      todayEffectiveMl: HydrationCalculator.sumEffective(entries),
      goalMl: goalMl,
      stopAtGoal: ref.watch(stopAtGoalEnabledProvider),
    );
  }

  String _fmtNext(DateTime? t) {
    if (t == null) return '暂无';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = day.difference(today).inDays;
    final label = diff == 0 ? '今天' : (diff == 1 ? '明天' : '${t.month}月${t.day}日');
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '$label $hm';
  }

  /// 「去开启」：再次发起系统权限请求并刷新状态
  Future<void> _enableNotifications() async {
    await _ensureNotificationPermission();
    final allowed = await NotificationService.notificationsEnabled();
    if (!mounted) return;
    setState(() => _notifAllowed = allowed);
  }

  /// 圆形星期选项：选中 = 青色圆 + 白字白勾，未选中 = 浅灰圆 + 灰字
  Widget _weekdayChip(int day, String label, bool selected) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.selectionClick();
        await ref.read(reminderWeekdaysProvider.notifier).toggle(day);
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? _accent : const Color(0xFFF0F0F2),
        ),
        alignment: Alignment.center,
        child: selected
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Icon(Icons.check_rounded,
                      color: Colors.white, size: 15),
                ],
              )
            : Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFAEAEB4),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  // ==================== 区块：通知样式预览 ====================

  /// 通知样式预览：文案与真实通知同源（剩余量实时取自今日记录），
  /// 用于直观调整通知外观；实际通知由系统渲染，圆角/字体以系统为准
  Widget _buildNotificationPreview() {
    final s = ref.watch(reminderProvider);
    final entries = ref.watch(todayEntriesProvider);
    final goalMl = ref.watch(profileProvider)?.dailyGoalMl ?? 2000;
    final remaining =
        math.max(0, goalMl - HydrationCalculator.sumEffective(entries));
    // 标题/正文与真实通知同一套引擎（进度/激励/饮水事实/自定义信息），
    // 随机文案以种子取值，避免每次重建都跳字
    final (title, body) = NotificationService.previewContent(
      seed: _previewSeed,
      message: s.message,
      customMessage: ref.watch(customMessageProvider).trim(),
      progressTitle: ref.watch(progressTitleEnabledProvider),
      motivationalTitle: ref.watch(motivationalTitleEnabledProvider),
      waterFacts: ref.watch(waterFactsEnabledProvider),
      remainingMl: remaining,
    );
    final showSticker = ref.watch(stickersEnabledProvider);
    final sticker = _previewChar ?? 'assets/images/characters/alpaca.svg';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '通知样式预览 · 点击换一条',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        GestureDetector(
          onTap: _rerollPreview,
          child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF8FDCF5), Color(0xFF3AA6DC)],
                      ),
                    ),
                    child: const Icon(
                      Icons.water_drop,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '喝水养成 · 1 分钟前',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.keyboard_arrow_up,
                    size: 18,
                    color: _textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          body,
                          style: const TextStyle(
                            color: Color(0xFF3B3B3F),
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 贴纸开关：随机角色卡展示在通知最右侧（真实通知为 largeIcon）
                  if (showSticker) ...[
                    const SizedBox(width: 12),
                    SvgPicture.asset(
                      sticker,
                      width: 46,
                      height: 46,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        ),
      ],
    );
  }

  /// 点击预览：换一个随机种子与角色卡（与真实通知的随机机制一致）
  Future<void> _rerollPreview() async {
    HapticFeedback.selectionClick();
    final card = await NotificationService.randomCharacterAsset();
    if (!mounted) return;
    setState(() {
      _previewSeed = DateTime.now().millisecondsSinceEpoch % 9973;
      if (card != null) _previewChar = card;
    });
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
            trailingText: _customPreview(),
            onTap: _editCustomMessage,
          ),
          _advancedStickerRow(),
        ]),
      ),
    );
  }

  /// 带箭头的高级设置行（onTap 为空时提示开发中）
  Widget _advancedRow({
    required IconData icon,
    required String title,
    required String subtitle,
    String? trailingText,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap ?? () => _showSnack('功能开发中'),
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
              // 开关变更影响通知内容/今日剩余槽位 → 立即重排
              await ref.read(provider.notifier).set(v);
              await ref.read(reminderProvider.notifier).rescheduleNow();
            },
          ),
        ],
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
                  '在通知右侧显示随机角色卡贴纸',
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
              // 贴纸影响通知正文内容 → 重排
              await ref.read(stickersEnabledProvider.notifier).set(v);
              await ref.read(reminderProvider.notifier).rescheduleNow();
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
    if (!mounted) return;
    if (_notifAllowed != granted) setState(() => _notifAllowed = granted);
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通知权限未开启：请到 系统设置 → 应用 → 喝水养成 → 通知 中允许'),
        ),
      );
    }
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

/// 刻度滑块：浅青细线 + 等距刻度 + 白色圆钮
///
/// 直接以手指 x 坐标换算数值：拖动过程中圆钮始终停在手指下方，
/// 只在松手时按 divisions 吸附并提交，避免使用 Material Slider 时
/// "值吸附 → 父级重建 → 圆钮跳位"造成的乱窜与不跟手。
class _TickSlider extends StatefulWidget {
  const _TickSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  State<_TickSlider> createState() => _TickSliderState();
}

class _TickSliderState extends State<_TickSlider> {
  /// 当前绘制的归一化位置（0~1）：拖动中 = 吸附刻度，松手后 = 待回写目标
  double? _dragT;

  /// 上一次上报的吸附值，用于避免同一档位重复触发父级重建
  double? _lastEmitted;

  /// 本次手势对应的吸附目标位置
  double? _targetT;

  /// 已提交、等待父级回写确认的数值
  double? _submittedValue;

  /// 手势序号，用于作废上一轮的超时兜底
  int _gestureSeq = 0;

  double _width = 1;

  double get _span => widget.max - widget.min;
  double get _step => _span / widget.divisions;

  double get _valueT =>
      ((widget.value - widget.min) / _span).clamp(0.0, 1.0);

  void _update(Offset local) {
    _gestureSeq++;
    _submittedValue = null;

    // 与绘制一致：轨道两端各内缩 _inset
    const inset = 17.0;
    final t =
        ((local.dx - inset) / (_width - inset * 2)).clamp(0.0, 1.0);
    final raw = widget.min + _span * t;
    // 以刻度为单位：越过相邻刻度中点即跳到该刻度，过程不停在刻度之间
    final snapped =
        (widget.min + ((raw - widget.min) / _step).round() * _step)
            .clamp(widget.min, widget.max);
    final snappedT = ((snapped - widget.min) / _span).clamp(0.0, 1.0);
    _targetT = snappedT;
    setState(() => _dragT = snappedT);
    if (snapped != _lastEmitted) {
      _lastEmitted = snapped;
      widget.onChanged(snapped);
    }
  }

  /// 松手：提交数值，并在父级回写新值前保持圆钮停在当前刻度
  void _end() {
    if (_dragT == null) {
      _lastEmitted = null;
      return;
    }
    final target = _targetT ?? _valueT;
    final submitted = _lastEmitted ?? widget.value;
    final seq = ++_gestureSeq;
    widget.onChangeEnd();
    _lastEmitted = null;
    _targetT = null;

    // 提交是异步的：父级回写新值前，继续用圆钮的目标位置绘制，
    // 否则会瞬间回落到旧值（表现为"闪到反方向尽头"）
    _submittedValue = submitted;
    setState(() => _dragT = target);

    // 兜底：父级没有回写新值（值未变化）时，稍后自行交还绘制权
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (!mounted || seq != _gestureSeq || _submittedValue == null) return;
      setState(() {
        _dragT = null;
        _submittedValue = null;
      });
    });
  }

  @override
  void didUpdateWidget(covariant _TickSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final submitted = _submittedValue;
    if (submitted != null && (widget.value - submitted).abs() < 0.001) {
      // 父级已回写为新值，交还绘制权（此处处于重建流程中，直接改字段即可）
      _submittedValue = null;
      _dragT = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        final t = _dragT ?? _valueT;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _update(d.localPosition),
          onTapUp: (_) => _end(),
          onHorizontalDragStart: (d) => _update(d.localPosition),
          onHorizontalDragUpdate: (d) => _update(d.localPosition),
          onHorizontalDragEnd: (_) => _end(),
          onHorizontalDragCancel: _end,
          child: CustomPaint(
            size: Size(constraints.maxWidth, 46),
            painter: _TickSliderPainter(t: t, divisions: widget.divisions),
          ),
        );
      },
    );
  }
}

class _TickSliderPainter extends CustomPainter {
  _TickSliderPainter({required this.t, required this.divisions});

  final double t;
  final int divisions;

  /// 轨道浅青
  static const _trackColor = Color(0xFF9FE2EC);

  /// 刻度青（比轨道略深）
  static const _tickColor = Color(0xFF6FD5E4);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    // 轨道与刻度两端各内缩一个圆钮半径，使首/尾刻度正好被圆钮盖住
    const radius = 17.0;
    final left = radius;
    final right = size.width - radius;
    final span = right - left;

    final linePaint = Paint()
      ..color = _trackColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(left, y), Offset(right, y), linePaint);

    final tickPaint = Paint()
      ..color = _tickColor
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= divisions; i++) {
      final x = left + span * i / divisions;
      canvas.drawLine(Offset(x, y - 10), Offset(x, y), tickPaint);
    }

    // 圆钮圆心对齐首尾刻度（滑到两端时把首/尾刻度盖住）
    final x = left + span * t;
    final thumb = Path()
      ..addOval(Rect.fromCircle(center: Offset(x, y), radius: radius));
    canvas.drawShadow(thumb, const Color(0x33000000), 6, false);
    canvas.drawPath(thumb, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TickSliderPainter old) =>
      old.t != t || old.divisions != divisions;
}

