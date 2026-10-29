import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/providers.dart';
import '../../core/sync/sync_api.dart';

/// 会员相关操作需要登录账号
class NotLoggedInError implements Exception {
  const NotLoggedInError();

  @override
  String toString() => '请先登录账号';
}

/// 积分兑换会员：每天所需积分 + 一次只能兑换 1 天
const int kMemberDayPoints = 60;

/// 套餐内绑定的单条会员权益（后台配置，随套餐下发）
class PlanBenefit {
  const PlanBenefit({
    required this.code,
    required this.name,
    this.description,
    this.icon,
  });

  /// characters / beverages / widgets / export / adfree …
  final String code;
  final String name;
  final String? description;
  final String? icon;

  static PlanBenefit fromJson(Map<String, dynamic> m) => PlanBenefit(
    code: (m['code'] ?? '').toString(),
    name: (m['name'] ?? '').toString(),
    description: m['description'] as String?,
    icon: m['icon'] as String?,
  );
}

/// PRD §2.7 会员套餐（服务端 membershipPlan 的下发结构）
class MembershipPlan {
  const MembershipPlan({
    required this.code,
    required this.name,
    required this.priceCents,
    required this.durationDays,
    this.badge,
    this.benefits = const [],
  });

  /// monthly / yearly / lifetime
  final String code;
  final String name;
  final int priceCents;

  /// 0 = 终身
  final int durationDays;
  final String? badge;

  /// 后台给该套餐绑定的权益；为空时会员页回退内置文案
  final List<PlanBenefit> benefits;

  String get priceLabel {
    final yuan = priceCents / 100;
    final text = yuan
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return '¥$text';
  }

  /// 日均价（终身不计算）
  String? get perDayLabel {
    if (durationDays <= 0) return null;
    final perDay = priceCents / 100 / durationDays;
    return '日均 ¥${perDay.toStringAsFixed(2)}';
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'priceCents': priceCents,
    'durationDays': durationDays,
    'badge': badge,
    'benefits': [
      for (final b in benefits)
        {'code': b.code, 'name': b.name, 'description': b.description, 'icon': b.icon},
    ],
  };

  static MembershipPlan fromJson(Map<String, dynamic> m) => MembershipPlan(
    code: (m['code'] ?? m['id'] ?? '').toString(),
    name: (m['name'] ?? '会员').toString(),
    priceCents: (m['priceCents'] as num?)?.toInt() ?? 0,
    durationDays: (m['durationDays'] as num?)?.toInt() ?? 0,
    badge: m['badge'] as String?,
    benefits: [
      for (final raw in (m['benefits'] as List<dynamic>? ?? const []))
        if (raw is Map) PlanBenefit.fromJson(Map<String, dynamic>.from(raw)),
    ],
  );

  /// 服务端不可达时的兜底套餐（价格与后台默认配置一致）
  static const List<MembershipPlan> fallback = [
    MembershipPlan(
      code: 'monthly',
      name: '月卡',
      priceCents: 690,
      durationDays: 30,
    ),
    MembershipPlan(
      code: 'yearly',
      name: '年卡',
      priceCents: 2990,
      durationDays: 365,
      badge: '推荐',
    ),
    MembershipPlan(
      code: 'lifetime',
      name: '永久会员',
      priceCents: 5990,
      durationDays: 0,
      badge: '一次买断',
    ),
  ];
}

/// 会员状态：active + expireAt(null = 永久)；redeemUntil 为积分兑换的到期时间
class MembershipState {
  const MembershipState({
    this.active = false,
    this.expireAt,
    this.planCode,
    this.redeemUntil,
  });

  final bool active;
  final DateTime? expireAt;
  final String? planCode;

  /// 积分兑换的 1 天会员到期时间（独立于付费订单，便于到期后再兑换）
  final DateTime? redeemUntil;

  bool get _serverValid =>
      active && (expireAt == null || expireAt!.isAfter(DateTime.now()));

  bool get _redeemValid =>
      redeemUntil != null && redeemUntil!.isAfter(DateTime.now());

  /// 是否在有效期内（付费订单 + 积分兑换任一有效）
  bool get isMember => _serverValid || _redeemValid;

  /// 是否有付费订单带来的有效期（用于区分「积分兑换的一天」）
  bool get hasPaidOrder => _serverValid;

  String get statusLabel {
    if (!isMember) return '未开通';
    if (_serverValid) {
      if (expireAt == null) return '永久会员';
      return '有效期至 ${_fmt(expireAt!)}';
    }
    return '积分兑换 · 有效期至 ${_fmt(redeemUntil!)}';
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
    'active': active,
    'expireAt': expireAt?.millisecondsSinceEpoch,
    'planCode': planCode,
    'redeemUntil': redeemUntil?.millisecondsSinceEpoch,
  };
}

class MembershipNotifier extends StateNotifier<MembershipState> {
  MembershipNotifier(this.ref) : super(const MembershipState()) {
    loaded = _load();
  }

  final Ref ref;
  static const _kKey = 'membership_state';

  /// 磁盘加载完成信号（避免恢复购买在加载前误判）
  late final Future<void> loaded;

  Future<void> _load() async {
    try {
      final storage = await ref.read(localStorageProvider.future);
      final raw = storage.prefs.getString(_kKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final expireMs = (m['expireAt'] as num?)?.toInt();
      final redeemMs = (m['redeemUntil'] as num?)?.toInt();
      if (!mounted) return;
      state = MembershipState(
        active: m['active'] as bool? ?? false,
        expireAt: expireMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expireMs),
        planCode: m['planCode'] as String?,
        redeemUntil: redeemMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(redeemMs),
      );
    } catch (_) {
      // 数据异常保持未开通
    }
  }

  Future<void> _persist() async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(_kKey, jsonEncode(state.toJson()));
  }

  /// 服务端确认支付后落库：有效期以服务端返回为准（保留积分兑换的记录）
  Future<void> applyServer({
    required String planCode,
    required DateTime? expireAt,
    required bool permanent,
  }) async {
    await loaded;
    state = MembershipState(
      active: true,
      expireAt: permanent ? null : expireAt,
      planCode: planCode,
      redeemUntil: state.redeemUntil,
    );
    await _persist();
  }

  /// 积分兑换 1 天会员：到期时间写入本地（不与付费订单叠加）
  Future<void> applyRedeemDay(DateTime until) async {
    await loaded;
    state = MembershipState(
      active: state.active,
      expireAt: state.expireAt,
      planCode: state.planCode,
      redeemUntil: until,
    );
    await _persist();
  }

  /// 用 /v1/membership/status 的返回更新本机状态；无变化时不触发重建
  Future<void> applyStatus(Map<String, dynamic> res) async {
    await loaded;
    if (res['isMember'] != true) return;
    final planCode = (res['planCode'] as String?) ?? 'member';
    final expireAt = DateTime.tryParse(res['expireAt']?.toString() ?? '');
    final permanent = res['permanent'] == true;
    final unchanged = state.hasPaidOrder &&
        state.planCode == planCode &&
        (permanent ? state.expireAt == null : state.expireAt == expireAt);
    if (unchanged) return;
    await applyServer(
      planCode: planCode,
      expireAt: expireAt,
      permanent: permanent,
    );
  }

  /// 退出登录 / 会话被顶掉：清空本机会员状态，会员权益随账号失效
  Future<void> reset() async {
    await loaded;
    state = const MembershipState();
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.remove(_kKey);
  }

  /// 恢复购买：以服务端购买记录为准（必须已登录且联网）
  Future<bool> restore() async {
    await loaded;
    final storage = await ref.read(localStorageProvider.future);
    if (!storage.hasAccountSession) {
      throw const NotLoggedInError();
    }
    final res = await SyncApi.membershipStatus(storage.syncToken!);
    if (res['isMember'] != true) {
      if (state.active) {
        // 只清付费订单状态，积分兑换的那一天仍然有效
        state = MembershipState(redeemUntil: state.redeemUntil);
        await _persist();
      }
      return false;
    }
    await applyServer(
      planCode: (res['planCode'] as String?) ?? state.planCode ?? 'member',
      expireAt: DateTime.tryParse(res['expireAt']?.toString() ?? ''),
      permanent: res['permanent'] == true,
    );
    return true;
  }
}

final membershipProvider =
    StateNotifierProvider<MembershipNotifier, MembershipState>((ref) {
      return MembershipNotifier(ref);
    });

/// 套餐列表：优先拉到后台配置，失败回退内置套餐
final membershipPlansProvider = FutureProvider<List<MembershipPlan>>((
  ref,
) async {
  try {
    final remote = await SyncApi.membershipPlans();
    final plans = remote
        .where((e) => (e['isPublished'] as bool?) ?? true)
        .map(MembershipPlan.fromJson)
        .where((p) => p.code.isNotEmpty && p.priceCents > 0)
        .toList();
    if (plans.isNotEmpty) return plans;
  } catch (_) {
    // 服务端不可达（真机/离线）时走兜底套餐
  }
  return MembershipPlan.fallback;
});
