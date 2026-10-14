import 'package:flutter/material.dart';

import '../widgets/liquid_preview.dart';
import '../widgets/picker_frame.dart';

/// 动画选择页（对标原版全屏页）
///
/// 1. 顶部：当前容器按实时动画选项渲染的动态预览
/// 2. 竖排选项列表：选中项浅灰圆角底 + 深色加粗，未选中灰色
/// 3. 底部：悬浮「取消 / 应用」胶囊；应用返回动画 key（未选返回 ''），取消返回 null
class DrinkAnimationScreen extends StatefulWidget {
  const DrinkAnimationScreen({
    super.key,
    required this.containerId,
    required this.color,
    this.initial,
  });

  /// 当前容器图标 id（顶部预览用）
  final String containerId;

  /// 液体颜色
  final Color color;

  /// 初始选中动画 key（新增默认 null = 未选择）
  final String? initial;

  @override
  State<DrinkAnimationScreen> createState() => _DrinkAnimationScreenState();
}

class _DrinkAnimationScreenState extends State<DrinkAnimationScreen> {
  static const _textDark = Color(0xFF1C1C1E);
  static const _optionGray = Color(0xFFC2C2C8);
  static const _optionBg = Color(0xFFF4F4F6);

  /// 动画选项（key → 标签，顺序对标原版：微气泡在前）
  static const _options = <String, String>{
    'micro': '微气泡',
    'bubbles': '气泡',
    'ice': '冰块',
    'rice': '米粒',
    'leaves': '茶叶',
    'none': '无',
  };

  String? _sel;

  @override
  void initState() {
    super.initState();
    _sel = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return PickerScaffold(
      preview: LiquidPreview(
        containerId: widget.containerId,
        color: widget.color,
        animation: _sel ?? 'bubbles',
        width: 150,
        height: 195,
      ),
      title: '动画',
      onCancel: () => Navigator.pop(context),
      onApply: () => Navigator.pop(context, _sel ?? ''),
      content: ListView(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 120),
        children: [
          for (final e in _options.entries)
            GestureDetector(
              onTap: () => setState(() => _sel = e.key),
              child: Container(
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _sel == e.key ? _optionBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  e.value,
                  style: TextStyle(
                    color: _sel == e.key ? _textDark : _optionGray,
                    fontSize: 20,
                    fontWeight: _sel == e.key ? FontWeight.w800 : FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
