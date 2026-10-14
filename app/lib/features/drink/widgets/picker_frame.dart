import 'package:flutter/material.dart';

/// 容器图标 / 颜色 / 动画 三个全屏选择页的统一骨架（对标原版）：
/// 顶部动态预览 + 居中大标题 + 内容区 + 底部悬浮「取消 / 应用」胶囊。
/// 应用返回选中值；取消 pop null 不改动状态。
class PickerScaffold extends StatelessWidget {
  const PickerScaffold({
    super.key,
    required this.preview,
    required this.title,
    required this.content,
    required this.onCancel,
    required this.onApply,
  });

  /// 顶部预览组件（在固定高度槽内居中）
  final Widget preview;

  /// 页面标题（图标 / 颜色 / 动画）
  final String title;

  /// 内容区（自身处理底部 110 留白避开胶囊）
  final Widget content;

  final VoidCallback onCancel;
  final VoidCallback onApply;

  static const _textDark = Color(0xFF1C1C1E);
  static const _pillGray = Color(0xFFF4F4F6);
  static const _pillTextGray = Color(0xFF6D6D72);
  static const _pillDark = Color(0xFF1F2733);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            SizedBox(height: 205, child: Center(child: preview)),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: _textDark,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Stack(
                children: [
                  content,
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 28,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _pill(
                          label: '取消',
                          background: _pillGray,
                          foreground: _pillTextGray,
                          onTap: onCancel,
                        ),
                        const SizedBox(width: 14),
                        _pill(
                          label: '应用',
                          background: _pillDark,
                          foreground: Colors.white,
                          onTap: onApply,
                        ),
                      ],
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

  Widget _pill({
    required String label,
    required Color background,
    required Color foreground,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
