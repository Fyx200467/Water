import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/preferred_unit.dart';
import '../home/providers/home_providers.dart';

/// 对标原版：底部弹出的单位选择弹层
///
/// 视觉：白色圆角卡片，标题"你使用什么单位"，两个浅蓝色胶囊按钮
class UnitSelectionSheet extends ConsumerStatefulWidget {
  const UnitSelectionSheet({super.key});

  /// 显示弹层并返回用户选择的单位；用户取消则返回 null
  static Future<PreferredUnit?> show(BuildContext context) {
    return showModalBottomSheet<PreferredUnit>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      enableDrag: true,
      isDismissible: true,
      builder: (_) => const UnitSelectionSheet(),
    );
  }

  @override
  ConsumerState<UnitSelectionSheet> createState() => _UnitSelectionSheetState();
}

class _UnitSelectionSheetState extends ConsumerState<UnitSelectionSheet> {
  PreferredUnit? _selected;
  static const _brand = Color(0xFF4DB8D8);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            '你使用什么单位',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1C1C1E),
                ),
          ),
          const SizedBox(height: 24),
          ...PreferredUnit.values.map(_unitButton),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _unitButton(PreferredUnit unit) {
    final isSelected = _selected == unit;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: () => _select(unit),
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected ? const Color(0xFF3AA9C9) : _brand,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(unit.label),
        ),
      ),
    );
  }

  Future<void> _select(PreferredUnit unit) async {
    setState(() => _selected = unit);
    // 持久化单位偏好
    await ref.read(preferredUnitProvider.notifier).select(unit);
    if (!mounted) return;
    // 短暂反馈后关闭
    Navigator.of(context).pop(unit);
  }
}
