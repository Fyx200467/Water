# 吨吨 iOS 桌面小组件（WidgetKit）接入说明

本目录是 iOS 小组件的 Swift 源码骨架。Windows 无法编译 iOS，需要在 macOS + Xcode 完成下面几步。

## 1. 新建 Widget Extension

Xcode 打开 `ios/Runner.xcworkspace`：

1. File → New → Target… → **Widget Extension**
2. Product Name 填 `WaterLlamaWidget`，勾选 **Include Configuration Intent** 不勾（用 StaticConfiguration）
3. 取消勾选 "Include Live Activity"（本版本不需要）
4. 建好后删除模板生成的 `WaterLlamaWidget.swift` / `WaterLlamaWidgetBundle.swift`，把本目录下的
   `WaterLlamaWidget.swift` 拖入该 Target（Target Membership 只勾 `WaterLlamaWidget`）
5. 用本目录的 `Info.plist` 覆盖模板 Info.plist（保留 `NSExtensionPointIdentifier = com.apple.widgetkit-extension`）

## 2. App Group（关键）

App 与小组件必须共享同一个 App Group：

- 在 Apple Developer 后台创建 App Group：`group.com.waterllama.waterLlama`
- `Runner` Target → Signing & Capabilities → **+ App Groups** → 勾选该 Group
- `WaterLlamaWidget` Target 同样添加 App Groups 并勾选同一个 Group
- `Runner/Runner.entitlements` 已追加该 Group；小组件 Target 用本目录的
  `WaterLlamaWidget.entitlements`

Flutter 侧已在 `lib/core/widget/home_widget_sync.dart` 调
`HomeWidget.setAppGroupId('group.com.waterllama.waterLlama')`，组名必须与上面完全一致。

## 3. URL Scheme（点按回跳）

`Runner/Info.plist` 已加入 `waterllama` scheme。小组件点按：

- 整卡 → `waterllama://home`（打开 App）
- 饮料格 → `waterllama://quick-add?slot=1..3`

App 首页已监听 `HomeWidget.initiallyLaunchedFromHomeWidget()` 与
`HomeWidget.widgetClicked`，冷/热启动都会按 slot 记录对应饮品。

## 4. 部署与刷新

- Deployment Target：小组件与 Runner 保持一致（建议 iOS 16.0+；17+ 自动使用
  `containerBackground`，16 走普通背景）
- `syncHomeWidget()` 在 iOS 上同样执行，写入 UserDefaults 后调用
  `HomeWidget.updateWidget(iOSName: 'WaterLlamaWidget')` 触发 Timeline 刷新
- Timeline 每 30 分钟请求一次；若 `widget_date` 与当前逻辑日不一致，
  今日饮水量显示为 0（与 App 的「一天重置时间」一致）

## 5. 数据键（与 Dart 侧一致）

| key | 类型 | 说明 |
| --- | --- | --- |
| `widget_today_ml` | Int | 今日有效饮水量 |
| `goal_ml` | Int | 每日目标 |
| `widget_date` | String | 逻辑日 `yyyy-MM-dd` |
| `reset_hour` / `reset_minute` | Int | 一天重置时刻 |
| `streak_days` / `streak_badge` / `streak_done` | Int/Bool | 连续天数与达标 |
| `bg_color` / `dark_text` | Int/Bool | 主题色（-1 = 默认）与深色文字 |
| `drink{1..3}_name` / `drink{1..3}_ml_value` | String/Int | 快捷饮料格 |

## 6. 已知限制

- iOS 通知音效统一使用系统默认音；`soundLabels` 里的自定义音效仅 Android 生效
- 点按饮料格会打开 App 完成录入（iOS 不支持 Android 那种无 UI 后台写入）
- 首次上架前需在 Apple Developer 后台确认 App Group 与 iCloud 没冲突
