import 'package:flutter/material.dart';

import '../widgets/liquid_preview.dart';
import '../widgets/picker_frame.dart';
import '../widgets/svg_container.dart';

/// 图标选择页（对标原版：顶部动态液体预览 + 容器剪影网格 + 取消/应用）
///
/// 容器来源：assets/images/containers/ 下的 SVG 单色实心剪影（运行时枚举，
/// 丢入新文件即可扩充）。containerId 约定 'svg:<文件名>'。
/// 1. 顶部：当前选中容器按饮品液体色动态填充（网格点选实时渲染）
/// 2. 中部：5 列滚动网格，灰色剪影，选中项渲染为饮品色
/// 3. 底部：悬浮「取消」（浅灰）与「应用」（深色）胶囊
/// 返回值：选中的容器 id（取消返回 null）
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
  static const _silhouetteGray = Color(0xFFE2E2E7);

  List<String> _ids = const [];
  String? _selId;

  @override
  void initState() {
    super.initState();
    _selId = widget.initialId;
    _loadIds();
  }

  Future<void> _loadIds() async {
    final ids = await loadSvgContainerIds();
    if (!mounted) return;
    setState(() {
      _ids = ids;
      if (_ids.isNotEmpty && (_selId == null || !_ids.contains(_selId))) {
        _selId = _ids.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selId = _selId;
    return PickerScaffold(
      preview: selId == null
          ? const SizedBox()
          : LiquidPreview(
              containerId: selId,
              color: widget.color,
              animation: 'bubbles', // 复用首页水的气泡效果
              width: 150,
              height: 195,
            ),
      title: '图标',
      onCancel: () => Navigator.pop(context),
      onApply: () => Navigator.pop(context, _selId),
      content: GridView.builder(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 110),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          crossAxisSpacing: 12,
          mainAxisSpacing: 18,
          childAspectRatio: 0.72,
        ),
        itemCount: _ids.length,
        itemBuilder: (ctx, i) {
          final id = _ids[i];
          final selected = id == selId;
          return GestureDetector(
            onTap: () => setState(() => _selId = id),
            child: Center(
              child: SvgContainerIcon(
                containerId: id,
                // 液体风格（编辑页预览同款）：液体占杯身 70%，
                // 选中 = 饮品色液体 + 浅灰空杯；未选中 = 深浅两档灰
                color: selected ? widget.color : _silhouetteGray,
                emptyColor:
                    selected ? null : const Color(0xFFF4F4F8),
                fillRatio: 0.7,
                size: 64,
              ),
            ),
          );
        },
      ),
    );
  }
}
