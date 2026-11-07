//
//  QuickAddIntent.swift
//  桌面小组件「点按即记录」（iOS 17+ App Intent）
//
//  背景：WidgetKit 的 Link 只能打开 App，无法在桌面直接写数据。
//  用 AppIntent 在扩展进程内完成：
//    1. 读 drink{slot}_ml_value / eff_ml_value / id（Dart 同步写入）
//    2. 追加 native_pending_adds 队列（"slot:ml:ts:beverageId|..."，
//       与 Android QuickAddReceiver 完全同一格式）
//    3. widget_today_ml 乐观累加并重算 percent / goal_num / goal_unit
//    4. reloadTimelines 让卡片立即重绘
//  App 下次前台由 HomeScreen._drainNativeWidgetAdds 消费队列写入数据库，
//  再推一次真实数据矫正桌面数字。
//
//  约束：iOS 17 以下自动退回 Link（打开 App 内快速录入）。
//

import AppIntents
import Foundation
import WidgetKit

@available(iOS 17.0, *)
struct QuickAddDrinkIntent: AppIntent {
    static var title: LocalizedStringResource = "记录一杯饮品"
    static var description = IntentDescription("在桌面小组件直接记录，无需打开 App")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "槽位")
    var slot: Int

    init() {}

    init(slot: Int) {
        self.slot = slot
    }

    private static let appGroupId = "group.com.waterllama.waterLlama"
    private static let lock = NSLock()

    func perform() async throws -> some IntentResult {
        guard slot >= 1, slot <= 3,
              let d = UserDefaults(suiteName: Self.appGroupId) else {
            return .result()
        }
        // 未完成初始化引导时不录入（与 Dart 侧闸门一致）
        guard d.bool(forKey: "profile_initialized") else { return .result() }

        Self.lock.lock()
        defer { Self.lock.unlock() }

        let vol = d.integer(forKey: "drink\(slot)_ml_value")
        guard vol > 0 else { return .result() }
        let effMl = d.integer(forKey: "drink\(slot)_eff_ml_value")
        let beverageId = d.string(forKey: "drink\(slot)_id") ?? ""
        let ts = Int(Date().timeIntervalSince1970 * 1000)

        // 1) 补录队列：App 前台 drain 时走 DrinkEntry.create 正式入库
        let entry = "\(slot):\(vol):\(ts):\(beverageId)"
        let pending = d.string(forKey: "native_pending_adds") ?? ""
        d.set(pending.isEmpty ? entry : pending + "|" + entry,
              forKey: "native_pending_adds")

        // 2) 桌面数字乐观累加（口径与 Android QuickAddReceiver 一致）
        let goal = max(d.integer(forKey: "goal_ml"), 1)
        let today0 = d.string(forKey: "widget_date") == Self.logicalDayKey(d)
            ? d.integer(forKey: "widget_today_ml") : 0
        d.set(Self.logicalDayKey(d), forKey: "widget_date")
        let today = today0 + max(effMl, 0)
        d.set(today, forKey: "widget_today_ml")
        let pct = min(100, Int((Double(today) * 100 / Double(goal)).rounded()))
        d.set("\(pct)%", forKey: "percent")
        if today >= 1000 {
            d.set(String(format: "%.1f", Double(today) / 1000), forKey: "goal_num")
            d.set("升", forKey: "goal_unit")
        } else {
            d.set("\(today)", forKey: "goal_num")
            d.set("ml", forKey: "goal_unit")
        }
        d.synchronize()

        WidgetCenter.shared.reloadTimelines(ofKind: "WaterLlamaWidget")
        return .result()
    }

    /// 逻辑日：重置时刻之前算前一天（与 Dart LogicalDay / Widget Provider 一致）
    private static func logicalDayKey(_ d: UserDefaults) -> String {
        let now = Date()
        let cal = Calendar.current
        var day = cal.startOfDay(for: now)
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let resetHour = d.integer(forKey: "reset_hour")
        let resetMinute = d.integer(forKey: "reset_minute")
        if (comps.hour ?? 0) * 60 + (comps.minute ?? 0) < resetHour * 60 + resetMinute {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: day)
    }
}
