import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/providers.dart';
import '../../core/sync/points_sync.dart';
import '../../shared/widgets/app_back_button.dart';
import 'points_provider.dart';

/// 我的积分：余额 + 今日进度 + 收支明细（下拉刷新，最多保留 300 条）
class PointsScreen extends ConsumerStatefulWidget {
  const PointsScreen({super.key});

  @override
  ConsumerState<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends ConsumerState<PointsScreen> {
  static const _bg = Color(0xFFF7F7F9);
  static const _ink = Color(0xFF1C1C1E);
  static const _gray = Color(0xFF8E8E93);
  static const _gold = Color(0xFFE0A63C);
  static const _green = Color(0xFF2FB36B);

  @override
  void initState() {
    super.initState();
    unawaited(_refreshFromServer());
  }

  /// 进入积分页即拉取云端余额：别处（后台/其它设备）加的积分无需重启 App
  Future<void> _refreshFromServer() async {
    try {
      final storage = await ref.read(localStorageProvider.future);
      if (!storage.hasAccountSession) return;
      await PointsSync.sync(storage);
    } catch (_) {
      // 静默失败，沿用本机缓存
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pointsProvider);
    final topInset = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _refreshFromServer,
              color: _gold,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20, topInset + 62, 20, 32),
                children: [
                  _balanceCard(context, state),
                  const SizedBox(height: 18),
                  _historyCard(state),
                  const SizedBox(height: 14),
                  const Text(
                    '积分来自吨吨乐园的小游戏与每日任务，可兑换会员天数；'
                    '积分属于账号权益，游客（未登录）不计分，登录后积分与明细跟随账号。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _gray, fontSize: 11, height: 1.5),
                  ),
                ],
              ),
            ),
            Positioned(
              top: topInset + 8,
              left: 12,
              child: const AppBackButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _balanceCard(BuildContext context, PointsState state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF55C0DE), Color(0xFF8ADFF0)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                'assets/icons/menu/points.svg',
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '当前积分',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${state.balance}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 26),
          // 底部一行：左侧今日所得，右侧兑换会员入口
          Row(
            children: [
              Text(
                '今日 +${state.todayEarned}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push('/membership'),
                child: const Row(
                  children: [
                    Text(
                      '兑换会员',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: Colors.white),
                  ],
                ),
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
                  '还没有积分记录，去吨吨乐园赚第一笔积分吧',
                  style: TextStyle(color: _gray, fontSize: 13),
                ),
              ),
            )
          else
            for (final item in _grouped(items)) _recordRow(item),
        ],
      ),
    );
  }

  /// 同一来源、同一天、同方向的流水合并成一条（多次小额加分只显示一行）
  List<_GroupedRecord> _grouped(List<PointsRecord> items) {
    final map = <String, _GroupedRecord>{};
    final out = <_GroupedRecord>[];
    for (final r in items) {
      final day = '${r.at.year}-${r.at.month}-${r.at.day}';
      final key = '${r.source}|$day|${r.amount >= 0 ? 1 : 0}';
      final existed = map[key];
      if (existed == null) {
        final g = _GroupedRecord(r);
        map[key] = g;
        out.add(g);
      } else {
        existed
          ..amount += r.amount
          ..count += 1;
        if (r.at.isAfter(existed.at)) existed.at = r.at;
      }
    }
    return out;
  }

  Widget _recordRow(_GroupedRecord record) {
    final positive = record.amount >= 0;
    final at = record.at;
    final time =
        '${at.month}月${at.day}日 ${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Center(child: _sourceIcon(record.source, positive)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.count > 1
                      ? '${_sourceLabel(record.source)} · ${record.count} 次'
                      : _sourceLabel(record.source),
                  style: const TextStyle(color: _ink, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(time, style: const TextStyle(color: _gray, fontSize: 11)),
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

  /// 流水来源 → 对应图标（与来源一一对应，不加底色）
  Widget _sourceIcon(String source, bool positive) {
    if (source == 'match3') {
      return SvgPicture.asset('assets/icons/menu/match3.svg',
          width: 20, height: 20);
    }
    if (source == 'defense') {
      return SvgPicture.asset('assets/icons/menu/defense.svg',
          width: 20, height: 20);
    }
    if (source == 'checkin') {
      return SvgPicture.asset('assets/icons/menu/calendar_header.svg',
          width: 18, height: 18);
    }
    if (source == 'milestone') {
      return const Icon(Icons.water_drop_rounded,
          size: 18, color: Color(0xFF4DB8D8));
    }
    if (source == 'challenge') {
      return SvgPicture.asset('assets/icons/menu/crown.svg',
          width: 18, height: 18);
    }
    if (!positive || source.startsWith('redeem')) {
      return SvgPicture.asset('assets/icons/menu/redeem.svg',
          width: 18, height: 18);
    }
    return const Icon(Icons.add_rounded, size: 18, color: _gold);
  }

  /// 流水来源 → 展示文案
  String _sourceLabel(String source) {
    if (source.startsWith('redeem:')) {
      final item = source.substring('redeem:'.length);
      if (item == 'member_day') return '兑换会员 1 天';
      return '兑换商品';
    }
    if (source == 'match3') return '消消乐奖励';
    if (source == 'defense') return '守卫战奖励';
    if (source == 'checkin') return '每日签到';
    if (source == 'milestone') return '饮水达标奖励';
    if (source == 'challenge') return '挑战奖励';
    return '积分变动';
  }
}

/// 明细合并后的单行记录
class _GroupedRecord {
  _GroupedRecord(PointsRecord record)
      : source = record.source,
        amount = record.amount,
        at = record.at,
        count = 1;

  final String source;
  int amount;
  DateTime at;
  int count;
}
