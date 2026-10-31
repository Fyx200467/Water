import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/storage/providers.dart';
import '../../shared/models/beverage.dart';
import '../../shared/models/drink_entry.dart';
import '../../shared/models/preferred_unit.dart';
import '../../shared/widgets/sparkles_text.dart';
import '../settings/widget_settings_screen.dart';
import '../characters/character_art.dart';
import '../characters/character_collection_provider.dart';
import '../characters/current_character_provider.dart';
import '../drink/providers/beverage_catalog_provider.dart';
import '../drink/providers/custom_beverage_provider.dart';
import '../drink/services/hydration_calculator.dart';
import '../membership/membership_provider.dart';
import '../onboarding/widgets/animal_silhouette.dart';
import '../settings/settings_flags.dart';
import '../stats/history_screen.dart';
import '../stats/providers/stats_providers.dart';
import 'habit_module.dart';
import 'confetti_rain.dart';
import 'daily_review_screen.dart';
import 'providers/home_providers.dart';
import 'widgets/slingshot_track.dart';

/// PRD §2.2 首页（对标原版 WaterLlama 主页）
///
/// 布局（自上而下）：
/// 1. 顶部：左上"1 天"青色圆形徽章 + 右上菜单按钮
/// 2. 核心数据：青色大字"{totalMl}" + 灰色"进水量·{percent}% 的目标"
/// 3. 中央：大羊驼剪影（空杯态浅灰 + 按进度纯青色填充 + 波浪水面晃动）
/// 4. 底部操作栏：水杯按钮(+) / "+98 种物品和功能"胶囊 / 羊驼头像(+)
/// 5. 最底部：浅青色圆角横幅"滴酒不沾的十月"挑战
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  // 品牌色规范
  static const _brandCyan = Color(0xFF4DB8D8);
  static const _hintGray = Color(0xFF8E8E93);

  /// 小组件同步防抖计时器（冷启动延迟 1 秒等 provider 首载；数据变化
  /// 时复用同一计时器去抖，1 秒内多次变化只推一次）
  Timer? _widgetSyncTimer;

  /// 小组件点击事件订阅（热启动 onNewIntent 转发）
  StreamSubscription<Uri?>? _widgetClickSub;

  final ScrollController _scrollCtrl = ScrollController();

  /// 习惯卡堆叠效果用：把滚动像素透传给卡牌区（堆叠位置按滚动实时计算）
  final ValueNotifier<double> _scrollPixels = ValueNotifier(0);

  /// 弹弓发射命中检测用：角色卡片 bounds 的全局 key
  final GlobalKey _animalKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollCtrl.addListener(_onScroll);
    // 冷启动延迟 1 秒同步一次桌面小组件
    _scheduleWidgetSync();
    // 数据驱动同步：今日记录或连续天数一变就防抖推送小组件——覆盖
    // App 内手动加饮、历史页补录昨日记录（连签到天数变但今日量不变）、
    // 目标修改等所有入口，小组件与 App 始终实时一致（此前只在冷启动
    // 同步一次，补录历史后小组件天数不更新的根因）
    ref.listenManual(todayEntriesProvider, (_, __) => _scheduleWidgetSync());
    ref.listenManual(checkinDaysProvider, (_, __) => _scheduleWidgetSync());
    // 桌面小组件饮料格点击快速录入（冷启动 URI + 热启动事件流）
    HomeWidget.initiallyLaunchedFromHomeWidget().then(
      (uri) => _handleWidgetLaunch(uri),
    );
    _widgetClickSub = HomeWidget.widgetClicked.listen(_handleWidgetLaunch);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetSyncTimer?.cancel();
    _widgetClickSub?.cancel();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _scrollPixels.dispose();
    super.dispose();
  }

  /// 回前台重载当日记录：小组件饮品格后台录入（独立 isolate 写库、
  /// 不拉起 App）后，进程存活期间的内存态需要追平
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeRefresh());
    }
  }

  /// 回前台追平后台写入：先 reload 磁盘偏好（后台 isolate/原生侧写过
  /// prefs，主进程缓存会滞后），再补录小组件队列、重载当日记录
  Future<void> _resumeRefresh() async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.reloadPrefs();
    if (!mounted) return;
    await _drainNativeWidgetAdds();
    if (!mounted) return;
    await ref.read(todayEntriesProvider.notifier).refresh();
    if (!mounted) return;
    // 回前台顺手拉一次云端饮品目录：后台改图标/加饮品无需重启 App
    ref.read(beverageCatalogProvider.notifier).refresh();
  }

  /// 排空原生快捷录入队列：vivo 冻结窗口内点按由 QuickAddReceiver 纯原生
  /// 写偏好（"slot:ml:ts:beverageId|..."）并即时重绘桌面，正式记录在这里补入 DB——
  /// 走与手动录入完全相同的 DrinkEntry.create 折算管线，统计/回看一致。
  /// 每成功补录一条即回写剩余队列（中途失败/被杀不会重复入账）；失败
  /// 保留当前及后续条目待下次重试（小组件数字以缓存累计，不丢数据）
  ///
  /// _draining 互斥：resume 与 1s 防抖同步会同时触发，并发 drain 会把同一
  /// 批条目各入账一次
  bool _draining = false;

  Future<void> _drainNativeWidgetAdds() async {
    if (_draining) return;
    _draining = true;
    try {
      final pending = await HomeWidget.getWidgetData<String>(
        'native_pending_adds',
      );
      if (pending == null || pending.isEmpty) return;
      // 等槽位配置与自定义饮品加载完成（冷启动早期必然经历这个窗口）
      await ref.read(widgetSettingsProvider.notifier).loaded;
      await ref.read(customBeveragesProvider.notifier).loaded;
      await ref.read(beverageCatalogProvider.notifier).loaded;
      final s = ref.read(widgetSettingsProvider);
      final all = ref.read(beverageLibraryProvider);
      final items = pending.split('|').where((e) => e.isNotEmpty).toList();
      var lockedDropped = 0;
      for (var i = 0; i < items.length; i++) {
        final parts = items[i].split(':');
        // 兼容旧格式（3 段，无饮品 id）与新格式（4 段）
        if (parts.length < 3) continue;
        final slot = int.tryParse(parts[0]);
        final ml = int.tryParse(parts[1]);
        final ts = int.tryParse(parts[2]);
        if (slot == null || ml == null || ml <= 0) continue;
        if (slot < 1 || slot > 3) continue;
        // 优先用点按当时下发的饮品 id（用户之后改配置也不会入错饮品）
        final carriedId = parts.length >= 4 ? parts[3] : null;
        final fallbackId = switch (slot) {
          1 => s.drink1,
          2 => s.drink2,
          _ => s.drink3,
        };
        Beverage? carried;
        if (carriedId != null && carriedId.isNotEmpty) {
          for (final x in all) {
            if (x.id == carriedId) {
              carried = x;
              break;
            }
          }
        }
        // 按槽位配置的饮品兜底；饮品库为空（账号切换/目录未就绪）时
        // 必须保留队列等下次重试——此前 `all.first` 会抛 StateError，
        // 导致整批补录中止
        var beverage = carried;
        if (beverage == null) {
          for (final x in all) {
            if (x.id == fallbackId) {
              beverage = x;
              break;
            }
          }
        }
        beverage ??= all.isEmpty ? null : all.first;
        if (beverage == null) {
          debugPrint('[home] beverage library empty, keep pending adds');
          return;
        }
        // 会员专属饮品：非会员的桌面小组件入账不能静默丢弃（桌面数字已
        // 累加），这里丢弃并计数，结束后按真实数据矫正桌面
        if (beverage.lockedFor(ref.read(membershipProvider).isMember)) {
          lockedDropped += 1;
          final rest = items.sublist(i + 1);
          await HomeWidget.saveWidgetData<String>(
            'native_pending_adds',
            rest.isEmpty ? null : rest.join('|'),
          );
          continue;
        }
        try {
          await ref
              .read(todayEntriesProvider.notifier)
              .add(
                DrinkEntry.create(
                  beverage: beverage,
                  volumeMl: ml,
                  drankAt: ts == null
                      ? null
                      : DateTime.fromMillisecondsSinceEpoch(ts),
                  // 幂等主键：「槽位 + 点按时间戳」同一次点按重放时覆盖
                  // 同一条记录（回写队列失败/并发 drain 不会重复入账）
                  clientId: ts == null ? null : 'widget-$slot-$ts',
                ),
              );
        } catch (e) {
          // 入库失败：保留本条及后续条目，下次前台再重试
          debugPrint('[home] drain native widget add failed: $e');
          return;
        }
        final rest = items.sublist(i + 1);
        await HomeWidget.saveWidgetData<String>(
          'native_pending_adds',
          rest.isEmpty ? null : rest.join('|'),
        );
      }
      if (lockedDropped > 0) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text('有 $lockedDropped 次小组件饮水属于会员专属饮品，未记录')),
          );
        }
        // 桌面数字已按原生快速路径累加，丢弃后要推一次真实数据矫正
        _scheduleWidgetSync();
      }
    } catch (e) {
      debugPrint('[home] drain native widget adds failed: $e');
    } finally {
      _draining = false;
    }
  }

  /// 滚动联动：把滚动像素透传给习惯卡堆叠区
  void _onScroll() {
    _scrollPixels.value = _scrollCtrl.offset;
  }

  /// 防抖调度小组件同步：复用 _widgetSyncTimer，1 秒内的连续变化
  /// （如批量补录）只触发最后一次推送
  void _scheduleWidgetSync() {
    _widgetSyncTimer?.cancel();
    _widgetSyncTimer = Timer(const Duration(seconds: 1), _syncHomeWidget);
  }

  /// 同步桌面小组件：补录原生点按队列 → 读取今日合计 / 目标 / 连续签到
  /// 推送刷新（冷启动 1s + 数据变化防抖 1s 双入口）
  Future<void> _syncHomeWidget() async {
    if (!mounted) return;
    // 先补录原生快捷录入队列，保证冷启动即看到点按累计的水量
    await _drainNativeWidgetAdds();
    if (!mounted) return;
    final goalMl = ref.read(profileProvider)?.dailyGoalMl ?? 2000;
    final todayMl = HydrationCalculator.sumEffective(
      ref.read(todayEntriesProvider),
    );
    final streak = await ref.read(checkinDaysProvider.future);
    if (!mounted) return;
    await syncWidgetFromSettings(
      ref.read,
      todayMl: todayMl,
      goalMl: goalMl,
      streakDays: streak,
    );
  }

  /// 处理小组件饮料格点击：`waterllama://quick-add?slot={1..3}`
  void _handleWidgetLaunch(Uri? uri) {
    if (uri == null || uri.host != 'quick-add') return;
    final slot = int.tryParse(uri.queryParameters['slot'] ?? '');
    if (slot == null || slot < 1 || slot > 3) return;
    _quickAddFromWidget(slot);
  }

  /// 小组件快速录入：按槽位映射小组件设置的饮品与容量，
  /// 走与手动录入完全相同的 DrinkEntry.create 折算管线
  Future<void> _quickAddFromWidget(int slot) async {
    if (!mounted) return;
    final s = ref.read(widgetSettingsProvider);
    // 三个槽位固定映射小组件设置的饮品与容量
    final (String id, int vol) = switch (slot) {
      1 => (s.drink1, s.vol1),
      2 => (s.drink2, s.vol2),
      _ => (s.drink3, s.vol3),
    };
    if (vol <= 0) return;
    final all = ref.read(beverageLibraryProvider);
    final b = all.firstWhere((x) => x.id == id, orElse: () => all.first);
    final entry = DrinkEntry.create(beverage: b, volumeMl: vol);
    await ref.read(todayEntriesProvider.notifier).add(entry);
    final streak = await ref.read(checkinDaysProvider.future);
    if (!mounted) return;
    await syncWidgetFromSettings(
      ref.read,
      todayMl: HydrationCalculator.sumEffective(ref.read(todayEntriesProvider)),
      goalMl: ref.read(profileProvider)?.dailyGoalMl ?? 2000,
      streakDays: streak,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已通过桌面小组件录入 ${b.name} ${UnitFormat.volume(vol, compact: true)}',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 根据当前时间返回"星期一"~"星期日"（用于完成态文案"完美星期X"）
  String _weekdayName() {
    const names = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return names[DateTime.now().weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(dailyProgressProvider);
    final checkin = ref.watch(checkinDaysProvider);
    final currentChar = ref.watch(effectiveCurrentCharacterProvider);
    // 保持收集进度常驻监听：喝水跨过 2000ml 里程碑即随机点亮角色
    ref.watch(characterCollectionProvider);
    // 单位切换后首页数字需要立即按新单位重绘
    ref.watch(preferredUnitProvider);

    // 目标完成后角色保持彩色点亮态，不再 2 秒后自动恢复
    final isLit = progress.isComplete;
    final percent = (progress.progress * 100).round();
    final done = progress.isComplete;

    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.white,
      // 内容直接铺到状态栏下方（edge-to-edge）：上滑时页面从状态栏下穿过，
      // 不会被顶部白条裁掉；悬浮按钮单独下移，让出状态栏高度
      body: Stack(
        children: [
          // 底层：可滚动内容（第一屏铺满视口，习惯模块从下一屏开始）
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, cons) => CustomScrollView(
                controller: _scrollCtrl,
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: cons.maxHeight,
                      child: Column(
                        children: [
                          // 给悬浮按钮 + 状态栏留出空间
                          SizedBox(height: 64 + topInset),
                          // 1. 核心数据：完成时显示"完美星期X！"+ml·%目标；未完成时显示原数字
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              children: [
                                if (done) ...[
                                  // 完成态：庆祝文案（星期X 取自系统时间）
                                  // 达标瞬间起常驻闪耀星光
                                  SparklesText(
                                    child: Text(
                                      '完美${_weekdayName()}',
                                      style: const TextStyle(
                                        color: _brandCyan,
                                        fontSize: 40,
                                        fontWeight: FontWeight.w800,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SparklesText(
                                    count: 6,
                                    seed: 19,
                                    child: Text(
                                      '${UnitFormat.volume(progress.totalEffectiveMl, compact: true)} 进水量 · $percent% 的目标',
                                      style: const TextStyle(
                                        color: _hintGray,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ] else ...[
                                  // 未完成态：原版数据文案（液面高光扫过）；
                                  // 数字滚动：从旧值慢慢数到新值（回首页才播）
                                  _DeferredTween(
                                    end: progress.totalEffectiveMl.toDouble(),
                                    duration: const Duration(milliseconds: 700),
                                    curve: Curves.easeOutCubic,
                                    builder: (_, v) => _LiquidShimmerText(
                                      text: UnitFormat.volume(v, compact: true),
                                      style: const TextStyle(
                                        color: _brandCyan,
                                        fontSize: 56,
                                        fontWeight: FontWeight.w800,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '进水量 · $percent% 的目标',
                                    style: const TextStyle(
                                      color: _hintGray,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 2. 中央：大羊驼剪影（弹性区域撑开）
                          Expanded(
                            child: Center(
                              child: Container(
                                key: _animalKey,
                                // 液面过渡：返回首页后液体从旧液位慢慢
                                // 涨到新液位（1.1s easeOut，非跳变）
                                child: _DeferredTween(
                                  end: progress.progress.clamp(0.0, 1.0),
                                  duration: const Duration(milliseconds: 1100),
                                  curve: Curves.easeOutCubic,
                                  builder: (_, v) => AnimalSilhouette(
                                    animalId: currentChar,
                                    fillRatio: v,
                                    accentColor: _brandCyan,
                                    solidFillColor: _brandCyan,
                                    size: 280,
                                    // 点亮态显示全彩插画，否则剪影+液体填充
                                    fullArt: isLit,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 2.5 完成态庆祝横幅「告诉我的朋友！」（celebrateDay 开关控制显隐；
                          //     点击进入「今日回顾」庆祝海报页）
                          if (done) _CelebrateBanner(animalId: currentChar),
                          const SizedBox(height: 8),
                          // 3. 底部饮品栏：固定为弧线轨道（弹弓发射水滴击中角色）
                          Transform.translate(
                            offset: const Offset(0, -26),
                            child: SlingshotDrinkTrack(
                              targetKey: _animalKey,
                              height: 206,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 5. 习惯挑战列表（养成健康的日常习惯 N/9）
                  SliverToBoxAdapter(
                    child: HabitModule(scrollPixels: _scrollPixels),
                  ),
                  // 6. 页面到底提示
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            'assets/icons/home/bottom_tip.svg',
                            width: 18,
                            height: 18,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '到底啦',
                            style: TextStyle(
                              color: Color(0xFFB0B0B5),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 末端留出系统导航栏安全区（内容已铺到屏幕底部）
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.paddingOf(context).bottom,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 顶层：悬浮按钮（不随内容滚动），下移状态栏高度避免被遮挡
          Positioned(
            top: topInset + 8,
            left: 20,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 左上角：天数徽章（外圈进度环 + 启动展开动画）→ 打开历史记录页
                // 签到天数 = 当天打开过 App 即记录一天
                // 完成态时在「天数」和「✓」之间循环切换（持续，不是只点亮时）
                checkin.maybeWhen(
                  data: (days) => _DayBadge(
                    days: days,
                    progress: progress.progress,
                    showCycle: done,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
                    ),
                  ),
                  orElse: () => _DayBadge(
                    days: 0,
                    progress: progress.progress,
                    onTap: null,
                  ),
                ),
                // 右上角：菜单按钮（三根波浪线，尺寸与左上角徽章按钮一致）
                IconButton(
                  onPressed: () => context.push('/settings'),
                  constraints: const BoxConstraints.tightFor(
                    width: 42,
                    height: 42,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const CustomPaint(
                    size: Size(32, 24),
                    painter: _MenuWavesPainter(),
                  ),
                ),
              ],
            ),
          ),
          // 礼炮彩带层：完成态时持续从屏幕上方飘落（不阻挡点击）
          Positioned.fill(
            child: IgnorePointer(child: ConfettiRain(active: done)),
          ),
        ],
      ),
    );
  }
}

/// 徽章按钮本体高度（圆形直径 / 胶囊高度），按钮与进度环共用
const double _kBadgeH = 34;

/// 左上角青色天数徽章（点击打开历史记录页）
/// - 外圈进度环：实时显示当日饮水量进度，0ml 时顶部只显示一个小圆点（对标原版）
/// - 启动动画：先横向展开为胶囊显示完整「N 天」，1.5 秒后收回圆形只显示「N」
/// - showCycle=true（完成当日目标）时在「天数」和「✓」之间循环切换（每 2 秒）
class _DayBadge extends StatefulWidget {
  const _DayBadge({
    required this.days,
    required this.progress,
    this.showCycle = false,
    this.onTap,
  });
  final int days;

  /// 当日饮水进度（0.0~1.0），驱动外圈进度环
  final double progress;
  final bool showCycle;
  final VoidCallback? onTap;

  @override
  State<_DayBadge> createState() => _DayBadgeState();
}

class _DayBadgeState extends State<_DayBadge> {
  bool _showCheck = false;
  bool _expanded = false; // 进入首页先显示圆形，1 秒后再展开
  Timer? _toggleTimer;
  Timer? _expandTimer;
  Timer? _collapseTimer;

  @override
  void initState() {
    super.initState();
    // 启动动画时序：进入首页 1 秒后展开为胶囊「N 天」，保持 1.5 秒后收回圆形
    _expandTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _expanded = true);
      _collapseTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _expanded = false);
      });
    });
    if (widget.showCycle) _startToggle();
  }

  @override
  void didUpdateWidget(covariant _DayBadge old) {
    super.didUpdateWidget(old);
    if (widget.showCycle && !old.showCycle) {
      _startToggle();
    } else if (!widget.showCycle && old.showCycle) {
      _stopToggle();
      if (_showCheck) setState(() => _showCheck = false);
    }
  }

  void _startToggle() {
    _toggleTimer?.cancel();
    _toggleTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() => _showCheck = !_showCheck);
    });
  }

  void _stopToggle() {
    _toggleTimer?.cancel();
    _toggleTimer = null;
  }

  @override
  void dispose() {
    _stopToggle();
    _expandTimer?.cancel();
    _collapseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showCheck = widget.showCycle && _showCheck;
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 88.0 + _extraWidth,
        height: 42,
        // 宽度动画驱动：每帧重建按钮 + 进度环，环随形状逐帧变形（圆↔胶囊）
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: _shapeWidth),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          builder: (ctx, w, _) => Stack(
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.none,
            children: [
              // 外圈进度环：沿当前形状（圆/胶囊）的外轮廓描边
              // 扫过长度 = 当日饮水量进度，0ml 时顶部一个小圆点
              Positioned.fill(
                child: CustomPaint(
                  painter: _BadgeRingPainter(
                    progress: widget.progress.clamp(0.0, 1.0),
                    shapeWidth: w,
                  ),
                ),
              ),
              // 按钮本体：34（圆形）↔ 76（展开胶囊）
              Container(
                width: w,
                height: _kBadgeH,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF4DB8D8),
                  borderRadius: BorderRadius.circular(_kBadgeH / 2),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: showCheck
                      ? const Text(
                          '✓',
                          key: ValueKey('check'),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : _showExpandedContent(w)
                      ? Padding(
                          key: const ValueKey('full'),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          // 数字居左、「天」居右，对标原版展开态的宽松间距；
                          // 内容宽度固定为目标胶囊宽（不绑定当前帧宽 w）：
                          // 收回时出场子组件会被 AnimatedSwitcher 冻结，
                          // 若绑定 w 会被收缩中的容器钳制产生文字骤缩跳变；
                          // 固定宽度 + FittedBox 保证任意帧宽下连续缩放、绝不溢出
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: _shapeWidth - 36.0,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${widget.days}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Text(
                                    '天',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : Text(
                          '${widget.days}',
                          key: const ValueKey('num'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 天数每多一位数字，展开胶囊加宽 9（三位数「100 天」也不会挤压变形）
  int get _extraWidth => math.max(0, '${widget.days}'.length - 1) * 9;

  /// 按钮当前目标宽度（34=圆形，76+N*9=展开胶囊）
  double get _shapeWidth => _expanded ? 76.0 + _extraWidth : _kBadgeH;

  /// 展开内容仅在动画接近完成时切换：早期帧就显示会让文字缩得过小、观感差
  /// （溢出已由「固定内容宽度 + FittedBox」从根本上排除，此处阈值纯为观感）
  bool _showExpandedContent(double w) => _expanded && w >= _shapeWidth - 20;
}

/// 徽章外圈进度环：沿按钮当前形状（圆形/胶囊）外轮廓描边
/// - 外轮廓 = 按钮矩形外扩 0.2px 间隙 + 半描边的 stadium 轮廓（跟随展开动画逐帧变形）
/// - 起点固定在顶部 12 点方向，顺时针扫过（进度 × 周长）
/// - 解析几何逐段绘制（直线 + 四分之一圆弧），不依赖 PathMetrics：
///   其闭合轮廓起点在 Impeller 下会偏移，产生起点越过 12 点、端点凸起等伪影
/// - 0ml 时也画一小段（配合终点圆头呈现为顶部小圆点，对标原版）
class _BadgeRingPainter extends CustomPainter {
  _BadgeRingPainter({required this.progress, required this.shapeWidth});
  final double progress;

  /// 按钮当前宽度（含动画中间帧）
  final double shapeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    const double stroke = 3.5;
    const double gap = 0.8; // 环内沿与按钮边缘的间距（贴近浑然一体）

    final m = gap + stroke / 2; // 按钮边缘到环中心线的距离
    final center = Offset(shapeWidth / 2, size.height / 2);
    final halfW = shapeWidth / 2 + m;
    final r = _kBadgeH / 2 + m; // 圆角半径（stadium 形：= 半高 + 外扩）
    final straight = halfW - r; // 顶/底边单侧直线长（圆形态为 0）

    // 进度环用比按钮更深一档的蓝色，拉开层次（按钮 0xFF4DB8D8 浅水色）
    final ringColor = const Color(0xFF2E93B8);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..color = ringColor;
    final capPaint = Paint()..color = ringColor;

    // 周长 = 4 段直线 + 4 段四分之一圆弧
    final q = math.pi / 2 * r;
    final total = 4 * straight + 4 * q;
    // 0 进度也画总长的 2%（配合终点圆头呈现为顶部正中小圆点，对标原版 0ml 态）
    var remain = math.max(progress.clamp(0.0, 1.0) * total, total * 0.02);

    // 当前绘制端点：从 12 点整出发，随各段推进
    var cap = Offset(center.dx, center.dy - r);

    // 直线段：dirX=±1（水平），长度 len
    void lineSeg(double dirX, double len) {
      if (remain <= 0) return;
      final d = math.min(remain, len);
      if (d <= 0) return;
      final to = cap + Offset(dirX * d, 0);
      canvas.drawLine(cap, to, paint);
      cap = to;
      remain -= d;
    }

    // 圆弧段：半圆圆心 x = circleCx（y 与按钮中心同高），起始角 startAngle，弧长 len
    void arcSeg(double circleCx, double startAngle, double len) {
      if (remain <= 0) return;
      final d = math.min(remain, len);
      if (d <= 0) return;
      final c = Offset(circleCx, center.dy);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        startAngle,
        d / r,
        false,
        paint,
      );
      final a = startAngle + d / r;
      cap = c + Offset(r * math.cos(a), r * math.sin(a));
      remain -= d;
    }

    // 顺时针从 12 点整逐段推进（各段切线连续，端点精确衔接）
    final rightCx = center.dx + straight; // 右半圆圆心
    final leftCx = center.dx - straight; // 左半圆圆心
    lineSeg(1, straight); // 上半右直线 →
    arcSeg(rightCx, -math.pi / 2, q); // 右上四分之一弧 ↘
    arcSeg(rightCx, 0, q); // 右下四分之一弧 ↙
    lineSeg(-1, 2 * straight); // 下边直线（右→左）
    arcSeg(leftCx, math.pi / 2, q); // 左下四分之一弧 ↖
    arcSeg(leftCx, math.pi, q); // 左上四分之一弧 ↗
    lineSeg(1, straight); // 上半左直线（回到 12 点整）

    // 终点补圆头：0 进度时呈现为顶部小圆点，满进度时在 12 点整圆润收口
    canvas.drawCircle(cap, stroke / 2, capPaint);
  }

  @override
  bool shouldRepaint(covariant _BadgeRingPainter old) =>
      old.progress != progress || old.shapeWidth != shapeWidth;
}

/// 单根波浪线参数
class _Wave {
  const _Wave({
    required this.y,
    required this.amp,
    required this.cycles,
    required this.phase,
  });
  final double y; // 垂直基线位置（占高度比例）
  final double amp; // 振幅（px）
  final double cycles; // 波峰周期数
  final double phase; // 相位偏移（rad）
}

/// 右上角菜单按钮图标：三根波浪线（替代三横线，水波意象呼应喝水主题）
///
/// 对标原版：三根等长同形、左右对齐的密集波浪线，深灰粗线无背景
class _MenuWavesPainter extends CustomPainter {
  const _MenuWavesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF636E78);

    // 三根线同形同相、等长对齐，密集波峰如「≈」，叠出整齐的水波层次
    const waves = [
      _Wave(y: 0.16, amp: 1.9, cycles: 1.75, phase: 0.0),
      _Wave(y: 0.50, amp: 1.9, cycles: 1.75, phase: 0.0),
      _Wave(y: 0.84, amp: 1.9, cycles: 1.75, phase: 0.0),
    ];
    for (final w in waves) {
      final baseY = size.height * w.y;
      final path = Path()..moveTo(0, baseY);
      const steps = 48;
      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        path.lineTo(
          size.width * t,
          baseY + w.amp * math.sin(2 * math.pi * w.cycles * t + w.phase),
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MenuWavesPainter oldDelegate) => false;
}

/// 延迟过渡动画（首页专用）：end 变化时若首页正被上层页面遮盖
/// （如加量页），挂起过渡，待返回首页（上层路由关闭完成）后再从
/// 当前值慢慢动画到新值；页面可见时立即过渡。用于角色液面与总量
/// 数字——「加完水返回首页」看到液体上涨 / 数字滚动的过程而非跳变
class _DeferredTween extends StatefulWidget {
  const _DeferredTween({
    required this.end,
    required this.duration,
    required this.curve,
    required this.builder,
  });

  final double end;
  final Duration duration;
  final Curve curve;
  final Widget Function(BuildContext context, double value) builder;

  @override
  State<_DeferredTween> createState() => _DeferredTweenState();
}

class _DeferredTweenState extends State<_DeferredTween>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late double _value;
  double _from = 0;
  double _to = 0;

  /// 被上层页面遮盖期间发生了数据变化：回首页后补播
  bool _pending = false;
  Animation<double>? _secondary;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _value = widget.end; // 首帧直接定格，无进场动画
    _ctrl.addListener(() {
      final t = widget.curve.transform(_ctrl.value);
      setState(() => _value = _from + (_to - _from) * t);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sec = ModalRoute.of(context)?.secondaryAnimation;
    if (!identical(sec, _secondary)) {
      _secondary?.removeStatusListener(_onSecondaryStatus);
      _secondary = sec;
      sec?.addStatusListener(_onSecondaryStatus);
    }
  }

  /// 上层页面（加量页）pop 关闭完成回到首页 → 补播挂起的过渡
  void _onSecondaryStatus(AnimationStatus st) {
    if (st == AnimationStatus.dismissed && _pending && mounted) {
      _pending = false;
      _start();
    }
  }

  @override
  void didUpdateWidget(_DeferredTween oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.end != oldWidget.end) {
      if (ModalRoute.of(context)?.isCurrent ?? true) {
        _start();
      } else {
        _pending = true; // 被加量页遮盖：返回首页后再播（期间显示旧值）
      }
    }
  }

  void _start() {
    _from = _value;
    _to = widget.end;
    _ctrl
      ..duration = widget.duration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _secondary?.removeStatusListener(_onSecondaryStatus);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 兜底补播：数据在被上层页面/弹窗遮盖期间发生变化，而遮盖是通过
    // 非动画方式撤掉的（如顶号弹窗期间 Provider 整体刷新），这里在当前
    // 路由重回前台时补一次过渡，避免数字/液面长期停留在旧值。
    if (_pending && (ModalRoute.of(context)?.isCurrent ?? true)) {
      _pending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }
    return widget.builder(context, _value);
  }
}

/// 顶部总量数字的「液面高光」：柔和白色亮带每 2 秒自左向右扫过字体，
/// 仿液体表面反光流动；ShaderMask 只重着色亮带经过的区域，
/// 字色保持品牌青不变
class _LiquidShimmerText extends StatefulWidget {
  const _LiquidShimmerText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_LiquidShimmerText> createState() => _LiquidShimmerTextState();
}

class _LiquidShimmerTextState extends State<_LiquidShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    // 一轮 4s：前一半时间光带扫过（约 2s），后一半完全静止
    duration: const Duration(milliseconds: 4000),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        // 前半周期扫光，后半周期停在字外（亮带不可见）
        final sweep = (_ctrl.value / 0.5).clamp(0.0, 1.0);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            // 亮带：透明 → 白 → 透明（软边光带，占画框 40% 宽）
            colors: [
              Colors.transparent,
              Colors.white.withOpacity(0.25),
              Colors.transparent,
            ],
            stops: const [0.3, 0.5, 0.7],
            transform: _SlidingHighlightTransform(
              shift: Curves.easeInOut.transform(sweep),
            ),
          ).createShader(bounds),
          child: Text(widget.text, style: widget.style),
        );
      },
    );
  }
}

/// 高光带平移：shift 0→1 时亮带中心从画框左侧外滑到右侧外
/// （t 从 -1.5w 到 +1.5w，首尾帧亮带完全在字外，循环无跳变）
class _SlidingHighlightTransform extends GradientTransform {
  const _SlidingHighlightTransform({required this.shift});

  final double shift;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (shift * 3 - 1.5), 0, 0);
}

/// 完成态庆祝横幅（角色卡与饮品栏之间，单条不翻页）
/// - 黑色胶囊「告诉我的朋友！」按钮（白方块溢出胶囊左端，内青色角色剪影）
///   —— 受设置页 celebrateDay 开关控制，关闭时不渲染
/// - 点击进入「今日回顾」庆祝海报页（DailyReviewScreen）
class _CelebrateBanner extends StatelessWidget {
  const _CelebrateBanner({required this.animalId});

  final String animalId;

  void _openReview(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DailyReviewScreen(animalId: animalId)),
    );
  }

  /// 青色角色剪影（白色方块内）
  Widget _cyanSilhouette(double size) => ColorFiltered(
    colorFilter: const ColorFilter.mode(Color(0xFF4DB8D8), BlendMode.srcIn),
    child: CharacterArt(animalId: animalId, unlocked: false, size: size),
  );

  /// 黑色胶囊庆祝按钮——固定 280 宽与上方角色对齐、水平居中，
  /// 双层斜卡片层叠在胶囊左端上方；点击进入今日回顾页
  Widget _celebrateButton(BuildContext context) => Center(
    child: GestureDetector(
      onTap: () => _openReview(context),
      child: SizedBox(
        width: 280,
        height: 66,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // 黑色胶囊：占满 280 宽（卡片下方）
            Positioned(
              left: 12,
              right: 0,
              top: 7,
              bottom: 7,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C22),
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.only(left: 70),
                child: const Text(
                  '告诉我的朋友！',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            // 双层斜卡片：浅青外框 + 白色内芯（对标原版拍立得样式）
            Positioned(
              left: 0,
              child: Transform.rotate(
                angle: -0.1, // 约 -6°，对标原版斜置卡片
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCEFF6),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(5),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(child: _cyanSilhouette(40)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsFlags.instance,
      builder: (ctx, _) {
        // 「告诉我的朋友！」总开关：关闭后完成态庆祝横幅不出现（实时生效）
        if (!SettingsFlags.instance.celebrateDay) {
          return const SizedBox.shrink();
        }

        return _celebrateButton(context);
      },
    );
  }
}
