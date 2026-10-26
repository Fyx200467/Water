import '../../features/settings/settings_flags.dart';

/// 「一天中的重置时间」逻辑日口径（设置页可配，默认 00:00 = 自然日）
///
/// 一天的分界线不是午夜 00:00，而是用户设定的重置时刻：
/// 逻辑日 D 的有效区间 = [D + reset, D+1 + reset)。
/// 此刻在重置时间之前 → 仍属于「昨天」的逻辑日
/// （例：重置 03:00，周二 01:30 喝的水计入周一）。
///
/// 约定：逻辑日用「当日 00:00 的自然日」作为 key（时间部分恒为零点），
/// 所有按日分组/按日查询/今日判断都必须走这里，不得再自行
/// DateTime(y, m, d) 截断，否则口径漂移。
class LogicalDay {
  LogicalDay._();

  /// 当日重置时刻（距零点的分钟数，0~1435）
  static int get resetMinutes =>
      SettingsFlags.instance.resetHour * 60 + SettingsFlags.instance.resetMinute;

  /// 任意时刻所属的逻辑日 key（时间部分为零点）
  static DateTime of(DateTime t) {
    final d = DateTime(t.year, t.month, t.day);
    if (t.hour * 60 + t.minute < resetMinutes) {
      return d.subtract(const Duration(days: 1));
    }
    return d;
  }

  /// 现在所属的逻辑日（「今天」的唯一口径）
  static DateTime today() => of(DateTime.now());

  /// 时刻 t 是否属于逻辑日 [dayKey]
  static bool sameDay(DateTime t, DateTime dayKey) {
    final k = of(t);
    return k.year == dayKey.year &&
        k.month == dayKey.month &&
        k.day == dayKey.day;
  }

  /// 逻辑日 [dayKey] 的起始时刻（含）
  static DateTime startOf(DateTime dayKey) =>
      DateTime(dayKey.year, dayKey.month, dayKey.day)
          .add(Duration(minutes: resetMinutes));

  /// 逻辑日 [dayKey] 的结束时刻（不含）= 下一逻辑日的起始
  static DateTime endOf(DateTime dayKey) =>
      startOf(dayKey).add(const Duration(days: 1));

  /// yyyy-MM-dd 字符串 key（排序即日期序）
  static String keyString(DateTime dayKey) =>
      '${dayKey.year}-${dayKey.month.toString().padLeft(2, '0')}-${dayKey.day.toString().padLeft(2, '0')}';

  // ---------------- 一周开始时间（0=周日，1=周一） ----------------

  /// 每周第一天的 DateTime.weekday 值（Monday=1 … Sunday=7）
  static int get weekStartWeekday =>
      SettingsFlags.instance.weekStart == 0 ? DateTime.sunday : DateTime.monday;

  /// [dayKey] 所在周的第一天（逻辑日 key）
  static DateTime weekStartOf(DateTime dayKey) {
    final target = weekStartWeekday;
    var d = DateTime(dayKey.year, dayKey.month, dayKey.day);
    while (d.weekday != target) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  /// 日历表头标签（按一周开始时间轮转）
  static List<String> get weekHeaderLabels {
    const base = ['一', '二', '三', '四', '五', '六', '日'];
    if (weekStartWeekday == DateTime.sunday) {
      return [base[6], ...base.sublist(0, 6)];
    }
    return base;
  }

  /// 月历 1 号前的空白格数（相对一周开始时间的偏移）
  static int leadingBlanksOf(DateTime firstOfMonth) =>
      (firstOfMonth.weekday - weekStartWeekday) % 7;
}
