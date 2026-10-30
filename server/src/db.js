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
    paid_at        TEXT
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


export const nowIso = () => new Date().toISOString();
export { dbPath };
