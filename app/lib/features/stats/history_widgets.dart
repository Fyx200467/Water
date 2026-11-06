part of 'history_screen.dart';

// ==================== 顶部大徽章 ====================

/// 青色进度环大徽章（Y 轴翻转卡）：
/// - 进场：仅本次启动 App 后第一次进入本页时绕 Y 轴自转 3 圈（减速缓动）
///   定格在「%/今天的饮水量」正面；之后再次进入不再自动转
/// - 点击：绕 Y 轴翻 180° 露出背面「N/天连续签到」，再点翻回正面
///   （连续翻面角度累加，方向始终一致）
class _TopBadge extends StatefulWidget {
  const _TopBadge({required this.percent, required this.streakDays});
  final double percent;
  final int streakDays;

  @override
  State<_TopBadge> createState() => _TopBadgeState();
}

/// 本次 App 会话内是否已播放过徽章进场自转（会话级只转一次）
bool _badgeAutoSpunThisSession = false;

class _TopBadgeState extends State<_TopBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  /// 当前 Y 轴旋转角（弧度，连续累加）；进场自转时从 3 整圈减速转到 0（正面）
  double _angle = 0;
  double _from = 0;
  double _to = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    _ctrl.addListener(() {
      setState(() {
        _angle = _from +
            (_to - _from) * Curves.easeOutCubic.transform(_ctrl.value);
      });
    });
    // 只在本次会话第一次进入时自动转几下；后续进入直接定格正面
    if (!_badgeAutoSpunThisSession) {
      _badgeAutoSpunThisSession = true;
      _from = _angle = 3 * 2 * math.pi;
      _to = 0;
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 点击翻面：角度累加半圈（动画中忽略点击，避免角度跳变）
  void _flip() {
    if (_ctrl.isAnimating) return;
    HapticFeedback.selectionClick();
    _from = _angle;
    _to = _angle + math.pi;
    _ctrl.duration = const Duration(milliseconds: 650);
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    // cos(θ) > 0 → 正面朝向观察者（今日饮水量），否则背面（连续签到）；
    // 背面文字额外绕 Y 转 180° 抵消镜像，保证可读
    final showFront = math.cos(_angle) >= 0;
    final value = showFront
        ? '${(widget.percent * 100).round()}%'
        : '${widget.streakDays}';
    final label = showFront ? '今天的饮水量' : '天连续签到';

    return GestureDetector(
      onTap: _flip,
      child: SizedBox(
        width: 140,
        height: 140,
        child: CustomPaint(
          // 静态进度环：始终固定不转，翻面的只有环内蓝色圆
          painter: _BadgePainter(widget.percent.clamp(0.0, 1.0)),
          child: Center(
            child: SizedBox(
              width: 112,
              height: 112,
              child: Transform(
                alignment: Alignment.center,
                // 透视投影：让翻转有近大远小的 3D 纵深感
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0016)
                  ..rotateY(_angle),
                child: Container(
                  decoration: const BoxDecoration(
                    color: _kCyan,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: showFront
                      ? _texts(value, label)
                      : Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..rotateY(math.pi),
                          child: _texts(value, label),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 圆内文字（正面/背面共用）
  Widget _texts(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ],
    );
  }
}

// ==================== 月历 ====================

/// 当月月历：
/// - 标题行（yyyy-MM 左对齐 + 日历小图标）+ 分隔线 + 周一起始表头
///   （对标竞品布局，无卡片背景）
/// - 有喝水记录的日期被达标度小进度环包围（蓝≥100%、橙≥70%、红<70%），
///   今天不做黑圆特殊渲染
/// - 右下角对勾小圆标仅出现在「喝过水」的日期：当天=绿色底，
///   已过日期=灰色底，未来/未喝水的日期不显示
/// - 点击任意日期 → onSelect 回调（驱动选中日期内容区动态切换）
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.data,
    required this.goalMl,
    required this.month,
    required this.today,
    required this.onSelect,
    this.onPrevMonth,
    this.onNextMonth,
  });
  final Map<int, DayTotal> data;

  /// 当日饮水目标（ml），用于计算进度环比例与颜色
  final int goalMl;

  /// 当前展示的月份（该月 1 日），列表点选其它月份日期时随之切换
  final DateTime month;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;

  /// 上/下一个月（null = 不可翻，例如已是当前月）
  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;

  /// 进度环颜色：蓝=达标 / 橙=≥70% / 红=<70%（统计结果说明口径）
  static const _kOrange = Color(0xFFF5A623);
  static const _kRed = Color(0xFFE5484D);

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    // 一周起始随「一周开始时间」设置（周日或周一）
    final leading = LogicalDay.leadingBlanksOf(first);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final rowCount = (leading + daysInMonth + 6) ~/ 7;

    // 内边距：让日历内容与屏幕边缘保持更远距离（叠加外层 22 边距）
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: Column(
      children: [
        // 标题行：yyyy-MM 左对齐加粗 + 右侧日历小图标（对标竞品）
        Row(
          children: [
            Text(
              '${month.year}-${month.month.toString().padLeft(2, '0')}',
              style: const TextStyle(
                color: _kTextDark,
                fontSize: 18,
                fontWeight: FontWeight.w400,
              ),
            ),
            const Spacer(),
            // 翻月箭头：左侧看更早月份，右侧回到更近月份（当前月禁用）
            _monthArrow(Icons.chevron_left, onPrevMonth),
            const SizedBox(width: 2),
            _monthArrow(Icons.chevron_right, onNextMonth),
            const SizedBox(width: 8),
            // 用户自绘日历图标（assets/icons/menu/calendar_header.svg）
            SvgPicture.asset(
              'assets/icons/menu/calendar_header.svg',
              width: 22,
              height: 22,
            ),
          ],
        ),
        const SizedBox(height: 14),
        // 表头：随「一周开始时间」轮转（周日或周一起始，灰蓝色）
        Row(
          children: [
            for (final w in LogicalDay.weekHeaderLabels)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: const TextStyle(
                      color: Color(0xFF8A97A8),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var row = 0; row < rowCount; row++)
          SizedBox(
            height: 54,
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(child: _cell(row * 7 + col - leading + 1, daysInMonth)),
              ],
            ),
          ),
      ],
      ),
    );
  }

  /// 翻月箭头（禁用态变浅灰）
  Widget _monthArrow(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onTap();
            }
          : null,
      child: SizedBox(
        width: 26,
        height: 26,
        child: Icon(
          icon,
          size: 20,
          color: enabled ? _kTextDark : const Color(0xFFC7CDD4),
        ),
      ),
    );
  }

  Widget _cell(int day, int daysInMonth) {
    if (day < 1 || day > daysInMonth) return const SizedBox.shrink();

    final cellDate = DateTime(month.year, month.month, day);
    final isFuture = cellDate.isAfter(today);
    final isToday = cellDate.year == today.year &&
        cellDate.month == today.month &&
        cellDate.day == today.day;
    // monthDataProvider 以月内 0 基索引为 key
    final dt = data[day - 1];
    // 有饮水条目即点亮（不看正负）：净量为负的日子（负容量记录）同样算有记录
    final hasRecord = dt != null && dt.count > 0;

    // 有喝水记录的日期（含今天）→ 进度环包围（替代原日期下方圆点）：
    // 环比例 = 当日净量 / 目标，环色按达标度（蓝/橙/红）
    final showRing = !isFuture && hasRecord;
    final ratio = goalMl > 0 && dt != null
        ? (dt.effectiveMl / goalMl).clamp(0.0, 1.0)
        : 0.0;
    final ringColor = ratio >= 1.0
        ? _kCyan
        : ratio >= 0.7
            ? _kOrange
            : _kRed;

    // 所有日期统一普通字重（选中不做任何视觉特殊化）
    final TextStyle numberStyle = TextStyle(
      color: isFuture ? _kFutureGray : _kTextDark,
      fontSize: 14,
      fontWeight: FontWeight.w400,
    );

    final Widget number = Text('$day', style: numberStyle);

    // 右下角对勾小圆标（对标竞品）：仅「喝过水」的日期显示——
    // 当天=绿色底，已过日期=灰色底；未来日期与未喝水的日期不显示
    final Widget cellContent = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (showRing)
          SizedBox(
            width: 30,
            height: 30,
            child: CustomPaint(
              painter: _DayRingPainter(ratio, ringColor),
              child: Center(child: number),
            ),
          )
        else
          number,
        if (!isFuture && hasRecord)
          Positioned(
            right: -3,
            bottom: -2,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isToday
                    ? const Color(0xFF17C3A3)
                    : const Color(0xFFC7CDD4),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 9,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 未来日期不可点击（还没到的日期无法选中/补录）
      onTap: isFuture ? null : () => onSelect(cellDate),
      child: SizedBox(
        height: 54,
        child: Center(child: cellContent),
      ),
    );
  }
}

// ==================== 筛选弹层 ====================

/// 饮品筛选弹层：白底圆角顶部 + 右上 X + 浅灰圆角行（饮品图标与首页/管理页一致）
class _FilterSheet extends StatelessWidget {
  const _FilterSheet({
    required this.current,
    required this.entries,
    required this.pool,
    required this.onSelect,
  });

  final String current;
  final List<DrinkEntry> entries;

  /// 首页/管理页同款饮品池（预设 + 自定义）
  final List<Beverage> pool;
  final ValueChanged<String> onSelect;

  /// (筛选 token, 展示名, 饮品对象[池内命中], 回退图标[仅条目但饮品已删除])
  ///
  /// token 用 `id:<beverageId>` 定位饮品，饮品改名后历史记录仍能连续筛选；
  /// 已删除的饮品只能用 `name:<name>` 匹配它留下的历史记录。
  List<(String, String, Beverage?, IconData?, Color?)> _options() {
    final out = <(String, String, Beverage?, IconData?, Color?)>[];
    void add(String token, String label,
        [Beverage? b, IconData? icon, Color? color]) {
      if (!out.any((o) => o.$1 == token)) out.add((token, label, b, icon, color));
    }

    add('全部', '全部');
    for (final b in pool) {
      add('id:${b.id}', b.name, b);
    }
    // 仅出现在历史记录中、但饮品已被删除的条目：回退分类图标
    for (final e in entries) {
      if (!pool.any((b) => b.id == e.beverageId)) {
        add('name:${e.beverageName}', e.beverageName, null,
            e.beverageCategory.icon, e.beverageCategory.color);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final opts = _options();

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // 右上角 X
            Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE9E9EB),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close,
                      color: Color(0xFF8E8E93), size: 20),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: opts.length,
                itemBuilder: (ctx, i) {
                  final o = opts[i];
                  final isAll = o.$1 == '全部';
                  final selected = current == o.$1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          onSelect(o.$1);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              // 饮品图标（与管理页/首页一致）；「全部」= 分层饮品色水滴
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: Center(
                                  child: isAll
                                      ? const CustomPaint(
                                          size: Size(28, 28),
                                          painter: _WaterDropPainter(),
                                        )
                                      : o.$3 != null
                                          ? _beverageIcon(o.$3!, 28)
                                          : Icon(o.$4,
                                              size: 24, color: o.$5),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  o.$2,
                                  style: const TextStyle(
                                    color: Color(0xFF1C1C1E),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              // 选中：青色实心圆 ✓
                              if (selected)
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: const BoxDecoration(
                                    color: _kCyan,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check,
                                      size: 14, color: Colors.white),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 通用小组件 ====================

/// 功能胶囊按钮（浅青背景）
class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE0F4F8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: const Color(0xFF6B6B70)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B6B70),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 滑动容量选择：游标固定居中、刻度尺随手指平移，松手后按速度惯性滑行
class _BackfillSlideArea extends StatefulWidget {
  const _BackfillSlideArea({required this.volume, required this.onChanged});

  final int volume;
  final ValueChanged<int> onChanged;

  @override
  State<_BackfillSlideArea> createState() => _BackfillSlideAreaState();
}

class _BackfillSlideAreaState extends State<_BackfillSlideArea>
    with SingleTickerProviderStateMixin {
  static const int _minV = 10;
  static const int _maxV = 2000;

  late final AnimationController _fling =
      AnimationController.unbounded(vsync: this);
  // 拖动过程中的连续值（避免依赖父级重建后的整数值）
  double _dragValue = 0;
  // 刻度尺的连续数值源：直接驱动 CustomPainter 重绘，不触发整棵子树重建
  late final ValueNotifier<double> _value =
      ValueNotifier<double>(_clamp(widget.volume));
  // 最近一次同步给父级的数值（父级按 10ml 量化，只有跨档时才通知）
  late int _lastSent = widget.volume;

  static double _clamp(num v) => v.clamp(_minV, _maxV).toDouble();

  @override
  void initState() {
    super.initState();
    _fling.addListener(_onFlingTick);
  }

  @override
  void didUpdateWidget(_BackfillSlideArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父级数值被外部改动（切换饮品、点外部按钮）时同步刻度
    if (widget.volume != oldWidget.volume && widget.volume != _lastSent) {
      _lastSent = widget.volume;
      if (!_fling.isAnimating) {
        _dragValue = _clamp(widget.volume);
        _value.value = _dragValue;
      }
    }
  }

  @override
  void dispose() {
    _value.dispose();
    _fling.dispose();
    super.dispose();
  }

  /// 连续值负责刻度平滑移动；父级只在跨过 10ml 时收到一次通知，
  /// 避免每个拖动事件都重建整个弹窗
  void _emit(double v) {
    final clamped = _clamp(v);
    _value.value = clamped;
    final quantized = (clamped / 10).round() * 10;
    if (quantized == _lastSent) return;
    _lastSent = quantized;
    widget.onChanged(quantized);
  }

  void _onFlingTick() {
    if (!mounted) return;
    _emit(_fling.value);
  }

  void _onDragStart(DragStartDetails _) {
    _fling.stop();
    _dragValue = _clamp(widget.volume);
    _value.value = _dragValue;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // 手指左滑 → 数值增大（刻度尺向左移动），每 1px ≈ 1.6ml
    _dragValue = _clamp(_dragValue - d.delta.dx * 100 / _kSlidePxPer100);
    _emit(_dragValue);
  }

  void _onDragEnd(DragEndDetails d) {
    final vPx = d.velocity.pixelsPerSecond.dx;
    if (vPx.abs() < 80) return;
    // 像素速度换算成 ml/s（左滑为负 → 容量增大）
    final vMl = -vPx * 100 / _kSlidePxPer100;
    // 惯性滑行距离 = 速度 / 衰减系数，再按速度决定时长
    final target = (_dragValue + vMl / 3.5).clamp(_minV.toDouble(), _maxV.toDouble());
    final dist = (target - _dragValue).abs();
    if (dist < 10) return;
    final ms = (dist / vMl.abs() * 2200).clamp(220.0, 900.0);
    _fling.stop();
    _fling.value = _dragValue;
    _fling.animateTo(
      target,
      duration: Duration(milliseconds: ms.round()),
      curve: Curves.easeOutCubic,
    );
  }

  /// 加减按钮：本地立即更新刻度，再同步父级
  void _step(int delta) {
    _fling.stop();
    _dragValue = _clamp(widget.volume + delta);
    _emit(_dragValue);
  }

  Widget _stepButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFF6C7885), width: 1.2),
        ),
        child: Icon(icon, size: 11, color: const Color(0xFF4E5A66)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clamped = widget.volume.clamp(_minV, _maxV);

    return Center(
      child: Padding(
        // 让整组（数值 + 刻度尺）在卡片内视觉居中
        padding: const EdgeInsets.only(bottom: 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // − 值 + ：按钮固定在数值两侧（不随数字位数左右跳动）
          LayoutBuilder(
            builder: (_, cons) => SizedBox(
              width: cons.maxWidth,
              height: 28,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$clamped',
                        style: const TextStyle(
                          color: _kTextDark,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        ' ml',
                        style: TextStyle(
                          color: _kHintGray,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Transform.translate(
                    offset: const Offset(-62, 0),
                    child: _stepButton(
                      icon: Icons.remove,
                      onTap: () => _step(-10),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(62, 0),
                    child: _stepButton(
                      icon: Icons.add,
                      onTap: () => _step(10),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (_, cons) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: ClipRect(
                child: CustomPaint(
                  size: Size(cons.maxWidth, 104),
                  painter: _VolumeRulerPainter(value: _value, color: _kCyan),
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
