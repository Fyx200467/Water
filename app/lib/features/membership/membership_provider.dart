import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/providers.dart';
import '../../core/sync/sync_api.dart';
import '../../core/sync/sync_service.dart';

/// PRD §2.7 会员套餐（服务端 membershipPlan 的下发结构）
class MembershipPlan {
  const MembershipPlan({
    required this.code,
    required this.name,
    required this.priceCents,
    required this.durationDays,
    this.badge,
  });

  /// monthly / yearly / lifetime
  final String code;
  final String name;
  final int priceCents;

  /// 0 = 终身
  final int durationDays;
  final String? badge;

  String get priceLabel => '¥${(priceCents / 100).toStringAsFixed(0)}';

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
      };

  static MembershipPlan fromJson(Map<String, dynamic> m) => MembershipPlan(
        code: (m['code'] ?? m['id'] ?? '').toString(),
        name: (m['name'] ?? '会员').toString(),
        priceCents: (m['priceCents'] as num?)?.toInt() ?? 0,
        durationDays: (m['durationDays'] as num?)?.toInt() ?? 0,
        badge: m['badge'] as String?,
      );

  /// 服务端不可达时的兜底套餐（价格与后台默认配置一致）
  static const List<MembershipPlan> fallback = [
    MembershipPlan(
      code: 'monthly',
      name: '月卡',
      priceCents: 1800,
      durationDays: 30,
    ),
    MembershipPlan(
      code: 'yearly',
      name: '年卡',
      priceCents: 9800,
      durationDays: 365,
      badge: '推荐',
    ),
    MembershipPlan(
      code: 'lifetime',
      name: '永久会员',
      priceCents: 19800,
      durationDays: 0,
      badge: '一次买断',
    ),
  ];
}

/// 会员状态：active + expireAt(null = 永久)
class MembershipState {
  const MembershipState({this.active = false, this.expireAt, this.planCode});

  final bool active;
  final DateTime? expireAt;
  final String? planCode;

  /// 是否在有效期内（过期后自动失效，无需服务端回调）
  bool get isMember =>
      active && (expireAt == null || expireAt!.isAfter(DateTime.now()));

  String get statusLabel {
    if (!isMember) return '未开通';
    if (expireAt == null) return '永久会员';
    final d = expireAt!;
    return '有效期至 ${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'active': active,
        'expireAt': expireAt?.millisecondsSinceEpoch,
        'planCode': planCode,
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
      if (!mounted) return;
      state = MembershipState(
        active: m['active'] as bool? ?? false,
        expireAt: expireMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expireMs),
        planCode: m['planCode'] as String?,
      );
    } catch (_) {
      // 数据异常保持未开通
    }
  }

  Future<void> _persist() async {
    final storage = await ref.read(localStorageProvider.future);
    await storage.prefs.setString(_kKey, jsonEncode(state.toJson()));
  }

  /// 服务端确认支付后落库：有效期以服务端返回为准
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
    );
    await _persist();
  }

  /// 恢复购买：以服务端购买记录为准（必须联网）
  Future<bool> restore() async {
    await loaded;
    final storage = await ref.read(localStorageProvider.future);
    await SyncService.ensureSession(storage);
    final res = await SyncApi.membershipStatus(storage.syncToken!);
    if (res['isMember'] != true) {
      if (state.active) {
        state = const MembershipState();
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
final membershipPlansProvider =
    FutureProvider<List<MembershipPlan>>((ref) async {
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
