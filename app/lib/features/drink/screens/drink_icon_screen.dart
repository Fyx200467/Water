import 'package:flutter/material.dart';

import '../widgets/container_shapes.dart';

/// 图标选择页（对标原版：顶部大预览 + 容器剪影网格 + 取消/应用）
///
/// 1. 顶部：当前选中容器按饮品液体色实时填充预览
/// 2. 中部：5 列滚动网格，灰色剪影，选中项渲染为饮品色
/// 3. 底部：悬浮「取消」（浅灰）与「应用」（深色）胶囊
/// 返回值：选中的容器形状 id（取消返回 null）
class DrinkIconScreen extends StatefulWidget {
  const DrinkIconScreen({
    super.key,
    required this.color,
    this.initialId,
  });

  /// 饮品液体色（预览与选中项填充色）
  final Color color;

  /// 初始选中容器 id
  final String? initialId;

  @override
  State<DrinkIconScreen> createState() => _DrinkIconScreenState();
}

class _DrinkIconScreenState extends State<DrinkIconScreen> {
  static const _textDark = Color(0xFF1C1C1E);

  late String _selId =
      widget.initialId ?? kContainerShapes.first.id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            // 顶部大预览：选中容器按饮品色填充
            SizedBox(
              width: 150,
              height: 168,
              child: CustomPaint(
                painter: ContainerShapePainter(
                    id: _selId, color: widget.color),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '图标',
              style: TextStyle(
                color: _textDark,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            // 容器剪影网格（底部为悬浮按钮留白）
            Expanded(
              child: Stack(
                children: [
                  GridView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(24, 16, 24, 110),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 18,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: kContainerShapes.length,
                    itemBuilder: (ctx, i) {
                      final shape = kContainerShapes[i];
                      final selected = shape.id == _selId;
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selId = shape.id),
                        child: CustomPaint(
                          painter: ContainerShapePainter(
                            id: shape.id,
                            color: selected
                                ? widget.color
                                : kContainerGray,
                          ),
                        ),
                      );
                    },
                  ),
                  // 底部悬浮 取消/应用 胶囊
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 28,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _pill(
                          label: '取消',
                          background: const Color(0xFFF4F4F6),
                          foreground: const Color(0xFF6D6D72),
                          onTap: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 14),
                        _pill(
                          label: '应用',
                          background: const Color(0xFF1F2733),
                          foreground: Colors.white,
                          onTap: () =>
                              Navigator.pop(context, _selId),
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
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
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
