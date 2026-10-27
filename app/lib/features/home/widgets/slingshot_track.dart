import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sound/sound_service.dart';
import '../../../shared/models/beverage.dart';
import '../../../shared/models/drink_entry.dart';
import '../../../shared/models/preferred_unit.dart';
import '../../drink/providers/custom_beverage_provider.dart';
import '../../drink/screens/add_drink_screen.dart';
import '../../drink/widgets/svg_container.dart';
import '../providers/home_providers.dart';

/// 首页「趣味玩法」弧形饮品轨道
///
/// 布局模型（与旧版彻底不同）：
/// - 只渲染以当前居中饮品为中心、左右各 2 个（共 5 槽），相邻槽位
///   横向间距 = 屏宽 * 0.235，因此在 12 个饮品时也不会挤成一团
/// - 每个槽位的圆心严格落在椭圆弧 y = bottom - arcH*sin(πt) 上
/// - 居中槽位放大到 1.5x 并上浮容量气泡；两侧按距离缩小、降低不透明度
/// - 左右滑动带惯性，松手后吸附到最近槽位，居中饮品唯一高亮
/// - 居中饮品下拉弹弓、松手后水滴走全局 Overlay 沿抛物线飞向角色
class SlingshotDrinkTrack extends ConsumerStatefulWidget {
  const SlingshotDrinkTrack({
    super.key,
    required this.targetKey,
    this.height = 200,
  });

  final GlobalKey targetKey;
  final double height;

  @override
  ConsumerState<SlingshotDrinkTrack> createState() =>
      _SlingshotDrinkTrackState();
}

class _SlingshotDrinkTrackState extends ConsumerState<SlingshotDrinkTrack>
    with TickerProviderStateMixin {
  /// 相邻饮品横向间距占屏宽比例（约 0.3 屏宽，比原先更疏）
  static const _spacing = 0.30;

  /// 渲染范围：中心左右各 2.2 个槽位
  static const _span = 2.4;

  /// 白色圆底直径
  static const _circleD = 64.0;

  late List<_TrackDrink> _drinks;

  /// 当前居中位置（饮品索引空间，可为浮点）
  double _pos = 0;
  Timer? _flingTimer;

  late final AnimationController _snapAnim;
  double _snapFrom = 0;
  double _snapTo = 0;

  /// 下拉位移（直接跟随手指）
  double _pull = 0;

  /// 按下点是否落在居中饮品上（只有它能被下拉）
  bool _pullAvailable = false;
  bool _pulling = false;

  /// 下拉超过该距离松手才发射（过小会与页面竖滑误触串味）
  static const double _pullThreshold = 32;

  /// 发射 / 水花动画令牌：新动画取消旧动画时，旧回调不得误清新状态
  int _flightToken = 0;
  int _splashToken = 0;

  /// 用户手动改过的容量（按饮品 id 记住；改过才覆盖默认档）
  final Map<String, int> _pickedMl = {};

  /// 当前居中饮品的容量：默认取该饮品容量档的中间档
  ///（3 档 → 第二档；水 5 档 → 中间档），用户改过则用改过的值
  int get _currentMl {
    final drink = _drinks[_centerIndex];
    final picked = _pickedMl[drink.id];
    if (picked != null) return picked;
    final vols = [...drink.beverage.volumes]..sort();
    return vols.isEmpty ? drink.defaultMl : vols[(vols.length - 1) ~/ 2];
  }

  /// 本次实际增加的有效水分（啤酒、咖啡等按分类系数折算）
  int get _effMl => _drinks[_centerIndex].beverage.effectiveMl(_currentMl);

  /// 带符号容量文案：正数 '+xxxml'、负数自身带 '-xxxml'（正负号只出现一次）
  static String _signedMl(int ml) =>
      ml >= 0 ? '+${UnitFormat.volume(ml, compact: true)}' : UnitFormat.volume(ml, compact: true);

  /// 水滴飞行
  late final AnimationController _dropAnim;
  _Flight? _flight;
  OverlayEntry? _flightEntry;

  /// 命中水花
  late final AnimationController _splashAnim;
  Offset? _splashAt;
  OverlayEntry? _splashEntry;

  double get _screenW => MediaQuery.of(context).size.width;
  double get _baseY => widget.height - 30;

  /// 弧高：曲度平缓（参考设计中弧线只轻微起伏）
  double get _arcH => widget.height * 0.26;

  @override
  void initState() {
    super.initState();
    _drinks = _buildDrinkList();
    // 管理页的开关 / 排序 / 自定义饮品变化时才重建列表；
    // 此前在 build 里每帧重算（拖动时 60fps 白跑一遍）属于纯浪费
    ref.listenManual(homeDrinksProvider, (_, __) {
      if (mounted) setState(_syncDrinks);
    });
    ref.listenManual(customBeveragesProvider, (_, __) {
      if (mounted) setState(_syncDrinks);
    });
    _snapAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        final v = _snapAnim.value;
        final e = 1 - math.pow(1 - v, 3).toDouble();
        setState(() => _pos = _snapFrom + (_snapTo - _snapFrom) * e);
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) setState(() => _settled = true);
      });
    _dropAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    _splashAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
  }

  /// 与饮品管理页的开关/排序同步：id 序列一变就重建列表并收敛居中位置
  void _syncDrinks() {
    final next = _buildDrinkList();
    if (next.length == _drinks.length) {
      var same = true;
      for (var i = 0; i < next.length; i++) {
        if (next[i].id != _drinks[i].id) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    _drinks = next;
    _pos = _pos.clamp(0.0, (next.length - 1).toDouble());
  }

  @override
  void dispose() {
    _flingTimer?.cancel();
    _routeAnim?.removeListener(_onRouteCovered);
    _snapAnim.dispose();
    _dropAnim.dispose();
    _splashAnim.dispose();
    _flightEntry?.remove();
    _splashEntry?.remove();
    super.dispose();
  }

  List<_TrackDrink> _buildDrinkList() {
    final customs = ref.read(customBeveragesProvider);
    final homeDrinks = ref.read(homeDrinksProvider);
    final pool = [
      ...Beverage.presets.where((b) => b.id != 'water_pure'),
      ...customs,
    ];
    final byId = {for (final b in pool) b.id: b};
    final ordered = orderedVisibleIds(homeDrinks, pool);
    final water = Beverage.presets.firstWhere((e) => e.id == 'water_pure');
    final list = <_TrackDrink>[
      _TrackDrink(
        id: water.id,
        name: '白水',
        beverage: water,
        containerId: _resolveContainer(water),
      ),
      for (final id in ordered)
        if (id != water.id && byId[id] != null)
          _TrackDrink(
            id: id,
            name: byId[id]!.name,
            beverage: byId[id]!,
            containerId: _resolveContainer(byId[id]!),
          ),
    ];
    // 只放行的饮品才上图（与管理页开关一一对应，不做任何补齐）
    return list;
  }

  /// 轨道上永远要有可见的容器图：containerId 为空的自定义饮品
  /// 依次回退到模板预设、同分类预设，避免出现「透明槽位」却仍能发射
  String _resolveContainer(Beverage b) {
    if (b.containerId != null && b.containerId!.isNotEmpty) {
      return b.containerId!;
    }
    for (final p in Beverage.presets) {
      if (p.id == b.templateId && p.containerId != null) {
        return p.containerId!;
      }
    }
    for (final p in Beverage.presets) {
      if (p.category == b.category && p.containerId != null) {
        return p.containerId!;
      }
    }
    return Beverage.presets.first.containerId!;
  }

  // ==================== 几何 ====================

  /// 饮品 i 相对居中位置的带符号索引差（循环取最近）
  double _delta(int i) {
    final n = _drinks.length;
    var d = (i - _pos) % n;
    if (d > n / 2) d -= n;
    if (d < -n / 2) d += n;
    return d;
  }

  /// 槽位横坐标（弧线参数 t，可越界到屏幕外）
  double _tOf(double d) => 0.5 + d * _spacing;

  /// 弧上纵坐标：标准圆弧（两端落在 baseY，顶点为 baseY - arcH）
  double _yOf(double t) {
    final tc = t.clamp(0.0, 1.0);
    final r = _arcRadius;
    final dx = (tc - 0.5) * _screenW;
    final cy = _baseY - _arcH + r;
    return cy - math.sqrt(math.max(0.0, r * r - dx * dx));
  }

  /// 圆弧半径：由半弦长 W/2 与矢高 arcH 反推
  double get _arcRadius {
    final half = _screenW / 2;
    return (half * half + _arcH * _arcH) / (2 * _arcH);
  }

  /// 是否处于滑动/吸附过程中（此时隐藏容量胶囊）
  bool _settled = true;

  /// 居中饮品索引
  int get _centerIndex {
    final n = _drinks.length;
    return ((_pos.round() % n) + n) % n;
  }

  /// 居中杯的真实弧线参数：正常吸附后恰为 0.5，若停在半格也能跟随实际位置
  double get _centerT => _tOf(_delta(_centerIndex));

  /// 居中杯真实横坐标（容量标签、下拉提示、喷射起点都以它为准，
  /// 避免与固定在 w/2 的文字错位）
  double get _centerX => _screenW * _centerT;

  /// 缩放：居中仅轻微放大，两侧依次缩小
  double _scaleOf(double ad) {
    final s = 1.12 - 0.24 * ad;
    return s.clamp(0.70, 1.12);
  }

  double _opacityOf(double ad) => (1.0 - 0.26 * ad).clamp(0.40, 1.0);

  // ==================== 拖拽（横滑选饮品 / 下拉发射） ====================

  /// 0 未判定、1 横滑、2 竖向
  int _mode = 0;
  int? _pointer;
  double _downX = 0;
  double _downY = 0;
  double _startPos = 0;
  double _lastX = 0;
  double _lastTime = 0;
  double _velocityX = 0;

  void _onPointerDown(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _downX = e.localPosition.dx;
    _downY = e.localPosition.dy;
    _startPos = _pos;
    _lastX = _downX;
    _lastTime = e.timeStamp.inMicroseconds / 1e6;
    _velocityX = 0;
    _mode = 0;
    _pulling = false;
    _pull = 0;
    // 只有按在居中饮品附近才允许下拉发射；上一发还在飞时不允许再拉
    final c = Offset(_centerX, _yOf(_centerT));
    _pullAvailable = !_dropAnim.isAnimating &&
        (_downX - c.dx).abs() <= 66 &&
        (_downY - c.dy).abs() <= 78;
    _flingTimer?.cancel();
    _snapAnim.stop();
    if (!_settled) setState(() => _settled = true);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final dx = e.localPosition.dx - _downX;
    final dy = e.localPosition.dy - _downY;
    if (_mode == 0) {
      if (dx.abs() < 4 && dy.abs() < 4) return;
      // 主方向判定：横向优先
      if (dx.abs() >= dy.abs()) {
        _mode = 1;
      } else {
        _mode = 2;
        if (!_pullAvailable) return;
        HapticFeedback.selectionClick();
        _pulling = true;
      }
    }
    if (_mode == 2) {
      if (!_pulling) return;
      // 直接跟随手指：Listener 坐标固定，不会随饮品下移而漂移
      final next = dy.clamp(0.0, 120.0);
      if ((next - _pull).abs() >= 0.01) setState(() => _pull = next);
      return;
    }

    // 少于 2 个饮品时没有可切换的对家，横滑只会让同一颗绕圈重复
    //（只剩水时表现为左右乱窜），直接禁用；2 个饮品仍可来回切换
    if (_drinks.length < 2) return;

    final now = e.timeStamp.inMicroseconds / 1e6;
    if (now - _lastTime > 0.0005) {
      _velocityX = (e.localPosition.dx - _lastX) / (now - _lastTime);
      _lastTime = now;
      _lastX = e.localPosition.dx;
    }
    final unitPx = _screenW * _spacing;
    setState(() {
      _pos = _startPos - dx / unitPx;
      _settled = false;
    });
  }

  void _onPointerUp(PointerEvent e) {
    if (e.pointer != _pointer) return;
    final horizontal = _mode == 1;
    final pulled = _pulling;
    final drag = _pull;
    final vx = _velocityX;
    _pointer = null;
    _mode = 0;
    _pulling = false;
    if (_pull > 0) setState(() => _pull = 0);

    // 下拉松手：超过阈值才发射（容量已有默认档，无需先手动选择）
    if (pulled) {
      if (drag >= _pullThreshold) _fire(drag);
      // 发射 / 轻拉到一半松手都要回正：否则轨道会停在半格，
      // 居中杯偏离屏幕中心、容量标签与杯身错位
      _snapToNearest(_pos);
      return;
    }
    if (!horizontal || _drinks.length < 2) {
      // 点按（改容量）与轻触也要回正，避免吸附动画被按下打断后停在半格
      _snapToNearest(_pos);
      return;
    }

    final unitPx = _screenW * _spacing;
    var v = -vx / unitPx; // 槽位/秒
    var pos = _pos;
    if (v.abs() > 0.25) {
      _flingTimer?.cancel();
      _flingTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        v *= 0.93;
        pos += v * 0.016;
        if (v.abs() < 0.18) {
          timer.cancel();
          _snapToNearest(pos);
          return;
        }
        setState(() => _pos = pos);
      });
    } else {
      _snapToNearest(pos);
    }
  }

  /// 指针被系统取消（来电、系统手势抢占等）：只回弹吸附，绝不发射
  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _mode = 0;
    _pulling = false;
    if (_pull > 0) setState(() => _pull = 0);
    _snapToNearest(_pos);
  }

  void _snapToNearest(double from) {
    final target = from.roundToDouble();
    if ((from - target).abs() < 0.005) {
      setState(() {
        _pos = target;
        _settled = true;
      });
      return;
    }
    _snapFrom = from;
    _snapTo = target;
    _settled = false;
    _snapAnim.forward(from: 0);
  }

  /// 选容量：直接复用标准加量页（pickOnly 模式只返回容量，不记账）
  Future<void> _pickCapacity() async {
    final drink = _drinks[_centerIndex];
    final ml = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => AddDrinkScreen(
          beverageId: drink.id,
          pickOnly: true,
        ),
      ),
    );
    if (ml != null && mounted) setState(() => _pickedMl[drink.id] = ml);
  }

  // ==================== 发射 ====================

  void _fire(double pullDepth) {
    // 上一发还在飞：忽略本次发射。否则重新 forward 会取消上一发的 Ticker，
    // 旧完成回调会误删新飞行并提前入账，造成重复/漏记
    if (_dropAnim.isAnimating) return;
    final ml = _currentMl;
    final drink = _drinks[_centerIndex];
    final selfBox = context.findRenderObject() as RenderBox?;
    final targetBox =
        widget.targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (selfBox == null) return;

    final start = selfBox.localToGlobal(
      Offset(_centerX, _yOf(_centerT) + pullDepth),
    );
    // 角色卡片暂时不可用时回退到屏幕中上方：仍然完成飞行和记账，
    // 不再静默失败让用户以为已经打出去了
    final end = targetBox != null
        ? targetBox.localToGlobal(targetBox.size.center(Offset.zero))
        : Offset(_screenW / 2, MediaQuery.of(context).size.height * 0.36);

    const gravity = 2400.0;
    final dur = _dropAnim.duration!.inMilliseconds / 1000.0;
    final vx = (end.dx - start.dx) / dur;
    final vy = (end.dy - start.dy) / dur - 0.5 * gravity * dur;

    _flight = _Flight(
      drink: drink,
      ml: ml,
      effectiveMl: drink.beverage.effectiveMl(ml),
      start: start,
      vx: vx,
      vy: vy,
      gravity: gravity,
      duration: dur,
    );

    _flightEntry?.remove();
    _flightEntry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _dropAnim,
          builder: (_, __) {
            final f = _flight;
            if (f == null) return const SizedBox.shrink();
            final p = f.position(_dropAnim.value);
            return Stack(
              children: [
                for (var i = 6; i >= 1; i--)
                  Positioned(
                    left: p.dx - 8 + (p.dx - f.position(_dropAnim.value - i * 0.02).dx) * -1,
                    top: p.dy - 8 + (p.dy - f.position(_dropAnim.value - i * 0.02).dy) * -1,
                    child: Opacity(
                      opacity: (0.30 - i * 0.04).clamp(0.04, 0.30),
                      child: Container(
                        width: 16 - i.toDouble(),
                        height: 16 - i.toDouble(),
                        decoration: BoxDecoration(
                          color: f.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: p.dx - 15,
                  top: p.dy - 15,
                  child: _DropBody(color: f.color),
                ),
              ],
            );
          },
        ),
      ),
    );
    Overlay.of(context).insert(_flightEntry!);

    final token = ++_flightToken;
    _dropAnim.forward(from: 0).then((_) {
      if (!mounted || token != _flightToken) return;
      _flightEntry?.remove();
      _flightEntry = null;
      final f = _flight;
      _flight = null;
      if (f == null) return;
      _onHit(f);
    }, onError: (_) {
      // 被新的发射取消：旧飞行的收尾交给新飞行处理，这里不做任何清理
    });
  }

  Future<void> _onHit(_Flight f) async {
    HapticFeedback.mediumImpact();
    // 命中音效（设置页「App 声音」总开关控制）
    SoundService.dropHit();
    // 飘字展示「有效水分」（如啤酒 330ml × 0.65 ≈ 215ml），与首页进度口径一致
    _showSplash(f.end, f.color, f.effectiveMl);
    await _recordEntry(f);
  }

  /// 记账：折算算法与标准加量页完全一致（DrinkEntry.create → beverage.effectiveMl）
  Future<void> _recordEntry(_Flight f) async {
    final entry = DrinkEntry.create(
      beverage: f.drink.beverage,
      volumeMl: f.ml,
    );
    try {
      await ref.read(todayEntriesProvider.notifier).add(entry);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('记录失败，请稍后重试')),
      );
    }
  }

  /// 命中点水花：8 颗小水滴向外扩散淡出 + 「+xml」飘字
  void _showSplash(Offset at, Color color, int ml) {
    _splashAt = at;
    _splashEntry?.remove();
    final token = ++_splashToken;
    _splashEntry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _splashAnim,
          builder: (_, __) {
            final center = _splashAt;
            if (center == null) return const SizedBox.shrink();
            final t = _splashAnim.value;
            final r = 6 + 42 * t;
            final op = (1 - t).clamp(0.0, 1.0);
            // 浅色饮品（白粥等）直接上液色几乎看不见，压暗一档保证可读
            final labelColor = color.computeLuminance() > 0.72
                ? Color.lerp(color, Colors.black, 0.45)!
                : color;
            return Stack(
              children: [
                for (var i = 0; i < 8; i++)
                  Positioned(
                    left: center.dx - 5 + math.cos(i * math.pi / 4) * r,
                    top: center.dy - 5 + math.sin(i * math.pi / 4) * r * 0.7,
                    child: Opacity(
                      opacity: op,
                      child: Container(
                        width: 10 - 4 * t,
                        height: 10 - 4 * t,
                        decoration: BoxDecoration(
                          // 水花跟随饮品液色，而不是固定青色
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                // 命中数值飘字：向上浮起并淡出
                Positioned(
                  left: center.dx - 60,
                  top: center.dy - 34 - 26 * t,
                  width: 120,
                  child: Opacity(
                    opacity: (1 - t * 1.3).clamp(0.0, 1.0),
                    child: Center(
                      child: Text(
                        _signedMl(ml),
                        style: TextStyle(
                          color: labelColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          // Overlay 里的 Text 不在 Material 下，会继承
                          // WidgetsApp 兜底的黄色双下划线，显式去掉
                          decoration: TextDecoration.none,
                          shadows: const [
                            Shadow(color: Colors.white, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    Overlay.of(context).insert(_splashEntry!);
    _splashAnim.forward(from: 0).then((_) {
      if (token != _splashToken) return;
      _splashEntry?.remove();
      _splashEntry = null;
      _splashAt = null;
    }, onError: (_) {
      // 被下一次命中取消：由新的水花接管
    });
  }

  // ==================== 页面被盖住时的收尾 ====================

  Animation<double>? _routeAnim;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 首页路由被新页面（如菜单页）盖住时，飞行的水滴/水花必须立刻撤销：
    // 它们插在根 Overlay 上，不撤销就会浮在新页面上；而且非当前路由的
    // Ticker 会被静音，_dropAnim 永远停在 animating → 再也发射不出去（卡死）
    final anim = ModalRoute.of(context)?.secondaryAnimation;
    if (anim != _routeAnim) {
      _routeAnim?.removeListener(_onRouteCovered);
      _routeAnim = anim;
      _routeAnim?.addListener(_onRouteCovered);
    }
  }

  void _onRouteCovered() {
    if ((_routeAnim?.value ?? 0) > 0) _abortFlight();
  }

  /// 撤销在途飞行 / 水花（不动用户数据：已打出去的那一发照常记账）
  void _abortFlight() {
    final pending = _flight;
    final flying = pending != null || _dropAnim.isAnimating;
    // 令牌自增：旧的 forward 回调（若已排队）直接失效，避免重复记账
    _flightToken++;
    _splashToken++;
    _flightEntry?.remove();
    _flightEntry = null;
    _splashEntry?.remove();
    _splashEntry = null;
    _flight = null;
    _splashAt = null;
    if (_dropAnim.isAnimating) _dropAnim.stop();
    if (_splashAnim.isAnimating) _splashAnim.stop();
    if (flying && pending != null) _recordEntry(pending);
  }

  // ==================== 构建 ====================

  @override
  Widget build(BuildContext context) {
    final w = _screenW;
    final n = _drinks.length;
    final centerIdx = _centerIndex;

    // 渲染顺序：远的先画、近的后画（居中在最上层）
    final entries = <(_TrackDrink, int, double)>[];
    for (var i = 0; i < n; i++) {
      final d = _delta(i);
      if (d.abs() > _span) continue;
      entries.add((_drinks[i], i, d));
    }
    // 远的先画、居中的最后画（压在最上层）；|delta| 相同时按索引定序，
    // 避免排序结果每帧抖动导致叠压关系闪跳
    entries.sort((a, b) {
      final c = b.$3.abs().compareTo(a.$3.abs());
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });

    return SizedBox(
      width: w,
      height: widget.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 轨道弧线
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ArcPainter(
                  width: w,
                  baseY: _baseY,
                  arcH: _arcH,
                ),
              ),
            ),
          ),
          // 横滑手势层 + 饮品（原始指针事件，避免与子级手势冲突）
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final e in entries)
                    _buildItem(e.$1, e.$2, e.$3, centerIdx),
                ],
              ),
            ),
          ),
          // 容量胶囊：只固定显示在居中饮品上方（滑动/吸附/下拉过程中隐藏，
          // 否则会与「松手发射」提示上下叠成两行）
          if (_settled && !_pulling)
            Positioned(
              left: _centerX - 44,
              top: _yOf(_centerT) - 68,
              width: 88,
              child: IgnorePointer(
                child: Center(
                  // 无底色胶囊，文字跟随饮品色
                  child: Text(
                    // 胶囊展示当前选中饮品的原始容量，不带正负号
                    UnitFormat.volume(_currentMl, compact: true),
                    style: TextStyle(
                      color: _drinks[centerIdx].liquidColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          // 下拉进度提示：超过阈值后明确「松手发射」，避免误触后不知会记账
          if (_pulling && _pull >= _pullThreshold)
            Positioned(
              left: _centerX - 70,
              top: _yOf(_centerT) + _pull - 62,
              width: 140,
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    '松手发射 ${_signedMl(_effMl)}',
                    style: TextStyle(
                      color: _drinks[centerIdx].liquidColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          // 只剩白水时的空态提示（不拦截手势）
          if (n == 1)
            const Positioned(
              left: 0,
              right: 0,
              top: 2,
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    '仅显示白水 · 可在饮品管理中开启更多饮品',
                    style: TextStyle(color: Color(0xFFB4BAC4), fontSize: 11),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItem(
    _TrackDrink drink,
    int index,
    double delta,
    int centerIdx,
  ) {
    final ad = delta.abs();
    final isCenter = index == centerIdx;
    final t = _tOf(delta);
    final x = _screenW * t;
    final y = _yOf(t) + (isCenter ? _pull : 0);

    final scale = _scaleOf(ad);
    final opacity = _opacityOf(ad);
    final liquid = drink.liquidColor;

    // 盒中心 = 圆心；盒高留出上气泡与下名称的空间
    const bw = 132.0;
    const bh = widgetHeight;

    return Positioned(
      // 必须按饮品 id 固定 key：绘制顺序随 |delta| 排序会变，无 key 时
      // 同位置元素会复用到另一饮品，SvgContainerIcon 反复重载 → 滑动抽搐
      key: ValueKey('slot_${drink.id}'),
      left: x - bw / 2,
      top: y - bh / 2,
      width: bw,
      height: bh,
      child: Opacity(
        opacity: opacity,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (isCenter) {
              HapticFeedback.selectionClick();
              // 已选容量保留，可连续发射；点按只是为了改容量
              _pickCapacity();
            } else {
              _snapToNearest(_pos + delta);
            }
          },
          // 占位竖向手势：夺取竞技场，避免下拉时页面跟着滚动
          //（真正的位移由上层 Listener 用固定坐标跟随手指计算）
          onVerticalDragStart: isCenter ? (_) {} : null,
          onVerticalDragUpdate: isCenter ? (_) {} : null,
          onVerticalDragEnd: isCenter ? (_) {} : null,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // 饮品插画（无白色圆底）
                SizedBox(
                  width: _circleD,
                  height: _circleD,
                  child: SvgContainerIcon(
                    containerId: drink.containerId,
                    color: liquid,
                    fillRatio: 0.92,
                  ),
                ),
                // 名称只在被选中的饮品下方显示
                if (isCenter)
                  Positioned(
                    top: bh / 2 + 38,
                    child: Text(
                      drink.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: liquid,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const widgetHeight = 176.0;
}

// ==================== 数据模型 ====================

class _TrackDrink {
  const _TrackDrink({
    required this.id,
    required this.name,
    required this.beverage,
    required this.containerId,
  });

  final String id;
  final String name;
  final Beverage beverage;

  /// 轨道上实际渲染的容器图（已解析回退，保证非空）
  final String containerId;

  Color get liquidColor => beverage.liquidColor ?? beverage.category.color;
  int get defaultMl => beverage.defaultMl;
}

class _Flight {
  _Flight({
    required this.drink,
    required this.ml,
    required this.effectiveMl,
    required this.start,
    required this.vx,
    required this.vy,
    required this.gravity,
    required this.duration,
  });

  final _TrackDrink drink;
  final int ml;
  final int effectiveMl;
  final Offset start;
  final double vx;
  final double vy;
  final double gravity;
  final double duration;

  Color get color => drink.liquidColor;

  Offset position(double t) {
    final s = t.clamp(0.0, 1.0) * duration;
    return Offset(
      start.dx + vx * s,
      start.dy + vy * s + 0.5 * gravity * s * s,
    );
  }

  Offset get end => position(1.0);
}

// ==================== 绘制 ====================

class _DropBody extends StatelessWidget {
  const _DropBody({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(7, 5, 7, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(9),
        ),
      ),
    );
  }
}

/// 弧线轨道
class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.width,
    required this.baseY,
    required this.arcH,
  });

  final double width;
  final double baseY;
  final double arcH;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      // 与首页背景（白色）同色：弧线只用来排布饮品，不显示线条
      ..color = Colors.white
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    // 标准圆弧：半弦长 width/2、矢高 arcH
    final half = width / 2;
    final r = (half * half + arcH * arcH) / (2 * arcH);
    final cy = baseY - arcH + r;

    final path = Path();
    for (var i = 0; i <= 120; i++) {
      final t = i / 120;
      final x = width * t;
      final dx = x - half;
      final y = cy - math.sqrt(math.max(0.0, r * r - dx * dx));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) =>
      old.width != width || old.baseY != baseY || old.arcH != arcH;
}
