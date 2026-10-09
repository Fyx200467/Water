import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../drink/widgets/drink_input_sheet.dart';
import 'providers/home_providers.dart';
import 'widgets/fluid_canvas.dart';
import 'widgets/progress_ring.dart';

/// PRD §2.2 首页动物养成核心
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _waveCtrl;
  late final AnimationController _bounceCtrl;
  late final AnimationController _levelCtrl;
  late Animation<double> _levelAnim;
  double _prevProgress = 0;

  @override
  void initState() {
    super.initState();
    // PRD §4.1 60fps 流体动画
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _levelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _levelAnim = AlwaysStoppedAnimation(0);
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _bounceCtrl.dispose();
    _levelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(dailyProgressProvider);
    final animalAsync = ref.watch(dailyAnimalProvider);

    // 进度变化触发动画
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (progress.progress != _prevProgress) {
        _levelCtrl.value = 0;
        _levelAnim = Tween<double>(
          begin: _prevProgress,
          end: progress.progress,
        ).animate(CurvedAnimation(
          parent: _levelCtrl,
          curve: Curves.easeInOutCubicEmphasized,
        ));
        _levelCtrl.forward(from: 0);
        _bounceCtrl.forward(from: 0);
        _prevProgress = progress.progress;
      }
    });

    final theme = Theme.of(context);

    return animalAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('动物加载失败：$e')),
      ),
      data: (animal) {
        return Scaffold(
          appBar: AppBar(
            title: Text('${animal.name} · 今日养成',
                style: theme.textTheme.titleLarge),
            actions: [
              IconButton(
                icon: const Icon(Icons.calendar_month_outlined),
                tooltip: '数据统计',
                onPressed: () => context.push('/stats'),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: '设置',
                onPressed: () => context.push('/settings'),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_waveCtrl, _bounceCtrl, _levelCtrl]),
                    builder: (ctx, _) {
                      final curProgress = _levelAnim.value;
                      return Center(
                        child: ProgressRing(
                          progress: curProgress,
                          size: 320,
                          child: SizedBox(
                            width: 280, height: 280,
                            child: RepaintBoundary(
                              child: CustomPaint(
                                size: const Size(280, 280),
                                painter: FluidPainter(
                                  progress: curProgress,
                                  animal: animal,
                                  wavePhase: _waveCtrl.value * 2 * 3.1415926,
                                  bounce: _bounceCtrl.value,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${progress.totalEffectiveMl}',
                            style: theme.textTheme.displayMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              '/ ${progress.goalMl} ml',
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: progress.progress.clamp(0, 1),
                        minHeight: 10,
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            progress.isComplete
                                ? '今日已达成 · 太棒啦'
                                : '还差 ${progress.remaining} ml',
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(
                            '完成 ${(progress.progress * 100).round()}%',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (progress.entries.isNotEmpty)
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: progress.entries.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final e = progress.entries[i];
                        return Chip(
                          avatar: Icon(e.beverageCategory.icon, size: 18),
                          label: Text('${e.volumeMl}ml · ${e.beverageName}'),
                          labelStyle: theme.textTheme.labelSmall,
                          onDeleted: () => ref
                              .read(todayEntriesProvider.notifier)
                              .remove(e.clientId),
                        );
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: ElevatedButton.icon(
                    onPressed: () => DrinkInputSheet.show(context),
                    icon: const Icon(Icons.add_circle_outline, size: 28),
                    label: const Text('喝水'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
}
