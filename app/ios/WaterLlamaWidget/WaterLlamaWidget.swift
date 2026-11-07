//
//  WaterLlamaWidget.swift
//  吨吨 iOS 桌面小组件（WidgetKit）
//
//  版式对标 Android 桌面小组件（android/app/src/main/res/layout/
//  water_llama_widget.xml）：左侧「总量+单位 / 百分比 / 圆形连续徽章」，
//  中部角色插画，右侧三个胶囊饮料按钮（+ 与饮品图标）。
//
//  数据来源：Flutter 侧 home_widget 插件通过 App Group
//  `group.com.waterllama.waterLlama` 写入的 UserDefaults（键名与 Android
//  Provider 完全一致）：
//    goal_num / goal_unit / percent / streak_days / streak_done / streak_badge
//    bg_color / dark_text / tile_color
//    drink{1..3}_name / drink{1..3}_ml / drink{1..3}_ml_value / drink{1..3}_icon_png
//  角色图：Dart 侧 renderFlutterWidget 在 iOS 上把 PNG 直接写进 App Group
//  容器（home_widget/character_frame_N.png），这里用绝对路径读取；
//  饮品图标在 App 主沙盒内，扩展读不到，故以 base64 走 UserDefaults。
//
//  WidgetKit 限制：不支持帧动画，液体波浪与 ✓/天数轮播改为静态帧/静态徽章。
//

import SwiftUI
import WidgetKit

private let appGroupId = "group.com.waterllama.waterLlama"
private let widgetKind = "WaterLlamaWidget"

/// 主文字色（与 Android widget_colors.xml 同值）
private let inkLight = Color(red: 0.110, green: 0.110, blue: 0.118) // #1C1C1E
/// 次要文字色
private let inkSub = Color(red: 0.620, green: 0.620, blue: 0.643) // #9E9EA4
/// 饮料胶囊默认底色 #F1F1F4
private let tileDefault = Color(red: 0.945, green: 0.945, blue: 0.957)
/// 徽章描边 #D9D9E1
private let badgeStroke = Color(red: 0.851, green: 0.851, blue: 0.882)

struct WaterDrink: Identifiable {
    let id: Int              // 1...3（点按回跳 slot）
    let name: String
    let mlLabel: String      // 容量文案，如「250ml」「1.2L」
    let addable: Bool        // ml_value > 0 才允许点按录入
    let icon: UIImage?
}

struct WaterEntry: TimelineEntry {
    let date: Date
    let amountNum: String
    let amountUnit: String
    let percentText: String
    let streakDays: Int
    let showStreak: Bool
    let done: Bool
    let bgColor: Color
    let darkText: Bool
    let tileColor: Color
    let mascot: UIImage?
    let drinks: [WaterDrink]
}

struct WaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterEntry {
        WaterEntry(
            date: Date(), amountNum: "1.1", amountUnit: "升", percentText: "60%",
            streakDays: 3, showStreak: true, done: false,
            bgColor: .white, darkText: false, tileColor: tileDefault,
            mascot: nil,
            drinks: [
                WaterDrink(id: 1, name: "纯净水", mlLabel: "250ml", addable: true, icon: nil),
                WaterDrink(id: 2, name: "果汁", mlLabel: "300ml", addable: true, icon: nil),
                WaterDrink(id: 3, name: "碳酸饮料", mlLabel: "330ml", addable: true, icon: nil),
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WaterEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WaterEntry>) -> Void) {
        let entry = loadEntry()
        // 半小时刷新一次；跨逻辑日由 loadEntry 判断归零
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> WaterEntry {
        let d = UserDefaults(suiteName: appGroupId)
        let goalMl = max(d?.integer(forKey: "goal_ml") ?? 2000, 1)
        var todayMl = d?.integer(forKey: "widget_today_ml") ?? 0

        // 逻辑日与 App 一致：重置时刻之前算「昨天」，跨天归零
        let storedDay = d?.string(forKey: "widget_date") ?? ""
        if storedDay != Self.logicalDayKey(d) {
            todayMl = 0
        }

        // 数字/单位优先用 Dart 已格式化好的文案（与 Android 完全一致），
        // 缺键时按 todayMl 兜底换算
        var num = d?.string(forKey: "goal_num") ?? ""
        var unit = d?.string(forKey: "goal_unit") ?? ""
        if num.isEmpty {
            if todayMl >= 1000 {
                num = String(format: "%.1f", Double(todayMl) / 1000)
                unit = "升"
            } else {
                num = "\(todayMl)"
                unit = "ml"
            }
        }
        var percentText = d?.string(forKey: "percent") ?? ""
        if percentText.isEmpty {
            let p = goalMl > 0 ? min(100, Int((Double(todayMl) * 100 / Double(goalMl)).rounded())) : 0
            percentText = "\(p)%"
        }
        // Dart 侧 streak_days 以字符串写入，整数读取会拿到 0，故先按字符串解析
        let streakDays = Int(d?.string(forKey: "streak_days") ?? "") ?? (d?.integer(forKey: "streak_days") ?? 0)

        var drinks: [WaterDrink] = []
        for i in 1...3 {
            let name = d?.string(forKey: "drink\(i)_name") ?? ""
            let mlLabel = d?.string(forKey: "drink\(i)_ml") ?? ""
            let mlValue = d?.integer(forKey: "drink\(i)_ml_value") ?? 0
            let icon = Self.imageFromBase64(d?.string(forKey: "drink\(i)_icon_png"))
            guard !name.isEmpty || !mlLabel.isEmpty else { continue }
            drinks.append(WaterDrink(id: i, name: name, mlLabel: mlLabel, addable: mlValue > 0, icon: icon))
        }

        let rawBg = d?.integer(forKey: "bg_color") ?? -1
        let rawTile = d?.integer(forKey: "tile_color") ?? -2
        return WaterEntry(
            date: Date(),
            amountNum: num,
            amountUnit: unit,
            percentText: percentText,
            streakDays: streakDays,
            showStreak: d?.bool(forKey: "streak_badge") ?? true,
            done: d?.bool(forKey: "streak_done") ?? false,
            bgColor: rawBg == -1 ? .white : Self.color(argb: rawBg),
            darkText: d?.bool(forKey: "dark_text") ?? false,
            tileColor: rawTile == -2 ? tileDefault : Self.color(argb: rawTile),
            mascot: Self.imageFromAppGroup(d, key: "character_frame_0")
                ?? Self.imageFromPath(d?.string(forKey: "character_icon")),
            drinks: drinks
        )
    }

    /// App Group 共享容器内的角色帧（Dart 侧 renderFlutterWidget 写入的绝对路径）
    private static func imageFromAppGroup(_ d: UserDefaults?, key: String) -> UIImage? {
        guard let path = d?.string(forKey: key), !path.isEmpty else { return nil }
        return UIImage(contentsOfFile: path)
    }

    private static func imageFromPath(_ path: String?) -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        return UIImage(contentsOfFile: path)
    }

    private static func imageFromBase64(_ b64: String?) -> UIImage? {
        guard let b64, !b64.isEmpty, let data = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: data)
    }

    private static func logicalDayKey(_ d: UserDefaults?) -> String {
        let now = Date()
        let cal = Calendar.current
        let resetHour = d?.integer(forKey: "reset_hour") ?? 0
        let resetMinute = d?.integer(forKey: "reset_minute") ?? 0
        let comps = cal.dateComponents([.hour, .minute], from: now)
        var day = cal.startOfDay(for: now)
        if (comps.hour ?? 0) * 60 + (comps.minute ?? 0) < resetHour * 60 + resetMinute {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: day)
    }

    /// Flutter 侧以 ARGB 有符号整数下发
    private static func color(argb: Int) -> Color {
        let v = UInt32(bitPattern: Int32(truncatingIfNeeded: argb))
        return Color(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255,
            opacity: Double((v >> 24) & 0xFF) / 255
        )
    }
}

struct WaterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WaterEntry

    private var ink: Color { entry.darkText ? .white : inkLight }
    private var subInk: Color { entry.darkText ? .white.opacity(0.65) : inkSub }

    var body: some View {
        Group {
            if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .widgetBackground(entry.bgColor)
        .widgetURL(URL(string: "waterllama://home"))
    }

    // MARK: - 中尺寸（对标 Android 3×2）

    private var medium: some View {
        ZStack(alignment: .leading) {
            // 角色插画：居中于卡宽约 1/3 处，垫在文字/按钮之下（z 序）
            if let mascot = entry.mascot {
                Image(uiImage: mascot)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .padding(.leading, 54)
            }
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    amountRow(size: 26)
                    Text(entry.percentText)
                        .font(.system(size: 12))
                        .foregroundColor(subInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if entry.showStreak {
                        badge
                    }
                }
                .frame(width: 62, alignment: .leading)

                Spacer(minLength: 0)

                VStack(spacing: 4) {
                    ForEach(entry.drinks) { drinkRow($0) }
                }
                .frame(width: 112)
            }
        }
    }

    // MARK: - 小尺寸（Android 无对应规格，取同一视觉语言的精简版）

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            amountRow(size: 24)
            Text(entry.percentText)
                .font(.system(size: 11))
                .foregroundColor(subInk)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                if entry.showStreak {
                    badge
                }
                Spacer(minLength: 0)
                if let mascot = entry.mascot {
                    Image(uiImage: mascot)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                }
            }
        }
    }

    // MARK: - 组件

    private func amountRow(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(entry.amountNum)
                .font(.system(size: size, weight: .heavy))
                .foregroundColor(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(entry.amountUnit)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(subInk)
                .lineLimit(1)
        }
    }

    /// 圆形连续徽章：白底 + 浅描边；达标显示 ✓，否则显示天数
    private var badge: some View {
        ZStack {
            Circle().fill(Color.white)
            Circle().stroke(badgeStroke, lineWidth: 1.5)
            Text(entry.done ? "✓" : "\(entry.streakDays)")
                .font(.system(size: entry.done ? 13 : 12, weight: .bold))
                .foregroundColor(inkLight)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 30, height: 30)
    }

    @ViewBuilder
    private func drinkRow(_ drink: WaterDrink) -> some View {
        if drink.addable, let url = URL(string: "waterllama://quick-add?slot=\(drink.id)") {
            Link(destination: url) { drinkTile(drink) }
        } else {
            drinkTile(drink)
        }
    }

    private func drinkTile(_ drink: WaterDrink) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .trailing, spacing: 1) {
                if !drink.mlLabel.isEmpty {
                    Text(drink.mlLabel)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if !drink.name.isEmpty {
                    Text(drink.name)
                        .font(.system(size: 9.5))
                        .foregroundColor(subInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            ZStack(alignment: .leading) {
                Capsule().fill(entry.tileColor)
                Text("+")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ink)
                    .padding(.leading, 8)
                if let icon = drink.icon {
                    HStack {
                        Spacer()
                        Image(uiImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .padding(.trailing, 6)
                    }
                }
            }
            .frame(width: 56, height: 34)
        }
        .frame(height: 36)
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
