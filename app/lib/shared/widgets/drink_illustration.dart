import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 饮品插画图标（对标原版 WaterLlama）
///
/// 加载 assets/images/drinks/{id}.svg 矢量插画资源
class DrinkIllustration extends StatelessWidget {
  const DrinkIllustration({
    super.key,
    required this.beverageId,
    this.color = const Color(0xFF4DB8D8),
    this.size = 52,
    this.highlight = false,
  });

  final String beverageId;
  final Color color;
  final double size;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final path = 'assets/images/drinks/$beverageId.svg';
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        path,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => _FallbackDrink(color: color, size: size),
      ),
    );
  }
}

/// 资源加载失败时的回退占位
class _FallbackDrink extends StatelessWidget {
  const _FallbackDrink({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 0.7,
      height: size * 0.7,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, Colors.white, 0.2)!, color],
        ),
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
    );
  }
}
