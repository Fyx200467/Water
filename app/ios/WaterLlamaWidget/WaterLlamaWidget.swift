//
//  WaterLlamaWidget.swift
//  吨吨 iOS 桌面小组件（WidgetKit）
//
//  数据来源：Flutter 侧 home_widget 插件通过 App Group
//  `group.com.waterllama.waterLlama` 写入的 UserDefaults：
//    widget_today_ml / goal_ml / widget_date / reset_hour / reset_minute
//    percent / streak_days / streak_badge / streak_done
//    bg_color / dark_text / drink{1..3}_name / drink{1..3}_ml
//
//  接入方式见同目录 README.md（Windows 上无法编译 iOS，需在 Xcode 完成）。
//

import SwiftUI
import WidgetKit

private let appGroupId = "group.com.waterllama.waterLlama"
private let widgetKind = "WaterLlamaWidget"

struct WaterEntry: TimelineEntry {
    let date: Date
    let todayMl: Int
    let goalMl: Int
    let streakDays: Int
    let showStreak: Bool
    let done: Bool
    let themeColor: Color?
    let darkText: Bool
    let drinkNames: [String]
    let drinkMl: [Int]
}

struct WaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterEntry {
        WaterEntry(
            date: Date(), todayMl: 1200, goalMl: 2000, streakDays: 12,
            showStreak: true, done: false, themeColor: nil, darkText: false,
            drinkNames: ["水", "茶", "咖啡"], drinkMl: [250, 200, 150]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WaterEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WaterEntry>) -> Void) {
        let entry = loadEntry()
        // 半小时刷新一次；逻辑日跨天由 loadEntry 判断归零
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> WaterEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let goalMl = max(defaults?.integer(forKey: "goal_ml") ?? 2000, 1)
        var todayMl = defaults?.integer(forKey: "widget_today_ml") ?? 0

        // 逻辑日与 App 一致：重置时刻之前算「昨天」，跨天归零
        let storedDay = defaults?.string(forKey: "widget_date") ?? ""
        if storedDay != Self.logicalDayKey(defaults) {
            todayMl = 0
        }

        var names: [String] = []
        var mls: [Int] = []
        for i in 1...3 {
            let name = defaults?.string(forKey: "drink\(i)_name") ?? ""
            let ml = defaults?.integer(forKey: "drink\(i)_ml_value") ?? 0
            if !name.isEmpty && ml > 0 {
                names.append(name)
                mls.append(ml)
            }
        }

        let rawColor = defaults?.integer(forKey: "bg_color") ?? -1
        return WaterEntry(
            date: Date(),
            todayMl: todayMl,
            goalMl: goalMl,
            streakDays: defaults?.integer(forKey: "streak_days") ?? 0,
            showStreak: defaults?.bool(forKey: "streak_badge") ?? true,
            done: defaults?.bool(forKey: "streak_done") ?? false,
            themeColor: rawColor == -1 ? nil : Self.color(argb: rawColor),
            darkText: defaults?.bool(forKey: "dark_text") ?? false,
            drinkNames: names,
            drinkMl: mls
        )
    }

    private static func logicalDayKey(_ defaults: UserDefaults?) -> String {
        let now = Date()
        let cal = Calendar.current
        let resetHour = defaults?.integer(forKey: "reset_hour") ?? 0
        let resetMinute = defaults?.integer(forKey: "reset_minute") ?? 0
        let comps = cal.dateComponents([.hour, .minute], from: now)
        var day = cal.startOfDay(for: now)
        if (comps.hour ?? 0) * 60 + (comps.minute ?? 0) < resetHour * 60 + resetMinute {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: day)
    }

    private static func color(argb: Int) -> Color {
        let v = UInt32(bitPattern: Int32(truncatingIfNeeded: argb))
        return Color(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct WaterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WaterEntry

    private let accent = Color(red: 0.231, green: 0.702, blue: 0.859) // #3BB3DB

    private var percent: Int {
        guard entry.goalMl > 0 else { return 0 }
        return min(100, Int((Double(entry.todayMl) * 100 / Double(entry.goalMl)).rounded()))
    }

    private var bg: Color { entry.themeColor ?? Color(red: 0.98, green: 0.98, blue: 0.99) }
    private var ink: Color { entry.darkText ? .white : Color(red: 0.11, green: 0.11, blue: 0.12) }
    private var subInk: Color { entry.darkText ? .white.opacity(0.7) : .gray }

    var body: some View {
        content
            .padding(14)
            .widgetBackground(bg)
            .widgetURL(URL(string: "waterllama://home"))
    }

    @ViewBuilder
    private var content: some View {
        if family == .systemMedium {
            HStack(spacing: 14) {
                ring(size: 84)
                VStack(alignment: .leading, spacing: 6) {
                    amount
                    progressBar
                    if entry.showStreak && entry.streakDays > 0 {
                        streakChip
                    }
                }
                if !entry.drinkNames.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(Array(zip(entry.drinkNames, entry.drinkMl).enumerated()), id: \.offset) { idx, item in
                            Link(destination: URL(string: "waterllama://quick-add?slot=\(idx + 1)")!) {
                                HStack(spacing: 5) {
                                    Text(item.0).font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                    Text("\(item.1)").font(.system(size: 11))
                                }
                                .foregroundColor(ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(accent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .frame(width: 66)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    amount
                    Spacer()
                    if entry.showStreak && entry.streakDays > 0 {
                        streakChip
                    }
                }
                Spacer(minLength: 0)
                progressBar
            }
        }
    }

    private var amount: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(entry.todayMl >= 1000
                     ? String(format: "%.1f", Double(entry.todayMl) / 1000)
                     : "\(entry.todayMl)")
                    .font(.system(size: family == .systemMedium ? 28 : 30, weight: .heavy))
                    .foregroundColor(ink)
                    .minimumScaleFactor(0.7)
                Text(entry.todayMl >= 1000 ? "升" : "ml")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(subInk)
            }
            Text("目标 \(entry.goalMl >= 1000 ? String(format: "%.1f", Double(entry.goalMl) / 1000) + " 升" : "\(entry.goalMl) ml")")
                .font(.system(size: 11))
                .foregroundColor(subInk)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(accent.opacity(0.16))
                Capsule()
                    .fill(accent)
                    .frame(width: max(6, geo.size.width * CGFloat(percent) / 100))
            }
        }
        .frame(height: 7)
    }

    private func ring(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.16), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(percent)%")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundColor(ink)
                if entry.done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accent)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private var streakChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill").font(.system(size: 9))
            Text("\(entry.streakDays)").font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(entry.darkText ? .white : Color(red: 0.85, green: 0.55, blue: 0.16))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            (entry.darkText ? Color.white.opacity(0.22) : Color(red: 1, green: 0.94, blue: 0.85))
        )
        .clipShape(Capsule())
    }
}

@main
struct WaterLlamaWidgetBundle: WidgetBundle {
    var body: some Widget {
        WaterLlamaWidget()
    }
}

struct WaterLlamaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind, provider: WaterProvider()) { entry in
            WaterWidgetView(entry: entry)
        }
        .configurationDisplayName("吨吨喝水")
        .description("查看今日饮水量、目标完成度与连续天数，点饮料格快速记录。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private extension View {
    @ViewBuilder
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) { color }
        } else {
            background(color)
        }
    }
}
