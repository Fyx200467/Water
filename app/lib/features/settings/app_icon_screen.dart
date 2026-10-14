import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/storage/providers.dart';

// ============================================================
// App 图标选择页（对标原版 WaterLlama「App 图标」页）
//
// 结构：
// 1. 返回圆钮 + 居中大标题「App 图标」
// 2. 3 列圆角方块图标网格（彩色角色插画铺满各色底 + 扁平杯/水滴图标）
// 3. 页面背景跟随系统深浅模式（深色模式下背景转黑，图标自带底色不变）
// 4. 点击图标选中（青色描边 + 白色对勾角标），选择持久化
//
// 注：Android 平台运行时切换桌面图标需为每个变体注册 activity-alias
// 并内置对应 mipmap 资源，此页先完成原版 UI 与选择状态，后续可接原生。
// ============================================================

/// 图标变体底色（对标原版：天蓝/浅蓝/白/奶油/黑/黄轮换）
const List<Color> _iconBgs = [
  Color(0xFF4DB8D8), // 天蓝
  Color(0xFFADE1F5), // 浅蓝
  Color(0xFFF7F7F9), // 白
  Color(0xFFF5ECDC), // 奶油
  Color(0xFF1C1C22), // 黑
  Color(0xFFFFD54F), // 黄
];

/// 出现在图标网格里的角色（全彩插画，动物系辨识度最高）
const List<String> _iconCharacters = [
  'alpaca', 'sheep', 'rabbit',
  'fox', 'corgi', 'orange_cat',
  'sleepy_cat', 'silly_dog', 'poodle',
  'husky', 'polar_bear', 'red_squirrel',
  'whale', 'dolphin', 'turtle',
  'parrot', 'duck', 'hedgehog',
];

class AppIconScreen extends ConsumerStatefulWidget {
  const AppIconScreen({super.key});

  @override
  ConsumerState<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends ConsumerState<AppIconScreen> {
  static const _kKey = 'app_icon_selection';
  static const _textDark = Color(0xFF1C1C1E);

  String? _selected; // 选中图标 id

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final saved = storage.prefs.getString(_kKey);
    if (saved != null && mounted) setState(() => _selected = saved);
  }

  Future<void> _select(String id) async {
    setState(() => _selected = id);
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(_kKey, id);
  }

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final pageBg = dark ? const Color(0xFF0E0E10) : Colors.white;

    // 图标清单：角色插画变体 + 扁平杯/水滴图形变体
    final icons = <_AppIconEntry>[
      for (var i = 0; i < _iconCharacters.length; i++)
        for (var j = 0; j < _iconBgs.length; j++)
          _AppIconEntry(
            id: 'char_${_iconCharacters[i]}_$j',
            svg: 'assets/images/characters/${_iconCharacters[i]}.svg',
            bg: _iconBgs[j],
          ),
      // 扁平水滴/杯图标（浅色底 + 深色底，对标原版末尾的杯/水滴块）
      const _AppIconEntry(
          id: 'glyph_drop_light',
          bg: Color(0xFFF7F7F9),
          glyph: Icons.water_drop,
          glyphColor: Color(0xFF35B5D6)),
      const _AppIconEntry(
          id: 'glyph_cup_light',
          bg: Color(0xFFF7F7F9),
          glyph: Icons.local_drink,
          glyphColor: Color(0xFFE5605C)),
      const _AppIconEntry(
          id: 'glyph_drop_dark',
          bg: Color(0xFF1C1C22),
          glyph: Icons.water_drop,
          glyphColor: Color(0xFF35B5D6)),
      const _AppIconEntry(
          id: 'glyph_cup_dark',
          bg: Color(0xFF1C1C22),
          glyph: Icons.local_drink,
          glyphColor: Color(0xFF4DB8D8)),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: pageBg,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: dark
                            ? const Color(0xFF26262C)
                            : const Color(0xFFE9E9EC),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.chevron_left,
                          color: dark
                              ? const Color(0xFFC7C7CC)
                              : const Color(0xFF5A5A60),
                          size: 28),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text('App 图标',
                    style: TextStyle(
                        color: dark ? Colors.white : _textDark,
                        fontSize: 28,
                        fontWeight: FontWeight.w800)),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1,
                  ),
                  itemCount: icons.length,
                  itemBuilder: (ctx, i) {
                    final e = icons[i];
                    return _IconTile(
                      entry: e,
                      selected: _selected == e.id,
                      dark: dark,
                      onTap: () => _select(e.id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppIconEntry {
  const _AppIconEntry({
    required this.id,
    required this.bg,
    this.svg,
    this.glyph,
    this.glyphColor,
  });

  final String id;
  final Color bg;

  /// 角色插画 SVG（与 glyph 二选一）
  final String? svg;
  final IconData? glyph;
  final Color? glyphColor;
}

class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.entry,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  final _AppIconEntry entry;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 圆角方块图标（squircle 近似：24% 圆角）
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Container(
                color: e.bg,
                alignment: Alignment.center,
                padding: e.svg != null
                    ? const EdgeInsets.all(6)
                    : EdgeInsets.zero,
                child: e.svg != null
                    ? SvgPicture.asset(e.svg!, fit: BoxFit.contain)
                    : Icon(e.glyph, color: e.glyphColor, size: 46),
              ),
            ),
          ),
          // 选中标记：青色描边 + 右下白圆对勾
          if (selected) ...[
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                      color: const Color(0xFF35B5D6), width: 3),
                ),
              ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFF35B5D6),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.check,
                    color: Colors.white, size: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
