import 'package:flutter/material.dart';

/// 全局统一返回按钮：深色左箭头（无底色），点击区域与尺寸保持不变。
///
/// 各页面直接使用本组件，避免出现箭头粗细、圆底大小不一的返回按钮。
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onTap});

  /// 自定义点击行为；默认返回上一页
  final VoidCallback? onTap;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      child: const SizedBox(
        width: _size,
        height: _size,
        child: Icon(
          Icons.arrow_back_ios_new,
          size: 15,
          color: Color(0xFF1C1C1E),
        ),
      ),
    );
  }
}
