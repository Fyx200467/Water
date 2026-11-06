// 吨吨守卫战：页面层（HUD + 画布交互 + 结算）
//
// 玩法：缺水怪兽沿固定路线冲向终点水杯，在虚线炮位上建造 / 升级 / 出售防御塔，
// 守住水杯里的水量直到全部波次清空。通关解锁下一关（进度只存本机）。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../../points/points_provider.dart';
import 'defense_game.dart';
import 'defense_levels.dart';
import 'defense_models.dart';
import 'defense_painter.dart';
import 'defense_rules.dart';

/// 吨吨守卫战主界面
class DefenseScreen extends ConsumerStatefulWidget {
  const DefenseScreen({super.key});

  @override
  ConsumerState<DefenseScreen> createState() => _DefenseScreenState();
}

class _DefenseScreenState extends ConsumerState<DefenseScreen>
    with SingleTickerProviderStateMixin {
  static const _brandCyan = Color(0xFF4DB8D8);
  static const _ink = Color(0xFF171A26);

  late final Ticker _ticker;

  /// 逐帧重绘信号（只触发画布重绘，不重建整棵组件树）
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  late DefenseGame _game;
  Duration _lastElapsed = Duration.zero;
  int _hudFrame = 0;

  /// 当前关卡（1 起）与已通关的最高关卡数（0~5）
  int _level = 1;
  int _cleared = 0;

  /// 已解锁的最高关卡（通关的下一关，最多第 5 关）
  int get _maxUnlocked =>
      math.min(DefenseRules.levelCount, _cleared + 1);

  DefenseTower? _selectedTower;

  /// 原地弹出的小菜单：点空炮位选塔，点已建塔升级/出售。
  /// 菜单打开期间游戏照常推进，不暂停。
  DefenseCell? _menuSlot;
  DefenseTower? _menuTower;

  bool _paused = false;
  bool _resultShown = false;

  @override
  void initState() {
    super.initState();
    // 竖屏塔防：锁定竖屏，避免横置时布局被压扁
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]),
    );
    _game = DefenseGame(level: defenseLevelFor(1));
    _ticker = createTicker(_onTick)..start();
    unawaited(_restoreProgress());
  }

  @override
  void dispose() {
    // 恢复系统旋转，避免影响其它页面
    unawaited(
      SystemChrome.setPreferredOrientations(DeviceOrientation.values),
    );
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  /// 读取本机通关进度：进入即从最新解锁关卡开始
  Future<void> _restoreProgress() async {
    try {
      final storage = await ref.read(localStorageProvider.future);
      if (!mounted) return;
      final cleared = storage.defenseClearedLevels;
      if (cleared <= _cleared) return;
      _cleared = cleared;
      _startLevel(math.min(DefenseRules.levelCount, cleared + 1));
    } catch (_) {
      // 本地存储异常时按第 1 关开始，不影响游玩
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    if (dt <= 0 || _paused || _resultShown) return;

    _game.update(dt);
    _repaint.value += 1;

    // HUD 每 ~100ms 刷新一次，画布仍保持 60fps
    _hudFrame += 1;
    if (_hudFrame % 6 == 0) setState(() {});

    if (_game.phase != DefensePhase.playing && !_resultShown) {
      _resultShown = true;
      _closeMenu();
      unawaited(_showResult(_game.phase == DefensePhase.won));
    }
  }

  void _startLevel(int level) {
    setState(() {
      _level = level.clamp(1, DefenseRules.levelCount);
      _game = DefenseGame(level: defenseLevelFor(_level));
      _selectedTower = null;
      _menuSlot = null;
      _menuTower = null;
      _paused = false;
      _resultShown = false;
    });
  }

  // ==================== 交互 ====================

  void _handleTap(Offset local, double cell) {
    if (!_game.isPlaying || _paused) return;

    // 布阵阶段：点出口处的光圈也能直接开局
    if (!_game.started && _game.pathPoints.isNotEmpty) {
      final start = _game.pathPoints.first;
      final gate = Offset(
        start.x.clamp(0.5, defenseCols - 0.5) * cell,
        start.y.clamp(0.5, defenseRows - 0.5) * cell,
      );
      if ((local - gate).distance <= cell * 0.55) {
        _startBattle();
        return;
      }
    }

    final col = (local.dx / cell).floor();
    final row = (local.dy / cell).floor();
    if (col < 0 || col >= defenseCols || row < 0 || row >= defenseRows) {
      return;
    }

    final tower = _game.towerAt(col, row);
    if (tower != null) {
      _openTowerMenu(tower);
      return;
    }
    final slot = _game.level.slotAt(col, row);
    if (slot != null) _openSlotMenu(slot);
  }

  /// 布阵结束：点出口标记后才开始出怪
  void _startBattle() {
    if (!_game.isPlaying || _game.started) return;
    HapticFeedback.mediumImpact();
    _game.startWaves();
    _repaint.value += 1;
    setState(() {});
  }

  /// 点空炮位：就在炮位旁边弹出三种炮塔，选好即建（游戏不暂停）
  void _openSlotMenu(DefenseCell slot) {
    HapticFeedback.selectionClick();
    setState(() {
      _menuSlot = slot;
      _menuTower = null;
      _selectedTower = null;
    });
  }

  /// 点已建塔：就在塔旁边弹出升级 / 出售（游戏不暂停）
  void _openTowerMenu(DefenseTower tower) {
    HapticFeedback.selectionClick();
    setState(() {
      _menuTower = tower;
      _menuSlot = null;
      _selectedTower = tower;
    });
  }

  void _closeMenu() {
    if (_menuSlot == null && _menuTower == null && _selectedTower == null) {
      return;
    }
    setState(() {
      _menuSlot = null;
      _menuTower = null;
      _selectedTower = null;
    });
    _repaint.value += 1;
  }

  void _buildAt(DefenseTowerType type) {
    final slot = _menuSlot;
    if (slot == null) return;
    final result = _game.placeTower(slot.col, slot.row, type);
    switch (result) {
      case DefensePlaceResult.ok:
        HapticFeedback.lightImpact();
        _closeMenu();
      case DefensePlaceResult.noGold:
        _toast('水滴币不足，等下一波奖励再建塔');
      case DefensePlaceResult.occupied:
        _toast('这个炮位已经有塔了');
        _closeMenu();
      case DefensePlaceResult.notSlot:
        _toast('只能建在虚线炮位上');
        _closeMenu();
      case DefensePlaceResult.notPlaying:
        break;
    }
  }

  void _upgradeMenuTower() {
    final tower = _menuTower;
    if (tower == null) return;
    final result = _game.upgradeTower(tower);
    switch (result) {
      case DefenseUpgradeResult.ok:
        HapticFeedback.mediumImpact();
        setState(() {});
        _repaint.value += 1;
      case DefenseUpgradeResult.noGold:
        _toast('水滴币不足，先攒一攒');
      case DefenseUpgradeResult.maxLevel:
        _toast('这座塔已经满级了');
      case DefenseUpgradeResult.missing:
        _closeMenu();
      case DefenseUpgradeResult.notPlaying:
        break;
    }
  }

  void _sellMenuTower() {
    final tower = _menuTower;
    if (tower == null) return;
    final refund = _game.sellTower(tower);
    if (refund <= 0) return;
    HapticFeedback.selectionClick();
    _closeMenu();
    _toast('已出售，返还 $refund 水滴币');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 出口的开始标记：点它之后才开始出怪
  Widget _startMarker(double cell, double boardW, double boardH) {
    final start = _game.pathPoints.first;
    final gx = start.x.clamp(0.5, defenseCols - 0.5) * cell;
    final gy = start.y.clamp(0.5, defenseRows - 0.5) * cell;
    const w = 86.0;
    const h = 34.0;
    final left = (gx + cell * 0.5).clamp(6.0, boardW - w - 6).toDouble();
    final top = (gy - h / 2).clamp(6.0, boardH - h - 6).toDouble();
    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: GestureDetector(
        key: const ValueKey('defense-start'),
        behavior: HitTestBehavior.opaque,
        onTap: _startBattle,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(h / 2),
            border: Border.all(color: _brandCyan, width: 1.6),
            boxShadow: const [
              BoxShadow(
                color: Color(0x334DB8D8),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_arrow_rounded, size: 16, color: _brandCyan),
              SizedBox(width: 1),
              Text(
                '开始',
                maxLines: 1,
                style: TextStyle(
                  color: _cyanText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 炮位 / 炮塔旁边的原地菜单（不遮全屏、不暂停游戏）
  List<Widget> _menuLayers(double cell, double boardW, double boardH) {
    final slot = _menuSlot;
    final tower = _menuTower;
    if (slot == null && tower == null) return const [];

    final anchor = slot?.center ?? tower!.center;
    final center = Offset(anchor.x * cell, anchor.y * cell);
    final ringR = cell * 1.05;
    final cardW = math.min(boardW - 16, math.max(212.0, cell * 6.6));
    final estH = tower != null ? 116.0 : 126.0;

    var top = center.dy - ringR - estH - 6;
    if (top < 6) top = center.dy + ringR + 6;
    if (top + estH > boardH - 6) top = math.max(6, boardH - estH - 6);
    final left = (center.dx - cardW / 2)
        .clamp(8.0, math.max(8.0, boardW - cardW - 8))
        .toDouble();

    final color = tower != null ? Color(tower.type.color) : _brandCyan;

    return [
      // 点空白处收起；点到别的炮位 / 炮塔则直接切换菜单，不用点两次
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            _closeMenu();
            _handleTap(d.localPosition, cell);
          },
          child: const ColoredBox(color: Color(0x0D000000)),
        ),
      ),
      // 炮位光圈
      Positioned(
        left: center.dx - ringR,
        top: center.dy - ringR,
        width: ringR * 2,
        height: ringR * 2,
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.16),
              border: Border.all(
                color: color.withValues(alpha: 0.9),
                width: cell * 0.08,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ),
      ),
      // 选择卡片
      Positioned(
        left: left,
        top: top,
        width: cardW,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: tower != null
              ? _buildTowerMenuBody(tower, color)
              : _buildSlotMenuBody(color),
        ),
      ),
    ];
  }

  Widget _buildSlotMenuBody(Color color) {
    final types = DefenseTowerType.values;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              '选择炮塔',
              style: TextStyle(
                color: _ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.water_drop_rounded,
              size: 11,
              color: Color(0xFFE8B44A),
            ),
            const SizedBox(width: 2),
            Text(
              '${_game.gold}',
              style: const TextStyle(
                color: Color(0xFF3C3C43),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final type in types)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: type == types.last ? 0 : 4,
                  ),
                  child: _MenuTowerOption(
                    type: type,
                    affordable: _game.gold >= type.cost,
                    onTap: () => _buildAt(type),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTowerMenuBody(DefenseTower tower, Color color) {
    final cost = DefenseRules.upgradeCost(tower.type, tower.level);
    final refund = DefenseRules.sellValue(tower.invested);
    final maxed = tower.level >= DefenseRules.maxTowerLevel;
    final trait = switch (tower.type) {
      DefenseTowerType.droplet => '单体',
      DefenseTowerType.cannon => '范围',
      DefenseTowerType.ice => '减速',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${tower.type.label} · Lv${tower.level}',
              style: const TextStyle(
                color: _ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              '满级 ${DefenseRules.maxTowerLevel}',
              style: const TextStyle(color: Color(0xFF9B9BA1), fontSize: 9.5),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          '伤害 ${DefenseRules.damageOf(tower.type, tower.level).toStringAsFixed(0)}'
          ' · 射程 ${DefenseRules.rangeOf(tower.type, tower.level).toStringAsFixed(1)}'
          ' · 间隔 ${DefenseRules.cooldownOf(tower.type, tower.level).toStringAsFixed(2)}s'
          ' · $trait',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 10),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: _MenuAction(
                label: maxed ? '已满级' : '升级 $cost',
                icon: Icons.arrow_upward_rounded,
                enabled: !maxed && _game.gold >= cost,
                color: color,
                filled: true,
                onTap: _upgradeMenuTower,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _MenuAction(
                label: '出售 +$refund',
                icon: Icons.sell_rounded,
                enabled: true,
                color: const Color(0xFFE8B44A),
                filled: false,
                onTap: _sellMenuTower,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== 结算 ====================

  Future<void> _showResult(bool won) async {
    var isGuest = true;
    try {
      final storage = await ref.read(localStorageProvider.future);
      isGuest = !storage.hasAccountSession;
    } catch (_) {
      // 本地存储异常不阻塞结算弹窗
    }

    // 首次通关（当前关卡还没通关过）拿全额积分，重复通关按 60% 折算
    final firstClear = won && _level > _cleared;
    final score = won
        ? DefenseRules.scoreFor(
            levelIndex: _level,
            lives: _game.lives,
            repeat: !firstClear,
          )
        : 0;

    if (won && firstClear) {
      _cleared = _level;
      try {
        final storage = await ref.read(localStorageProvider.future);
        await storage.setDefenseClearedLevels(_cleared);
      } catch (_) {
        // 进度落盘失败不影响本局
      }
    }

    // 积分是账号权益：游客不计分；发分失败也不影响结算
    var earned = 0;
    if (won && !isGuest) {
      try {
        earned = await ref
            .read(pointsProvider.notifier)
            .earn(source: 'defense', amount: score)
            .timeout(const Duration(seconds: 3), onTimeout: () => 0);
      } catch (_) {
        earned = 0;
      }
    }
    if (!mounted) return;

    final capped = ref.read(pointsProvider).capReachedForSource('defense');
    final allCleared = _level >= DefenseRules.levelCount;
    final pointsText = isGuest
        ? '登录后才能获得积分，游客不计分'
        : earned > 0
        ? '获得 $earned 积分'
        : capped
        ? '今日守卫战积分已达上限（$pointsDailyGameCap）'
        : '今日暂无可用积分';

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  won
                      ? (allCleared ? '全部关卡通关！' : '第 $_level 关 通关啦！')
                      : '水杯见底了',
                  style: TextStyle(
                    color: won ? _brandCyan : const Color(0xFF7C7C82),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  won
                      ? '剩余水量 ${_game.lives} · 击退怪兽 ${_game.kills}'
                      : '水杯里的水被喝光啦，换个思路：把塔建在转弯处试试',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF3C3C43),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  won ? pointsText : '本局不计积分',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop('home'),
                        child: const Text(
                          '返回乐园',
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
                        onPressed: () => Navigator.of(ctx).pop('next'),
                        child: Text(
                          won
                              ? (allCleared ? '再玩一次' : '下一关')
                              : '再试一次',
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
      ),
    );

    if (!mounted) return;
    switch (action) {
      case 'home':
        Navigator.of(context).pop();
      case 'next':
        _startLevel(won ? (allCleared ? _level : _level + 1) : _level);
      default:
        // 兜底：弹窗被系统关闭时重开本关
        _startLevel(_level);
    }
  }

  // ==================== 关卡选择 ====================

  void _openLevels() {
    // 选关弹窗打开期间先暂停本局，避免一边选关一边被漏怪
    final wasPaused = _paused;
    _closeMenu();
    if (!wasPaused) setState(() => _paused = true);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4E7EC),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '选择关卡',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                for (final level in defenseLevels)
                  _LevelRow(
                    level: level,
                    locked: level.index > _maxUnlocked,
                    current: level.index == _level,
                    cleared: level.index <= _cleared,
                    onTap: level.index > _maxUnlocked
                        ? null
                        : () {
                            Navigator.of(ctx).pop();
                            _startLevel(level.index);
                          },
                  ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      if (!mounted) return;
      // 只是收起弹窗（没切关）时恢复原状态；切关时 _startLevel 已重置
      if (!wasPaused && _paused) setState(() => _paused = false);
    });
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            _hud(),
            Expanded(child: _board()),
            _hintBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final levelPill = GestureDetector(
      onTap: _openLevels,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '第 $_level 关',
          style: const TextStyle(
            color: _cyanText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    final pauseButton = GestureDetector(
      onTap: () {
        if (!_paused) _closeMenu();
        setState(() => _paused = !_paused);
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          size: 18,
          color: const Color(0xFF3C3C43),
        ),
      ),
    );

    // 用 Row 而不是 Stack：标题与右侧按钮各占各的位置，
    // 大字号 / 窄屏时标题自动省略，不会层叠到关卡按钮上
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            const AppBackButton(),
            const SizedBox(width: 4),
            const Expanded(
              child: Text(
                '吨吨守卫战',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF3C3C43),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            levelPill,
            const SizedBox(width: 8),
            pauseButton,
          ],
        ),
      ),
    );
  }

  static const _cyanText = Color(0xFF3FA9CB);

  Widget _hud() {
    final next = _game.nextWaveIn;
    final remain = _game.remainingEnemies;
    // 第一波开始前 currentWave 还是 0，显示成 1/N 更符合“即将第 1 波”
    final waveShown = _game.currentWave <= 0 ? 1 : _game.currentWave;
    final status = !_game.isPlaying
        ? ''
        : !_game.started
        ? '布阵阶段 · 点出口的「开始」再召唤怪兽'
        : remain == 0 && next > 0
        ? (_game.currentWave <= 0
              ? '缺水怪兽来袭 · ${next.ceil()} 秒后到达'
              : '本波已清空 · 下一波 ${next.ceil()} 秒后到达')
        : remain > 0 && next > 0
        ? '本波剩余 $remain 只 · ${next.ceil()} 秒后下一波'
        : remain > 0
        ? (_game.currentWave >= _game.waveCount
              ? '最后一波 · 还剩 $remain 只怪兽'
              : '怪兽正在冲向水杯 · 还剩 $remain 只')
        : '正在结算…';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
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
                Expanded(
                  child: _HudChip(
                    icon: Icons.local_drink_rounded,
                    iconColor: _brandCyan,
                    value: '${_game.lives}',
                    label: '水杯水量',
                  ),
                ),
                Expanded(
                  child: _HudChip(
                    icon: Icons.water_drop_rounded,
                    iconColor: const Color(0xFFE8B44A),
                    value: '${_game.gold}',
                    label: '水滴币',
                  ),
                ),
                Expanded(
                  child: _HudChip(
                    icon: Icons.waves_rounded,
                    iconColor: const Color(0xFF6C8AE4),
                    value: '$waveShown/${_game.waveCount}',
                    label: '波次',
                  ),
                ),
                Expanded(
                  child: _HudChip(
                    icon: Icons.shield_rounded,
                    iconColor: const Color(0xFF9B7BE8),
                    value: '${_game.kills}',
                    label: '击退怪兽',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF9B9BA1), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _board() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = math.min(
          constraints.maxWidth / defenseCols,
          constraints.maxHeight / defenseRows,
        );
        final width = cell * defenseCols;
        final height = cell * defenseRows;
        return Center(
          child: Container(
            key: const ValueKey('defense-board'),
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFDDEEF5)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A4DB8D8),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _handleTap(d.localPosition, cell),
                  child: CustomPaint(
                    size: Size(width, height),
                    painter: DefensePainter(
                      game: _game,
                      selectedTower: _selectedTower,
                      repaint: _repaint,
                    ),
                  ),
                ),
                if (_game.isPlaying && !_game.started && !_paused)
                  _startMarker(cell, width, height),
                ..._menuLayers(cell, width, height),
                if (_paused)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => setState(() => _paused = false),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.28),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.pause_circle_filled_rounded,
                              color: Colors.white,
                              size: 44,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '已暂停',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '点击继续游戏',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 底部操作提示 + 炮塔图例（建塔改为点炮位弹面板，这里只做说明）
  Widget _hintBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (final type in DefenseTowerType.values)
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_towerIcon(type), size: 15, color: Color(type.color)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${type.label} ${type.cost}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF3C3C43),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '点虚线炮位选塔建造 · 点已建炮塔升级 / 出售',
            style: TextStyle(color: Color(0xFF9B9BA1), fontSize: 11),
          ),
        ],
      ),
    );
  }

  IconData _towerIcon(DefenseTowerType type) => switch (type) {
    DefenseTowerType.droplet => Icons.water_drop_rounded,
    DefenseTowerType.cannon => Icons.emoji_food_beverage_rounded,
    DefenseTowerType.ice => Icons.ac_unit_rounded,
  };
}

/// HUD 单项（图标 + 数字 + 说明）
class _HudChip extends StatelessWidget {
  const _HudChip({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: iconColor),
            const SizedBox(width: 3),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Color(0xFF3C3C43),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF9B9BA1), fontSize: 11),
        ),
      ],
    );
  }
}

/// 原地菜单里的单个炮塔选项
class _MenuTowerOption extends StatelessWidget {
  const _MenuTowerOption({
    required this.type,
    required this.affordable,
    required this.onTap,
  });

  final DefenseTowerType type;
  final bool affordable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(type.color);
    return GestureDetector(
      onTap: affordable ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: affordable ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.26),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Icon(
                  switch (type) {
                    DefenseTowerType.droplet => Icons.water_drop_rounded,
                    DefenseTowerType.cannon => Icons.emoji_food_beverage_rounded,
                    DefenseTowerType.ice => Icons.ac_unit_rounded,
                  },
                  size: 16,
                  color: color,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                type.label,
                maxLines: 1,
                style: const TextStyle(
                  color: Color(0xFF171A26),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.water_drop_rounded,
                    size: 9,
                    color: Color(0xFFE8B44A),
                  ),
                  const SizedBox(width: 1),
                  Text(
                    '${type.cost}',
                    style: TextStyle(
                      color: affordable
                          ? const Color(0xFF3C3C43)
                          : const Color(0xFFEF6B6B),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
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
}

/// 原地菜单里的主操作按钮（升级 / 出售）
class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.color,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = filled
        ? (enabled ? Colors.white : const Color(0xFF9B9BA1))
        : color;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: filled
              ? (enabled ? color : const Color(0xFFEDEFF2))
              : color.withValues(alpha: enabled ? 0.16 : 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: textColor),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 关卡选择行
class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.level,
    required this.locked,
    required this.current,
    required this.cleared,
    required this.onTap,
  });

  final DefenseLevel level;
  final bool locked;
  final bool current;
  final bool cleared;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cyan = const Color(0xFF4DB8D8);
    final hint = locked
        ? '通过上一关解锁'
        : current
        ? '进行中'
        : cleared
        ? '已通关'
        : '可挑战';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: current ? cyan.withValues(alpha: 0.1) : const Color(0xFFF7F9FB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: current ? cyan : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: locked ? const Color(0xFFE9ECF0) : cyan.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: locked
                  ? const Icon(
                      Icons.lock_rounded,
                      size: 14,
                      color: Color(0xFF9B9BA1),
                    )
                  : Text(
                      '${level.index}',
                      style: TextStyle(
                        color: current ? cyan : const Color(0xFF3C3C43),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '第 ${level.index} 关 · ${level.name}',
                    style: TextStyle(
                      color: locked ? const Color(0xFF9B9BA1) : const Color(0xFF171A26),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${level.waves.length} 波 · ${level.slots.length} 个炮位',
                    style: const TextStyle(color: Color(0xFF9B9BA1), fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              hint,
              style: TextStyle(
                color: locked ? const Color(0xFFB4BAC4) : const Color(0xFF8E8E93),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
