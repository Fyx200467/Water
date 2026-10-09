# 喝水养成 App（对标 WaterLlama）

iOS + Android 双端喝水养成 App。基于 [PRD](./.trae/documents/water-llama-app-implementation-plan.md) 实施，分 V1.0（无 AI）+ V2.0（AI 差异化）两阶段。

## 模块结构

| 目录 | 说明 |
|---|---|
| `app/` | Flutter 客户端，覆盖 iOS/Android 单码库 |
| `server/` | NestJS + PostgreSQL + Redis 后端 |
| `admin/` | 后台管理（M5 起） |
| `docs/` | 设计文档、API 文档 |
| `.trae/documents/` | 实施计划 |

## 启动

### 客户端
```bash
cd app
flutter pub get
flutter run
```

### 后端
```bash
cd server
npm install
docker compose up -d postgres redis
npx prisma migrate dev
npm run start:dev
```

## 里程碑进度

- [x] M1 — 工程脚手架
- [ ] M2 — 首页养成核心 + 饮水录入（PRD §2.1 §2.2 §2.3）
- [ ] M3 — 数据统计 + 提醒 + 设置（PRD §2.4 §2.5 §2.8）
- [ ] M4 — 会员 + 双端桌面小组件（PRD §2.6 §2.7）
- [ ] M5 — 后台管理 + 数据同步（PRD §3）

V2.0 AI 模块仅留接口，不纳入本期实施。
