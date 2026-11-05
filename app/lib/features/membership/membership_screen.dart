import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/analytics/analytics.dart';
import '../../core/storage/providers.dart';
import '../../core/sync/points_sync.dart';
import '../../core/sync/sync_api.dart';
import '../../shared/widgets/account_avatar.dart';
import '../../shared/widgets/app_back_button.dart';
import '../../shared/widgets/tier_nickname.dart';
import '../points/points_provider.dart';
import '../points/points_screen.dart';
import '../settings/cloud_backup_screen.dart';
import '../settings/legal_screen.dart';
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

  /// 触发付费墙的权益点（如「全部角色」），用于顶部提示
  final String? feature;

  @override
  ConsumerState<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends ConsumerState<MembershipScreen> {
  static const _bg = Color(0xFFF5FAFC);
  static const _ink = Color(0xFF1C1C1E);
  static const _gray = Color(0xFF8E8E93);
  static const _cyan = Color(0xFF4DB8D8);
  static const _gold = Color(0xFFE0A63C);

  String? _selectedCode;

  /// 是否勾选「已阅读并同意会员服务协议」，未勾选时主按钮置灰
  bool _agreed = false;

  /// 待运营确认的开通申请（会员页顶部提示条）
  Map<String, dynamic>? _pending;

  /// 最近一次被后台拒绝的申请（展示提示条，用户可关闭）
  Map<String, dynamic>? _rejected;
  String? _dismissedRejectedId;

  /// 24 小时内可自助退款的最近一笔付费订单（积分兑换单不展示入口）
  Map<String, dynamic>? _refundable;

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
      // 积分余额也以服务端为准，避免兑换弹层显示过期余额
      await PointsSync.sync(storage);
    } catch (_) {
      // 静默同步失败不打扰用户
    }
  }

  /// 同步最新一笔申请：pending 显示提示条；rejected 显示未通过提示；
  /// paid 表示运营已确认，直接在页面内开通；24 小时内还展示自助退款入口
  Future<void> _refreshOrderState() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final storage = await ref.read(localStorageProvider.future);
      if (!storage.hasAccountSession || !mounted) return;
      final latest = await SyncApi.latestMembershipOrder(storage.syncToken!);
      if (!mounted) return;
      final status = latest?['status']?.toString();
      final refundable = _isRefundable(latest) ? latest : null;
      if (status == 'pending') {
        setState(() {
          _pending = latest;
          _rejected = null;
          _refundable = null;
        });
      } else if (status == 'rejected') {
        final id = latest?['id']?.toString() ?? '';
        if (_pending != null || id != _dismissedRejectedId) {
          setState(() {
            _pending = null;
            _rejected = latest;
            _refundable = null;
          });
        } else {
          setState(() => _pending = null);
        }
      } else if (status == 'refunded') {
        // 后台退款：只扣掉该订单对应天数，以服务端最新有效期为准
        if (_pending != null || _rejected != null || _refundable != null) {
          setState(() {
            _pending = null;
            _rejected = null;
            _refundable = null;
          });
        }
        final storage = await ref.read(localStorageProvider.future);
        if (storage.hasAccountSession) {
          try {
            await ref.read(membershipProvider.notifier).restore();
          } catch (_) {}
        }
      } else if (status == 'paid') {
        setState(() {
          _pending = null;
          _rejected = null;
          _refundable = refundable;
        });
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

  /// 付费订单支付后 24 小时内可自助退款；积分兑换单没有现金可退
  bool _isRefundable(Map<String, dynamic>? order) {
    if (order == null || order['status']?.toString() != 'paid') return false;
    if ((order['source']?.toString() ?? 'payment') == 'points') return false;
    final paidAt =
        DateTime.tryParse(order['paidAt']?.toString() ?? '') ??
        DateTime.tryParse(order['createdAt']?.toString() ?? '');
    if (paidAt == null) return false;
    return DateTime.now().difference(paidAt) < const Duration(hours: 24);
  }

  /// 自助退款：二次确认后调用服务端接口，退回现金并扣减对应会员天数
  Future<void> _selfRefund() async {
    final order = _refundable;
    if (order == null) return;
    final days = (order['durationDays'] as num?)?.toInt() ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '申请退款',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Text(
          days > 0
              ? '退款后将扣减该订单对应的 $days 天会员，已使用的天数不返还。确定退款吗？'
              : '退款后将撤销这笔永久会员。确定退款吗？',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(color: _gray)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _cyan),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认退款'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final storage = await ref.read(localStorageProvider.future);
      if (!storage.hasAccountSession) return;
      await SyncApi.refundMembershipOrder(
        storage.syncToken!,
        order['id'] as String,
      );
      if (!mounted) return;
      setState(() => _refundable = null);
      try {
        await ref.read(membershipProvider.notifier).restore();
      } catch (_) {}
      await _refreshAll();
      if (!mounted) return;
      _toast('退款成功，对应会员天数已扣减');
    } on SyncApiException catch (e) {
      if (mounted) _toast(e.message);
    } catch (_) {
      if (mounted) _toast('退款失败，请稍后重试');
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
    (
      'assets/images/icons/benefit_characters.svg',
      '全部角色',
      '免费版每日限量，会员解锁全部 41 个角色',
    ),
    (
      'assets/images/icons/benefit_beverages.svg',
      '全部饮品库',
      '解锁奶茶、酒类与自定义饮品',
    ),
    (
      'assets/images/icons/benefit_export.svg',
      '数据导出',
      '一键导出全部饮水记录 CSV',
    ),
  ];

  // 会员等级图标：月卡=银钻，年卡=金钻，永久=炫钻
  static const _crownSilver =
      'assets/images/icons/membership_badge_silver.svg';
  static const _crownGold = 'assets/images/icons/membership_badge_gold.svg';
  static const _crownRainbow =
      'assets/images/icons/membership_badge_rainbow.svg';

  /// 当前会员等级图标：永久=炫钻，年卡=金钻，月卡/积分兑换按所选等级
  String? _tierCrown(MembershipState m) =>
      m.isMember ? tierCrownAsset(m.tier) : null;

  /// 套餐卡上的等级图标：月卡=银钻，年卡=金钻，永久=炫钻
  String _planCrown(String code) => switch (code) {
    'yearly' => _crownGold,
    'lifetime' => _crownRainbow,
    _ => _crownSilver,
  };

  /// 套餐卡配色：月卡银色、年卡金色、永久炫彩
  ({List<Color> bg, Color border, Color band, Color accent}) _tierStyle(
    String code,
  ) => switch (code) {
    'yearly' => (
      bg: const [Color(0xFFFFFDF5), Color(0xFFF8E6B9)],
      border: const Color(0xFFE6CF96),
      band: const Color(0xFFF6E9C6),
      accent: const Color(0xFFD9A21B),
    ),
    'lifetime' => (
      bg: const [
        Color(0xFFFFF3FA),
        Color(0xFFEDF4FF),
        Color(0xFFF2ECFF),
      ],
      border: const Color(0xFFDFD2FF),
      band: const Color(0xFFEDE6FF),
      accent: const Color(0xFFA07BFF),
    ),
    _ => (
      bg: const [Colors.white, Color(0xFFE9ECF1)],
      border: const Color(0xFFCBD2DB),
      band: const Color(0xFFE3E7ED),
      accent: const Color(0xFF8A96A5),
    ),
  };

  /// 服务端未配置原价时，用调价前的旧价作为划线原价
  int? _legacyOriginalCents(String code) => switch (code) {
    'monthly' => 690,
    'yearly' => 2990,
    'lifetime' => 5990,
    _ => null,
  };

  /// 分转元，去掉末尾多余的 0
  String _priceNumber(int cents) {
    final yuan = cents / 100;
    return yuan
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

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
    final account = ref.watch(cloudBackupStateProvider).valueOrNull;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            // 顶部浅色渐变：从品牌浅青过渡到页面底色，作为用户区底衬
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 220,
              child: const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFEAF7FB), Color(0xFFF5FAFC)],
                    ),
                  ),
                ),
              ),
            ),
            ListView(
              padding: EdgeInsets.fromLTRB(20, topInset + 62, 20, 24),
              children: [
                _header(membership, account),
                const SizedBox(height: 40),
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
                Row(
                  children: [
                    for (var i = 0; i < plans.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _planCard(
                          plans[i],
                          selected,
                          locked: membership.isPermanent,
                        ),
                      ),
                    ],
                  ],
                ),
                if (membership.isMember) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      membership.isPermanent
                          ? '已开通永久会员，无需续费'
                          : '续费天数在当前有效期基础上顺延，升级立即生效',
                      style: const TextStyle(color: _gray, fontSize: 11),
                    ),
                  ),
                ],
                if (_refundable != null) ...[
                  const SizedBox(height: 2),
                  Center(child: _refundLink()),
                ],
                const SizedBox(height: 30),
                _benefitsTitle(),
                const SizedBox(height: 14),
                _benefitsCard(selected),
                const SizedBox(height: 22),
                _pointsRow(membership),
              ],
            ),
            // 悬浮返回按钮：不随内容滚动，压在页面左上角
            Positioned(
              top: topInset + 8,
              left: 12,
              child: const AppBackButton(),
            ),
          ],
        ),
        bottomNavigationBar: _bottomBar(selected, membership),
      ),
    );
  }

  /// 自助退款入口：仅 24 小时内的已支付付费订单展示
  Widget _refundLink() {
    return TextButton(
      onPressed: _selfRefund,
      style: TextButton.styleFrom(
        foregroundColor: _gray,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text(
        '申请退款（支付后 24 小时内可退）',
        style: TextStyle(fontSize: 11, decoration: TextDecoration.underline),
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
                  style: const TextStyle(fontSize: 13),
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

  /// 用户区：头像 + 昵称 + 会员标识，第二行为套餐与有效期
  Widget _header(MembershipState m, CloudBackupState? account) {
    final loggedIn = account?.isLoggedIn ?? false;
    final nickname = loggedIn ? account!.nickname : '未登录';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AccountAvatar(
          size: 64,
          loggedIn: loggedIn,
          avatarPath: account?.avatarPath,
          padding: 2,
          background: loggedIn
              ? const Color(0xFFDCEFFD)
              : const Color(0xFFF2F2F7),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: _tierNickname(nickname, m),
                  ),
                  if (m.isMember) ...[
                    const SizedBox(width: 5),
                    SvgPicture.asset(
                      _tierCrown(m)!,
                      width: 20,
                      height: 20,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _statusLine(m),
                style: const TextStyle(color: _gray, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 昵称按会员等级着色：银钻银灰、金钻金色、炫钻渐变流光
  Widget _tierNickname(String nickname, MembershipState m) => TierNickname(
    text: nickname,
    tier: m.isMember ? m.tier : null,
    fontSize: 19,
  );

  /// 状态行：未开通仅显示状态；会员显示套餐名与到期时间
  String _statusLine(MembershipState m) {
    if (!m.isMember) return '未开通';
    if (m.hasPaidOrder) {
      if (m.expireAt == null) return '${m.planName} · 长期有效';
      return '${m.planName} · ${m.statusLabel}';
    }
    return m.statusLabel;
  }

  Widget _planCard(MembershipPlan plan, MembershipPlan selected, {
    bool locked = false,
  }) {
    final on = plan.code == selected.code;
    // 卡片上只显示「月卡 / 年卡 / 永久」，不带“会员”后缀
    final nameLabel = plan.name.replaceFirst(RegExp(r'会员$'), '');
    final style = _tierStyle(plan.code);
    final rawOriginal = plan.originalPriceCents;
    final originalCents = rawOriginal != null && rawOriginal > 0
        ? rawOriginal
        : _legacyOriginalCents(plan.code);
    final showOriginal =
        originalCents != null && originalCents > plan.priceCents;
    return SizedBox(
      height: 142,
      child: GestureDetector(
        onTap: locked
            ? null
            : () {
                setState(() => _selectedCode = plan.code);
                Analytics.track(
                  'plan_select',
                  props: {'plan': plan.code, 'priceCents': plan.priceCents},
                );
              },
        behavior: HitTestBehavior.opaque,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: style.bg,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: on ? style.accent : style.border,
              width: on ? 2 : 1,
            ),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: style.accent.withValues(alpha: 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 16, 6, 0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            _planCrown(plan.code),
                            width: 18,
                            height: 18,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              nameLabel,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            const Text(
                              '¥',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              plan.priceLabel.replaceFirst('¥', ''),
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (showOriginal) ...[
                        const SizedBox(height: 10),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 10),
                            children: [
                              const TextSpan(
                                text: '¥',
                                style: TextStyle(color: Color(0xFF35B7E0)),
                              ),
                              TextSpan(
                                text: _priceNumber(originalCents),
                                style: const TextStyle(
                                  color: Color(0xFF9A9FA8),
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: Color(0xFFD64545),
                                  decorationThickness: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                    ],
                  ),
                ),
              ),
              Container(
                height: 30,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: style.band,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(17),
                  ),
                ),
                child: Text(
                  plan.perDayLabel ?? '长期有效',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF4A4F57),
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 权益区标题：参考稿为居中加粗标题，不带两侧装饰线
  Widget _benefitsTitle() {
    return const Center(
      child: Text(
        'VIP尊享会员权益',
        style: TextStyle(
          color: _ink,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// 积分兑换行：左侧积分图标，右侧兑换按钮（参考稿放在权益区下方）
  Widget _pointsRow(MembershipState m) {
    final points = ref.watch(pointsProvider);
    final cheapest = kRedeemTierPoints[MembershipTier.silver]!;
    final enough = points.balance >= cheapest;
    // 永久会员无需再兑换；其他会员期内兑换按天顺延
    final canRedeem = !m.isPermanent && enough;

    final String action;
    if (m.isPermanent) {
      action = '无需兑换';
    } else if (enough) {
      action = '兑换';
    } else {
      action = '积分不足';
    }

    return GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PointsScreen())),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/icons/menu/points.svg',
              width: 20,
              height: 20,
            ),
            const SizedBox(width: 8),
            const Text('积分兑换', style: TextStyle(color: _ink, fontSize: 14)),
            const Spacer(),
            GestureDetector(
              onTap: canRedeem ? () => _redeemSheet(m) : null,
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: canRedeem
                        ? const Color(0xFFD5D7DB)
                        : const Color(0xFFE6E7E9),
                  ),
                ),
                child: Text(
                  action,
                  style: TextStyle(
                    color: canRedeem ? const Color(0xFF4A4F57) : _gray,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 三档积分兑换：30 积分银钻 / 50 积分金钻 / 100 积分炫钻，各 1 天
  Future<void> _redeemSheet(MembershipState m) async {
    final balance = ref.read(pointsProvider).balance;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  '积分兑换会员',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '当前 $balance 积分',
                  style: const TextStyle(color: _gray, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '兑换 1 天会员，昵称按所选等级显示；会员期内自动顺延到期时间',
                style: TextStyle(color: _gray, fontSize: 11),
              ),
            ),
            const SizedBox(height: 12),
            for (final tier in MembershipTier.values)
              _redeemOptionRow(
                ctx,
                tier,
                balance,
                m,
              ),
          ],
        ),
      ),
    );
  }

  Widget _redeemOptionRow(
    BuildContext sheetCtx,
    MembershipTier tier,
    int balance,
    MembershipState m,
  ) {
    final cost = kRedeemTierPoints[tier]!;
    final enabled = !m.isPermanent && balance >= cost;
    final sub = '1 天，${redeemTierLabel(tier)}效果';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled
          ? () {
              Navigator.pop(sheetCtx);
              _redeemTier(tier, cost);
            }
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8EAED)),
        ),
        child: Row(
          children: [
            SvgPicture.asset(tierCrownAsset(tier), width: 22, height: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    redeemTierLabel(tier),
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
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
            Text(
              '$cost 积分',
              style: TextStyle(
                color: enabled ? _ink : _gray,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled ? _cyan : const Color(0xFFEDEEF0),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                enabled ? '兑换' : '积分不足',
                style: TextStyle(
                  color: enabled ? Colors.white : _gray,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 消耗积分兑换 1 天会员（仅非会员可兑，到期后才能再次兑换）
  Future<void> _redeemTier(MembershipTier tier, int cost) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('积分兑换 1 天会员'),
        content: Text(
          '将消耗 $cost 积分，开通 1 天「${redeemTierLabel(tier)}」效果。\n'
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
    if (!storage.hasAccountSession) {
      _toast('请先登录账号后再兑换，积分会同步到账号');
      return;
    }
    try {
      // 兑换在服务端完成：扣分与开通会员日都由服务端校验，余额以服务端为准
      final expireAt = await PointsSync.redeemMemberDay(
        storage,
        tier: tier.name,
      );
      if (!mounted) return;
      await ref
          .read(membershipProvider.notifier)
          .applyRedeemDay(expireAt, tier);
      if (!mounted) return;
      _toast('已兑换 1 天会员，${redeemTierLabel(tier)}立即生效');
    } catch (e) {
      if (!mounted) return;
      _toast(e is SyncApiException ? e.message : '兑换失败，请检查网络后重试');
    }
  }

  /// 后台权益 code -> 图标资源；未收录的 code 返回 null，由通用图标兜底
  static String? _benefitAsset(String code) {
    switch (code) {
      case 'characters':
        return 'assets/images/icons/benefit_characters.svg';
      case 'beverages':
        return 'assets/images/icons/benefit_beverages.svg';
      case 'export':
        return 'assets/images/icons/benefit_export.svg';
      default:
        return null;
    }
  }

  Widget _benefitsCard(MembershipPlan plan) {
    // 权益由后台按套餐绑定下发；为空（离线/未配置）时回退内置文案。
    // 「专属小组件」与「无广告」不再属于会员权益，后台仍下发时也过滤掉。
    final hidden = {'widgets', 'adfree'};
    final List<(String?, String, String)> items = plan.benefits.isEmpty
        ? [for (final (asset, title, sub) in _benefits) (asset, title, sub)]
        : [
            for (final b in plan.benefits)
              if (!hidden.contains(b.code))
                (
                  _benefitAsset(b.code),
                  b.name.replaceAll('全部动物角色', '全部角色'),
                  b.description ?? '',
                ),
          ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          for (final (asset, title, sub) in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: asset != null
                        ? SvgPicture.asset(
                            asset,
                            width: 28,
                            height: 28,
                          )
                        : const Icon(
                            Icons.check_circle_outline,
                            size: 24,
                            color: _gray,
                          ),
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
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 底部固定操作区：主按钮 + 协议勾选，始终悬浮在列表之上
  Widget _bottomBar(MembershipPlan plan, MembershipState m) {
    // 永久会员不再需要续费；「待确认」申请也会暂时锁住按钮
    final permanent = m.isPermanent;
    final locked = _pending != null || permanent;
    final enabled = !locked;
    final String label;
    if (permanent) {
      label = '已开通永久会员';
    } else if (_pending != null) {
      label = '等待运营确认';
    } else if (m.isMember) {
      label = '续费 / 升级 ${plan.priceLabel}';
    } else {
      label = '立即开通 ${plan.priceLabel}';
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 50,
                child: Material(
                  borderRadius: BorderRadius.circular(25),
                  clipBehavior: Clip.antiAlias,
                  color: enabled ? Colors.transparent : const Color(0xFFE9E9EC),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: enabled
                          ? const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color(0xFF3B8CFF),
                                Color(0xFF7FB8FF),
                              ],
                            )
                          : null,
                    ),
                    child: InkWell(
                      onTap: enabled
                          ? () {
                              // 未勾选协议时不置灰，点击后提示，避免首屏像"按钮不可用"
                              if (!_agreed) {
                                _toast('请先勾选同意《吨吨会员服务协议》');
                                return;
                              }
                              _subscribe(plan);
                            }
                          : null,
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: enabled ? Colors.white : _gray,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _agreementRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _agreementRow() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _agreed = !_agreed),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: _agreed ? _cyan : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: _agreed ? _cyan : const Color(0xFFC7CCD3),
              ),
            ),
            child: _agreed
                ? const Icon(Icons.check, size: 11, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 6),
          const Text('已阅读并同意', style: TextStyle(color: _gray, fontSize: 12)),
          GestureDetector(
            onTap: _openAgreement,
            child: const Text(
              '《吨吨会员服务协议》',
              style: TextStyle(color: _cyan, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// 复用设置页已有的条款与隐私页面（0 = 用户协议）
  void _openAgreement() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LegalScreen(initialTab: 0)));
  }

  Future<void> _subscribe(MembershipPlan plan) async {
    if (ref.read(membershipProvider).isPermanent) {
      _toast('已开通永久会员，无需续费');
      return;
    }
    if (_pending != null) {
      _toast('已有待确认的开通申请，请等待运营处理');
      return;
    }
    final alreadyMember = ref.read(membershipProvider).isMember;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(alreadyMember ? '确认续费/升级${plan.name}？' : '确认开通${plan.name}？'),
        content: Text(
          '内测阶段无需付款：提交申请后由运营确认，确认后会员自动生效。\n\n'
          '${plan.priceLabel} · '
          '${plan.durationDays > 0 ? '${plan.durationDays} 天' : '永久有效'}\n\n'
          '${alreadyMember ? '续费天数将在当前有效期基础上顺延，升级立即生效。\n\n' : ''}'
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
              style: const TextStyle(color: _ink, fontSize: 18),
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
