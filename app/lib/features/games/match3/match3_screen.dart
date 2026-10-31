import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../shared/models/beverage.dart';
import '../../drink/providers/beverage_catalog_provider.dart';
import '../../drink/widgets/svg_container.dart';
import '../../points/points_provider.dart';
import '../../points/points_screen.dart';
import 'match3_rules.dart';

/// 棋盘格：带稳定 id 才能在交换/下落时保持 widget 身份并播放位移动画
class _Tile {
  _Tile({
    required this.id,
    required this.kind,
    required this.r,
    required this.c,
    this.spawn = false,
  });

  final int id;
  int kind;
  int r;
  int c;

  /// 正在被消除（缩放淡出中）
  bool clearing = false;

  /// 新补位（从缩小状态长出来）
  bool spawn;
}

/// 饮品消消乐：经典相邻交换三消
///
/// - 棋盘图格 = 从「内置 12 款 + 用户新增饮品」里随机抽取的饮品图标
///   （不看饮品管理页的开关；自定义饮品删除后自然不再出现）
/// - 限步数达成目标分：每局 20 步，目标 2000 分，三连 30 分/格，连锁加倍
/// - 通关按「分数 / 1000」折算积分，受积分体系每日上限约束
class Match3Screen extends ConsumerStatefulWidget {
  const Match3Screen({super.key});

  @override
  ConsumerState<Match3Screen> createState() => _Match3ScreenState();
}

class _Match3ScreenState extends ConsumerState<Match3Screen> {
  static const _brandCyan = Color(0xFF4DB8D8);
  static const _rows = 8;
  static const _cols = 8;

  /// 每局随机抽多少种饮品上盘（种类太多几乎凑不出三连）
  static const _kindSlots = 6;
  static const _movesPerLevel = 20;
  static const _targetScore = 2000;

  final _rnd = math.Random();
  static const _rules = Match3Rules(rows: _rows, cols: _cols);

  late List<List<_Tile?>> _grid;

  /// 本局 kinds 下标 → 饮品
  late List<Beverage> _pool;

  int _nextId = 0;
  int _score = 0;
  int _moves = _movesPerLevel;
  bool _busy = false;
  bool _finished = false;
  _Tile? _selected;

  /// 滑动交换：记录从哪一格起滑、累计位移
  Offset _dragAcc = Offset.zero;

  @override
  void initState() {
    super.initState();
    _pool = _pickPool();
    _startGame();
  }

  /// 抽取本局使用的饮品：水固定上盘，其余从内置预设 + 用户新增里随机补足
  List<Beverage> _pickPool() {
    final water = Beverage.presets.firstWhere((b) => b.id == 'water_pure');
    final others = ref
        .read(beverageLibraryProvider)
        .where((b) => b.id != 'water_pure')
        .toList();
    final seen = <String>{};
    final uniq = [
      for (final b in others)
        if (seen.add(b.id)) b,
    ]..shuffle(_rnd);
    return [water, ...uniq.take(_kindSlots - 1)];
  }

  // ==================== 棋盘 ====================

  void _startGame() {
    setState(() {
      _score = 0;
      _moves = _movesPerLevel;
      _finished = false;
      _busy = false;
      _selected = null;
      _generateBoard();
    });
  }

  void _generateBoard() {
    _grid = List.generate(_rows, (_) => List<_Tile?>.filled(_cols, null));
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        _grid[r][c] = _Tile(
          id: _nextId++,
          kind: _rnd.nextInt(_pool.length),
          r: r,
          c: c,
        );
      }
    }
    // 开局不允许自带三连，且必须存在可行交换
    var guard = 0;
    while (guard++ < 400) {
      final matches = _rules.findMatches(_kinds());
      if (matches.isEmpty && _rules.hasPossibleMove(_kinds())) break;
      final dirty = matches.isNotEmpty ? matches : _randomCell();
      for (final i in dirty) {
        _grid[i ~/ _cols][i % _cols]!.kind = _rnd.nextInt(_pool.length);
      }
    }
  }

  Set<int> _randomCell() => {_rnd.nextInt(_rows) * _cols + _rnd.nextInt(_cols)};

  List<List<int>> _kinds() => [
    for (final row in _grid) [for (final t in row) t?.kind ?? -1],
  ];

  void _swapTiles(_Tile a, _Tile b) {
    final ar = a.r, ac = a.c;
    a.r = b.r;
    a.c = b.c;
    _grid[a.r][a.c] = a;
    b.r = ar;
    b.c = ac;
    _grid[b.r][b.c] = b;
  }

  // ==================== 交互 ====================

  void _onTap(_Tile t) {
    if (_busy || _finished) return;
    final sel = _selected;
    if (sel == null || identical(sel, t)) {
      setState(() => _selected = identical(sel, t) ? null : t);
      return;
    }
    final adjacent = (sel.r - t.r).abs() + (sel.c - t.c).abs() == 1;
    if (!adjacent) {
      setState(() => _selected = t);
      return;
    }
    _attemptSwap(sel, t);
  }

  /// 手指滑动交换：按主方向与相邻格换位
  void _onDragEnd(_Tile t) {
    final acc = _dragAcc;
    _dragAcc = Offset.zero;
    if (_busy || _finished) return;
    const threshold = 14.0;
    if (acc.dx.abs() < threshold && acc.dy.abs() < threshold) return;

    final int dr, dc;
    if (acc.dx.abs() > acc.dy.abs()) {
      dr = 0;
      dc = acc.dx > 0 ? 1 : -1;
    } else {
      dr = acc.dy > 0 ? 1 : -1;
      dc = 0;
    }
    final nr = t.r + dr;
    final nc = t.c + dc;
    if (nr < 0 || nr >= _rows || nc < 0 || nc >= _cols) return;
    final other = _grid[nr][nc];
    if (other == null || other.clearing) return;
    setState(() => _selected = null);
    _attemptSwap(t, other);
  }

  Future<void> _attemptSwap(_Tile a, _Tile b) async {
    setState(() {
      _busy = true;
      _selected = null;
      _swapTiles(a, b);
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    if (_rules.findMatches(_kinds()).isEmpty) {
      // 交换不成三连：弹回原位，不计步数
      setState(() => _swapTiles(a, b));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (mounted) setState(() => _busy = false);
      return;
    }

    HapticFeedback.selectionClick();
    setState(() => _moves--);
    await _resolveCascades();
    if (!mounted) return;
    setState(() => _busy = false);
    _checkResult();
  }

  /// 连锁消除：消除 → 下落补位 → 再判定，直到没有三连
  Future<void> _resolveCascades() async {
    var combo = 1;
    while (true) {
      final matches = _rules.findMatches(_kinds());
      if (matches.isEmpty) break;

      final gain = matches.length * 30 * combo;
      HapticFeedback.lightImpact();
      setState(() {
        _score += gain;
        for (final i in matches) {
          _grid[i ~/ _cols][i % _cols]?.clearing = true;
        }
      });
      await Future<void>.delayed(const Duration(milliseconds: 230));
      if (!mounted) return;

      setState(() {
        for (final i in matches) {
          _grid[i ~/ _cols][i % _cols] = null;
        }
        _applyGravity();
      });
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;

      setState(() {
        for (final row in _grid) {
          for (final t in row) {
            t?.spawn = false;
          }
        }
      });
      combo++;
    }

    if (!_rules.hasPossibleMove(_kinds())) {
      setState(_reshuffle);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// 列内下落 + 顶部补新格
  void _applyGravity() {
    for (var c = 0; c < _cols; c++) {
      var write = _rows - 1;
      for (var r = _rows - 1; r >= 0; r--) {
        final t = _grid[r][c];
        if (t == null) continue;
        if (write != r) {
          _grid[write][c] = t;
          t.r = write;
          _grid[r][c] = null;
        }
        write--;
      }
      for (var r = write; r >= 0; r--) {
        _grid[r][c] = _Tile(
          id: _nextId++,
          kind: _rnd.nextInt(_pool.length),
          r: r,
          c: c,
          spawn: true,
        );
      }
    }
  }

  /// 死局重排：打乱现有 kinds，保证无立即三连且有可行交换
  void _reshuffle() {
    final tiles = [
      for (final row in _grid)
        for (final t in row)
          if (t != null) t,
    ];
    var guard = 0;
    while (guard++ < 60) {
      final kinds = [for (final t in tiles) t.kind]..shuffle(_rnd);
      for (var i = 0; i < tiles.length; i++) {
        tiles[i].kind = kinds[i];
      }
      if (_rules.findMatches(_kinds()).isEmpty &&
          _rules.hasPossibleMove(_kinds())) {
        return;
      }
    }
  }

  void _checkResult() {
    if (_score >= _targetScore) {
      _finished = true;
      _showResult(won: true);
    } else if (_moves <= 0) {
      _finished = true;
      _showResult(won: false);
    }
  }

  Future<void> _showResult({required bool won}) async {
    final storage = await ref.read(localStorageProvider.future);
    // 积分是账号权益：游客不计分，结算只提示登录后可获得
    final isGuest = !storage.hasAccountSession;
    final earned = (won && !isGuest)
        ? await ref
              .read(pointsProvider.notifier)
              .earn(
                source: 'match3',
                amount: _score ~/ PointsNotifier.scorePerPoint,
              )
        : 0;
    if (!mounted) return;
    final reachedCap = won && !isGuest && earned == 0;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                won ? '通关啦！' : '差一点就通关',
                style: TextStyle(
                  color: won ? _brandCyan : const Color(0xFF7C7C82),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '本局得分 $_score 分',
                style: const TextStyle(
                  color: Color(0xFF3C3C43),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                won
                    ? (isGuest
                          ? '登录后才能获得积分，游客不计分'
                          : (reachedCap ? '今日积分已达上限，明天再来～' : '获得 $earned 积分'))
                    : '目标 $_targetScore 分，再试一次吧',
                style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).pop();
                      },
                      child: const Text(
                        '返回',
                        style: TextStyle(color: Color(0xFF8E8E93)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _brandCyan,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _pool = _pickPool();
                        _startGame();
                      },
                      child: const Text(
                        '再来一局',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== UI ====================

  Widget _drinkIcon(Beverage b, double size) {
    if (hasContainerIcon(b.containerId)) {
      return SvgContainerIcon(
        containerId: b.containerId!,
        color: b.color,
        fillRatio: 0.9,
        size: size,
      );
    }
    return Icon(b.icon, color: b.color, size: size * 0.82);
  }

  Widget _buildTile(_Tile t, double cell) {
    final beverage = _pool[t.kind % _pool.length];
    final selected = identical(_selected, t);
    return AnimatedPositioned(
      key: ValueKey(t.id),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      left: t.c * cell,
      top: t.r * cell,
      width: cell,
      height: cell,
      child: AnimatedScale(
        scale: t.clearing ? 0.0 : (t.spawn ? 0.45 : 1.0),
        duration: const Duration(milliseconds: 210),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: t.clearing ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 210),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _onTap(t),
            onPanStart: (_) => _dragAcc = Offset.zero,
            onPanUpdate: (d) => _dragAcc += d.delta,
            onPanEnd: (_) => _onDragEnd(t),
            onPanCancel: () => _dragAcc = Offset.zero,
            // 格子不铺底色，饮品图标直接落在棋盘上；
            // 选中时只在这一格加浅青高亮描边，避免整盘白块显得笨重
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              margin: EdgeInsets.all(cell * 0.03),
              decoration: selected
                  ? BoxDecoration(
                      color: const Color(0xFFE4F7FC),
                      borderRadius: BorderRadius.circular(cell * 0.26),
                      border: Border.all(color: _brandCyan, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x334DB8D8),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    )
                  : null,
              child: Center(child: _drinkIcon(beverage, cell * 0.68)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hudChip(
    String label,
    String value, {
    Color? color,
    VoidCallback? onTap,
  }) {
    final chip = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color ?? const Color(0xFF3C3C43),
            fontSize: 20,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF9B9BA1), fontSize: 11.5),
        ),
      ],
    );
    return onTap == null
        ? chip
        : GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: chip,
          );
  }

  @override
  Widget build(BuildContext context) {
    final points = ref.watch(pointsProvider);
    final progress = (_score / _targetScore).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FA),
      // 顶部到中部的淡青渐层：让白色棋盘和透明图标有柔和的衬托
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEEF9FD), Color(0xFFF7F7FA)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶栏：返回 / 标题 / 重开（与饮品管理页同款浅灰圆钮）
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Row(
                  children: [
                    _CircleButton(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        size: 18,
                        color: Color(0xFF3C3C43),
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      '饮品消消乐',
                      style: TextStyle(
                        color: Color(0xFF3C3C43),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    _CircleButton(
                      onTap: _busy ? () {} : _startGame,
                      child: const Icon(
                        Icons.refresh_rounded,
                        size: 18,
                        color: Color(0xFF3C3C43),
                      ),
                    ),
                  ],
                ),
              ),
              // 信息区 + 棋盘 + 提示作为一个整体居中：信息下移、更贴近棋盘
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0F000000),
                                blurRadius: 14,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(child: _hudChip('得分', '$_score')),
                              Expanded(
                                child: _hudChip(
                                  '剩余步数',
                                  '$_moves',
                                  color: _brandCyan,
                                ),
                              ),
                              Expanded(
                                child: _hudChip(
                                  '积分',
                                  '${points.balance}',
                                  color: const Color(0xFFF2A93B),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const PointsScreen(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 14,
                            backgroundColor: const Color(0xFFEDEDF2),
                            valueColor: const AlwaysStoppedAnimation(
                              _brandCyan,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '目标 $_targetScore 分',
                        style: const TextStyle(
                          color: Color(0xFF9B9BA1),
                          fontSize: 12,
                        ),
                      ),
                      // 信息区与棋盘之间的呼吸感
                      const SizedBox(height: 32),
                      LayoutBuilder(
                        builder: (ctx, c) {
                          final cell = math.min(
                            (c.maxWidth - 40 - 24) / _cols,
                            math.min((c.maxHeight - 80 - 24) / _rows, 54.0),
                          );
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 棋盘子：白到浅青的柔光面板，无格底色的图标更清爽
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [Colors.white, Color(0xFFF0FAFE)],
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: const Color(0xFFE1F2F8),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x1A4DB8D8),
                                      blurRadius: 22,
                                      offset: Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: SizedBox(
                                  width: cell * _cols,
                                  height: cell * _rows,
                                  child: Stack(
                                    children: [
                                      for (final row in _grid)
                                        for (final t in row)
                                          if (t != null) _buildTile(t, cell),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 26),
                              const Text(
                                '点选或滑动相邻饮品交换位置，凑成三个以上即可消除',
                                style: TextStyle(
                                  color: Color(0xFF9B9BA1),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶栏圆钮（与饮品管理页一致：浅灰圆底 42×42）
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF2F2F5),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(width: 42, height: 42, child: Center(child: child)),
      ),
    );
  }
}
