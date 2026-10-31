import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics.dart';
import '../../core/storage/providers.dart';
import '../../core/sync/points_sync.dart';
import '../../core/sync/sync_api.dart';
import '../points/points_provider.dart';
import '../points/points_screen.dart';
import '../settings/cloud_backup_screen.dart';
import '../stats/services/export_csv.dart';
import 'membership_provider.dart';

/// 会员权益统一校验：
/// 会员直接放行；非会员进入付费墙，返回「本次操作后是否已成为会员」，
/// 调用方据此决定是否继续执行原动作。
Future<bool> ensureMember(
  BuildContext context,
  WidgetRef ref, {
  required String feature,
}) async {
  if (ref.read(membershipProvider).isMember) return true;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => MembershipScreen(feature: feature)));
  return ref.read(membershipProvider).isMember;
}

/// 会员中心 / 付费墙（PRD §2.7）
class MembershipScreen extends ConsumerStatefulWidget {
  const MembershipScreen({super.key, this.feature});

  /// 触发付费墙的权益点（如「全部动物角色」），用于顶部提示
  final String? feature;

  @override
  ConsumerState<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends ConsumerState<MembershipScreen> {
  static const _bg = Color(0xFFF7F7F9);
  static const _ink = Color(0xFF1C1C1E);
  static const _gray = Color(0xFF8E8E93);
  static const _cyan = Color(0xFF4DB8D8);
  static const _gold = Color(0xFFE0A63C);

  String? _selectedCode;

  /// 待运营确认的开通申请（会员页顶部提示条）
  Map<String, dynamic>? _pending;

  /// 最近一次被后台拒绝的申请（展示提示条，用户可关闭）
  Map<String, dynamic>? _rejected;
  String? _dismissedRejectedId;

  Timer? _pollTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // 漏斗起点：进入会员页；带 feature 说明是从会员权益拦截弹来的付费墙
    Analytics.track(
      'membership_view',
      props: {if (widget.feature != null) 'feature': widget.feature},
    );
    if (widget.feature != null) {
      Analytics.track('paywall_view', props: {'feature': widget.feature});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAll());
    // 页面停留期间轻量轮询：后台确认 / 拒绝后无需退出重进，10 秒内生效
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state != null && state != AppLifecycleState.resumed) return;
      _refreshAll();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait([_syncMembership(), _refreshOrderState()]);
  }

  /// 静默拉取服务端会员状态：只做「升级」，不会把本地已有权益降级
  Future<void> _syncMembership() async {
    try {
      final storage = await ref.read(localStorageProvider.future);
      if (!storage.hasAccountSession || !mounted) return;
      final res = await SyncApi.membershipStatus(storage.syncToken!);
      if (!mounted) return;
      await ref.read(membershipProvider.notifier).applyStatus(res);
    } catch (_) {
      // 静默同步失败不打扰用户
    }
  }

  /// 同步最新一笔申请：pending 显示提示条；rejected 显示未通过提示；
  /// paid 表示运营已确认，直接在页面内开通
  Future<void> _refreshOrderState() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final storage = await ref.read(localStorageProvider.future);
      if (!storage.hasAccountSession || !mounted) return;
      final latest = await SyncApi.latestMembershipOrder(storage.syncToken!);
      if (!mounted) return;
      final status = latest?['status']?.toString();
      if (status == 'pending') {
        setState(() {
          _pending = latest;
          _rejected = null;
        });
      } else if (status == 'rejected') {
        final id = latest?['id']?.toString() ?? '';
        if (_pending != null || id != _dismissedRejectedId) {
          setState(() {
            _pending = null;
            _rejected = latest;
          });
        } else {
          setState(() => _pending = null);
        }
      } else if (status == 'paid') {
        if (_pending != null || _rejected != null) {
          setState(() {
            _pending = null;
            _rejected = null;
          });
        }
        await ref.read(membershipProvider.notifier).applyStatus(latest!);
      } else if (_pending != null) {
        setState(() => _pending = null);
      }
    } catch (_) {
      // 网络失败时保留上次结果，不打扰用户
    } finally {
      _refreshing = false;
    }
  }

  /// 撤回待确认申请
  Future<void> _cancelPending() async {
    final pending = _pending;
    if (pending == null) return;
    setState(() => _pending = null);
    try {
      final storage = await ref.read(localStorageProvider.future);
      if (!storage.hasAccountSession) return;
      await SyncApi.cancelMembershipOrder(
        storage.syncToken!,
        pending['id'] as String,
      );
      if (!mounted) return;
      _toast('已撤回开通申请');
    } catch (_) {
      if (!mounted) return;
      _toast('撤回失败，请稍后重试');
      await _refreshOrderState();
    }
  }

  static const _benefits = [
    (Icons.pets, '全部动物角色', '免费版每日限量，会员解锁全部 41 个角色'),
    (Icons.local_drink, '全部饮品库', '解锁奶茶、酒类与自定义饮品'),
    (Icons.widgets_outlined, '专属小组件', '自定义主题色与彩色字符层'),
    (Icons.ios_share, '数据导出', '一键导出全部饮水记录 CSV'),
    (Icons.block, '无广告', '纯净的饮水体验'),
  ];

  @override
  Widget build(BuildContext context) {
    final membership = ref.watch(membershipProvider);
    final plansAsync = ref.watch(membershipPlansProvider);
    final plans = plansAsync.asData?.value ?? MembershipPlan.fallback;
    final selected = plans.firstWhere(
      (p) => p.code == _selectedCode,
      orElse: () => plans.firstWhere(
        (p) => p.code == 'yearly',
        orElse: () => plans.first,
      ),
    );

    // 内容铺满整屏（状态栏区域同为页面底色），返回按钮悬浮在内容之上
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
                _header(membership),
                const SizedBox(height: 20),
                if (_pending != null && !membership.isMember) ...[
                  _pendingBanner(),
                  const SizedBox(height: 16),
                ],
                if (_rejected != null && !membership.isMember) ...[
                  _rejectedBanner(),
                  const SizedBox(height: 16),
                ],
                if (widget.feature != null && !membership.isMember) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6E6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 16, color: _gold),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '「${widget.feature}」为会员专属权益',
                            style: const TextStyle(
                              color: Color(0xFF9A6B12),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (!membership.isMember) ...[
                  Row(
                    children: [
                      for (var i = 0; i < plans.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(child: _planCard(plans[i], selected)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                _pointsCard(membership),
                const SizedBox(height: 18),
                _benefitsCard(selected),
                const SizedBox(height: 18),
                _subscribeButton(selected, membership),
                const SizedBox(height: 14),
                const Center(
                  child: Text(
                    '内测阶段无需付款：提交申请后由运营确认，确认后自动开通；'
                    '正式版接入应用内购买（iOS IAP / Google Play）',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _gray, fontSize: 11, height: 1.5),
                  ),
                ),
              ],
            ),
            // 悬浮返回按钮：不随内容滚动，压在页面左上角
            Positioned(
              top: topInset + 8,
              left: 12,
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                customBorder: const CircleBorder(),
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

  Widget _pendingBanner() {
    final name = (_pending?['planName'] as String?) ?? '会员';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF8FB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 18, color: _cyan),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name 开通申请审核中',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '运营确认后自动生效，无需付款',
                  style: TextStyle(fontSize: 11.5, color: _gray),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _cancelPending,
            child: const Text(
              '撤回',
              style: TextStyle(fontSize: 12.5, color: _gray),
            ),
          ),
        ],
      ),
    );
  }

  /// 后台拒绝后的提示条：用户可关闭，重新提交新申请后自动消失
  Widget _rejectedBanner() {
    final name = (_rejected?['planName'] as String?) ?? '会员';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDEDEE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: Color(0xFFE5484D)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name 开通申请未通过',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB3261E),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '运营未通过本次申请，可在下方重新选择套餐提交',
                  style: TextStyle(fontSize: 11.5, color: _gray),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _dismissedRejectedId = _rejected?['id']?.toString();
                _rejected = null;
              });
            },
            child: const Text(
              '关闭',
              style: TextStyle(fontSize: 12.5, color: _gray),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(MembershipState m) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: Color(0xFFFFF1D6),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.workspace_premium, size: 38, color: _gold),
        ),
        const SizedBox(height: 12),
        Text(
          m.isMember ? '吨吨会员已开通' : '开通吨吨会员',
          style: const TextStyle(
            color: _ink,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          m.isMember ? m.statusLabel : '解锁全部动物、饮品',
          style: const TextStyle(color: _gray, fontSize: 13),
        ),
      ],
    );
  }

  Widget _planCard(MembershipPlan plan, MembershipPlan selected) {
    final on = plan.code == selected.code;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedCode = plan.code);
        Analytics.track(
          'plan_select',
          props: {'plan': plan.code, 'priceCents': plan.priceCents},
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 14),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFEAF7FB) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: on ? _cyan : const Color(0xFFE9E9EC),
            width: on ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            if (plan.badge != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _gold,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  plan.badge!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              const SizedBox(height: 18),
            Text(
              plan.name,
              style: const TextStyle(
                color: _ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              plan.priceLabel,
              style: TextStyle(
                color: on ? _cyan : _ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              plan.perDayLabel ?? plan.badge ?? '长期有效',
              style: const TextStyle(color: _gray, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  /// 积分兑换入口：玩消消乐赚积分，1 天 / 份，到期后才能再兑
  Widget _pointsCard(MembershipState m) {
    final points = ref.watch(pointsProvider);
    final cost = kMemberDayPoints;
    final enough = points.balance >= cost;
    final byPoints = m.isMember && !m.hasPaidOrder;

    final String subtitle;
    if (m.isMember) {
      subtitle = byPoints ? '积分兑换的会员有效期内，到期后可再兑换 1 天' : '当前会员有效期内，到期后可再用积分兑换';
    } else if (enough) {
      subtitle = '$cost 积分兑换 1 天会员 · 当前 ${points.balance} 积分';
    } else {
      subtitle = '$cost 积分兑换 1 天会员 · 还差 ${cost - points.balance} 积分';
    }

    final String action;
    if (m.isMember) {
      action = '有效期内';
    } else if (enough) {
      action = '立即兑换';
    } else {
      action = '积分不足';
    }

    return GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PointsScreen())),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF4E0),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.stars_rounded, size: 22, color: _gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '积分兑换会员',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _gray,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 34,
              child: FilledButton(
                onPressed: (!m.isMember && enough) ? _redeemWithPoints : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _cyan,
                  disabledBackgroundColor: const Color(0xFFE9E9EC),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                child: Text(
                  action,
                  style: TextStyle(
                    color: (!m.isMember && enough) ? Colors.white : _gray,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 消耗积分兑换 1 天会员（仅非会员可兑，到期后才能再次兑换）
  Future<void> _redeemWithPoints() async {
    final cost = kMemberDayPoints;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('积分兑换 1 天会员'),
        content: Text(
          '将消耗 $cost 积分，兑换后立即生效 1 天。\n'
          '到期后才能再次兑换，不能叠加、不能提前续期。',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: _gray)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _cyan),
            child: const Text('确认兑换'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final storage = await ref.read(localStorageProvider.future);
    try {
      // 兑换在服务端完成：扣分与开通会员日都由服务端校验，余额以服务端为准
      final expireAt = await PointsSync.redeemMemberDay(storage);
      if (!mounted) return;
      await ref.read(membershipProvider.notifier).applyRedeemDay(expireAt);
      if (!mounted) return;
      _toast('已兑换 1 天会员，特权立即生效');
    } catch (e) {
      if (!mounted) return;
      _toast(e is SyncApiException ? e.message : '兑换失败，请检查网络后重试');
    }
  }

  /// 后台权益 code -> 图标；未收录的 code 用通用图标兜底
  static IconData _benefitIcon(String code) {
    switch (code) {
      case 'characters':
        return Icons.pets;
      case 'beverages':
        return Icons.local_drink;
      case 'widgets':
        return Icons.widgets_outlined;
      case 'export':
        return Icons.ios_share;
      case 'adfree':
        return Icons.block;
      default:
        return Icons.check_circle_outline;
    }
  }

  /// 会员专享「数据导出」：生成 CSV 并调起系统分享面板
  Future<void> _exportCsvFromBenefits() async {
    if (!ref.read(membershipProvider).isMember) {
      _toast('开通会员后可使用数据导出');
      return;
    }
    _toast('正在生成 CSV…');
    final result = await exportAllEntriesCsv(ref);
    if (!mounted) return;
    _toast(switch (result) {
      CsvExportResult.ok => '已生成 CSV，可在分享面板中保存或发送',
      CsvExportResult.empty => '暂无可导出的饮水记录',
      CsvExportResult.failed => '导出失败，请稍后重试',
    });
  }

  Widget _benefitsCard(MembershipPlan plan) {
    // 权益由后台按套餐绑定下发；为空（离线/未配置）时回退内置文案
    final items = plan.benefits.isEmpty
        ? [for (final (icon, title, sub) in _benefits) (icon, title, sub)]
        : [
            for (final b in plan.benefits)
              (_benefitIcon(b.code), b.name, b.description ?? ''),
          ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          for (final (icon, title, sub) in items)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              // 「数据导出」是唯一可点击的权益（会员导出全部记录为 CSV）
              onTap: title == '数据导出' ? _exportCsvFromBenefits : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEAF7FB),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 18, color: _cyan),
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
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sub,
                            style: const TextStyle(color: _gray, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    if (title == '数据导出')
                      const Icon(
                        Icons.download_rounded,
                        size: 18,
                        color: _cyan,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _subscribeButton(MembershipPlan plan, MembershipState m) {
    if (m.isMember) {
      return SizedBox(
        height: 50,
        child: FilledButton(
          onPressed: null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE9E9EC),
            disabledBackgroundColor: const Color(0xFFE9E9EC),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
          ),
          child: const Text(
            '已开通',
            style: TextStyle(
              color: _gray,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    if (_pending != null) {
      // 已有待确认申请：禁止重复下单，避免后台出现两条审核记录
      return SizedBox(
        height: 50,
        child: FilledButton(
          onPressed: null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE9E9EC),
            disabledBackgroundColor: const Color(0xFFE9E9EC),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
          ),
          child: const Text(
            '等待运营确认',
            style: TextStyle(
              color: _gray,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 50,
      child: FilledButton(
        onPressed: () => _subscribe(plan),
        style: FilledButton.styleFrom(
          backgroundColor: _cyan,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
        ),
        child: Text(
          '立即开通 ${plan.priceLabel}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _subscribe(MembershipPlan plan) async {
    if (_pending != null) {
      _toast('已有待确认的开通申请，请等待运营处理');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('确认开通${plan.name}？'),
        content: Text(
          '内测阶段无需付款：提交申请后由运营确认，确认后会员自动生效。\n\n'
          '${plan.priceLabel} · '
          '${plan.durationDays > 0 ? '${plan.durationDays} 天' : '永久有效'}\n\n'
          '开通需要联网提交申请。',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: _gray)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _cyan),
            child: const Text('提交订单'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final storage = await ref.read(localStorageProvider.future);
    if (!storage.hasAccountSession) {
      if (!mounted) return;
      _toast('开通会员需要先登录账号');
      await _openLogin();
      return;
    }
    final Map<String, dynamic> order;
    try {
      order = await SyncApi.createMembershipOrder(
        storage.syncToken!,
        plan.code,
      );
    } catch (_) {
      if (!mounted) return;
      _toast('无法连接服务器：会员开通需要联网，请检查网络后重试');
      return;
    }
    if (!mounted) return;
    final reused = order['reused'] == true;
    setState(() {
      _pending = order;
      _rejected = null;
    });
    if (reused) {
      _toast('已有待确认的申请，已为你打开进度');
    } else {
      Analytics.track(
        'order_submit',
        props: {
          'plan': plan.code,
          'priceCents': plan.priceCents,
          'orderId': order['id'],
        },
      );
    }

    final paid = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderWaitSheet(
        token: storage.syncToken!,
        orderId: order['id'] as String,
        order: order,
      ),
    );
    if (paid == null || !mounted) {
      // 用户中途关闭等待面板：申请仍在后台排队，刷新一下提示条
      await _refreshOrderState();
      return;
    }
    setState(() => _pending = null);

    await ref
        .read(membershipProvider.notifier)
        .applyServer(
          planCode: (paid['planCode'] as String?) ?? plan.code,
          expireAt: DateTime.tryParse(paid['expireAt']?.toString() ?? ''),
          permanent: paid['permanent'] == true,
        );
    Analytics.track(
      'order_confirmed',
      props: {'plan': plan.code, 'orderId': paid['id']},
    );
    if (!mounted) return;
    _toast('${plan.name}已开通');
  }

  /// 跳转账号页登录，返回后若已登录则继续原操作
  Future<void> _openLogin() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CloudBackupScreen()));
    if (!mounted) return;
    final storage = await ref.read(localStorageProvider.future);
    if (!storage.hasAccountSession) return;
    final token = storage.syncToken!;
    try {
      final res = await SyncApi.membershipStatus(token);
      if (res['isMember'] == true) {
        await ref
            .read(membershipProvider.notifier)
            .applyServer(
              planCode: (res['planCode'] as String?) ?? 'member',
              expireAt: DateTime.tryParse(res['expireAt']?.toString() ?? ''),
              permanent: res['permanent'] == true,
            );
        if (mounted) _toast('已同步会员权益');
      }
    } catch (_) {
      // 登录后查会员失败不阻塞流程
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 待支付订单：轮询服务端状态，确认支付后把订单信息返回给会员页
class _OrderWaitSheet extends StatefulWidget {
  const _OrderWaitSheet({
    required this.token,
    required this.orderId,
    required this.order,
  });

  final String token;
  final String orderId;
  final Map<String, dynamic> order;

  @override
  State<_OrderWaitSheet> createState() => _OrderWaitSheetState();
}

class _OrderWaitSheetState extends State<_OrderWaitSheet> {
  static const _ink = Color(0xFF1C1C1E);
  static const _gray = Color(0xFF8E8E93);
  static const _cyan = Color(0xFF4DB8D8);

  Timer? _timer;
  bool _polling = false;
  bool _paid = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling || _paid) return;
    _polling = true;
    try {
      final res = await SyncApi.membershipOrder(widget.token, widget.orderId);
      if (!mounted) return;
      if (res['status'] == 'rejected') {
        // 运营拒绝：停止轮询，提示用户可重新提交
        _timer?.cancel();
        setState(() => _error = '申请未通过，可重新选择套餐提交');
        return;
      }
      if (res['status'] == 'cancelled') {
        // 用户自己撤回：停止轮询，提示后由用户自行关闭
        _timer?.cancel();
        setState(() => _error = '申请已撤回，可重新选择套餐提交');
        return;
      }
      if (res['status'] == 'paid') {
        _timer?.cancel();
        setState(() {
          _paid = true;
          _error = null;
        });
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (!mounted) return;
        Navigator.of(context).pop(res);
        return;
      }
      setState(() => _error = null);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '网络异常，正在自动重试');
    } finally {
      _polling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cents = (widget.order['amountCents'] as num?)?.toInt() ?? 0;
    final price = '¥${(cents / 100).toStringAsFixed(2)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Icon(
              _paid ? Icons.check_circle : Icons.schedule,
              size: 42,
              color: _paid ? const Color(0xFF2FB36B) : _cyan,
            ),
            const SizedBox(height: 10),
            Text(
              _paid ? '会员已开通' : '申请已提交，等待确认',
              style: const TextStyle(
                color: _ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.order['planName'] ?? ''} · $price',
              style: const TextStyle(color: _ink, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Text(
              '订单号 ${widget.orderId}',
              style: const TextStyle(color: _gray, fontSize: 11),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6F8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _paid
                    ? '会员权益已生效，正在返回会员中心…'
                    : (_error ?? '内测阶段无需付款：运营确认后自动开通，本页会自动刷新'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _gray, fontSize: 12, height: 1.5),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _gray,
                        side: const BorderSide(color: Color(0xFFE5E5EA)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(23),
                        ),
                      ),
                      child: const Text('稍后处理'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: _paid ? null : _poll,
                      style: FilledButton.styleFrom(
                        backgroundColor: _cyan,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(23),
                        ),
                      ),
                      child: const Text('刷新状态'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
