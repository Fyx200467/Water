import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 弹出滚轮式时间选择器（24 小时制双列滚轮，底部弹层）
///
/// 返回选中的 [TimeOfDay]；点右上角关闭或点遮罩返回 null。
/// Android / iOS 共用同一套样式，避免 Material 表盘与本 App 视觉不一致。
Future<TimeOfDay?> showWheelTimePicker(
  BuildContext context, {
  required TimeOfDay initial,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (_) => WheelTimePickerSheet(initial: initial),
  );
}

class WheelTimePickerSheet extends StatefulWidget {
  const WheelTimePickerSheet({super.key, required this.initial});

  final TimeOfDay initial;

  @override
  State<WheelTimePickerSheet> createState() => _WheelTimePickerSheetState();
}

class _WheelTimePickerSheetState extends State<WheelTimePickerSheet> {
  static const double _itemExtent = 44;
  static const int _visibleRows = 5;

  /// 每列铺设的圈数：以中间圈为起点，向前/向后都能一直滚，
  /// 靠 index % count 取真实值，实现 23→00、59→00 的无缝循环
  static const int _loopTurns = 600;

  /// 弹层底色（比选中行略深，选中带才有层次）
  static const Color _bgColor = Color(0xFFF7F9FB);

  /// 选中数字的青
  static const Color _selectedColor = Color(0xFF2FBBDD);

  /// 「完成」按钮深藏青
  static const Color _confirmColor = Color(0xFF1F2A44);

  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minuteCtrl;
  late final ValueNotifier<int> _hourIndex;
  late final ValueNotifier<int> _minuteIndex;

  late int _hour;
  late int _minute;
  late int _hourBase;
  late int _minuteBase;

  @override
  void initState() {
    super.initState();
    _hour = widget.initial.hour.clamp(0, 23);
    _minute = widget.initial.minute.clamp(0, 59);
    // 从中间圈开始，两侧都有充足的可滚动空间
    _hourBase = 24 * (_loopTurns ~/ 2);
    _minuteBase = 60 * (_loopTurns ~/ 2);
    _hourCtrl =
        FixedExtentScrollController(initialItem: _hourBase + _hour);
    _minuteCtrl =
        FixedExtentScrollController(initialItem: _minuteBase + _minute);
    _hourIndex = ValueNotifier<int>(_hourBase + _hour);
    _minuteIndex = ValueNotifier<int>(_minuteBase + _minute);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    _hourIndex.dispose();
    _minuteIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset + 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 右上角关闭
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEDEDEF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: Color(0xFF9A9AA0),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: _itemExtent * _visibleRows,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 选中行白色圆角带（横跨两列）
                IgnorePointer(
                  child: Container(
                    height: _itemExtent,
                    margin: const EdgeInsets.symmetric(horizontal: 26),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF0F2F5)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0D000000),
                          blurRadius: 10,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _wheel(
                      controller: _hourCtrl,
                      selected: _hourIndex,
                      count: 24,
                      base: _hourBase,
                      onChanged: (v) => _hour = v,
                    ),
                    const SizedBox(width: 16),
                    _wheel(
                      controller: _minuteCtrl,
                      selected: _minuteIndex,
                      count: 60,
                      base: _minuteBase,
                      onChanged: (v) => _minute = v,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              Navigator.of(context).pop(TimeOfDay(hour: _hour, minute: _minute));
            },
            child: Container(
              width: 148,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _confirmColor,
                borderRadius: BorderRadius.circular(25),
              ),
              child: const Text(
                '完成',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 单列滚轮：循环铺满 [_loopTurns] 圈，两位数字，
  /// 离选中行越远颜色越淡
  Widget _wheel({
    required FixedExtentScrollController controller,
    required ValueNotifier<int> selected,
    required int count,
    required int base,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: 84,
      height: _itemExtent * _visibleRows,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: _itemExtent,
        diameterRatio: 1.55,
        perspective: 0.003,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (i) {
          HapticFeedback.selectionClick();
          selected.value = i;
          onChanged(i % count);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count * _loopTurns,
          builder: (context, index) {
            return ValueListenableBuilder<int>(
              valueListenable: selected,
              builder: (context, sel, _) {
                return Center(
                  child: Text(
                    (index % count).toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: _numberColor((index - sel).abs()),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  static Color _numberColor(int distance) {
    if (distance == 0) return _selectedColor;
    if (distance == 1) return const Color(0xFF87DCEE);
    if (distance == 2) return const Color(0xFFC0ECF7);
    return const Color(0xFFDCF4FA);
  }
}
