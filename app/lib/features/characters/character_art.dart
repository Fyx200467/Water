import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 角色插画渲染器：复用一张彩色 SVG，根据解锁状态切换两种渲染
///
/// - 已点亮（unlocked = true）：原色 SVG，显示彩色精美插画
/// - 未点亮（unlocked = false）：用 ColorFilter.mode(灰色, srcIn) 把整张 SVG
///   全部染成同一种灰色，得到"实色剪影"效果，自然呈现动物轮廓
///
/// 资源路径：assets/images/characters/$animalId.svg；
/// 后台上传素材传 [filePath]（文档目录 SVG 文件），染灰机制一致。
class CharacterArt extends StatelessWidget {
  const CharacterArt({
    super.key,
    required this.animalId,
    required this.unlocked,
    this.size = 56,
    this.silhouetteColor = const Color(0xFFC4C4C4),
    this.filePath,
  });

  final String animalId;
  final bool unlocked;
  final double size;
  final Color silhouetteColor;

  /// 后台上传素材的本地 SVG 文件路径（非 null 时优先于 assets）
  final String? filePath;

  static const _assetDir = 'assets/images/characters';

  @override
  Widget build(BuildContext context) {
    final path = '$_assetDir/$animalId.svg';
    final svg = filePath != null
        ? SvgPicture.file(
            File(filePath!),
            width: size,
            height: size,
            fit: BoxFit.contain,
          )
        : SvgPicture.asset(
            path,
            width: size,
            height: size,
            fit: BoxFit.contain,
          );

    if (unlocked) {
      return svg;
    }

    // 未点亮：把彩色 SVG 用 srcIn 混合模式整体染灰，得到实色剪影。
    // srcIn 会让目标像素的 RGB 全部变成 filter color，但保留 SVG 自身的 alpha 通道，
    // 所以动物轮廓内填灰色、轮廓外保持透明 —— 完美贴合原版的"线稿剪影"视觉。
    return ColorFiltered(
      colorFilter: ColorFilter.mode(silhouetteColor, BlendMode.srcIn),
      child: svg,
    );
  }
}
