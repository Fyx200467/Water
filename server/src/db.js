import { mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

// 开发阶段数据目录放在可写的工作区里，可用 DB_PATH 覆盖
const dbPath =
  process.env.DB_PATH ||
  join(homedir(), 'Documents', 'Trae-CN', 'default', '.water-server', 'water.db');
mkdirSync(dirname(dbPath), { recursive: true });

export const db = new DatabaseSync(dbPath);

db.exec(`
  PRAGMA journal_mode = WAL;
  PRAGMA foreign_keys = ON;

  CREATE TABLE IF NOT EXISTS users (
    id         TEXT PRIMARY KEY,
    anon_id    TEXT NOT NULL UNIQUE,
    nickname   TEXT NOT NULL DEFAULT '喝水羊驼',
    rev_seq    INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    deleted_at TEXT
  );

  CREATE TABLE IF NOT EXISTS sessions (
    token      TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL REFERENCES users(id),
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS drink_entries (
    user_id    TEXT NOT NULL REFERENCES users(id),
    client_id  TEXT NOT NULL,
    drank_at   TEXT NOT NULL,
    volume_ml  REAL NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    server_rev INTEGER NOT NULL,
    data       TEXT NOT NULL,
    PRIMARY KEY (user_id, client_id)
  );

  CREATE INDEX IF NOT EXISTS idx_entries_rev
    ON drink_entries(user_id, server_rev);

  CREATE TABLE IF NOT EXISTS settings (
    user_id    TEXT NOT NULL REFERENCES users(id),
    key        TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    server_rev INTEGER NOT NULL,
    value      TEXT,
    PRIMARY KEY (user_id, key)
  );

  CREATE INDEX IF NOT EXISTS idx_settings_rev
    ON settings(user_id, server_rev);

  CREATE TABLE IF NOT EXISTS membership_plans (
    code         TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    price_cents  INTEGER NOT NULL,
    duration_days INTEGER NOT NULL,
    badge        TEXT,
    is_published INTEGER NOT NULL DEFAULT 1,
    sort         INTEGER NOT NULL DEFAULT 0,
    updated_at   TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS admins (
    id            TEXT PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role          TEXT NOT NULL DEFAULT 'admin',
    created_at    TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS admin_sessions (
    token      TEXT PRIMARY KEY,
    admin_id   TEXT NOT NULL REFERENCES admins(id),
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS beverages (
    id             TEXT PRIMARY KEY,
    name           TEXT NOT NULL,
    category       TEXT NOT NULL,
    default_ml     INTEGER NOT NULL,
    hydration_ratio REAL NOT NULL,
    icon_url       TEXT,
    liquid_color   TEXT,
    member_only    INTEGER NOT NULL DEFAULT 0,
    sort           INTEGER NOT NULL DEFAULT 0,
    is_published   INTEGER NOT NULL DEFAULT 1,
    created_at     TEXT NOT NULL,
    updated_at     TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS characters (
    id            TEXT PRIMARY KEY,
    code          TEXT NOT NULL UNIQUE,
    name          TEXT NOT NULL,
    asset_url     TEXT NOT NULL,
    thumbnail_url TEXT,
    member_only   INTEGER NOT NULL DEFAULT 0,
    sort          INTEGER NOT NULL DEFAULT 0,
    is_published  INTEGER NOT NULL DEFAULT 1,
    created_at    TEXT NOT NULL,
    updated_at    TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS membership_orders (
    id             TEXT PRIMARY KEY,
    user_id        TEXT NOT NULL,
    plan_code      TEXT NOT NULL,
    plan_name      TEXT,
    duration_days  INTEGER NOT NULL DEFAULT 0,
    amount_cents   INTEGER NOT NULL,
    status         TEXT NOT NULL DEFAULT 'pending',
    external_tx_id TEXT,
    created_at     TEXT NOT NULL,
    paid_at        TEXT
  );

  CREATE INDEX IF NOT EXISTS idx_orders_status
    ON membership_orders(status, created_at);
`);

// 轻量迁移：历史库补列（users 个人资料 + 会员字段、订单套餐快照）
function addMissingColumns(table, columns) {
  const existing = new Set(
    db
      .prepare(`SELECT name FROM pragma_table_info('${table}')`)
      .all()
      .map((r) => r.name),
  );
  for (const [name, type] of Object.entries(columns)) {
    if (!existing.has(name)) db.exec(`ALTER TABLE ${table} ADD COLUMN ${name} ${type}`);
  }
}

addMissingColumns('users', {
  email: 'TEXT',
  phone: 'TEXT',
  gender: 'TEXT',
  weight_kg: 'REAL',
  height_cm: 'REAL',
  daily_goal_ml: 'INTEGER',
  membership_expire_at: 'TEXT',
  membership_permanent: 'INTEGER NOT NULL DEFAULT 0',
});

addMissingColumns('beverages', {
  icon_url: 'TEXT',
  liquid_color: 'TEXT',
});

addMissingColumns('membership_orders', {
  plan_name: 'TEXT',
  duration_days: 'INTEGER NOT NULL DEFAULT 0',
});

// 套餐默认值与 App 内置兜底保持一致
const seedPlan = db.prepare(
  `INSERT INTO membership_plans (code, name, price_cents, duration_days, badge, sort, updated_at)
   VALUES (?, ?, ?, ?, ?, ?, ?)
   ON CONFLICT(code) DO NOTHING`,
);
const seededAt = new Date().toISOString();
seedPlan.run('monthly', '月卡', 1800, 30, null, 1, seededAt);
seedPlan.run('yearly', '年卡', 9800, 365, '推荐', 2, seededAt);
seedPlan.run('lifetime', '永久会员', 19800, 0, '一次买断', 3, seededAt);

// 内置 12 款饮品：与 App 端 Beverage.presets 同 id，后台可直接改图标/颜色/容量。
// ON CONFLICT(id) DO NOTHING：重启不覆盖运营已改过的数据。icon_url 为空时
// 客户端继续用安装包里的本地 SVG 容器，填了才改用云端图标。
const seedBeverage = db.prepare(
  `INSERT INTO beverages (id, name, category, default_ml, hydration_ratio, icon_url, liquid_color, member_only, sort, is_published, created_at, updated_at)
   VALUES (?, ?, ?, ?, ?, NULL, ?, 0, ?, 1, ?, ?)
   ON CONFLICT(id) DO NOTHING`,
);
const builtinBeverages = [
  ['water_pure', '纯净水', 'water', 250, 1.0, null, 0],
  ['tea', '茶', 'tea', 250, 0.9, null, 1],
  ['coffee', '咖啡', 'coffee', 250, 0.7, '#6B3E2E', 2],
  ['milk_milk', '牛奶', 'milk', 250, 0.8, '#C8CDD0', 3],
  ['milk_tea', '奶茶', 'milkTea', 500, 0.8, '#A8723C', 4],
  ['milk_juice', '果汁', 'juice', 300, 0.8, '#FFB300', 5],
  ['soda', '碳酸饮料', 'soda', 330, 0.9, '#C9364F', 6],
  ['soup_porridge', '白粥', 'soup', 300, 0.85, '#F5EFE2', 7],
  ['soup_chicken', '鸡汤', 'soup', 250, 0.85, '#FFB300', 8],
  ['alcohol_beer', '啤酒', 'alcohol', 500, -0.4, '#FFC107', 9],
  ['alcohol_wine', '红酒', 'alcohol', 150, -0.95, '#A62034', 10],
  ['alcohol_spirits', '白酒', 'alcohol', 100, -3.18, '#E3E8EC', 11],
];
for (const [id, name, category, ml, ratio, color, sort] of builtinBeverages) {
  seedBeverage.run(id, name, category, ml, ratio, color, sort, seededAt, seededAt);
}

export const nowIso = () => new Date().toISOString();
export { dbPath };
