import 'package:flutter/material.dart';

/// 会员等级：银钻 / 金钻 / 炫钻
enum MembershipTier { silver, gold, rainbow }

/// 等级对应的皇冠图标
String tierCrownAsset(MembershipTier tier) => switch (tier) {
  MembershipTier.gold => 'assets/images/icons/membership_badge_gold.svg',
  MembershipTier.rainbow =>
    'assets/images/icons/membership_badge_rainbow.svg',
  MembershipTier.silver => 'assets/images/icons/membership_badge_silver.svg',
};

/// 等级对应的文字颜色（炫钻走渐变，不在这里取色）
Color tierTextColor(MembershipTier tier) => switch (tier) {
  MembershipTier.gold => const Color(0xFFD2A02A),
  MembershipTier.rainbow => const Color(0xFFA07BFF),
  MembershipTier.silver => const Color(0xFF8E99A8),
};

/// 昵称：按会员等级着色；炫钻带渐变 + 流光扫过高光
class TierNickname extends StatefulWidget {
  const TierNickname({
    super.key,
    required this.text,
    required this.tier,
    this.fontSize = 22,
    this.fontWeight = FontWeight.w700,
    this.height,
    this.baseColor = const Color(0xFF1F2329),
  });

  final String text;

  /// null 表示非会员，按普通文字展示
  final MembershipTier? tier;
  final double fontSize;
  final FontWeight fontWeight;
  final double? height;

  /// 非会员时的文字颜色
  final Color baseColor;

  @override
  State<TierNickname> createState() => _TierNicknameState();
}

class _TierNicknameState extends State<TierNickname>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // 文字越长，流光周期越长，扫过观感更自然
  Duration _durationFor(String text) {
    final ms = 1800 + text.runes.length * 260;
    return Duration(milliseconds: ms < 1600 ? 1600 : (ms > 6000 ? 6000 : ms));
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _durationFor(widget.text),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant TierNickname oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.duration = _durationFor(widget.text);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  TextStyle get _baseStyle => TextStyle(
    fontSize: widget.fontSize,
    fontWeight: widget.fontWeight,
    height: widget.height,
  );

  @override
  Widget build(BuildContext context) {
    final tier = widget.tier;
    final baseStyle = _baseStyle;

    if (tier == null) {
      return Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle.copyWith(color: widget.baseColor),
      );
    }

    // 会员昵称：底层文字 + 上层白色流光（银钻/金钻为纯色，炫钻为渐变）
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final base = tier == MembershipTier.rainbow
            ? ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xFFFF7AD9),
                    Color(0xFFA07BFF),
                    Color(0xFF35C7E0),
                  ],
                ).createShader(bounds),
                child: Text(
                  widget.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: baseStyle.copyWith(color: Colors.white),
                ),
              )
            : Text(
                widget.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: baseStyle.copyWith(color: tierTextColor(tier)),
              );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            base,
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment(-2.4 + 4.8 * t, -0.5),
                end: Alignment(-0.9 + 4.8 * t, 0.5),
                colors: const [
                  Color(0x00FFFFFF),
                  Color(0x2EFFFFFF),
                  Color(0xA6FFFFFF),
                  Color(0x2EFFFFFF),
                  Color(0x00FFFFFF),
                ],
                stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
              ).createShader(bounds),
              child: Text(
                widget.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: baseStyle.copyWith(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}
