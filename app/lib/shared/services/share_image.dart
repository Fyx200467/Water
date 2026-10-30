import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 组件截图 → PNG → 系统分享面板的通用工具
///
/// 历史页战绩卡、庆祝海报都是"看不见的原尺寸组件"：
/// [capture] 会把组件挂到离屏 Overlay 上按原始尺寸渲染，再按 pixelRatio
/// 导出（3 倍 = 1080 宽），避免受页面上 FittedBox 缩放影响。
class ShareImage {
  const ShareImage._();

  /// 离屏渲染 [builder] 的组件并分享成图片
  ///
  /// 组件必须自带固定尺寸（如 SizedBox(width: 360, height: 640)），
  /// 否则 Overlay 会给它无界约束。
  static Future<void> capture({
    required BuildContext context,
    required WidgetBuilder builder,
    required String fileName,
    String? text,
    double pixelRatio = 3,
  }) async {
    final key = GlobalKey();
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -4000,
        top: 0,
        child: RepaintBoundary(
          key: key,
          child: Builder(builder: builder),
        ),
      ),
    );
    overlay.insert(entry);
    try {
      // 等两帧 + 一点余量：保证离屏组件完成布局与首帧绘制
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('boundary_missing');
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = data?.buffer.asUint8List();
      if (bytes == null) throw StateError('encode_failed');
      await _share(bytes, fileName: fileName, text: text);
    } finally {
      entry.remove();
    }
  }

  /// 分享已经写好的 PNG 字节（临时文件方式，微信/QQ 可直接读取）
  static Future<void> _share(
    Uint8List bytes, {
    required String fileName,
    String? text,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: text,
      ),
    );
  }
}
