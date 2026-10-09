# 喝水养成 App（对标 WaterLlama）实施计划

## Context

用户上传了完整 PRD（`喝水养成APP（WaterLlama同款）PRD.docx`），要求实现一款对标 WaterLlama 的喝水养成 App，覆盖 iOS + Android 双端，并附带后台管理。PRD 明确分两阶段：

- **V1.0（本期稳上线，无 AI）**：养成核心 + 饮水工具 + 数据中心 + 权益设置 + 桌面小组件 + 后台管理
- **V2.0（AI 差异化迭代）**：AI 每日报告 / 个性化补水建议 / 拍照识别饮品 / 治愈文案 / 周诊断 / AI 后台

工作目录 `C:\Users\admin\Documents\Trae-CN\temp_20261009_01` 当前为空，属全新项目。本计划聚焦 V1.0 全量交付 + V2.0 框架预留，按可演示里程碑推进。

## 技术选型（已定）

| 层 | 选型 | 理由 |
|---|---|---|
| 移动端框架 | **Flutter 3.x（Dart）** | 单码库覆盖 iOS/Android；CustomPainter + AnimationController 天然适合 60fps 流体填充动画；Platform Channel 桥接桌面小组件；热重载便于调动画 |
| 状态管理 | **Riverpod 2.x** | 类型安全、可测试、依赖注入清晰，比 Provider 更适合复杂养成 App |
| 本地存储 | **Isar**（结构化数据） + **shared_preferences**（轻配置） | Isar 在 Flutter 端性能极佳，支持复杂查询；断网可写、联网同步 |
| 网络层 | **Dio + retrofit** | 拦截器、Token 刷新、错误降级齐备 |
| 路由 | **go_router** | 声明式、深链接友好 |
| 后端 | **Node.js + NestJS + PostgreSQL + Redis** | NestJS 模块化适配多业务域；PostgreSQL 支持 JSONB 存动态饮品库；Redis 做会话/限流 |
| 推送 | iOS APNs + Android（FCM + 主厂保活文档引导） | PRD 要求 ≥95% 送达率 |
| 桌面小组件 | iOS WidgetKit（Swift） + Android AppWidget（Kotlin） | Flutter 通过 MethodChannel/EventChannel 与原生小组件同步进度数据 |
| 部署 | Docker Compose（本地/预发） + 生产 K8s 可选 | V1.0 单实例够用 |

## 项目结构（Monorepo）

```
water-llama/
├── app/                              # Flutter 客户端
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app/                      # App 入口、路由、主题、国际化
│   │   │   ├── app.dart
│   │   │   ├── router.dart
│   │   │   └── theme/
│   │   ├── core/                     # 跨域基础设施
│   │   │   ├── network/              # Dio、拦截器、错误降级
│   │   │   ├── storage/              # Isar、shared_preferences 封装
│   │   │   ├── notification/         # 本地/远程通知统一服务
│   │   │   ├── permission/           # 通知、健康权限引导
│   │   │   └── util/                 # 日期、毫升转换单元
│   │   ├── features/                 # 按 PRD 模块拆分
│   │   │   ├── onboarding/           # 2.1 初始化&目标计算
│   │   │   ├── home/                # 2.2 首页动物养成核心
│   │   │   │   ├── widgets/
│   │   │   │   │   ├── fluid_canvas.dart        # CustomPainter 流体动画
│   │   │   │   │   ├── animal_avatar.dart
│   │   │   │   │   └── progress_ring.dart
│   │   │   │   ├── providers/
│   │   │   │   └── home_screen.dart
│   │   │   ├── drink/                # 2.3 饮水记录&饮品折算
│   │   │   │   ├── models/drink_entry.dart
│   │   │   │   ├── models/beverage.dart
│   │   │   │   ├── services/hydration_calculator.dart   # 折算算法
│   │   │   │   └── widgets/drink_input_sheet.dart
│   │   │   ├── reminder/             # 2.4 智能提醒
│   │   │   │   ├── services/scheduler.dart
│   │   │   │   └── widgets/reminder_edit_sheet.dart
│   │   │   ├── stats/                # 2.5 数据统计&日历
│   │   │   │   ├── widgets/day_card.dart
│   │   │   │   ├── widgets/week_chart.dart
│   │   │   │   └── widgets/month_calendar.dart
│   │   │   ├── membership/          # 2.7 会员权益
│   │   │   ├── settings/            # 2.8 基础设置
│   │   │   └── ai/                   # 2.9 V2.0 AI 预留接口
│   │   │       └── ai_service.dart   # 抽象接口，V2.0 注入实现
│   │   ├── l10n/                     # 多语言（V1.0 仅 zh-CN，V2.0 海外）
│   │   └── shared/
│   │       ├── models/user_profile.dart
│   │       ├── models/member_state.dart
│   │       └── widgets/
│   ├── ios/                          # iOS 工程目录 + WidgetKit 扩展
│   │   ├── Runner/
│   │   └── WaterWidget/              # WidgetKit Extension
│   │       └── WaterWidget.swift
│   ├── android/                      # Android 工程目录 + AppWidget
│   │   ├── app/src/main/kotlin/.../WaterWidgetProvider.kt
│   │   └── app/src/main/res/xml/water_widget_info.xml
│   ├── test/
│   └── pubspec.yaml
├── server/                           # NestJS 后端
│   ├── src/
│   │   ├── main.ts
│   │   ├── app.module.ts
│   │   ├── modules/
│   │   │   ├── auth/                 # 登录、JWT、refresh
│   │   │   ├── user/                 # 用户档案、目标
│   │   │   ├── drink-records/        # 饮水记录同步
│   │   │   ├── beverages/            # 饮品库配置下发
│   │   │   ├── characters/           # 动物角色素材管理
│   │   │   ├── membership/           # 会员套餐、订单
│   │   │   ├── notifications/        # 推送 token、定时任务
│   │   │   ├── stats/                # 数据看板
│   │   │   └── ai-config/            # V2.0 AI 后台预留
│   │   ├── common/                   # 拦截器、过滤器、装饰器
│   │   └── infra/                    # DB、Redis、Storage 客户端
│   ├── prisma/schema.prisma          # PostgreSQL ORM
│   ├── test/
│   └── package.json
├── admin/                            # 后台管理（V1.0 用 React Admin 起）
│   └── (按 PRD §3 模块)
├── docs/
│   └── api/                          # OpenAPI 自动生成
└── docker-compose.yml
```

## 关键技术难点与方案

### 1. 流体填充动画（PRD §4.1 60fps + §4.5 真实流体物理）
- 使用 `CustomPainter` + `AnimationController`（vsync）
- 流体波浪：双正弦波叠加 + `Path` 描述水位线，`canvas.clipPath` 裁剪填充区域
- 物理感：基于 `Curves.easeInOutCubicEmphasized` + 弹性余震，提交瞬间水位上涌、随后回稳
- 动物形象分层（身体 / 眼睛 / 嘴），水位过半时眼睛被遮、触发惊讶表情，强化养成感
- 性能：`RepaintBoundary` 包裹 canvas，避免全局重绘；isolate 预计算波浪采样点

### 2. 双端桌面小组件数据同步
- **数据流**：Flutter 写 Isar → App Groups（iOS）/ SharedPreferences（Android）共享存储 → 原生 Widget 读取 → 系统定时刷新 + Flutter 通过 MethodChannel 主动触发 `WidgetCenter.reloadAllTimelines`（iOS）/ `AppWidgetManager.update`（Android）
- **共享 key**：`water.today_progress`、`water.goal`、`water.animal_id`、`water.updated_at`
- **小组件尺寸**：iOS 支持 small/medium/family；Android 支持 2x2/4x2

### 3. 离线优先 + 同步策略（PRD §4.2 断网可记录）
- 客户端 Isar 本地为主源，所有写入先落库
- 同步队列：每条 DrinkEntry 带 `synced: bool` + `client_id`（UUID）
- 联网后批量 POST `/drink-records/batch`，服务端按 `client_id` 去重
- 冲突策略：服务端时间戳为准，回写本地

### 4. 智能饮水量目标算法（PRD §2.1）
基础公式参考体重公式 + 活动量调整：
```
基础目标 = 体重(kg) × 35ml
活动量加成：低 +0、中 +350、高 +700
性别修正：男 × 1.0、女 × 0.9
身高修正：身高>175 +200
```
最终值四舍五入到 50ml 整数倍，并夹紧在 [1500, 4000] 范围。

### 5. 饮品水分折算（PRD §2.3）
抽象 `Beverage` 模型：`{id, name, category, hydration_ratio, default_ml, icon}`
预设 6 大类内置默认比例（水 100% / 茶 90% / 咖啡 70% / 奶茶果汁牛奶 80% / 汤粥 85% / 酒类特殊）
酒类规则：`有效水分 = 毫升 × 0.0`（不贡献目标进度），同时记录"当日补水缺口"用于 AI 提示（V2.0）

### 6. V2.0 AI 抽象层（PRD §2.9）
V1.0 即定义接口但不接通：
```dart
abstract class AiService {
  Future<DailyReport> generateDailyReport(Date date);
  Future<HydrationAdvice> getPersonalizedAdvice();
  Future<BeverageRecognition> recognizeBeverage(File image);
  Future<String> dailyQuote();
  Future<WeeklyDiagnosis> weeklyDiagnosis();
}
```
V1.0 注入 `NoopAiService`（返回本地静态文案），V2.0 替换为后端代理实现，避免客户端硬编码密钥。

## 里程碑（M1-M5）

### M1 — 基础设施 & 工程脚手架（1 周）
- Flutter 工程初始化、依赖、主题、路由、Riverpod 配置
- NestJS 工程初始化、Prisma schema、Docker Compose（PostgreSQL + Redis）
- Isar schema、shared_preferences 封装、Dio + 拦截器
- CI 基础（lint、format、test）

### M2 — 首页养成核心 + 录入（1.5 周，PRD §2.2 §2.3 §2.1）
- Onboarding 表单（性别 / 体重 / 身高 / 活动量），目标计算算法
- 首页 CustomPainter 流体填充动画 + 动物形象分层
- 饮水录入 BottomSheet：预设容量 + 自定义 + 饮品库选择
- 饮品折算算法 + 进度实时更新
- DrinkEntry Isar 模型 + 增删改查

### M3 — 数据统计 + 提醒 + 设置（1.5 周，PRD §2.4 §2.5 §2.8）
- 本地通知调度（flutter_local_notifications）+ 自定义文案 + 免打扰时段
- 日 / 周 / 月统计页 + fl_chart 折线 + 自绘月历打卡
- 连续打卡统计 + 最长记录
- 设置页：身体信息、目标修改、提醒开关、音效、静默时段、版本、缓存清理、协议

### M4 — 会员 + 双端桌面小组件（1.5 周，PRD §2.6 §2.7）
- iOS WidgetKit 扩展 + App Groups 共享存储
- Android AppWidgetProvider + SharedPreferences 共享
- Flutter ↔ 原生 MethodChannel 同步进度
- 会员套餐 UI + RevenueCat / 自研收银接入预留
- 免费用户广告位 + 会员无广告开关

### M5 — 后台管理 + 数据同步（1.5 周，PRD §3）
- NestJS 模块：auth / user / drink-records / beverages / characters / membership / notifications / stats
- 客户端同步队列 + 断网回写
- React Admin 后台：用户、饮品库、角色素材、订单、数据看板、AI 后台占位
- OpenAPI 文档

### V2.0 迭代（不纳入本次实施，仅留接口）
- AI 报告 / 个性化建议 / 拍照识别 / 文案 / 周诊断
- AI 后台配置

## V1.0 验收（PRD §4 非功能性）

| 项 | 验证方法 |
|---|---|
| 启动加载 ≤0.5s | Flutter DevTools Performance 抓帧；冷启动时间 ≤500ms |
| 流体动画 60fps | DevTools 帧率曲线无掉帧；低端 Android 设备实测 |
| 提交实时响应 | 录入 → 进度更新无可见延迟（<16ms 单帧） |
| 后端响应 ≤200ms | NestJS 集成测试 + Postman 平均响应时长 |
| 崩溃率 ≤0.1% | Sentry / Firebase Crashlytics 接入后回归 |
| 提醒送达率 ≥95% | iOS APNs + Android FCM 真机回归；统计回执 |
| 断网打卡 | 飞行模式录入 → 联网 → 后端数据一致性检查 |
| 双端小组件 | iOS/Android 真机锁屏可见，进度实时同步 |
| 深浅色模式 | 系统切换主题，所有页面无违和 |

## 关键文件清单（首批落地）

- [app/lib/main.dart](file:///C:/Users/admin/Documents/Trae-CN/temp_20261009_01/app/lib/main.dart)
- [app/lib/app/app.dart](file:///C:/Users/admin/Documents/Trae-CN/temp_20261009_01/app/lib/app/app.dart)
- [app/lib/app/router.dart](file:///C:/Users/admin/Documents/Trae-CN/temp_20261009_01/app/lib/app/router.dart)
- [app/lib/features/home/widgets/fluid_canvas.dart](file:///C:/Users/admin/Documents/Trae-CN/temp_20261009_01/app/lib/features/home/widgets/fluid_canvas.dart)
- [app/lib/features/drink/services/hydration_calculator.dart](file:///C:/Users/admin/Documents/Trae-CN/temp_20261009_01/app/lib/features/drink/services/hydration_calculator.dart)
- [app/lib/features/onboarding/onboarding_screen.dart](file:///C:/Users/admin/Documents/Trae-CN/temp_20261009_01/app/lib/features/onboarding/onboarding_screen.dart)
- [app/lib/core/storage/isar_provider.dart](file:///C:/Users/admin/Documents/Trae-CN/temp_20261009_01/app/lib/core/storage/isar_provider.dart)
- [server/src/main.ts](file:///C:/Users/admin/Documents/Trae-CN/temp_20261009_01/server/src/main.ts)
- [server/prisma/schema.prisma](file:///C:/Users/admin/Documents/Trae-CN/temp_20261009_01/server/prisma/schema.prisma)
- [docker-compose.yml](file:///C:/Users/admin/Documents/Trae-CN/temp_20261009_01/docker-compose.yml)

## 待用户确认的关键决策

实施前需要你确认以下 4 项，避免方向性返工：

1. **后端实现优先级**：是否本期就要完整 NestJS 后台 + 数据同步 + React Admin 后台（M5 全做），还是 V1.0 先做纯客户端 + Isar 本地优先，后台同步降级为 stub？后者 1 周可出可演示版本。
2. **会员付费通道**：iOS IAP + Android Google Play Billing（推荐 RevenueCat 统一），还是仅做会员 UI 不接真实支付（先看产品形态）？
3. **动物形象素材**：你有现成的角色美术（PNG/Lottie），还是要 AI 占位图 + 后续替换？影响 M2 进度。
4. **AI 接口归属**：V2.0 AI 接入是国内大模型（豆包 / 通义 / DeepSeek）还是 OpenAI/Anthropic？影响 AI 后台配置模块设计。

确认后我将按 M1 → M5 顺序逐步落地，每个里程碑产出可运行的演示版本。
