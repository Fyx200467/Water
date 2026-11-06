import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/providers.dart';
import '../../shared/widgets/app_back_button.dart';
import '../home/providers/home_providers.dart';
import '../points/points_provider.dart';
import '../points/points_screen.dart';
import '../settings/cloud_backup_screen.dart';

/// 吨吨乐园：趣味小游戏 + 每日积分任务的聚合页
class PlaygroundScreen extends ConsumerWidget {
  const PlaygroundScreen({super.key});

  static const _bg = Color(0xFFF5FAFC);
  static const _ink = Color(0xFF171A26);
  static const _gray = Color(0xFF8E8E93);
  static const _sectionTitle = Color(0xFF6B7280);
  static const _cyan = Color(0xFF4DB8D8);
  /// 任务标题右侧的积分奖励小字（更小更淡）
  static const _rewardHint = Color(0xFFB4BAC4);

  /// 每日签到奖励
  static const int checkinPoints = 2;

  /// 今日饮水达标奖励
  static const int goalPoints = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(pointsProvider);
    final progress = ref.watch(dailyProgressProvider);
    final signedToday = points.hasEarnedToday('checkin');
    final goalClaimed = points.hasEarnedToday('milestone');
    final goalReached = progress.totalEffectiveMl >= progress.goalMl;
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: _bg,
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, topInset + 8, 20, 32),
        children: [
          // 返回与积分入口分列两侧
          SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Positioned(
                  left: 0,
                  child: AppBackButton(),
                ),
                Positioned(
                  right: 0,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PointsScreen()),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          SvgPicture.asset(
                            'assets/icons/menu/points.svg',
                            width: 16,
                            height: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${points.balance}',
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
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
          const SizedBox(height: 16),
          _heroCard(),
          const SizedBox(height: 22),
          const Text(
            '趣味小游戏',
            style: TextStyle(color: _sectionTitle, fontSize: 16),
          ),
          const SizedBox(height: 10),
          _gameCard(
            context,
            title: '饮品消消乐',
            subtitle: '三消 · 每 2000 分 +2 积分',
            icon: 'assets/icons/menu/match3.svg',
            route: '/game/match3',
          ),
          const SizedBox(height: 10),
          _gameCard(
            context,
            title: '吨吨守卫战',
            subtitle: '塔防 · 守住饮品，通关得积分',
            icon: 'assets/icons/menu/defense.svg',
            route: '/game/defense',
          ),
          const SizedBox(height: 22),
          const Text(
            '每日任务',
            style: TextStyle(color: _sectionTitle, fontSize: 16),
          ),
          const SizedBox(height: 10),
          // 两个任务合并为一张卡片，中间用浅色细线分隔
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                _taskTile(
                  icon: SvgPicture.asset(
                    'assets/icons/menu/calendar_header.svg',
                    width: 24,
                    height: 24,
                  ),
                  title: '每日签到',
                  reward: '+$checkinPoints',
                  action: signedToday ? '已签到' : '签到',
                  enabled: !signedToday,
                  onTap: () => _claim(context, ref, 'checkin', checkinPoints),
                ),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFEFF1F4),
                  indent: 16,
                  endIndent: 16,
                ),
                _taskTile(
                  icon: const Icon(Icons.emoji_events_rounded,
                      size: 24, color: Color(0xFFE0A63C)),
                  title: '今日饮水达标',
                  reward: '+$goalPoints',
                  action: goalClaimed
                      ? '已领取'
                      : (goalReached ? '领取 +$goalPoints' : '未达标'),
                  enabled: goalReached && !goalClaimed,
                  onTap: () => _claim(context, ref, 'milestone', goalPoints),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '积分属于账号权益：游客（未登录）不计分，登录后余额与明细跟随账号；'
            '积分可在会员页兑换会员天数。',
            textAlign: TextAlign.center,
            style: TextStyle(color: _gray, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 28, 16, 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF55C0DE), Color(0xFF8ADFF0)],
        ),
      ),
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/icons/menu/playground.svg',
            width: 54,
            height: 54,
            colorFilter: const ColorFilter.mode(
              Colors.white,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '玩一玩，赚积分',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '小游戏得分与每日任务都能攒积分，积分可兑换会员天数',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gameCard(
    BuildContext context, {
    required String title,
    required String icon,
    required String route,
    String? subtitle,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              SvgPicture.asset(icon, width: 24, height: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: _ink, fontSize: 15),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: _rewardHint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _cyan,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  '去玩',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taskTile({
    required Widget icon,
    required String title,
    String? reward,
    required String action,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Row(
        children: [
          SizedBox(width: 24, height: 24, child: Center(child: icon)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: _ink, fontSize: 15),
                    ),
                    if (reward != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        reward,
                        style: const TextStyle(
                          color: _rewardHint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: enabled ? onTap : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: enabled ? _cyan : const Color(0xFFEDEFF2),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                action,
                style: TextStyle(
                  color: enabled ? Colors.white : _gray,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 领取每日任务积分：未登录先引导登录，已领取则提示
  Future<void> _claim(
    BuildContext context,
    WidgetRef ref,
    String source,
    int amount,
  ) async {
    final storage = await ref.read(localStorageProvider.future);
    if (!storage.hasAccountSession) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CloudBackupScreen()),
      );
      return;
    }
    final granted =
        await ref.read(pointsProvider.notifier).claimDaily(
              source: source,
              amount: amount,
            );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(granted > 0 ? '已领取 +$granted 积分' : '今天已经领取过了'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
