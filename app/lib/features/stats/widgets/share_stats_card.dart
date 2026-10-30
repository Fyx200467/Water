import 'package:flutter/material.dart';

import '../providers/stats_providers.dart';

/// 历史页「战绩图片」：竖版统计卡（360×640 逻辑像素，导出 3 倍 = 1080×1920）
///
/// 内容按当前视图生成：日期视图=当月、趋势视图=本周、列表视图=本月。
/// 不显示昵称/头像/邮箱等个人信息。
class StatsShareCard extends StatelessWidget {
  const StatsShareCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.totalText,
    required this.avgText,
    required this.completeDays,
    required this.streakDays,
    required this.days,
  });

  final String title;
  final String subtitle;
  final String totalText;
  final String avgText;
  final int completeDays;
  final int streakDays;

  /// 图表数据（按日期升序）
  final List<DayTotal> days;

  static const _cyan = Color(0xFF4DB8D8);
  static const _deep = Color(0xFF1C1C1E);
  static const _gray = Color(0xFF8E8E93);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      height: 640,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE6F6FB), Color(0xFFFFFFFF)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '吨吨',
                style: TextStyle(
                  color: _cyan,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              const Text(
                '@吨吨_app',
                style: TextStyle(
                  color: _cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Text(
            title,
            style: const TextStyle(
              color: _deep,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: _gray, fontSize: 12),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _statTile('总进水量', totalText)),
              const SizedBox(width: 10),
              Expanded(child: _statTile('日均', avgText)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _statTile('达标天数', '$completeDays 天')),
              const SizedBox(width: 10),
              Expanded(child: _statTile('连续达标', '$streakDays 天')),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: _chart()),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              '保持充足的水分，拥有快乐的心情！',
              style: TextStyle(color: _gray, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// 指标小卡：浅色底 + 标题 + 数值
  Widget _statTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _gray, fontSize: 11)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: _deep,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  /// 每日柱状图：达标日深青、部分达标浅青、无记录灰色轨道
  Widget _chart() {
    if (days.isEmpty) {
      return const Center(
        child: Text('暂无数据', style: TextStyle(color: _gray, fontSize: 13)),
      );
    }
    final maxMl = days.fold<int>(1, (m, d) => d.effectiveMl > m ? d.effectiveMl : m);
    final n = days.length;
    final gap = n <= 10 ? 8.0 : 3.0;
    final showEvery = n <= 10 ? 1 : 5;

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (_, box) {
              final barW =
                  ((box.maxWidth - gap * (n - 1)) / n).clamp(2.0, 100.0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    _bar(days[i], barW, box.maxHeight, maxMl),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 16,
          child: LayoutBuilder(
            builder: (_, box) {
              final barW =
                  ((box.maxWidth - gap * (n - 1)) / n).clamp(2.0, 100.0);
              return Row(
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    SizedBox(
                      width: barW,
                      child: Text(
                        i % showEvery == 0 ? _label(days[i]) : '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _gray, fontSize: 9),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _bar(DayTotal d, double w, double h, int maxMl) {
    final ratio = d.effectiveMl / maxMl;
    final barH = ratio <= 0 ? 3.0 : (h * ratio).clamp(6.0, h);
    final color = d.complete
        ? _cyan
        : (d.effectiveMl > 0
            ? _cyan.withValues(alpha: 0.38)
            : const Color(0xFFE5EDF1));
    return SizedBox(
      width: w,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: barH,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  /// 横轴标签：本周用「一二三…日」，月度用日期数字
  String _label(DayTotal d) {
    if (days.length <= 10) {
      const names = ['一', '二', '三', '四', '五', '六', '日'];
      return names[d.day.weekday - 1];
    }
    return '${d.day.day}';
  }
}
