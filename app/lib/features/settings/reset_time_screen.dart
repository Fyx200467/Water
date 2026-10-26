import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/providers/home_providers.dart';
import '../reminder/reminder_providers.dart';
import '../stats/providers/stats_providers.dart';
import 'settings_flags.dart';
import 'widget_settings_screen.dart';

// ============================================================
// 一天中的重置时间（对标原版：重置时间双轮 + 一周开始时间胶囊）
//
// 1. 返回圆钮 + 居中大标题 + 说明文案
// 2. 时:分 双滚轮（共享浅灰胶囊高亮，选中值青色放大，分钟步进 5）
// 3. 一周开始时间：星期日 / 星期一 两个胶囊（选中浅青底+青字+对勾圆）
// 选择均经 SettingsFlags 持久化，设置页角标实时同步；
// 保存后同步重载所有按逻辑日聚合的 Provider（当日记录/统计/打卡/
// 签到/年视图），保证「今天」口径立即切换
// ============================================================

class ResetTimeScreen extends ConsumerStatefulWidget {
  const ResetTimeScreen({super.key});

  @override
  ConsumerState<ResetTimeScreen> createState() => _ResetTimeScreenState();
}

class _ResetTimeScreenState extends ConsumerState<ResetTimeScreen> {
  static const _cyan = Color(0xFF35B5D6);
  static const _textDark = Color(0xFF1C1C1E);

  late int _hour;
  late int _minute; // 0~55，步进 5
  late int _weekStart; // 0 = 星期日，1 = 星期一

  final _hourCtrl = FixedExtentScrollController();
  final _minuteCtrl = FixedExtentScrollController();

  /// 轮盘每跳一格都全量刷新代价太高，这里只写盘 + 防抖重算
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    final f = SettingsFlags.instance;
    _hour = f.resetHour;
    _minute = f.resetMinute ~/ 5;
    _weekStart = f.weekStart;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _hourCtrl.jumpToItem(_hour);
        _minuteCtrl.jumpToItem(_minute);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    // 用户可能在防抖窗口内直接返回：这里补一次轻量落盘（不做重算）
    SettingsFlags.instance.save(
      resetHour: _hour,
      resetMinute: _minute * 5,
      weekStart: _weekStart,
    );
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  /// 轮盘滚动：设置立即落盘，重算合并到 400ms 后
  void _touch() {
    unawaited(SettingsFlags.instance.save(
      resetHour: _hour,
      resetMinute: _minute * 5,
      weekStart: _weekStart,
    ));
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 400), _persist);
  }

  /// 返回前调用：把未执行的重算立即做完，避免回到统计页看到旧口径
  Future<void> _flush() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _persist();
  }

  Future<void> _persist() async {
    await SettingsFlags.instance.save(
      resetHour: _hour,
      resetMinute: _minute * 5,
      weekStart: _weekStart,
    );
    if (!mounted) return;
    // 逻辑日口径已变化：重载当日记录并让所有按日聚合的 Provider 重算
    // （否则重启前「今天」/统计/月历仍沿用旧分界）
    await ref.read(todayEntriesProvider.notifier).refresh();
    if (!mounted) return;
    ref
      ..invalidate(last7DaysProvider)
      ..invalidate(monthDataProvider)
      ..invalidate(dayEntriesForProvider)
      ..invalidate(streakProvider)
      ..invalidate(checkinDaysProvider)
      ..invalidate(bestCheckinDaysProvider)
      ..invalidate(yearDailyProvider)
      ..invalidate(filteredLast7DaysProvider)
      ..invalidate(filteredYearDailyProvider)
      ..invalidate(yearEntriesProvider)
      ..invalidate(dailyAnimalProvider);
    // 「30 分钟内喝过水跳过提醒」与今日进度都按逻辑日统计，重置后必须重排
    await ref.read(reminderProvider.notifier).rescheduleNow();
    if (!mounted) return;
    // 桌面小组件的「今天水量」同样跟随逻辑日
    unawaited(ref.read(widgetSettingsProvider.notifier).refreshWidget());
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _BackButton(onTap: () async {
                      // 先把防抖的重算补齐再返回，保证统计页口径已切换
                      await _flush();
                      if (mounted) Navigator.pop(context);
                    }),
                  ),
                ),
                const SizedBox(height: 10),
                const Center(
                  child: Text('一天中的重置时间',
                      style: TextStyle(
                          color: _textDark,
                          fontSize: 28,
                          fontWeight: FontWeight.w800)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                  child: Text(
                    '选择你的一天通常结束的时间。你的饮水目标将在指定时间而不是常规的午夜 12:00（00:00）重置。从此刻开始，您的水分摄入量将开始新一天的计算。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: const Color(0xFF3C3C43).withValues(alpha: 0.75),
                        fontSize: 15,
                        height: 1.6),
                  ),
                ),
                const SizedBox(height: 40),
                _buildWheel(),
                const SizedBox(height: 44),
                Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    color: const Color(0xFFEFEFF2)),
                const SizedBox(height: 36),
                const Center(
                  child: Text('一周开始时间',
                      style: TextStyle(
                          color: _textDark,
                          fontSize: 24,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text('你每周的第一天是星期几?',
                      style: TextStyle(
                          color: const Color(0xFF3C3C43).withValues(alpha: 0.6),
                          fontSize: 14)),
                ),
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      _weekCapsule('星期日', 0),
                      const SizedBox(height: 10),
                      _weekCapsule('星期一', 1),
                    ],
                  ),
                ),
                const SizedBox(height: 44),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 时:分 双滚轮（共享居中胶囊高亮）
  Widget _buildWheel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: SizedBox(
        height: 150,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 居中胶囊高亮
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F1F4),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            Row(
              children: [
                Expanded(child: _wheel(_hourCtrl, 24, (i) {
                  _hour = i;
                  _touch();
                })),
                Expanded(child: _wheel(_minuteCtrl, 12, (i) {
                  _minute = i;
                  _touch();
                })),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _wheel(FixedExtentScrollController ctrl, int count,
      ValueChanged<int> onChanged) {
    return ListWheelScrollView.useDelegate(
      controller: ctrl,
      itemExtent: 44,
      diameterRatio: 10,
      perspective: 0.003,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (ctx, index) {
          return AnimatedBuilder(
            animation: ctrl,
            builder: (ctx, _) {
              final offset = ctrl.hasClients ? ctrl.offset / 44 : 0.0;
              final sel = (index - offset).abs().clamp(0.0, 1.0);
              final t = 1 - sel;
              return Center(
                child: Text(
                  _two(index * (count == 12 ? 5 : 1)),
                  style: TextStyle(
                    color: Color.lerp(
                        const Color(0xFF97979C).withValues(alpha: 0.55),
                        _cyan,
                        t),
                    fontSize: 21 + 3 * t,
                    fontWeight: t > 0.5 ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _weekCapsule(String label, int value) {
    final selected = _weekStart == value;
    return GestureDetector(
      onTap: () {
        setState(() => _weekStart = value);
        _touch();
      },
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE3F6FB) : const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                    color: selected ? _cyan : _textDark,
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
            const Spacer(),
            if (selected)
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                    color: _cyan, shape: BoxShape.circle),
                child: const Icon(Icons.check,
                    color: Colors.white, size: 15),
              ),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Color(0xFFE9E9EC),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.chevron_left,
            color: Color(0xFF5A5A60), size: 28),
      ),
    );
  }
}
