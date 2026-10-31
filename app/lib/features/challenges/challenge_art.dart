import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/sync/sync_api.dart';

/// 挑战插画：内置 assets、服务端上传图片（/media/...）与完整 URL 三种来源
class ChallengeArt extends StatelessWidget {
  const ChallengeArt({
    super.key,
    required this.asset,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  final String asset;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// 兜底插画：目录里填了错误/不存在的路径时不让卡片空白
  static const String _fallbackAsset =
      'assets/images/characters/red_squirrel.svg';

  @override
  Widget build(BuildContext context) {
    final a = asset.trim();
    // 内置资源（如 assets/images/characters/otter.svg）
    if (!a.startsWith('http') && !a.startsWith('/')) {
      return SvgPicture.asset(
        a.isEmpty ? _fallbackAsset : a,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: _svgError,
      );
    }
    // 服务端相对路径（/static/...、/media/...）统一拼接口域名；
    // 完整 URL 直接使用
    final url = a.startsWith('http') ? a : '${SyncApi.baseUrl}$a';
    if (url.toLowerCase().endsWith('.svg')) {
      return SvgPicture.network(
        url,
        width: width,
        height: height,
        fit: fit,
        placeholderBuilder: (_) => const SizedBox.shrink(),
        errorBuilder: _svgError,
      );
    }
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stack) => _fallback(),
    );
  }

  Widget _svgError(BuildContext context, Object error, StackTrace stack) =>
      _fallback();

  Widget _fallback() => SvgPicture.asset(
        _fallbackAsset,
        width: width,
        height: height,
        fit: fit,
      );
}
