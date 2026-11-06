import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../shared/models/beverage.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../../drink/providers/beverage_catalog_provider.dart';
import '../../drink/widgets/svg_container.dart';
import '../../points/points_provider.dart';
import '../../points/points_screen.dart';
import 'match3_rules.dart';

/// 消除生成的特效（棋盘格上的强化道具）
enum _Fx { none, lineRow, lineCol, bomb, colorBomb }

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

  /// 本格携带的特效（由 4 连 / T·L 型 / 5 连生成）
  _Fx fx = _Fx.none;
}

/// 玩法模式：闯关按关卡目标推进，无尽没有步数与分数上限
enum _Mode { level, endless }

/// 闯关棋盘形状：每关随机换一种几何图形
enum _BoardShape { full, diamond, circle, plus }

/// 饮品消消乐：经典相邻交换三消
///
/// - 闯关模式：每关限步数达成目标分，通关后进入下一关（棋盘随机换成
///   矩形 / 菱形 / 圆形 / 十字形），目标分与步数逐关递增
/// - 无尽模式：不限步数、不限分数，每累计 2000 分结算一次积分
/// - 棋盘图格 = 从「内置 12 款 + 用户新增饮品」里随机抽取的饮品图标
///   （不看饮品管理页的开关；自定义饮品删除后自然不再出现）
/// - 三连 30 分/格，连锁加倍
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
  static const _baseMoves = 20;
  static const _baseTarget = 2000;

  /// 无尽模式每累计多少分结算一次积分
  static const _endlessStep = 2000;

  final _rnd = math.Random();
  static const _rules = Match3Rules(rows: _rows, cols: _cols);

  late List<List<_Tile?>> _grid;

  /// 当前棋盘的有效格（几何形状遮罩）
  late List<List<bool>> _mask;

  /// 本局 kinds 下标 → 饮品
  late List<Beverage> _pool;

  int _nextId = 0;
  int _score = 0;
  int _moves = _baseMoves;
  int _level = 1;
  _Mode _mode = _Mode.level;
  _BoardShape _shape = _BoardShape.full;
  bool _busy = false;
  bool _finished = false;
  _Tile? _selected;

  /// 正在退出：先结算无尽模式零头再真正返回
  bool _leaving = false;

  /// 无尽模式已结算到的分数档位（每 2000 分一档）
  int _endlessAwarded = 0;

  /// 游客提示只弹一次，避免每个档位都弹
  bool _guestHintShown = false;

  /// 本地已保存的最高关卡：切换模式时从该关继续
  int _savedLevel = 1;

  /// 滑动交换：记录从哪一格起滑、累计位移
  Offset _dragAcc = Offset.zero;

  /// 当前关目标分：每关递增 800
  int get _targetScore => _baseTarget + (_level - 1) * 800;

  /// 当前关步数：前 6 关每关 +2，之后保持
  int get _movesForLevel => _baseMoves + math.min(_level - 1, 6) * 2;

  @override
  void initState() {
    super.initState();
    _pool = _pickPool();
    _shape = _pickShape();
    _mask = _maskFor(_shape);
    _startGame();
    unawaited(_restoreLevel());
  }

  /// 读取本地保存的闯关进度：下次进入直接从最高关卡开始
  Future<void> _restoreLevel() async {
    final storage = await ref.read(localStorageProvider.future);
    if (!mounted) return;
    _savedLevel = storage.match3Level;
    if (_mode != _Mode.level || _savedLevel <= _level) return;
    setState(() {
      _level = _savedLevel;
      _moves = _movesForLevel;
    });
  }

  /// 通关后记录新的最高关卡
  void _persistLevel(int level) {
    _savedLevel = level;
    unawaited(() async {
      final storage = await ref.read(localStorageProvider.future);
      await storage.setMatch3Level(level);
    }());
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

  /// 随机挑一种几何棋盘：矩形 / 菱形 / 圆形 / 十字
  _BoardShape _pickShape() {
    final shapes = _BoardShape.values;
    return shapes[_rnd.nextInt(shapes.length)];
  }

  /// 由形状生成 8×8 有效格遮罩
  List<List<bool>> _maskFor(_BoardShape shape) {
    bool keep(int r, int c) {
      final dr = (r - 3.5).abs();
      final dc = (c - 3.5).abs();
      return switch (shape) {
        _BoardShape.full => true,
        _BoardShape.diamond => dr + dc <= 4.25,
        _BoardShape.circle => dr * dr + dc * dc <= 12.6,
        _BoardShape.plus => (r >= 2 && r <= 5) || (c >= 2 && c <= 5),
      };
    }

    return [
      for (var r = 0; r < _rows; r++)
        [for (var c = 0; c < _cols; c++) keep(r, c)],
    ];
  }

  List<int> get _validCells => [
    for (var r = 0; r < _rows; r++)
      for (var c = 0; c < _cols; c++)
        if (_mask[r][c]) r * _cols + c,
  ];

  // ==================== 棋盘 ====================

  /// 切换模式 / 重开：闯关从已保存的最高关卡继续，无尽不限步数
  void _switchMode(_Mode mode) {
    if (_busy) return;
    setState(() {
      _mode = mode;
      _level = mode == _Mode.level ? _savedLevel : 1;
      _shape = mode == _Mode.endless ? _BoardShape.full : _pickShape();
      _mask = _maskFor(_shape);
      _startGame();
    });
  }

  void _startGame() {
    setState(() {
      _score = 0;
      _moves = _mode == _Mode.level ? _movesForLevel : _baseMoves;
      _endlessAwarded = 0;
      _finished = false;
      _busy = false;
      _selected = null;
      _generateBoard();
    });
  }

  /// 失败重试：保留本关已获得的分数与当前棋盘，只补满步数继续
  void _retryLevel() {
    setState(() {
      _moves = _movesForLevel;
      _finished = false;
      _busy = false;
      _selected = null;
    });
  }

  void _generateBoard() {
    _grid = List.generate(_rows, (_) => List<_Tile?>.filled(_cols, null));
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        if (!_mask[r][c]) continue;
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

  Set<int> _randomCell() {
    final cells = _validCells;
    return {cells[_rnd.nextInt(cells.length)]};
  }

  /// 逻辑棋盘：魔力鸟按 -2 上报，避免被普通三连匹配
  List<List<int>> _kinds() => [
    for (final row in _grid)
      [
        for (final t in row)
          t == null
              ? -1
              : (t.fx == _Fx.colorBomb ? -2 : t.kind),
      ],
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

    final aBomb = a.fx == _Fx.colorBomb;
    final bBomb = b.fx == _Fx.colorBomb;
    final bombSwap = aBomb || bBomb;

    if (!bombSwap && _rules.findMatches(_kinds()).isEmpty) {
      // 交换不成三连：弹回原位，不计步数
      setState(() => _swapTiles(a, b));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (mounted) setState(() => _busy = false);
      return;
    }

    HapticFeedback.selectionClick();
    if (_mode == _Mode.level) setState(() => _moves--);

    if (bombSwap) {
      // 魔力鸟：与任意相邻格交换都成立，消除该颜色全部格子
      final seeds = <int>{
        a.r * _cols + a.c,
        b.r * _cols + b.c,
      };
      if (aBomb && bBomb) {
        // 双魔力鸟：清空整盘
        seeds.addAll(_validCells);
      } else {
        final kind = aBomb ? b.kind : a.kind;
        for (var r = 0; r < _rows; r++) {
          for (var c = 0; c < _cols; c++) {
            final t = _grid[r][c];
            if (t != null && t.kind == kind) seeds.add(r * _cols + c);
          }
        }
      }
      // 魔力鸟自身的爆炸范围已在上面算好，这里不再重复触发
      final silent = <int>{
        if (aBomb) a.r * _cols + a.c,
        if (bBomb) b.r * _cols + b.c,
      };
      await _resolveCascades(seed: seeds, silent: silent);
    } else {
      await _resolveCascades();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (_mode == _Mode.endless) {
      await _settleEndless();
    } else {
      _checkResult();
    }
  }

  /// 无尽模式结算：每累计 2000 分入账 2 积分。
  /// 受服务端规则约束：单条 ≤200、每日小游戏 ≤500 分，
  /// 客户端提前按同一口径截断并提示，避免「提示得分后又被回退」。
  Future<void> _settleEndless() async {
    final reached = (_score ~/ _endlessStep) * _endlessStep;
    if (reached <= _endlessAwarded) return;
    final batches = (reached - _endlessAwarded) ~/ _endlessStep;
    _endlessAwarded = reached;

    final storage = await ref.read(localStorageProvider.future);
    if (!mounted) return;
    if (!storage.hasAccountSession) {
      if (!_guestHintShown) {
        _guestHintShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('登录后才能获得积分，游客不计分'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    final earned = await ref
        .read(pointsProvider.notifier)
        .earn(source: 'match3', amount: batches * 2);
    if (!mounted) return;
    final capped = ref.read(pointsProvider).gameCapReached;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          earned > 0
              ? '累计 $_score 分，获得 $earned 积分'
              : capped
              ? '今日消消乐积分已达上限（$pointsDailyGameCap）'
              : '今日暂无可用积分',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 退出无尽模式时补发不足 2000 分的零头（每 1000 分 1 积分，与整档规则一致）
  Future<void> _settleEndlessRemainder() async {
    if (_mode != _Mode.endless) return;
    final total = _score ~/ PointsNotifier.scorePerPoint;
    final awarded = _endlessAwarded ~/ PointsNotifier.scorePerPoint;
    if (total <= awarded) return;
    _endlessAwarded = total * PointsNotifier.scorePerPoint;
    await ref
        .read(pointsProvider.notifier)
        .earn(source: 'match3', amount: total - awarded);
  }

  /// 返回前先结算零头，再等一帧让 PopScope 的 canPop 生效
  Future<void> _leaveScreen() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await _settleEndlessRemainder();
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  /// 连锁消除：消除 → 下落补位 → 再判定，直到没有三连
  ///
  /// [seed] 为额外要消除的格子（魔力鸟交换时传入），
  /// [silent] 为不触发自身特效的格子（魔力鸟自身的范围已由调用方算好）
  Future<void> _resolveCascades({Set<int>? seed, Set<int>? silent}) async {
    var combo = 1;
    var extra = seed;
    var triggerSilent = silent;

    while (true) {
      final groups = _rules.findGroups(_kinds());
      final seeds = <int>{...?extra};
      final creations = <int, _Fx>{};
      for (final g in groups) {
        seeds.addAll(g.cells);
        final at = g.specialIndex;
        if (at != null && g.special != MatchSpecial.none) {
          final tile = _grid[at ~/ _cols][at % _cols];
          // 该格已有特效时优先触发旧特效，不再叠新的
          if (tile != null && tile.fx == _Fx.none) {
            creations[at] = _fxOf(g.special);
          }
        }
      }
      if (seeds.isEmpty) break;

      // 特效连锁：被清掉的格子若是特效，则扩大消除范围
      final clear = _gatherClear(seeds, silent: triggerSilent);
      triggerSilent = null;
      // 生成特效的格子保留下来（不参与本次消除）
      clear.removeAll(creations.keys);
      if (clear.isEmpty) break;

      final gain = clear.length * 30 * combo;
      HapticFeedback.lightImpact();
      setState(() {
        _score += gain;
        for (final i in clear) {
          _grid[i ~/ _cols][i % _cols]?.clearing = true;
        }
      });
      await Future<void>.delayed(const Duration(milliseconds: 230));
      if (!mounted) return;

      setState(() {
        for (final i in clear) {
          _grid[i ~/ _cols][i % _cols] = null;
        }
        for (final e in creations.entries) {
          _grid[e.key ~/ _cols][e.key % _cols]?.fx = e.value;
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
      extra = null;
      combo++;
    }

    if (!_rules.hasPossibleMove(_kinds())) {
      setState(_reshuffle);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// 从 [seeds] 出发展开特效连锁，得到本次真正要清掉的全部格子
  Set<int> _gatherClear(Set<int> seeds, {Set<int>? silent}) {
    final clear = <int>{};
    final queue = <int>[...seeds];
    while (queue.isNotEmpty) {
      final i = queue.removeLast();
      if (!clear.add(i)) continue;
      if (silent != null && silent.contains(i)) continue;
      final t = _grid[i ~/ _cols][i % _cols];
      if (t == null || t.fx == _Fx.none) continue;
      queue.addAll(_blast(t, i));
    }
    return clear;
  }

  /// 某个特效格爆炸时影响的格子（按棋盘遮罩裁剪）
  List<int> _blast(_Tile t, int i) {
    final r = i ~/ _cols;
    final c = i % _cols;
    switch (t.fx) {
      case _Fx.lineRow:
        return [
          for (var cc = 0; cc < _cols; cc++)
            if (_mask[r][cc]) r * _cols + cc,
        ];
      case _Fx.lineCol:
        return [
          for (var rr = 0; rr < _rows; rr++)
            if (_mask[rr][c]) rr * _cols + c,
        ];
      case _Fx.bomb:
        return [
          for (var rr = r - 1; rr <= r + 1; rr++)
            for (var cc = c - 1; cc <= c + 1; cc++)
              if (rr >= 0 &&
                  rr < _rows &&
                  cc >= 0 &&
                  cc < _cols &&
                  _mask[rr][cc])
                rr * _cols + cc,
        ];
      case _Fx.colorBomb:
        final kind = t.kind;
        return [
          for (var rr = 0; rr < _rows; rr++)
            for (var cc = 0; cc < _cols; cc++)
              if (_grid[rr][cc] != null &&
                  _grid[rr][cc]!.kind == kind &&
                  _grid[rr][cc]!.fx != _Fx.colorBomb)
                rr * _cols + cc,
        ];
      case _Fx.none:
        return const [];
    }
  }

  _Fx _fxOf(MatchSpecial special) => switch (special) {
    MatchSpecial.none => _Fx.none,
    MatchSpecial.lineRow => _Fx.lineRow,
    MatchSpecial.lineCol => _Fx.lineCol,
    MatchSpecial.bomb => _Fx.bomb,
    MatchSpecial.colorBomb => _Fx.colorBomb,
  };

  /// 列内下落 + 顶部补新格（按几何遮罩的有效格收拢）
  void _applyGravity() {
    for (var c = 0; c < _cols; c++) {
      final tiles = <_Tile>[];
      for (var r = _rows - 1; r >= 0; r--) {
        final t = _grid[r][c];
        if (t != null) tiles.add(t);
        _grid[r][c] = null;
      }
      // 从底部有效格开始依次放回
      var i = 0;
      for (var r = _rows - 1; r >= 0 && i < tiles.length; r--) {
        if (!_mask[r][c]) continue;
        final t = tiles[i++];
        t.r = r;
        t.c = c;
        _grid[r][c] = t;
      }
      // 剩余空间补新格
      for (var r = _rows - 1; r >= 0; r--) {
        if (!_mask[r][c] || _grid[r][c] != null) continue;
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
    if (_mode != _Mode.level) return;
    if (_score >= _targetScore) {
      setState(() => _finished = true);
      unawaited(_showResult(won: true));
    } else if (_moves <= 0) {
      setState(() => _finished = true);
      unawaited(_showResult(won: false));
    }
  }

  Future<void> _showResult({required bool won}) async {
    var isGuest = true;
    try {
      final storage = await ref.read(localStorageProvider.future);
      isGuest = !storage.hasAccountSession;
    } catch (_) {
      // 本地存储异常不应阻塞通关弹窗
    }
    // 积分是账号权益：游客不计分；发分失败也不影响结算与进入下一关
    var earned = 0;
    if (won && !isGuest) {
      try {
        earned = await ref
            .read(pointsProvider.notifier)
            .earn(
              source: 'match3',
              amount: _score ~/ PointsNotifier.scorePerPoint,
            )
            .timeout(const Duration(seconds: 3), onTimeout: () => 0);
      } catch (_) {
        earned = 0;
      }
    }
    if (!mounted) return;
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
                won ? '第 $_level 关通关啦！' : '差一点就通关',
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
                          : (earned > 0
                              ? '获得 $earned 积分'
                              : ref.read(pointsProvider).gameCapReached
                              ? '今日消消乐积分已达上限（$pointsDailyGameCap）'
                              : '本局得分不足 1000，暂无积分'))
                    : '目标 $_targetScore 分，已得 $_score 分会保留',
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
                        if (won) {
                          // 通关后进入下一关：目标更高，棋盘随机换新形状；
                          // 同时把最高关卡写入本地，下次进入直接继续
                          _level += 1;
                          _persistLevel(_level);
                          _shape = _pickShape();
                          _mask = _maskFor(_shape);
                          _startGame();
                        } else {
                          // 失败不再清零分数，补齐步数后接着打
                          _retryLevel();
                        }
                      },
                      child: Text(
                        won ? '下一关' : '再试一次',
                        style: const TextStyle(fontWeight: FontWeight.w700),
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

  /// 直线 / 爆炸 / 魔力鸟的角标（角标叠在饮品图标右下角，不替换饮品本身）
  Widget _fxBadge(_Fx fx, double cell) {
    final (icon, color) = switch (fx) {
      _Fx.lineRow => (Icons.swap_horiz_rounded, _brandCyan),
      _Fx.lineCol => (Icons.swap_vert_rounded, _brandCyan),
      _Fx.bomb => (Icons.flare_rounded, const Color(0xFFF2A93B)),
      _Fx.colorBomb => (Icons.auto_awesome_rounded, Colors.white),
      _Fx.none => (Icons.circle, _brandCyan),
    };
    final rainbow = fx == _Fx.colorBomb;
    return Container(
      width: cell * 0.34,
      height: cell * 0.34,
      decoration: BoxDecoration(
        color: rainbow ? null : Colors.white,
        gradient: rainbow
            ? const SweepGradient(
                colors: [
                  Color(0xFFEF7A8B),
                  Color(0xFFF2C14E),
                  Color(0xFF6BCB77),
                  Color(0xFF4DB8D8),
                  Color(0xFF9B7BE8),
                  Color(0xFFEF7A8B),
                ],
              )
            : null,
        shape: BoxShape.circle,
        border: Border.all(color: rainbow ? Colors.white : color, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Icon(icon, size: cell * 0.2, color: color),
    );
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
              child: Center(
                child: SizedBox(
                  width: cell,
                  height: cell,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 所有格子（含特效格、魔力鸟）都保持饮品图标
                      _drinkIcon(beverage, cell * 0.68),
                      if (t.fx != _Fx.none)
                        Positioned(
                          right: cell * 0.05,
                          bottom: cell * 0.05,
                          child: _fxBadge(t.fx, cell),
                        ),
                    ],
                  ),
                ),
              ),
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

  Widget _modePill(String label, _Mode mode) {
    final active = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: _busy ? null : () => _switchMode(mode),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _brandCyan : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF8E8E93),
              fontSize: 13,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = ref.watch(pointsProvider);
    final progress = _mode == _Mode.level
        ? (_score / _targetScore).clamp(0.0, 1.0)
        : ((_score % _endlessStep) / _endlessStep);

    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leaveScreen());
      },
      child: Scaffold(
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
                    const AppBackButton(),
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
                      // 玩法切换：闯关（限步数） / 无尽（不限步数与分数）
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0F000000),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              _modePill('闯关', _Mode.level),
                              _modePill('无尽', _Mode.endless),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
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
                                  _mode == _Mode.endless ? '∞' : '$_moves',
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
                        _mode == _Mode.level
                            ? '第 $_level 关 · 目标 $_targetScore 分'
                            : '无尽模式 · 每 2000 分 +2 积分',
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
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF9B9BA1),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                '4 连出直线特效，5 连 T/L 型出爆炸，5 连成线出魔力鸟',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFB4BAC4),
                                  fontSize: 11,
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
