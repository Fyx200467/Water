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

/// 选中图标持久化键（设置页「App 图标」行同步读取）
const kAppIconSelectionKey = 'app_icon_selection';

/// 未主动选择过的默认图标（图标页第一个，与桌面默认图标一致）
const kDefaultAppIconId = 'char_alpaca_0';

/// 当前选中的 App 图标 id（全局通知：设置页行内小图标跟随变化）
final ValueNotifier<String?> selectedAppIcon = ValueNotifier<String?>(null);

/// 图标清单：角色插画变体（各角色 × 各底色）+ 扁平杯/水滴图形变体。
/// 提为顶层函数：设置页「App 图标」行需要按 id 反查预览数据
List<AppIconEntry> buildAppIconCatalog() => [
      for (var i = 0; i < _iconCharacters.length; i++)
        for (var j = 0; j < _iconBgs.length; j++)
          AppIconEntry(
            id: 'char_${_iconCharacters[i]}_$j',
            svg: 'assets/images/characters/${_iconCharacters[i]}.svg',
            bg: _iconBgs[j],
          ),
      const AppIconEntry(
          id: 'glyph_drop_light',
          bg: Color(0xFFF7F7F9),
          glyph: Icons.water_drop,
          glyphColor: Color(0xFF35B5D6)),
      const AppIconEntry(
          id: 'glyph_cup_light',
          bg: Color(0xFFF7F7F9),
          glyph: Icons.local_drink,
          glyphColor: Color(0xFFE5605C)),
      const AppIconEntry(
          id: 'glyph_drop_dark',
          bg: Color(0xFF1C1C22),
          glyph: Icons.water_drop,
          glyphColor: Color(0xFF35B5D6)),
      const AppIconEntry(
          id: 'glyph_cup_dark',
          bg: Color(0xFF1C1C22),
          glyph: Icons.local_drink,
          glyphColor: Color(0xFF4DB8D8)),
    ];

/// App 图标小预览（设置页「App 图标」行左侧）：按当前选中 id 渲染
/// 迷你圆角方块图标，进选择页换图标后行内实时跟随
class AppIconPreview extends StatelessWidget {
  const AppIconPreview({super.key, required this.size, this.id});

  final double size;

  /// 覆盖 id（调试用）；缺省读全局 selectedAppIcon，再回退默认第一枚
  final String? id;

  @override
  Widget build(BuildContext context) {
    final catalog = buildAppIconCatalog();
    final selId = id ?? selectedAppIcon.value ?? kDefaultAppIconId;
    final e = catalog.firstWhere((x) => x.id == selId,
        orElse: () => catalog.first);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Container(
        width: size,
        height: size,
        color: e.bg,
        alignment: Alignment.center,
        padding: e.svg != null ? EdgeInsets.all(size * 0.08) : EdgeInsets.zero,
        child: e.svg != null
            ? SvgPicture.asset(e.svg!, fit: BoxFit.contain)
            : Icon(e.glyph, color: e.glyphColor, size: size * 0.62),
      ),
    );
  }
}

class AppIconScreen extends ConsumerStatefulWidget {
  const AppIconScreen({super.key});

  @override
  ConsumerState<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends ConsumerState<AppIconScreen> {
  static const _textDark = Color(0xFF1C1C1E);

  /// 原生图标切换通道：MainActivity 已注册同名 MethodChannel
  static const _channel = MethodChannel('app.icon.switcher');

  String? _selected; // 选中图标 id

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final saved = storage.prefs.getString(kAppIconSelectionKey);
    // 未主动选择过时默认选中图标页第一个（与桌面默认图标保持一致）
    if (mounted) {
      setState(() => _selected = saved ?? kDefaultAppIconId);
      selectedAppIcon.value ??= _selected;
    }
  }

  Future<void> _select(String id) async {
    setState(() => _selected = id);
    selectedAppIcon.value = id; // 设置页「App 图标」行小图标实时跟随
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(kAppIconSelectionKey, id);
    // 真实切换桌面图标：启用对应 activity-alias、停用当前别名
    // （部分 ROM 会在数秒内刷新桌面，期间图标可能短暂消失）
    try {
      await _channel.invokeMethod<void>(
          'setIcon', {'alias': 'com.waterllama.water_llama.AppIcon_$id'});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已应用，桌面图标将稍后自动更新')),
        );
      }
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('应用失败，请重试')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final pageBg = dark ? const Color(0xFF0E0E10) : Colors.white;

    final icons = buildAppIconCatalog();

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

/// 图标网格条目数据
class AppIconEntry {
  const AppIconEntry({
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

  final AppIconEntry entry;
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
