import 'dart:io';
import 'dart:math' as math;
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

  /// 滚动截长图：把当前视图从头到尾逐屏截图，纵向拼接成一张长图后分享
  ///
  /// [viewportKey] 必须挂在包住整个滚动视图的 RepaintBoundary 上。
  /// 截图期间会临时滚动页面，结束后恢复原位置；页面极长时自动降低
  /// 导出倍率，避免超大位图占用内存。
  static Future<void> shareScrollable({
    required BuildContext context,
    required ScrollController controller,
    required GlobalKey viewportKey,
    required String fileName,
    String? text,
  }) async {
    if (!controller.hasClients) throw StateError('no_scroll');
    final boundary =
        viewportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('boundary_missing');
    final size = boundary.size;
    final maxScroll = controller.position.maxScrollExtent;
    // 长图总高（逻辑像素）与导出倍率：短页面 2x，超长列表自动降级
    final totalLogical = maxScroll + size.height;
    var ratio = 2.0;
    const maxPixels = 40.0 * 1000 * 1000;
    if (size.width * totalLogical * ratio * ratio > maxPixels) {
      ratio = math.sqrt(maxPixels / (size.width * totalLogical)).clamp(1.0, 2.0);
    }
    final originalOffset = controller.offset;
    final frames = <ui.Image>[];
    final offsets = <double>[];
    try {
      var offset = 0.0;
      while (frames.length < 120) {
        controller.jumpTo(offset);
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 80));
        frames.add(await boundary.toImage(pixelRatio: ratio));
        offsets.add(offset);
        if (offset >= maxScroll - 0.5) break;
        offset = math.min(maxScroll, offset + size.height);
      }
    } finally {
      controller.jumpTo(originalOffset);
    }
    final outW = (size.width * ratio).round();
    final outH = (totalLogical * ratio).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    );
    for (var i = 0; i < frames.length; i++) {
      canvas.drawImage(frames[i], Offset(0, offsets[i] * ratio), Paint());
      frames[i].dispose();
    }
    final picture = recorder.endRecording();
    final stitched = await picture.toImage(outW, outH);
    picture.dispose();
    final data = await stitched.toByteData(format: ui.ImageByteFormat.png);
    stitched.dispose();
    final bytes = data?.buffer.asUint8List();
    if (bytes == null) throw StateError('encode_failed');
    await _share(bytes, fileName: fileName, text: text);
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
