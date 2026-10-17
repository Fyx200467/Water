import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../settings/settings_flags.dart';

/// SVG 矢量容器渲染组件
///
/// containerId 约定：'svg:<文件名>'（不含扩展名），对应
/// assets/images/containers/<文件名>.svg，要求单色实心剪影。
/// 图标库为运行时枚举：向目录丢入新 SVG 即自动出现在图标选择页，无需改代码。
/// 渲染机制：
/// - 静态图标：flutter_svg ColorFilter.srcIn 整体染色
/// - 动态液体：saveLayer 画液体层（波面 + 气泡），
///   再用 SVG alpha 以 BlendMode.dstIn 作蒙版裁剪进容器形状
bool isSvgContainer(String? id) => id != null && id.startsWith('svg:');

String svgContainerAsset(String id) =>
    'assets/images/containers/${id.substring(4)}.svg';

/// 运行时枚举 assets/images/containers/ 下全部 SVG 容器 id（按文件名排序）
///
/// 隐藏名单：设计不合格/与已有图标重复的容器，不在图标选择页出现
/// （2026-10 用户指定移除：条纹果汁瓶 / 斜吸管外带杯 / 粗把手马克杯 /
/// 冒热气茶杯）。文件保留在资产里，避免历史饮品 containerId 悬空
const Set<String> kHiddenContainerIds = {
  'svg:bottle',
  'svg:water_cup',
  'svg:water_cup_1',
  'svg:water_cup_2',
};

Future<List<String>> loadSvgContainerIds() async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    const prefix = 'assets/images/containers/';
    final ids = manifest
        .listAssets()
        .where((a) => a.startsWith(prefix) && a.endsWith('.svg'))
        .map((a) => 'svg:${a.substring(prefix.length, a.length - 4)}')
        .where((id) => !kHiddenContainerIds.contains(id))
        .toList()
      ..sort();
    return ids;
  } catch (_) {
    return const [];
  }
}

/// 容器图画的像素度量（viewBox 坐标系）：
/// - bounds：不透明内容的包围盒（SVG 源文件留白各异，液体必须按它对齐，
///   否则会出现液底悬空灰条 / 液面漫过杯口）
/// - bodyTop：主体（杯瓶碗身）顶部 y——逐行扫描最大连续不透明游程，
///   首个达到最大游程 50% 的行视为杯口沿，吸管 / 瓶颈 / 把手等窄结构被排除
class SvgArtMetrics {
  const SvgArtMetrics(this.bounds, this.bodyTop);

  final Rect bounds;
  final double bodyTop;
}

final Map<String, Future<SvgArtMetrics?>> _svgArtMetricsCache = {};

/// 对已加载的容器 SVG 做一次 160×160 alpha 光栅扫描（结果按 containerId 缓存）
Future<SvgArtMetrics?> loadSvgArtMetrics(
  String containerId,
  ui.Picture picture,
  Size viewBox,
) {
  if (viewBox.isEmpty) return Future.value(null);
  return _svgArtMetricsCache.putIfAbsent(containerId, () async {
    try {
      const r = 160;
      // 与目标盒子相同的非等比缩放光栅化，坐标系与 viewBox 线性对应
      final rec = ui.PictureRecorder();
      ui.Canvas(rec)
        ..scale(r / viewBox.width, r / viewBox.height)
        ..drawPicture(picture);
      final image = await rec.endRecording().toImage(r, r);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (data == null) return null;
      final px = data.buffer.asUint8List();

      var minX = r, maxX = -1, minY = r, maxY = -1;
      final runs = List<int>.filled(r, 0);
      var maxRun = 0;
      for (var y = 0; y < r; y++) {
        var run = 0, best = 0;
        for (var x = 0; x < r; x++) {
          if (px[(y * r + x) * 4 + 3] > 12) {
            run++;
            if (run > best) best = run;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
          } else {
            run = 0;
          }
        }
        runs[y] = best;
        if (best > 0) {
          if (y < minY) minY = y;
          maxY = y;
          if (best > maxRun) maxRun = best;
        }
      }
      if (maxX < 0 || maxRun == 0) return null;

      // 主体顶部：首个游程 ≥ 最大游程一半的行
      final threshold = maxRun * 0.5;
      var bodyRow = minY;
      for (var y = minY; y <= maxY; y++) {
        if (runs[y] >= threshold) {
          bodyRow = y;
          break;
        }
      }
      return SvgArtMetrics(
        Rect.fromLTRB(
          minX / r * viewBox.width,
          minY / r * viewBox.height,
          (maxX + 1) / r * viewBox.width,
          (maxY + 1) / r * viewBox.height,
        ),
        bodyRow / r * viewBox.height,
      );
    } catch (_) {
      return null;
    }
  });
}

/// 容器内上升气泡（所有容器液体共用的气泡动画逻辑）：
/// - 生成：仅出现在「floorY（10ml 液位线，生成区最深处）以上 + 整个容器
///   下三分之二」的固定区间随机位置——参考全部固定，拖动水量时出生点
///   与节奏完全不动；出生点在当前液面之上（含水量恰为 10ml 时）不显示，
///   水位升过时自然浮现
/// - 随机性：出生位置/大小/横摆相位在每颗气泡的每次出现时都重新抽取
///   （出现序号参与伪随机种子），避免固定循环造成「总在同一处出现」
/// - 路线：大幅 S 形上升（单一正弦横摆，弧度大，避免小弧度显得乱窜）
/// - 速度：按满杯液深的 3.5%~5% 每秒——基准取 refDepth（满杯液深，
///   同一容器恒定），不随当前水量（液面高度）压缩
/// - 样式（对标参考图）：液体色调浅一档的半透明圆盘 + 内部右下一道
///   弯月形高光（液体色略深）
/// - 尺寸随机：上限为满杯液深半径的 1.8%（clamp 1.2~5px），35%~100% 随机；
///   诞生时从极小长大 → 中段保持 → 末段逐渐缩小直至消散
/// - 生命 2.2~3.8s 随机、相位错开，偶尔同时出现几颗也自然；
///   提前抵达液面时就地加速消散
void drawRisingBubbles(
  Canvas canvas, {
  required Color liquidColor,
  required double left,
  required double right,
  required double bottom,
  required double surface,
  required double refDepth,
  required double floorY, // 生成区下限液位线（如 10ml 线）
  required double tSeconds,
  int count = 5,
  int seed = 0,
  double sizeScale = 1.0,
  double baseAlpha = 0.16,
}) {
  // 「杯子里的动画」总开关关闭：全部粒子动画停画（液面波浪不受影响）
  if (!SettingsFlags.instance.cupAnimations) return;
  double rnd(int i, int salt) {
    final v = math.sin((i + seed + 1) * 12.9898 + salt * 78.233) * 43758.5453;
    return v - v.floor();
  }

  double smooth(double x) {
    x = x.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  final depth = math.max(refDepth, 1.0);
  // 生成区完全由固定参考决定：最深处为 floorY（10ml 线），最高到容器
  // 下三分之二分界线——不随当前液面移动，拖动水量时气泡位置与节奏不变
  final zoneTop = bottom - depth * 2 / 3;
  final zoneBottom = math.min(floorY, bottom - 2);
  final zone = zoneBottom - zoneTop;
  if (zone < depth * 0.05) return; // 生成区异常狭窄则不出气泡
  // 大幅 S 形：单一正弦、约每 1.1 倍液深完成一个整波，弧度大而顺滑
  final swayAmp = (depth * 0.12).clamp(6.0, 20.0);
  final swayFreq = math.pi / (depth * 0.55);
  final paint = Paint();
  for (int i = 0; i < count; i++) {
    final period = 2.2 + rnd(i, 1) * 1.6; // 生命 2.2~3.8s，各自随机
    final phaseOffset = rnd(i, 2) * period + i * 0.7; // 相位错开
    final age = (tSeconds + phaseOffset) % period;
    // 该颗气泡当前是第几次出现：每次出现都换一批随机数（出生位置/大小/
    // 横摆相位），避免固定伪随机循环造成「总在同一处出现」
    final cycle = ((tSeconds + phaseOffset) / period).floor();
    final p = age / period;
    final speed = depth * (0.035 + rnd(i, 3) * 0.015); // px/s，恒定
    final spawnY = zoneBottom - rnd(i + cycle * 17, 4) * zone;
    // 出生点在当前液面之上则不显示（水量拖到 10ml 时液面 = 10ml 线，
    // 整个生成区都在液面之上，因此不会有任何气泡）
    if (spawnY < surface + 0.5) continue;
    final dist = speed * age;
    final maxRise = spawnY - (surface + 1); // 提前抵达液面则就地消散
    final rMax = (depth * 0.018).clamp(1.2, 5.0) * sizeScale;
    // 大小随机，上限为固定最大值（每次出现重新抽取）
    final r0 = rMax * (0.35 + rnd(i + cycle * 17, 5) * 0.65);
    final grow = 0.2 + 0.8 * smooth(p / 0.15); // 极小 → 正常
    var shrink = p > 0.6 ? 1 - smooth((p - 0.6) / 0.4) : 1.0; // 末段缩小
    var alpha = baseAlpha * smooth(p / 0.08);
    if (p > 0.6) alpha *= shrink;
    if (dist > maxRise) {
      final k = (1 - (dist - maxRise) / (speed * 0.3)).clamp(0.0, 1.0);
      shrink *= k;
      alpha *= k;
    }
    final r = r0 * grow * shrink;
    if (r < 0.3 || alpha < 0.02) continue;
    // 大幅 S 形上升路线：单一正弦横摆（相位随上升距离推进，每次出现重抽）
    final baseX = left + rnd(i + cycle * 17, 6) * (right - left);
    final cx = (baseX +
            swayAmp * math.sin(dist * swayFreq + rnd(i + cycle * 17, 8) * 6.3))
        .clamp(left + 2, right - 2);
    final cy = math.max(spawnY - dist, surface + r * 0.5);
    // 圆盘：液体色上叠白色的浅色调（参考图约 19% 白，按用户要求再调透明）
    paint.color = Colors.white.withValues(alpha: alpha.clamp(0.0, 1.0));
    canvas.drawCircle(Offset(cx, cy), r, paint);
    // 内部弯月高光：右下方向一道小弧线，颜色为液体色略深一档
    if (r >= 1.6) {
      paint.color = Color.lerp(liquidColor, Colors.black, 0.08)!
          .withValues(alpha: (alpha * 1.6).clamp(0.0, 1.0));
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, r * 0.16)
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(
          center: Offset(cx - r * 0.15, cy - r * 0.15),
          radius: r * 0.55,
        ),
        0.05, // 自右侧偏上起弧，扫过右下象限，形如逗号弯月
        1.25,
        false,
        paint,
      );
      paint
        ..style = PaintingStyle.fill
        ..strokeCap = StrokeCap.butt;
    }
  }
}

/// 茶叶粒子（对标原版绿茶容器：叶片沉在容器底部）：
/// - 分布：容器底部固定区间（液底上方 8%~38% 满杯液深），不随当前
///   液量压缩；高于当前液面的叶片跳过（低液量时自然隐藏，与气泡/米粒同哲学）
/// - 样式（用户参考图实测）：大叶 = 亮色椭圆叶片 + 深色弯缝中脉，
///   小叶 = 实心椭圆叶点；叶身 = 液体色叠约 24% 白提亮，中脉 = 液体色加深
/// - 动态：各自固定旋转角 + 轻微上下浮动（±2.5px，缓慢正弦）
void drawTeaLeaves(
  Canvas canvas, {
  required Color liquidColor,
  required double left,
  required double right,
  required double bottom, // 液底
  required double top, // 满杯液面顶（fillTop / 杯身顶）
  required double surface, // 当前液面基准线
  required double tSeconds, // 连续时钟秒（浮动相位）
  int count = 7,
  int seed = 13,
}) {
  // 「杯子里的动画」总开关关闭：茶叶停画
  if (!SettingsFlags.instance.cupAnimations) return;
  final depth = bottom - top;
  if (depth <= 0) return;
  final zoneBottom = bottom - depth * 0.08; // 最深（贴近液底）
  final zoneTop = bottom - depth * 0.38; // 最浅
  final rng = math.Random(seed);
  for (var i = 0; i < count; i++) {
    final baseY = zoneTop + (zoneBottom - zoneTop) * rng.nextDouble();
    if (baseY < surface + 2) continue; // 液面之上不显示
    final cx = left + (right - left) * (0.15 + rng.nextDouble() * 0.70);
    final cy = baseY + math.sin(tSeconds * 0.9 + i * 1.7) * 2.5;
    final big = i < 3; // 前三片为大叶（带中脉），其余为小叶点
    final len = big
        ? (right - left) * (0.055 + rng.nextDouble() * 0.02)
        : (right - left) * (0.028 + rng.nextDouble() * 0.015);
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rng.nextDouble() * math.pi * 2);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: len, height: len * 0.46),
      Paint()
        ..color = Color.lerp(liquidColor, Colors.white, 0.24)!,
    );
    if (big) {
      // 中脉：沿叶片长轴的深色弯缝
      canvas.drawPath(
        Path()
          ..moveTo(-len * 0.38, 0)
          ..quadraticBezierTo(0, len * 0.16, len * 0.38, 0),
        Paint()
          ..color = Color.lerp(liquidColor, Colors.black, 0.16)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = len * 0.11
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();
  }
}

/// 静态容器图标：单色剪影整体染色（首页饮品栏 / 管理页卡片用）。
/// 按图形包围盒归一化渲染——各源文件留白差异大（有的图形铺满画框、
/// 有的四周大量留白），固定 contain 会导致视觉大小不一致；统一把
/// 图形包围盒等比缩放至盒子的 92% 并居中，与预设插画的占空比对齐
///
/// fillRatio 非空时渲染「液体风格」（编辑页预览同款）：
/// 空杯剪影染 emptyColor，液体从液位线染到杯底（液面与杯口沿留
/// 5% 气隙，与 SvgContainerFill 同规则），整体按剪影 alpha 裁剪
class SvgContainerIcon extends StatefulWidget {
  const SvgContainerIcon({
    super.key,
    required this.containerId,
    required this.color,
    this.size = 52,
    this.fillRatio,
    this.emptyColor,
  });

  final String containerId;
  final Color color;
  final double size;

  /// 液体占杯身比例 0~1（null = 纯剪影整体染色）
  final double? fillRatio;

  /// 空杯部分颜色（液体风格用，默认浅灰 #E9E9EB，与动态液体容器一致）
  final Color? emptyColor;

  @override
  State<SvgContainerIcon> createState() => _SvgContainerIconState();
}

class _SvgContainerIconState extends State<SvgContainerIcon> {
  PictureInfo? _info;
  SvgArtMetrics? _metrics;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(SvgContainerIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 容器 id 变化必须重载（如编辑页选择新容器后同位置元素复用旧 State），
    // 否则 _load 的「已加载即跳过」守卫会一直显示旧容器剪影
    if (oldWidget.containerId != widget.containerId) {
      _info = null;
      _metrics = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    if (_info != null || _failed) return;
    try {
      final info = await vg.loadPicture(
        SvgAssetLoader(svgContainerAsset(widget.containerId)),
        context,
      );
      final metrics = await loadSvgArtMetrics(
        widget.containerId,
        info.picture,
        info.size,
      );
      if (mounted) {
        setState(() {
          _info = info;
          _metrics = metrics;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    // 未加载完成或失败回退：普通 contain 剪影（视觉大小可能略有偏差）
    if (_failed || info == null) {
      return SvgPicture.asset(
        svgContainerAsset(widget.containerId),
        colorFilter: ColorFilter.mode(widget.color, BlendMode.srcIn),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
      );
    }
    return CustomPaint(
      size: Size.square(widget.size),
      painter: _SvgIconPainter(
        picture: info.picture,
        viewBox: info.size,
        bounds: _metrics?.bounds,
        bodyTop: _metrics?.bodyTop,
        color: widget.color,
        fillRatio: widget.fillRatio,
        emptyColor: widget.emptyColor,
      ),
    );
  }
}

class _SvgIconPainter extends CustomPainter {
  _SvgIconPainter({
    required this.picture,
    required this.viewBox,
    required this.bounds,
    required this.bodyTop,
    required this.color,
    this.fillRatio,
    this.emptyColor,
  });

  final ui.Picture picture;
  final Size viewBox;
  final Rect? bounds;
  final double? bodyTop; // 杯口沿 y（viewBox 坐标，液体风格定位液面用）
  final Color color;
  final double? fillRatio; // null = 纯剪影；非空 = 液体风格
  final Color? emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    final fr = fillRatio;
    if (fr == null) {
      _paintSolid(canvas, size);
    } else {
      _paintLiquid(canvas, size, fr);
    }
  }

  /// 剪影绘制（调用方需自行 save/restore）：包围盒等比 contain-fit
  /// 至盒子的 92% 居中；无度量时退化为非等比铺满
  void _drawSilhouette(Canvas canvas, Size size) {
    final b = bounds;
    if (b == null || b.width <= 0 || b.height <= 0) {
      canvas.scale(
        size.width / viewBox.width,
        size.height / viewBox.height,
      );
      canvas.drawPicture(picture);
    } else {
      const targetFactor = 0.92;
      final s = math.min(
        size.width * targetFactor / b.width,
        size.height * targetFactor / b.height,
      );
      canvas.translate(
        size.width / 2 - (b.left + b.width / 2) * s,
        size.height / 2 - (b.top + b.height / 2) * s,
      );
      canvas.scale(s);
      canvas.drawPicture(picture);
    }
  }

  /// 液位线 y（icon 像素空间）：与 SvgContainerFill 同规则——
  /// 液面顶 = 杯口沿 + 5% 盒高气隙，液面按 fillRatio 在
  /// [液面顶, 图形底部] 区间内插值；无度量时按画框比例兜底
  double _levelY(Size size, double fr) {
    final b = bounds;
    final bt = bodyTop;
    if (b == null || b.width <= 0 || b.height <= 0 || bt == null) {
      return size.height * (1 - fr.clamp(0.0, 1.0));
    }
    const targetFactor = 0.92;
    final s = math.min(
      size.width * targetFactor / b.width,
      size.height * targetFactor / b.height,
    );
    final ty = size.height / 2 - (b.top + b.height / 2) * s;
    final bottomPx = b.bottom * s + ty;
    final liquidTopPx = bt * s + ty + size.height * 0.05;
    return liquidTopPx +
        (1 - fr.clamp(0.0, 1.0)) * (bottomPx - liquidTopPx);
  }

  /// 纯剪影：整体染色
  void _paintSolid(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.save();
    _drawSilhouette(canvas, size);
    canvas.restore();
    // 整体染色（restore 后画，矩形不受图标变换影响）
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = color
        ..blendMode = BlendMode.srcIn,
    );
    canvas.restore();
  }

  /// 液体风格：空杯染 emptyColor + 液体层染饮品色，按剪影 alpha 裁剪
  void _paintLiquid(Canvas canvas, Size size, double fr) {
    final empty = emptyColor ?? const Color(0xFFE9E9EB);
    // 1. 空杯：剪影整体染浅灰
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.save();
    _drawSilhouette(canvas, size);
    canvas.restore();
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = empty
        ..blendMode = BlendMode.srcIn,
    );
    canvas.restore();

    // 2. 液体：液位线以下矩形染饮品色，再按剪影 alpha 蒙版裁剪进杯形
    final level = _levelY(size, fr);
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(
      Rect.fromLTRB(0, level, size.width, size.height),
      Paint()..color = color,
    );
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..blendMode = BlendMode.dstIn,
    );
    canvas.save();
    _drawSilhouette(canvas, size);
    canvas.restore();
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SvgIconPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.fillRatio != fillRatio ||
      oldDelegate.emptyColor != emptyColor ||
      oldDelegate.bodyTop != bodyTop;
}

/// 动态液体容器：灰底空杯剪影 + 液体（波面/气泡）按 SVG alpha 蒙版填充
class SvgContainerFill extends StatefulWidget {
  const SvgContainerFill({
    super.key,
    required this.containerId,
    required this.color,
    required this.fillRatio,
    this.capacityMl,
    this.phase = 0,
    this.bubbleSeed = 0,
  });

  final String containerId;
  final Color color;

  /// 液面比例 0~1（水量 / 容器容量）
  final double fillRatio;

  /// 容器容量（ml），用于换算 10ml 气泡生成下限液位线
  final double? capacityMl;

  /// 波面相位（波浪动画）
  final double phase;

  /// 气泡推进种子（0~1 循环）
  final double bubbleSeed;

  @override
  State<SvgContainerFill> createState() => _SvgContainerFillState();
}

class _SvgContainerFillState extends State<SvgContainerFill> {
  PictureInfo? _info;
  SvgArtMetrics? _metrics;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(SvgContainerFill oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 容器 id 变化必须重载（同 SvgContainerIcon：列表复用元素时防旧图残留）
    if (oldWidget.containerId != widget.containerId) {
      _info = null;
      _metrics = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    if (_info != null || _failed) return;
    try {
      final info =
          await vg.loadPicture(SvgAssetLoader(svgContainerAsset(
        widget.containerId,
      )), context);
      final metrics = await loadSvgArtMetrics(
        widget.containerId,
        info.picture,
        info.size,
      );
      if (mounted) {
        setState(() {
          _info = info;
          _metrics = metrics;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) {
      // 加载失败回退：简单色块容器
      return _failed
          ? Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFE9E9EB),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                widthFactor: 1,
                heightFactor: widget.fillRatio.clamp(0.0, 1.0),
                child: ColoredBox(color: widget.color),
              ),
            )
          : const SizedBox();
    }
    return CustomPaint(
      size: Size.infinite,
      painter: _SvgLiquidPainter(
        picture: info.picture,
        viewBox: info.size,
        metrics: _metrics,
        color: widget.color,
        fillRatio: widget.fillRatio,
        capacityMl: widget.capacityMl,
        phase: widget.phase,
        bubbleSeed: widget.bubbleSeed,
      ),
    );
  }
}

class _SvgLiquidPainter extends CustomPainter {
  _SvgLiquidPainter({
    required this.picture,
    required this.viewBox,
    required this.metrics,
    required this.color,
    required this.fillRatio,
    required this.capacityMl,
    required this.phase,
    required this.bubbleSeed,
  });

  final ui.Picture picture;
  final Size viewBox;
  final SvgArtMetrics? metrics;
  final Color color;
  final double fillRatio;
  final double? capacityMl; // 容器容量 ml（10ml 生成线用）
  final double phase;
  final double bubbleSeed;

  /// 将 viewBox 坐标系的 SVG Picture 非等比铺满目标 size
  void _drawScaled(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / viewBox.width,
      size.height / viewBox.height,
    );
    canvas.drawPicture(picture);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 空容器：整只剪影染浅灰
    canvas.saveLayer(Offset.zero & size, Paint());
    _drawScaled(canvas, size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = const Color(0xFFE9E9EB)
        ..blendMode = BlendMode.srcIn,
    );
    canvas.restore();

    // 2. 液体层：波面以下填饮品色 + 上升气泡，随后按 SVG alpha 裁剪
    //    液底与液面按容器图形度量计算（源文件留白各异，不能按画框估算）
    canvas.saveLayer(Offset.zero & size, Paint());

    final m = metrics;
    final bottom = m == null
        ? size.height * 0.99
        : m.bounds.bottom / viewBox.height * size.height + 0.5;
    final bodyTop = m == null
        ? size.height * 0.03
        : m.bodyTop / viewBox.height * size.height;
    // 液面最高点与杯口沿保留气隙（满杯也不触口），与预设容器
    // _DrinkContainerPainter 的 fillTop=杯口沿+5%×画布高 同一规则
    final liquidTop = bodyTop + size.height * 0.05;
    final level =
        liquidTop + (1 - fillRatio.clamp(0.0, 1.0)) * (bottom - liquidTop);

    // 波面与预设容器同款：单空间正弦，满杯宽一个整波、振幅 3px，
    // 相位由 _waveCtrl 驱动（1.6s 走满 2π）
    const samples = 30;
    double waveY(double u) => level + math.sin(u * math.pi * 2 + phase) * 3;

    final wave = Path()..moveTo(0, bottom);
    for (var i = 0; i <= samples; i++) {
      final u = i / samples;
      wave.lineTo(size.width * u, waveY(u));
    }
    wave
      ..lineTo(size.width, bottom)
      ..close();
    canvas.drawPath(wave, Paint()..color = color);

    // 液面高光线（与预设容器一致：白色半透明描边）
    final surface = Path();
    for (var i = 0; i <= samples; i++) {
      final u = i / samples;
      if (i == 0) {
        surface.moveTo(size.width * u, waveY(u));
      } else {
        surface.lineTo(size.width * u, waveY(u));
      }
    }
    canvas.drawPath(
      surface,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 气泡：随机时间与位置出现（不随水量压缩），10ml 线以上且容器下半部
    // 随机生成，S 形上升，浅色圆盘 + 弯月高光 → 缩小消散
    if (fillRatio > 0.04) {
      final cap = capacityMl;
      final fullDepth = bottom - liquidTop;
      final floorY = cap == null || cap <= 10
          ? bottom - fullDepth * 0.7
          : bottom - fullDepth * (10 / cap);
      drawRisingBubbles(
        canvas,
        liquidColor: color,
        left: 0,
        right: size.width,
        bottom: bottom,
        surface: level,
        refDepth: fullDepth,
        floorY: floorY,
        tSeconds: bubbleSeed * 14, // 驱动控制器周期 14s
        count: 5,
        seed: 3,
      );
    }

    // SVG alpha 蒙版：液体被裁剪进容器剪影
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..blendMode = BlendMode.dstIn,
    );
    _drawScaled(canvas, size);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SvgLiquidPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.fillRatio != fillRatio ||
      oldDelegate.phase != phase ||
      oldDelegate.bubbleSeed != bubbleSeed ||
      oldDelegate.metrics != metrics;
}
