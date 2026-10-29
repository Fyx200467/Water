import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'points_provider.dart';

/// 我的积分：余额 + 今日进度 + 收支明细（本地流水，最多保留 60 条）
class PointsScreen extends ConsumerWidget {
  const PointsScreen({super.key});

  static const _bg = Color(0xFFF7F7F9);
  static const _ink = Color(0xFF1C1C1E);
  static const _gray = Color(0xFF8E8E93);
  static const _gold = Color(0xFFE0A63C);
  static const _green = Color(0xFF2FB36B);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pointsProvider);
    final topInset = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(20, topInset + 62, 20, 32),
              children: [
                _balanceCard(state),
                const SizedBox(height: 18),
                _historyCard(state),
                const SizedBox(height: 14),
                const Text(
                  '积分来自消消乐等任务，可兑换会员天数；'
                  '明细仅保存在本机，卸载重装后不保留。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _gray, fontSize: 11, height: 1.5),
                ),
              ],
            ),
            Positioned(
              top: topInset + 8,
              left: 12,
              child: GestureDetector(
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _balanceCard(PointsState state) {
    final cap = PointsNotifier.matchGameDailyCap;
    final ratio = (state.todayEarned / cap).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF4E0), Color(0xFFFFE7C2)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.stars_rounded, size: 20, color: _gold),
              const SizedBox(width: 6),
              const Text(
                '当前积分',
                style: TextStyle(color: _gold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${state.balance}',
            style: const TextStyle(
              color: _ink,
              fontSize: 40,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.7),
                    valueColor: const AlwaysStoppedAnimation(_gold),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '今日 +${state.todayEarned}/$cap',
                style: const TextStyle(color: Color(0xFF9A6B12), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _historyCard(PointsState state) {
    final items = state.history;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '积分明细',
            style: TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Center(
                child: Text(
                  '还没有积分记录，去消消乐赚第一笔积分吧',
                  style: TextStyle(color: _gray, fontSize: 13),
                ),
              ),
            )
          else
            for (final item in items) _recordRow(item),
        ],
      ),
    );
  }

  Widget _recordRow(PointsRecord record) {
    final positive = record.amount >= 0;
    final at = record.at;
    final time =
        '${at.month}月${at.day}日 ${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: positive
                  ? const Color(0xFFFFF4E0)
                  : const Color(0xFFEFF8FB),
              shape: BoxShape.circle,
            ),
            child: Icon(
              positive ? Icons.add_rounded : Icons.redeem_rounded,
              size: 18,
              color: positive ? _gold : const Color(0xFF4DB8D8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _sourceLabel(record.source),
                  style: const TextStyle(color: _ink, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  time,
                  style: const TextStyle(color: _gray, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            positive ? '+${record.amount}' : '${record.amount}',
            style: TextStyle(
              color: positive ? _green : _gray,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// 流水来源 → 展示文案
  String _sourceLabel(String source) {
    if (source.startsWith('redeem:')) {
      final item = source.substring('redeem:'.length);
      if (item == 'member_day') return '兑换会员 1 天';
      return '兑换商品';
    }
    if (source == 'match3') return '消消乐奖励';
    return '积分变动';
  }
}
