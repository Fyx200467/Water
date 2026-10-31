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

  -- 积分流水：客户端离线累计后补传，服务端按 (user_id, event_id) 去重，
  -- 余额始终由流水求和得出，不接受客户端直接改总额
  CREATE TABLE IF NOT EXISTS points_events (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL REFERENCES users(id),
    event_id    TEXT NOT NULL,
    source      TEXT NOT NULL,
    amount      INTEGER NOT NULL,
    occurred_at TEXT NOT NULL,
    created_at  TEXT NOT NULL,
    UNIQUE(user_id, event_id)
  );

  CREATE INDEX IF NOT EXISTS idx_points_time
    ON points_events(user_id, occurred_at DESC);

  -- 登录凭证：一个账号可绑定多种方式（邮箱 / 后续微信、QQ），
  -- identifier 已按 provider 归一化（邮箱统一小写），secret_hash 为空表示免密第三方
  CREATE TABLE IF NOT EXISTS user_credentials (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL REFERENCES users(id),
    provider    TEXT NOT NULL,
    identifier  TEXT NOT NULL,
    secret_hash TEXT,
    created_at  TEXT NOT NULL,
    UNIQUE(provider, identifier)
  );

  CREATE INDEX IF NOT EXISTS idx_credentials_user
    ON user_credentials(user_id);

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

  -- 会员权益目录：后台勾选绑定到套餐，客户端会员中心按套餐展示
  CREATE TABLE IF NOT EXISTS membership_benefits (
    code         TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    description  TEXT,
    icon         TEXT,
    sort         INTEGER NOT NULL DEFAULT 0,
    is_published INTEGER NOT NULL DEFAULT 1,
    created_at   TEXT NOT NULL
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

  -- 饮品分类：后台可增删，App 按 code 归类；base_category 用于
  -- 未知分类在客户端的默认折算/插画回退（取值同 App 内置九类）
  CREATE TABLE IF NOT EXISTS beverage_categories (
    code          TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    color         TEXT,
    base_category TEXT NOT NULL,
    sort          INTEGER NOT NULL DEFAULT 0,
    created_at    TEXT NOT NULL
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

  CREATE TABLE IF NOT EXISTS character_categories (
    code       TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    sort       INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
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
    paid_at        TEXT,
    -- payment = 付费开通；points = 积分兑换（amount_cents 为 0）
    source         TEXT NOT NULL DEFAULT 'payment',
    points_cost    INTEGER NOT NULL DEFAULT 0
  );

  CREATE INDEX IF NOT EXISTS idx_orders_status
    ON membership_orders(status, created_at);

  -- 内测版本发布：客户端启动时据此提示更新（最新启用的一条生效）
  CREATE TABLE IF NOT EXISTS app_releases (
    id           TEXT PRIMARY KEY,
    platform     TEXT NOT NULL,
    version_name TEXT NOT NULL,
    version_code INTEGER NOT NULL,
    download_url TEXT,
    notes        TEXT,
    force_update INTEGER NOT NULL DEFAULT 0,
    is_published INTEGER NOT NULL DEFAULT 1,
    created_at   TEXT NOT NULL
  );

  CREATE INDEX IF NOT EXISTS idx_releases_platform
    ON app_releases(platform, version_code DESC);

  -- 用户反馈（内测收集问题用）
  CREATE TABLE IF NOT EXISTS feedback (
    id          TEXT PRIMARY KEY,
    user_id     TEXT,
    content     TEXT NOT NULL,
    contact     TEXT,
    app_version TEXT,
    platform    TEXT,
    device      TEXT,
    status      TEXT NOT NULL DEFAULT 'open',
    created_at  TEXT NOT NULL,
    resolved_at TEXT
  );

  CREATE INDEX IF NOT EXISTS idx_feedback_status
    ON feedback(status, created_at);

  -- 首页贴士卡：后台可增删改，客户端目录下发；表为空时用安装包内置卡池兜底
  CREATE TABLE IF NOT EXISTS tips (
    id          TEXT PRIMARY KEY,
    group_code  TEXT NOT NULL,
    title       TEXT NOT NULL,
    bg_color    TEXT,
    fg_color    TEXT,
    image_url   TEXT,
    sort        INTEGER NOT NULL DEFAULT 0,
    is_published INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT NOT NULL
  );

  CREATE INDEX IF NOT EXISTS idx_tips_published
    ON tips(is_published, sort);

  -- 挑战卡：取代贴士卡，服务端下发挑战目录，App 按 sort 展示。
  -- benefits 存 JSON 数组 [[emoji, 文案], ...]，三个 forbidden_* 也存 JSON 数组；
  -- asset 支持安装包内置路径（assets/images/characters/xxx.svg）或上传/网络地址
  CREATE TABLE IF NOT EXISTS challenges (
    id                  TEXT PRIMARY KEY,
    title               TEXT NOT NULL,
    subtitle            TEXT,
    bg_color            TEXT,
    asset               TEXT,
    intro               TEXT,
    benefits            TEXT,
    todo                TEXT,
    days                INTEGER NOT NULL DEFAULT 10,
    reward_points       INTEGER NOT NULL DEFAULT 1000,
    forbidden_labels    TEXT,
    forbidden_keywords  TEXT,
    forbidden_categories TEXT,
    sort                INTEGER NOT NULL DEFAULT 0,
    is_published        INTEGER NOT NULL DEFAULT 1,
    created_at          TEXT NOT NULL
  );

  CREATE INDEX IF NOT EXISTS idx_challenges_published
    ON challenges(is_published, sort);

  -- 客户端异常上报：内测阶段收集 Dart 未捕获异常（自建，不引入第三方 SDK）
  CREATE TABLE IF NOT EXISTS client_errors (
    id          TEXT PRIMARY KEY,
    user_id     TEXT,
    message     TEXT NOT NULL,
    stack       TEXT,
    app_version TEXT,
    platform    TEXT,
    device      TEXT,
    created_at  TEXT NOT NULL
  );

  CREATE INDEX IF NOT EXISTS idx_client_errors_time
    ON client_errors(created_at DESC);

  -- 客户端行为埋点：只记录关键漏斗事件，按 actor 去重统计转化
  -- actor_id = 登录用户 ID；游客为 anon:<本机匿名 ID>
  CREATE TABLE IF NOT EXISTS analytics_events (
    id          TEXT PRIMARY KEY,
    actor_id    TEXT NOT NULL,
    user_id     TEXT,
    event       TEXT NOT NULL,
    props       TEXT,
    platform    TEXT,
    app_version TEXT,
    created_at  TEXT NOT NULL
  );

  CREATE INDEX IF NOT EXISTS idx_analytics_event
    ON analytics_events(event, created_at DESC);

  CREATE INDEX IF NOT EXISTS idx_analytics_actor
    ON analytics_events(actor_id, event);
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
  password_hash: 'TEXT',
  phone: 'TEXT',
  gender: 'TEXT',
  weight_kg: 'REAL',
  height_cm: 'REAL',
  age: 'INTEGER',
  activity_level: 'TEXT',
  daily_goal_ml: 'INTEGER',
  // 头像相对地址（/static/avatars/xxx.jpg），跨设备登录时下发
  avatar_url: 'TEXT',
  membership_expire_at: 'TEXT',
  membership_permanent: 'INTEGER NOT NULL DEFAULT 0',
});

// 单设备登录：新登录时旧会话标记为撤销，客户端据此提示「已在其他设备登录」
addMissingColumns('sessions', {
  revoked_at: 'TEXT',
});

// 挑战卡为后加模块：老库可能只有 tips 表，这里按列补齐保证可直接建表使用
addMissingColumns('challenges', {
  title: 'TEXT',
  subtitle: 'TEXT',
  bg_color: 'TEXT',
  asset: 'TEXT',
  intro: 'TEXT',
  benefits: 'TEXT',
  todo: 'TEXT',
  days: 'INTEGER NOT NULL DEFAULT 10',
  reward_points: 'INTEGER NOT NULL DEFAULT 1000',
  forbidden_labels: 'TEXT',
  forbidden_keywords: 'TEXT',
  forbidden_categories: 'TEXT',
  sort: 'INTEGER NOT NULL DEFAULT 0',
  is_published: 'INTEGER NOT NULL DEFAULT 1',
  created_at: 'TEXT',
});

// 邮箱登录：同一邮箱只允许一个账号（未登录用户 email 为空，故使用部分索引）
db.exec(`
  CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email
    ON users(email) WHERE email IS NOT NULL;
`);

// 历史账号回填为邮箱凭证（users.email/password_hash 保留双写，供后台展示）
db.exec(`
  INSERT OR IGNORE INTO user_credentials
    (id, user_id, provider, identifier, secret_hash, created_at)
  SELECT 'cred_' || id, id, 'email', lower(email), password_hash, created_at
    FROM users
   WHERE email IS NOT NULL AND password_hash IS NOT NULL;
`);

addMissingColumns('beverages', {
  icon_url: 'TEXT',
  liquid_color: 'TEXT',
  // 营养值按每 250ml 计（与 App 内置预设的展示口径一致），酒精为 %vol
  calories: 'INTEGER',
  caffeine_mg: 'INTEGER',
  alcohol_percent: 'INTEGER',
  // 快捷容量档位：water = 5 档（100/200/300/500/1000），regular = 3 档（250/330/500）
  volume_preset: "TEXT NOT NULL DEFAULT 'regular'",
  // 液体动画：bubbles / micro / ice / rice / none；为空时客户端按 bubbles 兜底
  animation: 'TEXT',
});

addMissingColumns('membership_orders', {
  plan_name: 'TEXT',
  duration_days: 'INTEGER NOT NULL DEFAULT 0',
  source: "TEXT NOT NULL DEFAULT 'payment'",
  points_cost: 'INTEGER NOT NULL DEFAULT 0',
});

// 角色分类：与客户端「每日 / 可爱 / 人 / 家 / 蔬果 / 植物」一一对应
addMissingColumns('characters', {
  category_code: "TEXT NOT NULL DEFAULT 'daily'",
  // 每日随机池：仅「每日」分类下的角色参与随机；=0 的角色不进池（后台可配）
  in_daily_pool: 'INTEGER NOT NULL DEFAULT 1',
});

// 角色分类会员权益：后台可配置整组免费 / 会员专属（客户端据此加锁）
// 首次迁移按原客户端硬编码回填：daily 免费、其余内置分类会员专属
const hadCategoryMemberFlag = db
  .prepare(`SELECT name FROM pragma_table_info('character_categories')`)
  .all()
  .some((r) => r.name === 'member_only');
addMissingColumns('character_categories', {
  member_only: 'INTEGER NOT NULL DEFAULT 0',
});
if (!hadCategoryMemberFlag) {
  db.prepare(`UPDATE character_categories SET member_only = 1 WHERE code <> 'daily'`).run();
}

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

// 会员权益目录：与客户端会员中心内置文案一致；套餐里存逗号分隔的 code
const seedBenefit = db.prepare(
  `INSERT INTO membership_benefits (code, name, description, icon, sort, created_at)
   VALUES (?, ?, ?, ?, ?, ?)
   ON CONFLICT(code) DO NOTHING`,
);
const builtinBenefits = [
  ['characters', '全部动物角色', '免费版每日限量，会员解锁全部角色', 'pets', 0],
  ['beverages', '全部饮品库', '解锁奶茶、酒类与自定义饮品', 'local_drink', 1],
  ['widgets', '专属小组件', '自定义主题色与彩色字符层', 'widgets', 2],
  ['export', '数据导出', '一键导出全部饮水记录 CSV', 'ios_share', 3],
  ['adfree', '无广告', '纯净的饮水体验', 'block', 4],
];
for (const [code, name, desc, icon, sort] of builtinBenefits) {
  seedBenefit.run(code, name, desc, icon, sort, seededAt);
}

// 老库补列后把所有套餐默认为「全量权益」，与改造前的客户端表现一致；
// 只补 NULL，运营把某套餐权益清空（写入空串）后重启不会被回填
addMissingColumns('membership_plans', {
  benefits: 'TEXT',
});
db.prepare('UPDATE membership_plans SET benefits = ? WHERE benefits IS NULL').run(
  builtinBenefits.map(([code]) => code).join(','),
);

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

// 内置饮品营养值回填：口径与 App 预设一致（卡路里/咖啡因按每 250ml，酒精为 %vol）。
// 只补空值，不覆盖运营已经改过的数据。
const builtinNutrition = [
  ['water_pure', 0, 0, null, 'bubbles'],
  ['tea', 0, 47, null, 'bubbles'],
  ['coffee', 5, 95, null, 'bubbles'],
  ['milk_milk', 155, 0, null, 'bubbles'],
  ['milk_tea', 170, 45, null, 'bubbles'],
  ['milk_juice', 110, 0, null, 'bubbles'],
  ['soda', 100, 25, null, 'bubbles'],
  ['soup_porridge', 80, 0, null, 'rice'],
  ['soup_chicken', 35, 0, null, 'rice'],
  ['alcohol_beer', 110, 0, 3, 'bubbles'],
  ['alcohol_wine', 200, 0, 10, 'bubbles'],
  ['alcohol_spirits', 550, 0, 20, 'bubbles'],
];
const fillBuiltinNutrition = db.prepare(
  `UPDATE beverages
      SET calories = COALESCE(calories, ?),
          caffeine_mg = COALESCE(caffeine_mg, ?),
          alcohol_percent = COALESCE(alcohol_percent, ?),
          animation = COALESCE(animation, ?)
    WHERE id = ?`,
);
for (const [id, calories, caffeine, alcohol, animation] of builtinNutrition) {
  fillBuiltinNutrition.run(calories, caffeine, alcohol, animation, id);
}
// 纯水使用 5 档快捷容量，其余饮品默认 3 档
db.prepare("UPDATE beverages SET volume_preset = 'water' WHERE id = 'water_pure'").run();

// 内置九个分类：code 与 App 的 BeverageCategory 枚举名一致。
// base_category 为历史字段，客户端已不再读取，仅保留兼容旧数据。
// ON CONFLICT DO NOTHING：后台改过的名称/颜色/排序重启后不被覆盖。
const seedCategory = db.prepare(
  `INSERT INTO beverage_categories (code, name, color, base_category, sort, created_at)
   VALUES (?, ?, ?, ?, ?, ?)
   ON CONFLICT(code) DO NOTHING`,
);
const builtinCategories = [
  ['water', '纯水', '#00BFDC', 'water', 0],
  ['tea', '茶水类', '#8BC34A', 'tea', 1],
  ['coffee', '咖啡类', '#795548', 'coffee', 2],
  ['milk', '牛奶', '#90A4AE', 'milk', 3],
  ['milkTea', '奶茶', '#A8723C', 'milkTea', 4],
  ['juice', '果汁', '#FFB300', 'juice', 5],
  ['soda', '碳酸饮料', '#C9364F', 'soda', 6],
  ['soup', '汤粥类', '#FF8A65', 'soup', 7],
  ['alcohol', '酒类', '#E57373', 'alcohol', 8],
];
for (const [code, name, color, base, sort] of builtinCategories) {
  seedCategory.run(code, name, color, base, sort, seededAt);
}

// 角色分类：与客户端分类一一对应；member_only = 1 表示整组会员专属
const seedCharacterCategory = db.prepare(
  `INSERT INTO character_categories (code, name, sort, member_only, created_at)
   VALUES (?, ?, ?, ?, ?)
   ON CONFLICT(code) DO NOTHING`,
);
const builtinCharacterCategories = [
  ['daily', '每日', 0, 0],
  ['cute', '可爱', 1, 1],
  ['people', '人', 2, 1],
  ['home', '家', 3, 1],
  ['fruits', '蔬果', 4, 1],
  ['plants', '植物', 5, 1],
];
for (const [code, name, sort, memberOnly] of builtinCharacterCategories) {
  seedCharacterCategory.run(code, name, sort, memberOnly, seededAt);
}

// 内置 90 个角色：与客户端 assets/images/characters 同名素材，
// 素材由部署时上传到 assets/preset/characters/<code>.svg。
// ON CONFLICT(code) DO NOTHING：运营改过的名称/排序重启后不被覆盖。
const seedCharacter = db.prepare(
  `INSERT INTO characters
     (id, code, name, category_code, asset_url, thumbnail_url, member_only, sort, is_published, created_at, updated_at)
   VALUES (?, ?, ?, ?, ?, NULL, 0, ?, 1, ?, ?)
   ON CONFLICT(code) DO NOTHING`,
);
const builtinCharacters = [
  ['alpaca', '羊驼'],
  ['pony', '小马'],
  ['rabbit', '兔子'],
  ['fox', '狐'],
  ['polar_bear', '白熊'],
  ['red_squirrel', '红松鼠'],
  ['hedgehog', '刺猬'],
  ['beaver', '河狸'],
  ['otter', '海獭'],
  ['duck', '鸭鸭'],
  ['parrot', '鹦鹉'],
  ['turtle', '乌龟'],
  ['husky', '二哈'],
  ['rooster', '公鸡'],
  ['chameleon', '变色龙'],
  ['gecko', '壁虎'],
  ['swan', '天鹅'],
  ['goat_kid', '小山羊'],
  ['otter_kid', '小海獭'],
  ['goat', '山羊'],
  ['mole', '打地鼠'],
  ['zebra', '斑马'],
  ['hippo', '河马'],
  ['dolphin', '海豚'],
  ['turkey', '火鸡'],
  ['leopard', '灰豹'],
  ['sheep', '绵羊'],
  ['ram', '羊'],
  ['skunk', '臭鼬'],
  ['firefly2', '萤火虫'],
  ['firefly', '萤火虫'],
  ['snake', '蛇'],
  ['hummingbird', '蜂鸟'],
  ['bat', '蝙蝠'],
  ['panther', '豹子'],
  ['boar', '野猪'],
  ['pheasant', '野鸡'],
  ['fish', '鱼'],
  ['whale', '鲸鱼'],
  ['bird', '鸟'],
  ['lobster', '龙虾'],
  ['comfort', '安慰'],
  ['greeting', '打招呼'],
  ['inspired', '振奋'],
  ['delighted', '欣喜'],
  ['pensive', '沉思'],
  ['content', '满足'],
  ['person_04', '人物 04'],
  ['person_06', '人物 06'],
  ['person_07', '人物 07'],
  ['zannet_01', '人物 01'],
  ['zannet_02', '人物 02'],
  ['zannet_04', '人物 03'],
  ['zannet_07', '人物 05'],
  ['zannet_11', '人物 08'],
  ['raise_cup', '举杯'],
  ['cartoon_person', '卡通人物'],
  ['eating_pizza', '吃披萨'],
  ['sofa_snacks', '沙发零食'],
  ['sofa_drink', '沙发饮料'],
  ['delivery_rider', '外卖员'],
  ['bride', '新娘'],
  ['discussion', '讨论'],
  ['shopping_girl', '购物女孩'],
  ['orange_cat', '乖橘猫'],
  ['silly_dog', '大傻狗狗'],
  ['pet', '宠物'],
  ['corgi', '小柯基'],
  ['poodle', '小贵宾'],
  ['homesick_rabbit', '想家兔兔'],
  ['sleepy_cat', '瞌睡喵'],
  ['pineapple', '菠萝'],
  ['strawberry', '草莓'],
  ['cherries', '车厘子'],
  ['orange', '橙子'],
  ['orange_smile', '橙子微笑'],
  ['blueberry_kid', '蓝莓小子'],
  ['avocado', '牛油果'],
  ['avocado_watermelon', '牛油果和西瓜'],
  ['persimmon', '柿子'],
  ['watermelon_smile', '西瓜笑脸'],
  ['cherry', '樱桃'],
  ['cherry_pair', '一对樱桃'],
  ['flower_bunch', '一小撮花'],
  ['little_flower', '一朵小花'],
  ['big_leaf_plant', '大叶植物'],
  ['little_thing', '小之物'],
  ['potted_big_leaf', '大叶盆栽'],
  ['green_cactus', '绿色仙人球'],
  ['mushroom_baby', '蘑菇宝宝'],
];
// 客户端分类顺序：每日 41 / 可爱 6 / 人 17 / 家 7 / 蔬果 12 / 植物 7
const characterCategorySlices = [
  ['daily', 0, 41],
  ['cute', 41, 47],
  ['people', 47, 64],
  ['home', 64, 71],
  ['fruits', 71, 83],
  ['plants', 83, 90],
];
builtinCharacters.forEach(([code, name], i) => {
  const category =
    characterCategorySlices.find(([, start, end]) => i >= start && i < end)?.[0] ??
    'daily';
  seedCharacter.run(
    code,
    code,
    name,
    category,
    `/static/preset/characters/${code}.svg`,
    i,
    seededAt,
    seededAt,
  );
});


// 内置 9 条挑战卡：内容精确搬运自 App 的 challenge_catalog.dart（HabitData.all）。
// 表为空时一次性写入种子；运营改过或删过之后重启不再补种。
// benefits 为 [[emoji, 文案], ...]；asset 保留安装包内置路径，App 可直接读取。
const builtinChallenges = [
  {
    id: 'caffeine_free',
    title: '向咖啡因说不的\n卷尾猴',
    subtitle: '暂时告别咖啡因带来的兴奋',
    bgColor: '#6D4C38',
    asset: 'assets/images/characters/red_squirrel.svg',
    intro:
      '咖啡因虽能短暂提神，但过量摄入会影响睡眠与情绪。用 10 天时间告别对咖啡因的依赖，找回自然的清醒节律。',
    benefits: [
      ['🦉', '改善睡眠质量。你会更快入睡，获得更多睡眠时间使身体恢复活力。'],
      ['🐢', '避免焦虑和抑郁。神经系统中的"战斗或逃跑"激素不会像现在这样经常受到刺激。'],
      ['🦷', '让牙齿更加健康洁白。咖啡渍更少，还能减少酸蚀度导致的牙釉质腐蚀情况。'],
    ],
    todo:
      '请保持在白天摄入的咖啡因总量低于 55 毫克。这通常等于半杯普通咖啡或卡布奇诺咖啡、一杯红茶或两杯绿茶或抹茶。请注意能量饮料和苏打水，因为可口可乐或百事可乐也含有咖啡因。',
    days: 10,
    rewardPoints: 1000,
    forbiddenLabels: ['美式咖啡', '卡布奇诺', '能量饮料', '可乐'],
    forbiddenKeywords: ['咖啡', '可乐', '能量饮料', '红牛'],
    forbiddenCategories: ['coffee'],
  },
  {
    id: 'tea_lover',
    title: '爱喝茶的\n霸王龙',
    subtitle: '用温和的茶水开启补水冒险',
    bgColor: '#3FA65C',
    asset: 'assets/images/characters/turtle.svg',
    intro:
      '茶是世界上仅次于水的第二大饮品。用花草茶与绿茶替代含糖饮料，既满足味蕾又补充水分，10 天养成温和饮茶的好习惯。',
    benefits: [
      ['🍃', '摄入更多抗氧化物质。茶多酚帮助身体对抗自由基，保持年轻状态。'],
      ['💧', '温和补水。淡茶水同样计入每日饮水量，风味更佳更容易坚持。'],
      ['😌', '舒缓身心。花草茶的天然香气能帮助放松情绪，缓解一天的疲劳。'],
    ],
    todo:
      '每天至少用一杯淡茶替代一份含糖饮料。避免空腹饮浓茶，下午 4 点后优先选择花草茶或低咖啡因茶，以免影响入睡。',
    days: 10,
    rewardPoints: 1000,
    forbiddenLabels: ['含糖饮料', '奶茶', '果汁', '汽水'],
    forbiddenKeywords: ['奶茶', '果汁', '汽水', '可乐'],
    forbiddenCategories: ['milkTea', 'juice', 'soda'],
  },
  {
    id: 'sugar_free',
    title: '不吃糖的\n猎豹',
    subtitle: '暂时戒掉零食与甜饮料',
    bgColor: '#D8354A',
    asset: 'assets/images/characters/leopard.svg',
    intro:
      '添加糖隐藏在饮料、零食甚至酱料里。10 天无糖挑战帮你重置味蕾，摆脱"甜蜜陷阱"，恢复敏锐的味觉与稳定的精力。',
    benefits: [
      ['⚡', '精力更稳定。血糖不再大起大落，午后犯困和情绪波动明显减少。'],
      ['✨', '皮肤更透亮。减少糖分摄入有助于维持胶原蛋白，肤色更均匀。'],
      ['🍋', '味觉更敏锐。重置味蕾后，水果的天然甜味也会变得格外迷人。'],
    ],
    todo:
      '挑战期间避免添加糖：不喝含糖饮料、不吃糖果与甜品。阅读配料表，白砂糖、果葡糖浆、蜂蜜等都算添加糖。天然水果可以正常吃。',
    days: 10,
    rewardPoints: 1000,
    forbiddenLabels: ['含糖饮料', '奶茶', '果汁', '甜品饮品'],
    forbiddenKeywords: ['糖', '奶茶', '果汁', '汽水'],
    forbiddenCategories: ['milkTea', 'juice', 'soda'],
  },
  {
    id: 'slim_sloth',
    title: '积极瘦身的\n树懒',
    subtitle: '慢下来，也能轻盈起来',
    bgColor: '#3F9E7B',
    asset: 'assets/images/characters/sheep.svg',
    intro:
      '瘦身不必激进节食。像树懒一样缓慢而坚定：饭前一杯水、细嚼慢咽、规律作息，10 天建立让身体自然轻盈的日常节奏。',
    benefits: [
      ['🥗', '饮食更自律。饭前喝水能带来适度饱腹感，避免无意识过量进食。'],
      ['💤', '睡眠与代谢更规律。固定的作息让身体修复效率更高。'],
      ['💪', '养成可持续的习惯。不反弹的减重，来自每天一点点的小改变。'],
    ],
    todo:
      '每天三餐前各喝一杯水，吃饭时专注细嚼慢咽（每口 15 次以上），晚上 11 点前入睡。不追求速度，坚持完成每一天就是胜利。',
    days: 10,
    rewardPoints: 1000,
    forbiddenLabels: ['含糖饮料', '奶茶', '啤酒', '红酒'],
    forbiddenKeywords: ['奶茶', '果汁', '汽水', '啤酒', '红酒'],
    forbiddenCategories: ['milkTea', 'juice', 'soda', 'alcohol'],
  },
  {
    id: 'lactose_free',
    title: '拒绝乳糖的\n鸭嘴兽',
    subtitle: '暂时告别牛奶和奶茶',
    bgColor: '#E88BB6',
    asset: 'assets/images/characters/duck.svg',
    intro:
      '如果你乳糖不耐受，奶茶和拿铁可能带来腹胀与不适。10 天暂时告别乳制品，观察身体的轻松变化，找到更适合自己的饮品。',
    benefits: [
      ['🌿', '肠胃更舒服。腹胀、肠鸣等乳糖不耐受症状明显缓解。'],
      ['🫧', '减少隐形糖分。奶茶往往含大量糖与植脂末，戒断后摄入更干净。'],
      ['🥥', '发现新选择。燕麦奶、椰奶等植物奶同样香浓，还能补充水分。'],
    ],
    todo:
      '挑战期间不喝牛奶、奶茶、拿铁等含乳糖饮品。咖啡可换美式或燕麦拿铁，注意查看奶茶配料表中的乳清与奶粉同样是乳糖来源。',
    days: 10,
    rewardPoints: 1000,
    forbiddenLabels: ['牛奶', '奶茶', '拿铁', '乳制品'],
    forbiddenKeywords: ['牛奶', '奶茶', '拿铁', '乳清'],
    forbiddenCategories: ['milk', 'milkTea'],
  },
  {
    id: 'vitamin',
    title: '维生素满满的\n海雀',
    subtitle: '多吃水果与蔬菜',
    bgColor: '#F59B31',
    asset: 'assets/images/characters/bird.svg',
    intro:
      '维生素与矿物质是身体运转的润滑剂。10 天里让蔬果成为每餐的主角，像海雀一样活力满满，皮肤、精力与免疫力都会回报你。',
    benefits: [
      ['🍊', '免疫力更强。维生素 C 帮助身体抵御换季的不适。'],
      ['🌟', '皮肤更有光泽。天然抗氧化剂由内而外滋养肌肤。'],
      ['🚀', '精力更充沛。均衡的微量营养素让疲劳感远离你。'],
    ],
    todo:
      '每天保证 3 份蔬菜 + 2 份水果（约每份一个拳头大小），颜色越丰富越好。果汁不能替代完整水果，尽量带皮吃以保留膳食纤维。',
    days: 10,
    rewardPoints: 1000,
    forbiddenLabels: ['果汁', '果味饮料', '加糖果茶'],
    forbiddenKeywords: ['果汁', '果味饮料', '果茶'],
    forbiddenCategories: ['juice'],
  },
  {
    id: 'no_alcohol',
    title: '对酒说不的\n熊',
    subtitle: '暂时戒掉定时喝酒的习惯',
    bgColor: '#5A5FC8',
    asset: 'assets/images/characters/polar_bear.svg',
    intro:
      '睡前小酌看似放松，实则打乱深睡节律。10 天不喝酒，让大脑与肝脏好好休息，你会发现清晨的自己比想象中清醒得多。',
    benefits: [
      ['🌙', '睡眠更深。快速眼动睡眠恢复，早晨醒来更有精神。'],
      ['❤️', '心血管减负。酒精带来的血压波动与潮红不再出现。'],
      ['🧠', '头脑更清晰。专注力与记忆力在戒断第一周就开始回升。'],
    ],
    todo:
      '挑战期间滴酒不沾，包括啤酒、红酒、白酒与含酒精饮料。聚会时可以用气泡水加青柠代替，睡前想小酌的冲动试试用一杯温水化解。',
    days: 10,
    rewardPoints: 1000,
    forbiddenLabels: ['啤酒', '红酒', '白酒', '鸡尾酒'],
    forbiddenKeywords: ['啤酒', '红酒', '白酒', '酒精'],
    forbiddenCategories: ['alcohol'],
  },
  {
    id: 'wine_free',
    title: '戒红酒的\n鼬鼠',
    subtitle: '暂时戒掉定时喝酒的习惯',
    bgColor: '#9E1B2F',
    asset: 'assets/images/characters/otter.svg',
    intro:
      '红酒常被视作"健康选择"，但过量饮酒从来都不是健康的选择。大多数人并不依赖酒精，但我们常常需要一点额外的动力来帮助我们控制饮酒。',
    benefits: [
      ['🐬', '让皮肤更加健康。你不会因饮酒而血流加速并血管扩张，从而避免皮肤发红或浮肿。'],
      ['🦩', '让体重更加轻盈。你不会因为酒精而丧失做出明智饮食选择的能力。'],
      ['🕊️', '情绪更平稳。酒精是抑制剂，戒断后情绪波动明显减少。'],
    ],
    todo:
      '挑战期间不饮用任何种类的红酒，包括干红、甜型与起泡酒。晚餐想配酒的仪式感可以用无醇葡萄酒或葡萄气泡水替代。',
    days: 10,
    rewardPoints: 1000,
    forbiddenLabels: ['干红', '甜红', '起泡酒', '香槟'],
    forbiddenKeywords: ['红酒', '葡萄酒', '香槟'],
    forbiddenCategories: ['alcohol'],
  },
  {
    id: 'beer_free',
    title: '不喝啤酒的\n鹿',
    subtitle: '聚会也不碰啤酒的清爽挑战',
    bgColor: '#D9B426',
    asset: 'assets/images/characters/ram.svg',
    intro:
      '啤酒的热量常被低估——一大杯等于一碗米饭。10 天不喝啤酒，告别"啤酒肚"的隐忧，聚会照样尽兴，身体更轻快。',
    benefits: [
      ['🎯', '腰围更友好。啤酒热量高且促进食欲，戒断后更容易控制体重。'],
      ['💛', '肝脏更轻松。肝脏获得休息，代谢功能逐步恢复。'],
      ['🧊', '补水更纯粹。用气泡水与鲜榨饮品替代，水分吸收效率更高。'],
    ],
    todo:
      '挑战期间不喝任何啤酒，包括无醇啤酒（仍含微量酒精与啤酒风味）。观赛聚会场景提前备好冰镇气泡水或康普茶，避免口渴时顺手拿起啤酒。',
    days: 10,
    rewardPoints: 1000,
    forbiddenLabels: ['工业啤酒', '精酿啤酒', '黑啤', '果啤'],
    forbiddenKeywords: ['啤酒', '精酿', '黑啤', '果啤'],
    forbiddenCategories: ['alcohol'],
  },
];

const challengeCount = db.prepare('SELECT COUNT(*) AS n FROM challenges').get().n;
if (challengeCount === 0) {
  const seedChallenge = db.prepare(
    `INSERT INTO challenges
       (id, title, subtitle, bg_color, asset, intro, benefits, todo, days,
        reward_points, forbidden_labels, forbidden_keywords, forbidden_categories,
        sort, is_published, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)`,
  );
  builtinChallenges.forEach((c, i) => {
    seedChallenge.run(
      c.id,
      c.title,
      c.subtitle,
      c.bgColor,
      c.asset,
      c.intro,
      JSON.stringify(c.benefits),
      c.todo,
      c.days,
      c.rewardPoints,
      JSON.stringify(c.forbiddenLabels),
      JSON.stringify(c.forbiddenKeywords),
      JSON.stringify(c.forbiddenCategories),
      i,
      seededAt,
    );
  });
}

export const nowIso = () => new Date().toISOString();
export { dbPath };
