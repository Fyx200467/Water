import 'package:flutter/foundation.dart';

/// PRD §2.7 会员权益
@immutable
class MemberState {
  const MemberState({
    required this.isMember,
    this.plan = MemberPlan.free,
    this.expireAt,
    this.benefits = const MemberBenefits.basic(),
  });

  final bool isMember;
  final MemberPlan plan;
  final DateTime? expireAt;
  final MemberBenefits benefits;

  bool get isValid {
    if (!isMember) return false;
    if (plan == MemberPlan.free) return false;
    if (expireAt != null && DateTime.now().isAfter(expireAt!)) return false;
    return true;
  }

  MemberState copyWith({
    bool? isMember,
    MemberPlan? plan,
    DateTime? expireAt,
    MemberBenefits? benefits,
  }) {
    return MemberState(
      isMember: isMember ?? this.isMember,
      plan: plan ?? this.plan,
      expireAt: expireAt ?? this.expireAt,
      benefits: benefits ?? this.benefits,
    );
  }

  factory MemberState.free() => const MemberState(isMember: false);

  factory MemberState.fromMap(Map<String, dynamic> m) => MemberState(
        isMember: (m['is_member'] as int) == 1,
        plan: MemberPlan.values.firstWhere(
          (p) => p.name == m['plan'],
          orElse: () => MemberPlan.free,
        ),
        expireAt: m['expire_at'] != null ? DateTime.tryParse(m['expire_at'] as String) : null,
      );

  Map<String, dynamic> toMap() => {
        'is_member': isMember ? 1 : 0,
        'plan': plan.name,
        'expire_at': expireAt?.toIso8601String(),
      };
}

enum MemberPlan {
  free('免费版'),
  monthly('月度会员'),
  yearly('年度会员'),
  lifetime('终身会员');

  const MemberPlan(this.label);
  final String label;
}

/// PRD §2.7 权益差异
@immutable
class MemberBenefits {
  const MemberBenefits({
    required this.allAnimals,
    required this.allBeverages,
    required this.specialAnimation,
    required this.specialWidget,
    required this.dataExport,
    required this.adFree,
    required this.aiFeatures,
  });

  const MemberBenefits.basic()
      : allAnimals = false,
        allBeverages = false,
        specialAnimation = false,
        specialWidget = false,
        dataExport = false,
        adFree = false,
        aiFeatures = false;

  const MemberBenefits.premium()
      : allAnimals = true,
        allBeverages = true,
        specialAnimation = true,
        specialWidget = true,
        dataExport = true,
        adFree = true,
        aiFeatures = true;

  final bool allAnimals;
  final bool allBeverages;
  final bool specialAnimation;
  final bool specialWidget;
  final bool dataExport;
  final bool adFree;
  final bool aiFeatures;
}
