part of 'history_screen.dart';

// ==================== 多层饮品色水滴按钮 ====================

/// 多层饮品色水滴（统计卡「全部」筛选按钮）：底部圆弧 + 顶部汇聚尖点，
/// 形状不变，内部改为 4 层横向色带填充（自上而下：酒类粉/奶类橙黄/
/// 纯水青/茶类绿），层间为轻微波浪分界，呼应竞品的分层配色设计
class _WaterDropPainter extends CustomPainter {
  const _WaterDropPainter();

  /// 色带颜色（自上而下），全部取自饮品分类色
  static const List<Color> _layerColors = [
    Color(0xFFE57373), // 酒类粉（顶部尖点区，对应参考图的粉层）
    Color(0xFFFFC107), // 奶类橙黄
    Color(0xFF00BFDC), // 纯水青
    Color(0xFF8BC34A), // 茶类绿（底部基色）
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final r = size.width * 0.31;
    final cy = size.height * 0.58;
    final tipY = size.height * 0.08;
    final drop = Path()
      ..moveTo(cx, tipY)
      // 右侧流线：从尖点外凸弧线过渡到圆右侧
      ..cubicTo(cx + r * 0.72, cy - r * 0.88, cx + r, cy - r * 0.48,
          cx + r, cy)
      // 底部半圆
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        0,
        math.pi,
        false,
      )
      // 左侧流线（对称）回尖点
      ..cubicTo(cx - r, cy - r * 0.48, cx - r * 0.72, cy - r * 0.88,
          cx, tipY)
      ..close();

    canvas.save();
    canvas.clipPath(drop);

    // 波浪分界线：baseY 上下做小幅正弦起伏
    Offset wavePoint(double x, double baseY, double amp, double phase) =>
        Offset(x, baseY + amp * math.sin(x / size.width * 2 * math.pi + phase));

    // 自上而下逐层覆盖：先整滴填顶色，再依次画下层色带
    // （每条色带从其波浪分界线一直铺到底，层层覆盖出 4 段）
    final span = cy + r - tipY;
    final bands = 3; // 分界线数量 = 层数 - 1
    for (var i = 0; i <= bands; i++) {
      final Color color;
      final Path band;
      if (i == 0) {
        color = _layerColors.first;
        band = Path()..addRect(Offset.zero & size);
      } else {
        color = _layerColors[i];
        final baseY = tipY + span * i / bands;
        final amp = size.width * 0.045;
        final phase = i * 1.8; // 各层波浪错开，更自然
        band = Path();
        const segs = 24;
        band.moveTo(0, baseY + amp * math.sin(phase));
        for (var s = 1; s <= segs; s++) {
          band.lineTo(
              size.width * s / segs, wavePoint(size.width * s / segs, baseY, amp, phase).dy);
        }
        band
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
      }
      canvas.drawPath(band, Paint()..color = color);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 进度环（静态）：浅青轨道 + 青色进度弧；环内蓝色圆由上层绘制
class _BadgePainter extends CustomPainter {
  const _BadgePainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 3;

    // 轨道
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = const Color(0xFFE3F2F7),
    );
    // 进度弧
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = _kCyan,
    );
  }

  @override
  bool shouldRepaint(_BadgePainter old) => old.progress != progress;
}

/// 日期小进度环：浅灰轨道 + 达标度色弧（自 12 点方向顺时针），
/// 用于逐日记录列表左侧的圆形进度标识
class _DayRingPainter extends CustomPainter {
  const _DayRingPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 2.2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..color = const Color(0xFFECECEE),
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_DayRingPainter old) =>
      old.progress != progress || old.color != color;
}

/// 简易柱状图：全圆角柱体（青色），值为 0 不画柱（只保留轴标签）。
/// line=true 时同数据渲染为折线图；标题区固定高度，保证天/周/月
/// 切换（单行/双行标题）时卡片总高度一致不上下跳
class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.title,
    required this.bars,
    required this.barWidth,
    required this.line,
  });
  final String title;
  final List<_BarData> bars;
  final double barWidth;
  final bool line;

  @override
  Widget build(BuildContext context) {
    // 取绝对值最大值：全是负数时也能正确归一（maxVal=0 会除零）
    final maxVal = bars.fold<int>(0, (a, b) => math.max(a, b.value.abs()));

    return Column(
      children: [
        // 标题区固定 38 高（容纳两行标题），单行/双行不改变卡片高度
        SizedBox(
          height: 38,
          child: Center(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _kTextDark,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        line
            ? _LineChartBody(bars: bars, maxVal: maxVal)
            : SizedBox(
                // 值标签(4+14) + 柱体88 + 间距6 + 轴标签12 + 余量 ≈ 144
                // 原 130 高度导致 "BOTTOM OVERFLOWED BY 3.0 PIXELS"，加高到 144 修复
                height: 144,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final b in bars)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // 柱顶值标签（负值红、今天青色加粗、其他天灰色）
                          if (b.valueLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                b.valueLabel!,
                                style: TextStyle(
                                  color: b.value < 0
                                      ? const Color(0xFFE8446A)
                                      : b.highlighted
                                          ? _kCyan
                                          : _kHintGray,
                                  fontSize: 11,
                                  fontWeight: b.highlighted
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          // 柱体：值为 0 不画（只保留轴标签，对标原版）；
                          // 负值（负容量记录/负日均）画红色柱，高度取绝对值
                          Container(
                            width: barWidth,
                            height: b.value != 0 && maxVal > 0
                                ? (b.value.abs() / maxVal * 88).clamp(6.0, 88.0)
                                : 0.0,
                            decoration: BoxDecoration(
                              color:
                                  b.value < 0 ? const Color(0xFFE8446A) : _kCyan,
                              borderRadius: BorderRadius.circular(
                                  math.min(8.0, barWidth / 2)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            b.label,
                            style: TextStyle(
                              color: b.highlighted ? _kCyan : _kHintGray,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
      ],
    );
  }
}

/// 折线图（与柱状图同 144 高度预算）：整个绘图交给 _LinePainter，
/// 含 XY 轴、横向网格线与底部轴标签
class _LineChartBody extends StatelessWidget {
  const _LineChartBody({required this.bars, required this.maxVal});
  final List<_BarData> bars;
  final int maxVal;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 144,
      child: CustomPaint(
        size: Size.infinite,
        painter: _LinePainter(bars, maxVal),
      ),
    );
  }
}

/// 折线绘制（含坐标轴）：
/// - Y 轴：每格 600ml 横向网格线 + 左侧刻度文字（600ml/1200ml/…），
///   上限 = 数据最大值向上取整到 600 的整数倍（至少 600）
/// - X 轴：底部轴线 + 各数据点正下方的天/周/月标签
/// - 青色圆角折线 + 数据点圆点（今天高亮加大），非空 valueLabel 标在点上方
///   （负值红）；负值按 0 处理
class _LinePainter extends CustomPainter {
  const _LinePainter(this.bars, this.maxVal);
  final List<_BarData> bars;
  final int maxVal;

  static const double _padLeft = 42; // 左侧 Y 轴刻度文字区
  static const double _padRight = 12;
  static const double _plotTop = 18; // 顶部留给数据点值标签
  static const double _xLabelH = 15; // 底部 X 轴标签区

  @override
  void paint(Canvas canvas, Size size) {
    final n = bars.length;
    if (n == 0) return;

    // Y 轴刻度：每格 600ml，上限向上取整到 600 的整数倍
    const yStep = 600.0;
    final steps = maxVal <= 0 ? 1 : (maxVal / yStep).ceil();
    final topV = steps * yStep;

    final plotBottom = size.height - _xLabelH - 2;
    final plotH = plotBottom - _plotTop;
    final plotW = size.width - _padLeft - _padRight;

    double xOf(int i) =>
        n == 1 ? _padLeft + plotW / 2 : _padLeft + i * plotW / (n - 1);
    double yOf(double v) => plotBottom - (v / topV) * plotH;

    TextPainter tp(String text,
        {Color color = const Color(0xFF9AA1A9),
        double fontSize = 9,
        FontWeight weight = FontWeight.w400}) {
      final p = TextPainter(
        text: TextSpan(
          text: text,
          style:
              TextStyle(color: color, fontSize: fontSize, fontWeight: weight),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      return p;
    }

    final gridPaint = Paint()
      ..color = const Color(0xFFEEF0F3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = const Color(0xFFC9CED4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // 横向网格线 + Y 轴刻度（0 格为 X 轴线，颜色更深）
    for (var s = 0; s <= steps; s++) {
      final v = s * yStep;
      final y = yOf(v);
      canvas.drawLine(Offset(_padLeft, y), Offset(size.width - _padRight, y),
          s == 0 ? axisPaint : gridPaint);
      final label =
          v == 0 ? '0' : UnitFormat.volume(v, compact: true);
      final p = tp(label);
      p.paint(canvas, Offset(_padLeft - 5 - p.width, y - p.height / 2));
    }
    // Y 轴竖线
    canvas.drawLine(
        Offset(_padLeft, _plotTop - 6), Offset(_padLeft, plotBottom), axisPaint);

    // 折线（负值按 0 处理，与柱状图红色负柱语义区分）
    Offset pointAt(int i) =>
        Offset(xOf(i), yOf(bars[i].value.clamp(0, topV).toDouble()));

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < n; i++) {
      path.lineTo(pointAt(i).dx, pointAt(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _kCyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 数据点 + 值标签 + X 轴标签
    for (var i = 0; i < n; i++) {
      final b = bars[i];
      final p = pointAt(i);
      canvas.drawCircle(
        p,
        b.highlighted ? 4.5 : 3.0,
        Paint()
          ..color = _kCyan
          ..style = PaintingStyle.fill,
      );
      if (b.highlighted) {
        canvas.drawCircle(
          p,
          4.5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
      final label = b.valueLabel;
      if (label != null) {
        final vtp = tp(
          label,
          color: b.value < 0
              ? const Color(0xFFE8446A)
              : b.highlighted
                  ? _kCyan
                  : _kHintGray,
          fontSize: 10,
          weight: FontWeight.w600,
        );
        // 值标签中心对齐数据点，左右与顶部均不出画布
        final dx = (p.dx - vtp.width / 2).clamp(0.0, size.width - vtp.width);
        final dy = (p.dy - 8 - vtp.height).clamp(0.0, size.height);
        vtp.paint(canvas, Offset(dx, dy));
      }
      // X 轴标签：数据点正下方，左右不出画布
      final xtp = tp(b.label,
          color: b.highlighted ? _kCyan : _kHintGray, fontSize: 10);
      final xdx = (p.dx - xtp.width / 2).clamp(0.0, size.width - xtp.width);
      xtp.paint(canvas, Offset(xdx, size.height - xtp.height));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.maxVal != maxVal ||
      old.bars.length != bars.length ||
      old.bars != bars;
}

/// 补上遗漏：滑动输入的刻度尺（游标固定居中，刻度随数值平移）
///
/// 每 25ml 一格刻度，每 100ml 一根长刻度并标注数值；
/// 数值增大时刻度整体左移，游标始终停在正中央。
class _VolumeRulerPainter extends CustomPainter {
  _VolumeRulerPainter({required this.value, required this.color})
      : super(repaint: value);

  /// 连续容量值：拖动时由 ValueNotifier 直接驱动重绘，不走 setState，
  /// 保证刻度以亚像素级平滑移动
  final ValueListenable<double> value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final current = value.value;
    final cx = size.width / 2;
    // 刻度统一以同一条中线上下对称：长/中/短三档只改长度，不改粗细
    const tickCenterY = 48.0;
    const majorHalf = 17.0;
    const midHalf = 15.0;
    const shortHalf = 9.0;
    final tickBottom = tickCenterY + majorHalf;
    // 画布左右各能容纳多少 ml
    final spanMl = cx / _kSlidePxPer100 * 100;
    final minVisible = current - spanMl;
    final maxVisible = current + spanMl;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    // 25ml 一格：0(=100) 最长、50 略短、25/75 约一半
    for (var v = (minVisible / 25).floorToDouble() * 25;
        v <= maxVisible;
        v += 25) {
      if (v < 0 || v > 2000) continue;
      final x = cx + (v - current) * _kSlidePxPer100 / 100;
      if (x < -4 || x > size.width + 4) continue;
      final rem = v % 100;
      final half = rem == 0
          ? majorHalf
          : rem == 50
              ? midHalf
              : shortHalf;
      canvas.drawLine(
        Offset(x, tickCenterY - half),
        Offset(x, tickCenterY + half),
        paint,
      );
    }

    // 每 100ml 标注数值（贴近边缘时按参考图自然裁切）
    for (var v = (minVisible / 100).floorToDouble() * 100;
        v <= maxVisible + 100;
        v += 100) {
      if (v < 0 || v > 2000) continue;
      final x = cx + (v - current) * _kSlidePxPer100 / 100;
      // 只画完整落在画布内的数值，避免边缘出现半截数字
      final tp = TextPainter(
        text: TextSpan(text: '${v.toInt()}', style: _kRulerLabelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final left = x - tp.width / 2;
      if (left < 0 || left + tp.width > size.width) continue;
      tp.paint(canvas, Offset(left, tickBottom + 22));
    }

    // 固定居中的游标：向下实心倒三角（与刻度线之间留出间距）
    final cursor = Path()
      ..moveTo(cx - 6, 0)
      ..lineTo(cx + 6, 0)
      ..lineTo(cx, 9)
      ..close();
    canvas.drawPath(cursor, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_VolumeRulerPainter old) => old.color != color;
}
