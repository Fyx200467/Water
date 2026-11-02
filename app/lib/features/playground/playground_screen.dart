import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/providers.dart';
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
  static const _cyan = Color(0xFF4DB8D8);

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
          // 标题 + 积分入口
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE5E5EA),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    size: 15,
                    color: _ink,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '吨吨乐园',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PointsScreen()),
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.stars_rounded,
                          size: 16, color: Color(0xFFE0A63C)),
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
            ],
          ),
          const SizedBox(height: 16),
          _heroCard(),
          const SizedBox(height: 22),
          const Text(
            '趣味小游戏',
            style: TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _gameCard(context),
          const SizedBox(height: 22),
          const Text(
            '每日任务',
            style: TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _taskTile(
            icon: Icons.event_available_rounded,
            iconBg: const Color(0xFFEAF7FB),
            iconColor: _cyan,
            title: '每日签到',
            desc: '每天来看看吨吨，立得 $checkinPoints 积分',
            action: signedToday ? '已签到' : '签到 +$checkinPoints',
            enabled: !signedToday,
            onTap: () => _claim(context, ref, 'checkin', checkinPoints),
          ),
          const SizedBox(height: 10),
          _taskTile(
            icon: Icons.emoji_events_rounded,
            iconBg: const Color(0xFFFFF4E0),
            iconColor: const Color(0xFFE0A63C),
            title: '今日饮水达标',
            desc: goalReached
                ? '今日已达标，领取 $goalPoints 积分'
                : '喝到 ${progress.goalMl}ml 即可领取 $goalPoints 积分',
            progress: goalReached
                ? null
                : '${progress.totalEffectiveMl} / ${progress.goalMl} ml',
            action: goalClaimed
                ? '已领取'
                : (goalReached ? '领取 +$goalPoints' : '未达标'),
            enabled: goalReached && !goalClaimed,
            onTap: () => _claim(context, ref, 'milestone', goalPoints),
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
      padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
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
            width: 46,
            height: 46,
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

  Widget _gameCard(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/game/match3'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF7FB),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  'assets/icons/menu/match3.svg',
                  width: 26,
                  height: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '消消乐',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '合成饮品得分，每 1000 分 = 1 积分，不限每日上限',
                      style: TextStyle(color: _gray, fontSize: 12),
                    ),
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
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taskTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String desc,
    required String action,
    required bool enabled,
    required VoidCallback onTap,
    String? progress,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: const TextStyle(color: _gray, fontSize: 12),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    progress,
                    style: const TextStyle(
                      color: Color(0xFF9A6B12),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
                  fontWeight: FontWeight.w600,
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
