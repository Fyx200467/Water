import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 动物液体填充（对标原版 WaterLlama 首页效果）
///
/// 简化方案（用户建议）：
/// - 直接用 SvgPicture.asset + BoxFit.contain 把 SVG 等比例缩放到正方形盒子
/// - 底层：染灰的 SVG 剪影（始终显示，0% 进度态）
/// - 顶层：彩色 SVG，用 ClipPath 从底部按 fillRatio 高度裁剪显示
///   （因为 SVG 轮廓外透明，彩色部分自动只在动物轮廓内可见 → 液体填充效果）
/// - fullArt=true（目标完成）：直接显示彩色 SVG，不染灰
/// - PNG 兼容：onboarding/welcome 等场景传入 'llama'/'panda'/'octopus' 时
///   自动用老 PNG 资源，渲染机制相同（染灰用 BlendMode.srcIn）
class AnimalSilhouette extends StatefulWidget {
  const AnimalSilhouette({
    super.key,
    required this.animalId,
    required this.fillRatio,
    required this.accentColor,
    this.size = 260,
    this.solidFillColor,
    this.fullArt = false,
    this.phase,
  });

  final String animalId;
  final double fillRatio;
  final Color accentColor;
  final double size;
  /// 非空时用纯色填充（替代彩色 SVG 顶层，用于强调品牌色液体）
  final Color? solidFillColor;
  /// true 时叠加全彩插画（五官可见）；false 时只有轮廓剪影+液体填充
  final bool fullArt;

  /// 非空时定格波浪相位（0..1，供离屏渲染桌面小组件动画帧，不启动
  /// 动画）；null 时正常循环播放水面波动动画
  final double? phase;

  @override
  State<AnimalSilhouette> createState() => _AnimalSilhouetteState();
}

class _AnimalSilhouetteState extends State<AnimalSilhouette>
    with SingleTickerProviderStateMixin {
  /// 波动动画驱动器：水面持续晃动
  late final AnimationController _wave;

  /// 老 PNG 资源映射（onboarding/welcome 仍可能传入这些 ID）
  static const _legacyPngPaths = <String, String>{
    'llama': 'assets/images/animal_llama_full.png',
    'panda': 'assets/images/animal_panda_full.png',
    'octopus': 'assets/images/animal_octopus_full.png',
  };

  static const _silhouetteGray = Color(0xFFEBEBEB);

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  /// 当前 animalId 对应的资源路径 + 是否 PNG
  ({String path, bool isPng}) get _asset {
    final png = _legacyPngPaths[widget.animalId];
    if (png != null) return (path: png, isPng: true);
    return (
      path: 'assets/images/characters/${widget.animalId}.svg',
      isPng: false,
    );
  }

  /// 构建单张插画 widget（彩色或染灰版）
  Widget _buildArt({required bool grayscale}) {
    final a = _asset;
    final img = a.isPng
        ? Image.asset(a.path, fit: BoxFit.contain)
        : SvgPicture.asset(a.path, fit: BoxFit.contain);
    if (!grayscale) return img;
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(_silhouetteGray, BlendMode.srcIn),
      child: img,
    );
  }

  /// 构建液体填充层（wavePhase 为弧度制波浪相位；定格帧与循环动画共用）
  Widget _buildLiquid(double wavePhase) {
    // 彩色液体层：可以是原色 SVG（默认）或 solidFillColor（品牌色液体）
    final liquidChild = widget.solidFillColor != null
        ? _SolidLiquid(
            size: widget.size,
            color: widget.solidFillColor!,
            art: _buildArt(grayscale: false),
          )
        : _buildArt(grayscale: false);
    return ClipPath(
      clipper: _LiquidSurfaceClipper(
        fillRatio: widget.fillRatio,
        phase: wavePhase,
      ),
      child: liquidChild,
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;

    // 目标完成：直接显示彩色 SVG，不染灰
    if (w.fullArt) {
      return SizedBox(
        width: w.size,
        height: w.size,
        child: Center(child: _buildArt(grayscale: false)),
      );
    }

    // 未完成：底层灰剪影 + 顶层彩色按 fillRatio 从底部裁剪
    return SizedBox(
      width: w.size,
      height: w.size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 底层：染灰剪影（始终显示，0% 进度态）
          Center(child: _buildArt(grayscale: true)),

          // 2. 顶层：彩色液体填充（按 fillRatio 从底部裁剪，带波浪面）
          if (w.fillRatio > 0)
            if (w.phase != null)
              // 定格相位：离屏渲染桌面小组件动画帧，不启动动画
              _buildLiquid(w.phase! * math.pi * 2)
            else
              AnimatedBuilder(
                animation: _wave,
                builder: (ctx, _) => _buildLiquid(_wave.value * math.pi * 2),
              ),
        ],
      ),
    );
  }
}

/// 液体表面波浪裁剪器：从底部按 fillRatio 高度裁剪，顶部带正弦波浪面
class _LiquidSurfaceClipper extends CustomClipper<Path> {
  _LiquidSurfaceClipper({required this.fillRatio, required this.phase});

  final double fillRatio;
  final double phase;

  @override
  Path getClip(Size size) {
    final surfaceY = size.height * (1 - fillRatio.clamp(0.0, 1.0));
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, surfaceY);
    const samples = 24;
    for (var i = 1; i <= samples; i++) {
      final t = i / samples;
      final x = size.width * t;
      // 2 个周期，振幅 2.5px（与原版幅度一致），每帧相位不同
      final wave = math.sin(t * math.pi * 2.0 + phase) * 2.5;
      path.lineTo(x, surfaceY + wave);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _LiquidSurfaceClipper old) =>
      old.fillRatio != fillRatio || old.phase != phase;
}

/// solidFillColor 模式：用纯色覆盖彩色 SVG 轮廓（用于品牌色液体效果）
class _SolidLiquid extends StatelessWidget {
  const _SolidLiquid({
    required this.size,
    required this.color,
    required this.art,
  });

  final double size;
  final Color color;
  final Widget art;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: art),
          // 用 srcIn 把彩色 SVG 染成纯色（保留 alpha 蒙版）
          ColorFiltered(
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            child: Center(child: art),
          ),
        ],
      ),
    );
  }
}
