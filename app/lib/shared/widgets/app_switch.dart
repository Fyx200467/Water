import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 全局统一 iOS 风格开关（视觉与「饮水提醒」页完全一致）
///
/// Material 自带 Switch 带有不可去除的内边距（约 8px 水平留白），
/// 不同行内显得宽窄不一、右缘对不齐。此组件固定 44×26 轨道 +
/// 22 圆钮，无隐藏边距；onChanged 为 null 时呈现禁用态（灰轨）
/// 且不可点。
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, this.onChanged});

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
