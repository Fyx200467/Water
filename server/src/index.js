import crypto from 'node:crypto';
import {
  appendFileSync,
  createReadStream,
  existsSync,
  mkdirSync,
  readdirSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { db, dbPath, nowIso } from './db.js';

const accessLog = process.env.ACCESS_LOG ||
  `${os.homedir()}/Documents/Trae-CN/default/.water-server/access.log`;
const logLine = (line) => {
  try {
    appendFileSync(accessLog, `${new Date().toISOString()} ${line}\n`);
  } catch {}
};

const assetsDir =
  process.env.ASSETS_DIR ||
  `${os.homedir()}/Documents/Trae-CN/default/.water-server/assets`;
mkdirSync(assetsDir, { recursive: true });

// 管理后台页面目录（可选，部署时通过 ADMIN_DIR 指定）
const adminDir =
  process.env.ADMIN_DIR ||
  `${os.homedir()}/Documents/Trae-CN/default/.water-server/admin`;

const PORT = Number(process.env.PORT || 3000);
const TOKEN_TTL_DAYS = 365;
const MAX_PUSH_ITEMS = 500;
const MAX_PULL_ITEMS = 500;

// ==================== HTTP 工具 ====================

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS',
};

function send(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
    ...corsHeaders,
  });
  res.end(payload);
}

const fail = (res, status, code, message) =>
  send(res, status, { error: { code, message } });

function readJson(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > 2 * 1024 * 1024) {
        reject(new Error('body_too_large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (!chunks.length) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        reject(new Error('invalid_json'));
      }
    });
    req.on('error', reject);
  });
}

/// 读取原始二进制请求体（素材上传用）
function readRaw(req, limit = 3 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > limit) {
        reject(new Error('body_too_large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

const staticTypes = {
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
};

/// 素材托管：/static/<文件名> 映射到 assets 目录
function serveStatic(res, pathname) {
  let rel = '';
  try {
    rel = decodeURIComponent(pathname.slice('/static/'.length));
  } catch {
    rel = '';
  }
  const root = path.resolve(assetsDir) + path.sep;
  const filePath = path.resolve(assetsDir, rel);
  if (!rel || !filePath.startsWith(root) || !existsSync(filePath)) {
    return fail(res, 404, 'not_found', '文件不存在');
  }
  const stat = statSync(filePath);
  if (!stat.isFile()) return fail(res, 404, 'not_found', '文件不存在');
  res.writeHead(200, {
    'Content-Type':
      staticTypes[path.extname(filePath).toLowerCase()] ||
      'application/octet-stream',
    'Content-Length': stat.size,
    'Cache-Control': 'public, max-age=86400',
    ...corsHeaders,
  });
  createReadStream(filePath).pipe(res);
}

const isIso = (v) => typeof v === 'string' && !Number.isNaN(Date.parse(v));

// ==================== 管理员鉴权 ====================

const ADMIN_TOKEN_TTL_DAYS = 7;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(password, salt, 32).toString('hex');
  return `${salt}:${hash}`;
}

function verifyPassword(password, stored) {
  const [salt, hash] = String(stored || '').split(':');
  if (!salt || !hash) return false;
  const expected = Buffer.from(hash, 'hex');
  const actual = crypto.scryptSync(password, salt, 32);
  return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
}

function createAdminSession(adminId) {
  const token = crypto.randomUUID();
  const created = new Date();
  const expires = new Date(created.getTime() + ADMIN_TOKEN_TTL_DAYS * 86400000);
  db.prepare(
    'INSERT INTO admin_sessions (token, admin_id, created_at, expires_at) VALUES (?, ?, ?, ?)',
  ).run(token, adminId, created.toISOString(), expires.toISOString());
  return { token, expiresAt: expires.toISOString() };
}

function authenticateAdmin(req) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) return null;
  const row = db
    .prepare(
      `SELECT s.expires_at, a.id, a.email, a.role
         FROM admin_sessions s JOIN admins a ON a.id = s.admin_id
        WHERE s.token = ?`,
    )
    .get(token);
  if (!row || row.expires_at < nowIso()) return null;
  return { id: row.id, email: row.email, role: row.role };
}

// 首次启动时写入默认管理员，账号密码可在环境变量里覆盖
const DEFAULT_ADMIN_EMAIL = process.env.ADMIN_EMAIL || 'admin@example.com';
const DEFAULT_ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin123456';
function ensureDefaultAdmin() {
  const email = DEFAULT_ADMIN_EMAIL.toLowerCase();
  const count = db.prepare('SELECT COUNT(*) AS n FROM admins').get().n;

  if (count === 0) {
    db.prepare(
      'INSERT INTO admins (id, email, password_hash, role, created_at) VALUES (?, ?, ?, ?, ?)',
    ).run(
      crypto.randomUUID(),
      email,
      hashPassword(DEFAULT_ADMIN_PASSWORD),
      'admin',
      nowIso(),
    );
    return;
  }

  // 应急重置：显式设置 ADMIN_RESET=1 时才用环境变量覆盖口令并踢掉旧会话
  if (process.env.ADMIN_RESET === '1' && process.env.ADMIN_PASSWORD) {
    const target =
      db.prepare('SELECT id FROM admins WHERE email = ?').get(email) ||
      db.prepare('SELECT id FROM admins ORDER BY created_at LIMIT 1').get();
    if (!target) return;
    db.prepare('UPDATE admins SET email = ?, password_hash = ? WHERE id = ?').run(
      email,
      hashPassword(DEFAULT_ADMIN_PASSWORD),
      target.id,
    );
    db.prepare('DELETE FROM admin_sessions WHERE admin_id = ?').run(target.id);
    console.log('[admin] password reset from ADMIN_PASSWORD');
  }
}

function pageArgs(url) {
  const page = Math.max(1, Number(url.searchParams.get('page') || 1) || 1);
  const rawSize = Number(url.searchParams.get('pageSize') || 20) || 20;
  const pageSize = Math.min(100, Math.max(1, rawSize));
  return { page, pageSize, offset: (page - 1) * pageSize };
}

const boolInt = (v) => (v ? 1 : 0);
const toBool = (v) => v === 1 || v === true;
const optInt = (v) => {
  if (v === undefined || v === null || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? Math.round(n) : null;
};

const VOLUME_PRESETS = new Set(['water', 'regular']);
const ANIMATIONS = new Set(['bubbles', 'micro', 'ice', 'rice', 'none']);

// 贴士卡分组：与客户端 TipGroup 一一对应
const TIP_GROUPS = new Set(['hydration', 'lifehacks', 'drinks', 'health', 'general']);

// 客户端埋点白名单：只收关键漏斗事件，避免被当成通用日志表
const ANALYTICS_EVENTS = new Set([
  'membership_view',
  'plan_select',
  'order_submit',
  'order_confirmed',
  'paywall_view',
  'checkin',
]);

const FUNNEL_STEPS = [
  ['membership_view', '进入会员页'],
  ['plan_select', '选择套餐'],
  ['order_submit', '提交申请'],
  ['order_confirmed', '开通成功'],
];

/// 校验饮品数值字段；partial=true 时只校验本次显式传入的字段。
/// 卡路里/咖啡因按每 250ml 计，酒精为 %vol。
function validateBeverageBody(body, partial = false) {
  if (!partial || body.defaultMl !== undefined) {
    const ml = Number(body.defaultMl ?? 250);
    if (!Number.isFinite(ml) || ml <= 0 || ml > 5000) {
      return { code: 'invalid_volume', message: '默认容量需为 1-5000 ml' };
    }
  }
  if (!partial || body.hydrationRatio !== undefined) {
    const ratio = Number(body.hydrationRatio ?? 1);
    if (!Number.isFinite(ratio) || ratio < -10 || ratio > 1.5) {
      return { code: 'invalid_ratio', message: '折算比例需在 -10 到 1.5 之间' };
    }
  }
  const nutrition = [
    ['calories', '卡路里', 10000],
    ['caffeineMg', '咖啡因', 5000],
    ['alcoholPercent', '酒精', 100],
  ];
  for (const [key, label, max] of nutrition) {
    if (body[key] === undefined || body[key] === null || body[key] === '') continue;
    const n = Number(body[key]);
    if (!Number.isFinite(n) || n < 0 || n > max) {
      return { code: 'invalid_nutrition', message: `${label}需为 0-${max}` };
    }
  }
  if (body.volumePreset !== undefined &&
      !VOLUME_PRESETS.has(String(body.volumePreset))) {
    return { code: 'invalid_volume_preset', message: '容量档位不合法' };
  }
  if (body.animation !== undefined && body.animation !== null &&
      body.animation !== '' && !ANIMATIONS.has(String(body.animation))) {
    return { code: 'invalid_animation', message: '液体动画不合法' };
  }
  return null;
}

const BEVERAGE_SELECT = `SELECT b.*, c.name AS category_name, c.color AS category_color,
       c.base_category
  FROM beverages b LEFT JOIN beverage_categories c ON c.code = b.category`;

function mapBeverage(r) {
  return {
    id: r.id,
    name: r.name,
    category: r.category,
    categoryName: r.category_name || null,
    categoryColor: r.category_color || null,
    baseCategory: r.base_category || null,
    defaultMl: r.default_ml,
    hydrationRatio: r.hydration_ratio,
    iconUrl: r.icon_url,
    liquidColor: r.liquid_color,
    // 营养值口径：卡路里/咖啡因按每 250ml，酒精为 %vol；空值表示未配置
    calories: r.calories ?? null,
    caffeineMg: r.caffeine_mg ?? null,
    alcoholPercent: r.alcohol_percent ?? null,
    volumePreset: r.volume_preset || 'regular',
    animation: r.animation || null,
    memberOnly: toBool(r.member_only),
    sort: r.sort,
    isPublished: toBool(r.is_published),
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

function mapCharacter(r) {
  return {
    id: r.id,
    code: r.code,
    name: r.name,
    categoryCode: r.category_code || 'daily',
    assetUrl: r.asset_url,
    thumbnailUrl: r.thumbnail_url,
    memberOnly: toBool(r.member_only),
    inDailyPool: toBool(r.in_daily_pool),
    sort: r.sort,
    isPublished: toBool(r.is_published),
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

/// 订单支付成功后写入会员有效期：按时长顺延，0 天视为永久
function grantMembership(userId, durationDays) {
  const user = db
    .prepare(
      'SELECT membership_expire_at, membership_permanent FROM users WHERE id = ?',
    )
    .get(userId);
  if (!user) return { expireAt: null, permanent: false };
  if (user.membership_permanent) return { expireAt: null, permanent: true };

  const now = Date.now();
  if (Number(durationDays) > 0) {
    const current = user.membership_expire_at
      ? Date.parse(user.membership_expire_at)
      : NaN;
    const base = Number.isFinite(current) && current > now ? current : now;
    const expireAt = new Date(base + Number(durationDays) * 86400000).toISOString();
    db.prepare(
      'UPDATE users SET membership_expire_at = ?, membership_permanent = 0 WHERE id = ?',
    ).run(expireAt, userId);
    return { expireAt, permanent: false };
  }

  db.prepare(
    'UPDATE users SET membership_permanent = 1, membership_expire_at = NULL WHERE id = ?',
  ).run(userId);
  return { expireAt: null, permanent: true };
}

/// 会员权益目录（后台勾选绑定到套餐）
function loadBenefitDict() {
  return db
    .prepare(
      `SELECT code, name, description, icon, sort, is_published
         FROM membership_benefits ORDER BY sort, code`,
    )
    .all();
}

/// 套餐里 benefits 存逗号分隔的权益 code，下发时展开成对象数组
function mapPlan(r, benefitDict = []) {
  const codes = String(r.benefits || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  return {
    code: r.code,
    name: r.name,
    priceCents: r.price_cents,
    durationDays: r.duration_days,
    badge: r.badge,
    benefits: codes
      .map((code) => benefitDict.find((b) => b.code === code))
      .filter(Boolean)
      .map((b) => ({
        code: b.code,
        name: b.name,
        description: b.description,
        icon: b.icon,
      })),
    isPublished: toBool(r.is_published),
    sort: r.sort,
    updatedAt: r.updated_at,
  };
}

// ==================== 账号与令牌 ====================

// ==================== 会话实时通道（SSE） ====================
// 旧设备常驻一条 /v1/session/stream 长连接：新设备登录时服务端立刻推送
// session_revoked，旧设备无需等下一轮同步轮询即可弹「已在其他设备登录」。
const sessionStreams = new Map(); // token -> Set<ServerResponse>

function notifySessionRevoked(tokens) {
  for (const token of tokens) {
    const streams = sessionStreams.get(token);
    if (!streams) continue;
    for (const stream of streams) {
      try {
        stream.write('event: session_revoked\ndata: {"reason":"another_device"}\n\n');
        stream.end();
      } catch {
        // 连接已断开：忽略，清理逻辑会移除
      }
    }
    sessionStreams.delete(token);
  }
}

function createSession(userId) {
  const token = crypto.randomUUID();
  const created = new Date();
  const expires = new Date(
    created.getTime() + TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000,
  );
  // 单设备登录：同一账号只保留最新会话，旧会话标记撤销并实时通知旧设备
  const oldTokens = db
    .prepare('SELECT token FROM sessions WHERE user_id = ? AND revoked_at IS NULL')
    .all(userId)
    .map((r) => r.token);
  db.prepare(
    'UPDATE sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL',
  ).run(created.toISOString(), userId);
  db.prepare(
    'INSERT INTO sessions (token, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)',
  ).run(token, userId, created.toISOString(), expires.toISOString());
  notifySessionRevoked(oldTokens);
  return { token, expiresAt: expires.toISOString() };
}

function authenticate(req) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) return null;
  const row = db
    .prepare(
      `SELECT s.expires_at, s.revoked_at, u.id, u.nickname, u.deleted_at
         FROM sessions s JOIN users u ON u.id = s.user_id
        WHERE s.token = ?`,
    )
    .get(token);
  if (!row || row.deleted_at) return null;
  // 会话已被新设备登录顶掉：单独返回 revoked，便于客户端提示原因
  if (row.revoked_at) return { revoked: true };
  if (row.expires_at < nowIso()) return null;
  return { id: row.id, nickname: row.nickname, token };
}

function isMemberUser(userId) {
  if (!userId) return false;
  const row = db
    .prepare(
      'SELECT membership_expire_at, membership_permanent FROM users WHERE id = ?',
    )
    .get(userId);
  if (!row) return false;
  return (
    !!row.membership_permanent ||
    (!!row.membership_expire_at && row.membership_expire_at > nowIso())
  );
}

function nextRev(userId) {
  return db
    .prepare('UPDATE users SET rev_seq = rev_seq + 1 WHERE id = ? RETURNING rev_seq')
    .get(userId).rev_seq;
}

const currentRev = (userId) =>
  db.prepare('SELECT rev_seq FROM users WHERE id = ?').get(userId).rev_seq;

// ==================== 路由 ====================

async function handle(req, res, url) {
  const method = req.method;
  // 管理后台使用 /api/v1 前缀，与 App 的 /v1 共用同一套实现
  const pathname = url.pathname.startsWith('/api/v1')
    ? url.pathname.slice(4)
    : url.pathname;
  logLine(`${method} ${url.pathname}${url.search}`);

  if (method === 'GET' && pathname === '/health') {
    return send(res, 200, { ok: true, time: nowIso(), db: dbPath });
  }

  if (method === 'GET' && pathname === '/') {
    return send(res, 200, {
      name: 'water-server',
      version: '0.1.0',
      endpoints: [
        'POST /v1/auth/guest',
        'GET /v1/me',
        'PATCH /v1/me',
        'POST /v1/sync/push',
        'GET /v1/sync/pull',
        'GET /v1/membership/plans',
        'POST /v1/auth/register',
        'POST /v1/auth/login',
        'POST /v1/admin/login',
        'GET|POST /v1/beverages',
        'GET|POST /v1/characters',
        'GET /v1/user',
        'GET /v1/membership/orders',
      ],
    });
  }

  // ==================== 账号注册 / 登录（邮箱 + 密码，暂代第三方登录） ====================

  if (method === 'POST' && pathname === '/v1/auth/register') {
    const body = await readJson(req);
    const email = String(body.email || '').trim().toLowerCase();
    const password = String(body.password || '');
    const nickname = String(body.nickname || '').trim() || '喝水羊驼';
    if (!EMAIL_RE.test(email)) {
      return fail(res, 400, 'invalid_email', '邮箱格式不合法');
    }
    if (password.length < 8) {
      return fail(res, 400, 'weak_password', '密码至少 8 位');
    }
    const existing = db
      .prepare('SELECT id FROM users WHERE email = ?')
      .get(email);
    if (existing) return fail(res, 409, 'email_taken', '该邮箱已注册');
    const userId = crypto.randomUUID();
    db.prepare(
      `INSERT INTO users (id, anon_id, nickname, email, password_hash, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    ).run(userId, `acct_${userId}`, nickname, email, hashPassword(password), nowIso());
    const session = createSession(userId);
    return send(res, 200, {
      userId,
      email,
      nickname,
      accessToken: session.token,
      expiresAt: session.expiresAt,
      cursor: 0,
    });
  }

  if (method === 'POST' && pathname === '/v1/auth/login') {
    const body = await readJson(req);
    const email = String(body.email || '').trim().toLowerCase();
    const password = String(body.password || '');
    if (!email || !password) {
      return fail(res, 400, 'invalid_credentials', '请输入邮箱和密码');
    }
    const user = db
      .prepare(
        `SELECT id, nickname, email, password_hash, rev_seq, deleted_at,
                avatar_url, daily_goal_ml
           FROM users WHERE email = ?`,
      )
      .get(email);
    if (!user || user.deleted_at || !verifyPassword(password, user.password_hash)) {
      return fail(res, 401, 'invalid_credentials', '邮箱或密码错误');
    }
    const session = createSession(user.id);
    return send(res, 200, {
      userId: user.id,
      email: user.email,
      nickname: user.nickname,
      avatarUrl: user.avatar_url || null,
      dailyGoalMl: user.daily_goal_ml ?? null,
      accessToken: session.token,
      expiresAt: session.expiresAt,
      cursor: user.rev_seq,
    });
  }

  if (method === 'POST' && pathname === '/v1/auth/guest') {
    const body = await readJson(req);
    const { anonId, nickname, platform } = body;
    if (typeof anonId !== 'string' || !/^[a-zA-Z0-9_-]{8,64}$/.test(anonId)) {
      return fail(res, 400, 'invalid_anon_id', 'anonId 格式不合法');
    }
    let user = db
      .prepare('SELECT id, nickname, rev_seq FROM users WHERE anon_id = ?')
      .get(anonId);
    if (!user) {
      const id = crypto.randomUUID();
      db.prepare(
        'INSERT INTO users (id, anon_id, nickname, created_at) VALUES (?, ?, ?, ?)',
      ).run(id, anonId, (nickname || '').trim() || '喝水羊驼', nowIso());
      user = db
        .prepare('SELECT id, nickname, rev_seq FROM users WHERE id = ?')
        .get(id);
    }
    const session = createSession(user.id);
    return send(res, 200, {
      userId: user.id,
      nickname: user.nickname,
      accessToken: session.token,
      expiresAt: session.expiresAt,
      cursor: user.rev_seq,
      platform: platform || null,
    });
  }

  // ==================== 静态素材（免鉴权，图标/图片托管） ====================
  if (method === 'GET' && pathname.startsWith('/static/')) {
    return serveStatic(res, pathname);
  }

  // ==================== 管理后台页面（免鉴权，静态 HTML） ====================
  if (method === 'GET' && (pathname === '/admin' || pathname === '/admin/')) {
    const file = path.join(adminDir, 'index.html');
    if (!existsSync(file)) {
      return fail(res, 404, 'not_found', '后台页面未部署');
    }
    res.writeHead(200, {
      'Content-Type': 'text/html; charset=utf-8',
      // 后台页面随时更新，禁止缓存，避免浏览器沿用旧版脚本
      'Cache-Control': 'no-store, must-revalidate',
      ...corsHeaders,
    });
    return createReadStream(file).pipe(res);
  }

  // ==================== 容器图标库（App 拉取，公开） ====================
  // 图标文件全部由后台上传到 assets/preset/containers，
  // App 联网时按此列表补齐/清理本地缓存，离线则沿用上次结果或安装包内置图标
  if (method === 'GET' && pathname === '/v1/catalog/containers') {
    const dir = path.join(assetsDir, 'preset', 'containers');
    const items = existsSync(dir)
      ? readdirSync(dir)
          .filter((n) => n.toLowerCase().endsWith('.svg'))
          .sort()
          .map((n) => ({
            id: n.slice(0, -4),
            url: `/static/preset/containers/${encodeURIComponent(n)}`,
          }))
      : [];
    return send(res, 200, { items });
  }

  // ==================== 角色目录（App 拉取，公开） ====================
  // 分类与角色全部由后台维护，App 联网时按此列表展示/下载素材；
  // 离线时沿用上次同步结果，未同步过则用安装包内置角色
  if (method === 'GET' && pathname === '/v1/catalog/characters') {
    const categories = db
      .prepare(
        'SELECT code, name, sort, member_only FROM character_categories ORDER BY sort, created_at',
      )
      .all();
    const items = db
      .prepare(
        `SELECT code, name, category_code, asset_url, member_only, sort
           FROM characters WHERE is_published = 1
          ORDER BY sort, created_at`,
      )
      .all();
    return send(res, 200, {
      categories: categories.map((r) => ({
        code: r.code,
        name: r.name,
        sort: r.sort,
        memberOnly: toBool(r.member_only),
      })),
      items: items.map((r) => ({
        id: r.code,
        code: r.code,
        name: r.name,
        categoryCode: r.category_code || 'daily',
        assetUrl: r.asset_url,
        memberOnly: toBool(r.member_only),
        sort: r.sort,
      })),
    });
  }

  // ==================== 饮品目录（App 拉取，公开，按登录态标记会员锁） ====================
  if (method === 'GET' && pathname === '/v1/catalog/beverages') {
    const rows = db
      .prepare(`${BEVERAGE_SELECT} WHERE b.is_published = 1 ORDER BY b.sort, b.created_at`)
      .all();
    const viewer = authenticate(req);
    const member = isMemberUser(viewer?.revoked ? null : viewer?.id);
    return send(
      res,
      200,
      rows.map((r) => ({
        ...mapBeverage(r),
        locked: toBool(r.member_only) && !member,
      })),
    );
  }

  // ==================== 会员套餐（App 拉取，公开） ====================
  if (method === 'GET' && pathname === '/v1/membership/plans') {
    const rows = db
      .prepare(
        'SELECT * FROM membership_plans WHERE is_published = 1 ORDER BY sort, price_cents',
      )
      .all();
    const dict = loadBenefitDict();
    return send(res, 200, rows.map((r) => mapPlan(r, dict)));
  }

  // 首页贴士卡目录（免鉴权）：空数组时客户端用内置卡池兜底
  if (method === 'GET' && pathname === '/v1/catalog/tips') {
    const rows = db
      .prepare(
        'SELECT * FROM tips WHERE is_published = 1 ORDER BY sort, created_at',
      )
      .all();
    return send(
      res,
      200,
      rows.map((r) => ({
        id: r.id,
        groupCode: r.group_code,
        title: r.title,
        bgColor: r.bg_color,
        fgColor: r.fg_color,
        imageUrl: r.image_url,
        sort: r.sort,
      })),
    );
  }

  // 版本检查（免鉴权）：返回该平台最新启用的版本，客户端据此提示更新
  if (method === 'GET' && pathname === '/v1/app/version') {
    const platform = String(url.searchParams.get('platform') || '').toLowerCase();
    const row = platform
      ? db
          .prepare(
            `SELECT * FROM app_releases
              WHERE platform = ? AND is_published = 1
              ORDER BY version_code DESC LIMIT 1`,
          )
          .get(platform)
      : null;
    if (!row) return send(res, 200, { versionCode: 0 });
    return send(res, 200, {
      versionName: row.version_name,
      versionCode: row.version_code,
      downloadUrl: row.download_url,
      notes: row.notes,
      forceUpdate: toBool(row.force_update),
    });
  }

  // 客户端埋点上报（免鉴权，可带 token）：批量、白名单、限长
  if (method === 'POST' && pathname === '/v1/events') {
    const body = await readJson(req);
    const list = Array.isArray(body.events) ? body.events : [];
    if (list.length > 20) {
      return fail(res, 400, 'too_many_events', '单次最多 20 条事件');
    }
    const viewer = authenticate(req);
    const userId = viewer && !viewer.revoked ? viewer.id : null;
    const anonId = String(body.anonId || '').trim().slice(0, 64);
    const actorId = userId || (anonId ? `anon:${anonId}` : null);
    if (!actorId) return fail(res, 400, 'missing_actor', '缺少用户标识');

    const platform = String(body.platform || '').slice(0, 16) || null;
    const appVersion = String(body.appVersion || '').slice(0, 32) || null;
    const insert = db.prepare(
      `INSERT INTO analytics_events
         (id, actor_id, user_id, event, props, platform, app_version, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    );
    let accepted = 0;
    for (const raw of list) {
      const item = raw && typeof raw === 'object' ? raw : {};
      const event = String(item.event || '');
      if (!ANALYTICS_EVENTS.has(event)) continue;
      let props = null;
      if (item.props && typeof item.props === 'object') {
        try {
          props = JSON.stringify(item.props).slice(0, 500);
        } catch {
          props = null;
        }
      }
      insert.run(
        crypto.randomUUID(),
        actorId,
        userId,
        event,
        props,
        platform,
        appVersion,
        nowIso(),
      );
      accepted += 1;
    }
    return send(res, 201, { accepted });
  }

  // ==================== 管理后台：登录 ====================
  if (method === 'POST' && pathname === '/v1/admin/login') {
    const body = await readJson(req);
    const email = String(body.email || '').trim().toLowerCase();
    const password = String(body.password || '');
    if (!email || !password) {
      return fail(res, 400, 'invalid_credentials', '邮箱和密码不能为空');
    }
    const admin = db
      .prepare('SELECT id, email, role, password_hash FROM admins WHERE email = ?')
      .get(email);
    if (!admin || !verifyPassword(password, admin.password_hash)) {
      return fail(res, 401, 'invalid_credentials', '邮箱或密码错误');
    }
    const session = createAdminSession(admin.id);
    return send(res, 200, {
      userId: admin.id,
      email: admin.email,
      role: admin.role,
      accessToken: session.token,
      expiresAt: session.expiresAt,
    });
  }

  // ==================== 管理后台：业务数据 ====================
  const isAdminRoute =
    pathname === '/v1/user' ||
    pathname.startsWith('/v1/beverages') ||
    pathname.startsWith('/v1/characters') ||
    pathname.startsWith('/v1/character-categories') ||
    (pathname === '/v1/membership/orders' && method === 'GET') ||
    /^\/v1\/membership\/orders\/[^/]+\/(paid|reject)$/.test(pathname) ||
    /^\/v1\/user\/[^/]+$/.test(pathname) ||
    pathname.startsWith('/v1/admin/');

  if (isAdminRoute) {
    const admin = authenticateAdmin(req);
    if (!admin) return fail(res, 401, 'unauthorized', '管理员登录已过期');

    // ---------- 管理员账号：查看 / 修改邮箱与密码 ----------
    if (pathname === '/v1/admin/account' && method === 'GET') {
      return send(res, 200, {
        id: admin.id,
        email: admin.email,
        role: admin.role,
      });
    }

    if (pathname === '/v1/admin/account' && method === 'PATCH') {
      const body = await readJson(req);
      const currentPassword = String(body.currentPassword || '');
      const row = db
        .prepare('SELECT id, email, role, password_hash FROM admins WHERE id = ?')
        .get(admin.id);
      if (!row || !verifyPassword(currentPassword, row.password_hash)) {
        return fail(res, 400, 'invalid_password', '当前密码不正确');
      }
      const nextEmail =
        body.email === undefined
          ? row.email
          : String(body.email || '').trim().toLowerCase();
      const nextPassword =
        body.newPassword === undefined ? null : String(body.newPassword || '');
      if (!EMAIL_RE.test(nextEmail)) {
        return fail(res, 400, 'invalid_email', '邮箱格式不合法');
      }
      if (nextPassword !== null && nextPassword.length < 8) {
        return fail(res, 400, 'weak_password', '新密码至少 8 位');
      }
      if (nextEmail !== row.email) {
        const dup = db
          .prepare('SELECT id FROM admins WHERE email = ? AND id <> ?')
          .get(nextEmail, row.id);
        if (dup) return fail(res, 409, 'email_taken', '该邮箱已被其他管理员使用');
        db.prepare('UPDATE admins SET email = ? WHERE id = ?').run(nextEmail, row.id);
      }
      if (nextPassword !== null) {
        db.prepare('UPDATE admins SET password_hash = ? WHERE id = ?').run(
          hashPassword(nextPassword),
          row.id,
        );
        // 其他设备的登录态全部失效，当前会话保留
        const token = (req.headers.authorization || '').slice(7);
        db.prepare(
          'DELETE FROM admin_sessions WHERE admin_id = ? AND token <> ?',
        ).run(row.id, token);
      }
      return send(res, 200, {
        id: row.id,
        email: nextEmail,
        role: row.role,
      });
    }

    // ---------- 素材上传（图标 / 图片） ----------
    if (pathname === '/v1/admin/assets' && method === 'POST') {
      const extRaw = String(url.searchParams.get('ext') || 'svg').toLowerCase();
      const ext = ['.svg', '.png', '.jpg', '.jpeg', '.webp'].includes(
        `.${extRaw}`,
      )
        ? extRaw
        : null;
      if (!ext) return fail(res, 400, 'invalid_ext', '仅支持 svg/png/jpg/webp');

      let buffer;
      try {
        buffer = await readRaw(req);
      } catch {
        return fail(res, 413, 'body_too_large', '文件超过 3MB');
      }
      if (!buffer.length) return fail(res, 400, 'empty_body', '文件为空');

      const name = `${crypto.randomUUID()}.${ext}`;

      // 目录可选：preset/containers（容器图标库，App 会同步）、preset/characters
      const dirRaw = String(url.searchParams.get('dir') || '')
        .replace(/^\/+|\/+$/g, '');
      if (!['', 'preset/containers', 'preset/characters'].includes(dirRaw)) {
        return fail(res, 400, 'invalid_dir', '非法目录');
      }
      // 保留原文件名（后台按图标文件名管理，App 以文件名作为容器 id）
      const nameRaw = String(url.searchParams.get('name') || '').trim();
      let fileName = name;
      if (nameRaw) {
        const base = path.basename(nameRaw).replace(/[^a-zA-Z0-9._-]/g, '_');
        if (!base || base.startsWith('.')) {
          return fail(res, 400, 'invalid_name', '非法文件名');
        }
        fileName = /\.[a-z0-9]+$/i.test(base) ? base : `${base}.${ext}`;
        if (!['.svg', '.png', '.jpg', '.jpeg', '.webp'].includes(
          path.extname(fileName).toLowerCase(),
        )) {
          return fail(res, 400, 'invalid_ext', '仅支持 svg/png/jpg/webp');
        }
      }

      const targetDir = path.join(assetsDir, dirRaw);
      mkdirSync(targetDir, { recursive: true });
      writeFileSync(path.join(targetDir, fileName), buffer);
      const rel = dirRaw ? `${dirRaw}/${fileName}` : fileName;
      return send(res, 200, { url: `/static/${rel}` });
    }

    // ---------- 图标库（素材列表 / 删除） ----------
    if (pathname === '/v1/admin/assets' && method === 'GET') {
      // 递归列出 assets 目录：preset/containers（客户端容器图标）、
      // preset/characters（客户端角色）以及后台上传的顶层素材
      const walk = (dir, prefix = '') => {
        const out = [];
        for (const n of readdirSync(dir)) {
          const full = path.join(dir, n);
          let stat;
          try {
            stat = statSync(full);
          } catch {
            continue;
          }
          const rel = prefix ? `${prefix}/${n}` : n;
          if (stat.isDirectory()) {
            out.push(...walk(full, rel));
          } else if (stat.isFile()) {
            out.push({
              name: rel,
              url: `/static/${rel}`,
              size: stat.size,
              updatedAt: stat.mtime.toISOString(),
            });
          }
        }
        return out;
      };
      const files = walk(assetsDir).sort((a, b) =>
        a.name < b.name ? -1 : a.name > b.name ? 1 : 0,
      );
      return send(res, 200, files);
    }

    const assetMatch = pathname.match(/^\/v1\/admin\/assets\/(.+)$/);
    if (assetMatch && method === 'DELETE') {
      // 支持子目录（preset/containers/xxx.svg），仍需防目录穿越
      const rel = decodeURIComponent(assetMatch[1]);
      const full = path.resolve(assetsDir, rel);
      const root = path.resolve(assetsDir) + path.sep;
      if (!rel || !full.startsWith(root) || !existsSync(full)) {
        return fail(res, 404, 'not_found', '文件不存在');
      }
      if (statSync(full).isDirectory()) {
        return fail(res, 400, 'invalid_name', '不能删除目录');
      }
      unlinkSync(full);
      return send(res, 200, { ok: true });
    }

    // ---------- 饮品库 ----------
    if (pathname === '/v1/beverages' && method === 'GET') {
      const { pageSize, offset } = pageArgs(url);
      const rows = db
        .prepare(
          `${BEVERAGE_SELECT} ORDER BY b.sort, b.created_at LIMIT ? OFFSET ?`,
        )
        .all(pageSize, offset);
      return send(res, 200, rows.map(mapBeverage));
    }

    if (pathname === '/v1/beverages' && method === 'POST') {
      const body = await readJson(req);
      const name = String(body.name || '').trim();
      if (!name) return fail(res, 400, 'invalid_name', '名称不能为空');
      const category = String(body.category || 'water');
      if (!db.prepare('SELECT 1 FROM beverage_categories WHERE code = ?').get(category)) {
        return fail(res, 400, 'invalid_category', '饮品分类不存在');
      }
      const invalid = validateBeverageBody(body);
      if (invalid) return fail(res, 400, invalid.code, invalid.message);
      const now = nowIso();
      const id = crypto.randomUUID();
      db.prepare(
        `INSERT INTO beverages
           (id, name, category, default_ml, hydration_ratio, icon_url, liquid_color,
            calories, caffeine_mg, alcohol_percent, volume_preset, animation,
            member_only, sort, is_published, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(
        id,
        name,
        category,
        Number(body.defaultMl ?? 250) || 250,
        Number(body.hydrationRatio ?? 1),
        String(body.iconUrl || '').trim() || null,
        String(body.liquidColor || '').trim() || null,
        optInt(body.calories),
        optInt(body.caffeineMg),
        optInt(body.alcoholPercent),
        String(body.volumePreset || 'regular'),
        String(body.animation || '').trim() || null,
        boolInt(body.memberOnly),
        Number(body.sort ?? 0) || 0,
        boolInt(body.isPublished ?? true),
        now,
        now,
      );
      const row = db.prepare(`${BEVERAGE_SELECT} WHERE b.id = ?`).get(id);
      return send(res, 200, mapBeverage(row));
    }

    const beverageMatch = pathname.match(/^\/v1\/beverages\/([^/]+)$/);
    if (beverageMatch) {
      const id = decodeURIComponent(beverageMatch[1]);
      const row = db.prepare(`${BEVERAGE_SELECT} WHERE b.id = ?`).get(id);
      if (!row) return fail(res, 404, 'not_found', '饮品不存在');

      if (method === 'DELETE') {
        db.prepare('DELETE FROM beverages WHERE id = ?').run(id);
        return send(res, 200, { ok: true });
      }

      if (method === 'PATCH') {
        const body = await readJson(req);
        const name = body.name === undefined ? row.name : String(body.name).trim();
        if (!name) return fail(res, 400, 'invalid_name', '名称不能为空');
        const category =
          body.category === undefined ? row.category : String(body.category);
        if (!db.prepare('SELECT 1 FROM beverage_categories WHERE code = ?').get(category)) {
          return fail(res, 400, 'invalid_category', '饮品分类不存在');
        }
        const invalid = validateBeverageBody(body, true);
        if (invalid) return fail(res, 400, invalid.code, invalid.message);
        db.prepare(
          `UPDATE beverages
              SET name = ?, category = ?, default_ml = ?, hydration_ratio = ?,
                  icon_url = ?, liquid_color = ?,
                  calories = ?, caffeine_mg = ?, alcohol_percent = ?,
                  volume_preset = ?, animation = ?,
                  member_only = ?, sort = ?, is_published = ?, updated_at = ?
            WHERE id = ?`,
        ).run(
          name,
          category,
          body.defaultMl === undefined ? row.default_ml : Number(body.defaultMl),
          body.hydrationRatio === undefined
            ? row.hydration_ratio
            : Number(body.hydrationRatio),
          body.iconUrl === undefined
            ? row.icon_url
            : String(body.iconUrl || '').trim() || null,
          body.liquidColor === undefined
            ? row.liquid_color
            : String(body.liquidColor || '').trim() || null,
          body.calories === undefined ? row.calories : optInt(body.calories),
          body.caffeineMg === undefined ? row.caffeine_mg : optInt(body.caffeineMg),
          body.alcoholPercent === undefined
            ? row.alcohol_percent
            : optInt(body.alcoholPercent),
          body.volumePreset === undefined
            ? row.volume_preset
            : String(body.volumePreset || 'regular'),
          body.animation === undefined
            ? row.animation
            : String(body.animation || '').trim() || null,
          body.memberOnly === undefined ? row.member_only : boolInt(body.memberOnly),
          body.sort === undefined ? row.sort : Number(body.sort),
          body.isPublished === undefined
            ? row.is_published
            : boolInt(body.isPublished),
          nowIso(),
          id,
        );
        const next = db.prepare(`${BEVERAGE_SELECT} WHERE b.id = ?`).get(id);
        return send(res, 200, mapBeverage(next));
      }
    }

    // ---------- 饮品分类（后台管理，分类只做归类，不承载任何计算） ----------
    if (pathname === '/v1/admin/categories' && method === 'GET') {
      const rows = db
        .prepare(
          `SELECT c.*,
                  (SELECT COUNT(*) FROM beverages b WHERE b.category = c.code) AS beverage_count
             FROM beverage_categories c
            ORDER BY c.sort, c.created_at`,
        )
        .all();
      return send(
        res,
        200,
        rows.map((r) => ({
          code: r.code,
          name: r.name,
          color: r.color,
          sort: r.sort,
          beverageCount: r.beverage_count,
          createdAt: r.created_at,
        })),
      );
    }

    if (pathname === '/v1/admin/categories' && method === 'POST') {
      const body = await readJson(req);
      const code = String(body.code || '').trim();
      const name = String(body.name || '').trim();
      const color = String(body.color || '').trim() || null;
      if (!/^[a-zA-Z][a-zA-Z0-9_]{0,31}$/.test(code)) {
        return fail(res, 400, 'invalid_code', '分类代码需为字母开头的英文/数字/下划线');
      }
      if (!name || name.length > 12) {
        return fail(res, 400, 'invalid_name', '分类名称需为 1-12 个字符');
      }
      if (db.prepare('SELECT 1 FROM beverage_categories WHERE code = ?').get(code)) {
        return fail(res, 409, 'code_taken', '分类代码已存在');
      }
      // base_category 为历史字段，直接写入自身代码占位；客户端已不再读取
      db.prepare(
        `INSERT INTO beverage_categories (code, name, color, base_category, sort, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      ).run(code, name, color, code, Number(body.sort ?? 0) || 0, nowIso());
      return send(res, 200, { code, name, color, sort: Number(body.sort ?? 0) || 0 });
    }

    const categoryMatch = pathname.match(/^\/v1\/admin\/categories\/([^/]+)$/);
    if (categoryMatch && method === 'PATCH') {
      const code = decodeURIComponent(categoryMatch[1]);
      const row = db
        .prepare('SELECT * FROM beverage_categories WHERE code = ?')
        .get(code);
      if (!row) return fail(res, 404, 'not_found', '分类不存在');
      const body = await readJson(req);
      const name = body.name === undefined ? row.name : String(body.name).trim();
      const color = body.color === undefined
        ? row.color
        : String(body.color || '').trim() || null;
      if (!name || name.length > 12) {
        return fail(res, 400, 'invalid_name', '分类名称需为 1-12 个字符');
      }
      db.prepare(
        'UPDATE beverage_categories SET name = ?, color = ?, sort = ? WHERE code = ?',
      ).run(
        name,
        color,
        body.sort === undefined ? row.sort : Number(body.sort) || 0,
        code,
      );
      return send(res, 200, {
        code,
        name,
        color,
        sort: body.sort === undefined ? row.sort : Number(body.sort) || 0,
      });
    }

    if (categoryMatch && method === 'DELETE') {
      const code = decodeURIComponent(categoryMatch[1]);
      if (!db.prepare('SELECT 1 FROM beverage_categories WHERE code = ?').get(code)) {
        return fail(res, 404, 'not_found', '分类不存在');
      }
      const used = db
        .prepare('SELECT COUNT(*) AS n FROM beverages WHERE category = ?')
        .get(code).n;
      if (used > 0) {
        return fail(res, 409, 'category_in_use', `该分类下还有 ${used} 款饮品，请先移走或删除`);
      }
      db.prepare('DELETE FROM beverage_categories WHERE code = ?').run(code);
      return send(res, 200, { ok: true });
    }

    // ---------- 会员套餐（后台配置，App 直接读取） ----------
    if (pathname === '/v1/admin/plans' && method === 'GET') {
      const rows = db
        .prepare('SELECT * FROM membership_plans ORDER BY sort, code')
        .all();
      const dict = loadBenefitDict();
      return send(res, 200, rows.map((r) => mapPlan(r, dict)));
    }

    // ---------- 会员权益目录（只读，套餐弹窗勾选用） ----------
    if (pathname === '/v1/admin/benefits' && method === 'GET') {
      return send(
        res,
        200,
        loadBenefitDict().map((b) => ({
          code: b.code,
          name: b.name,
          description: b.description,
          icon: b.icon,
          sort: b.sort,
          isPublished: toBool(b.is_published),
        })),
      );
    }

    const planMatch = pathname.match(/^\/v1\/admin\/plans\/([^/]+)$/);
    if (planMatch && method === 'PATCH') {
      const code = decodeURIComponent(planMatch[1]);
      const row = db
        .prepare('SELECT * FROM membership_plans WHERE code = ?')
        .get(code);
      if (!row) return fail(res, 404, 'not_found', '套餐不存在');
      const body = await readJson(req);
      const name = body.name === undefined ? row.name : String(body.name).trim();
      const priceCents = body.priceCents === undefined
        ? row.price_cents
        : Number(body.priceCents);
      const durationDays = body.durationDays === undefined
        ? row.duration_days
        : Number(body.durationDays);
      if (!name) return fail(res, 400, 'invalid_name', '套餐名称不能为空');
      if (!Number.isFinite(priceCents) || priceCents < 0) {
        return fail(res, 400, 'invalid_price', '价格不合法');
      }
      if (!Number.isFinite(durationDays) || durationDays < 0 || durationDays > 3650) {
        return fail(res, 400, 'invalid_duration', '时长需为 0-3650 天（0 表示永久）');
      }
      // 权益绑定：只接受权益目录里存在的 code，去重后按目录顺序存逗号分隔串
      const dict = loadBenefitDict();
      let benefits = row.benefits || '';
      if (body.benefits !== undefined) {
        if (!Array.isArray(body.benefits)) {
          return fail(res, 400, 'invalid_benefits', '权益需为数组');
        }
        const wanted = new Set(body.benefits.map((c) => String(c)));
        const unknown = [...wanted].filter((c) => !dict.some((b) => b.code === c));
        if (unknown.length) {
          return fail(res, 400, 'invalid_benefits', `未知权益：${unknown.join(',')}`);
        }
        benefits = dict
          .map((b) => b.code)
          .filter((c) => wanted.has(c))
          .join(',');
      }
      db.prepare(
        `UPDATE membership_plans
            SET name = ?, price_cents = ?, duration_days = ?, badge = ?,
                is_published = ?, sort = ?, benefits = ?, updated_at = ?
          WHERE code = ?`,
      ).run(
        name,
        Math.round(priceCents),
        Math.round(durationDays),
        body.badge === undefined
          ? row.badge
          : String(body.badge || '').trim() || null,
        body.isPublished === undefined
          ? row.is_published
          : boolInt(body.isPublished),
        body.sort === undefined ? row.sort : Number(body.sort) || 0,
        benefits,
        nowIso(),
        code,
      );
      const next = db
        .prepare('SELECT * FROM membership_plans WHERE code = ?')
        .get(code);
      return send(res, 200, mapPlan(next, dict));
    }

    // ---------- 角色分类 ----------
    if (pathname === '/v1/character-categories' && method === 'GET') {
      const rows = db
        .prepare(
          `SELECT c.code, c.name, c.sort, c.member_only,
                  (SELECT COUNT(*) FROM characters ch WHERE ch.category_code = c.code) AS count
             FROM character_categories c
            ORDER BY c.sort, c.created_at`,
        )
        .all();
      return send(
        res,
        200,
        rows.map((r) => ({
          code: r.code,
          name: r.name,
          sort: r.sort,
          memberOnly: toBool(r.member_only),
          count: r.count,
        })),
      );
    }

    if (pathname === '/v1/character-categories' && method === 'POST') {
      const body = await readJson(req);
      const code = String(body.code || '').trim().toLowerCase();
      const name = String(body.name || '').trim();
      if (!/^[a-z0-9_]+$/.test(code) || !name) {
        return fail(res, 400, 'invalid_payload', 'code（小写字母/数字/下划线）和名称必填');
      }
      if (db.prepare('SELECT 1 AS x FROM character_categories WHERE code = ?').get(code)) {
        return fail(res, 409, 'duplicate_code', '分类 code 已存在');
      }
      const sort = Number(body.sort ?? 0) || 0;
      const memberOnly = boolInt(body.memberOnly);
      db.prepare(
        'INSERT INTO character_categories (code, name, sort, member_only, created_at) VALUES (?, ?, ?, ?, ?)',
      ).run(code, name, sort, memberOnly, nowIso());
      return send(res, 200, { code, name, sort, memberOnly: !!memberOnly, count: 0 });
    }

    const charCategoryMatch = pathname.match(
      /^\/v1\/character-categories\/([^/]+)$/,
    );
    if (charCategoryMatch) {
      const code = decodeURIComponent(charCategoryMatch[1]);
      const row = db
        .prepare('SELECT * FROM character_categories WHERE code = ?')
        .get(code);
      if (!row) return fail(res, 404, 'not_found', '分类不存在');

      if (method === 'PATCH') {
        const body = await readJson(req);
        const name = body.name === undefined ? row.name : String(body.name).trim();
        if (!name) return fail(res, 400, 'invalid_name', '名称不能为空');
        const sort = body.sort === undefined ? row.sort : Number(body.sort) || 0;
        const memberOnly =
          body.memberOnly === undefined ? row.member_only : boolInt(body.memberOnly);
        db.prepare(
          'UPDATE character_categories SET name = ?, sort = ?, member_only = ? WHERE code = ?',
        ).run(name, sort, memberOnly, code);
        return send(res, 200, { code, name, sort, memberOnly: !!memberOnly });
      }

      if (method === 'DELETE') {
        const used = db
          .prepare('SELECT COUNT(*) AS c FROM characters WHERE category_code = ?')
          .get(code);
        if ((used?.c || 0) > 0) {
          return fail(
            res,
            409,
            'category_not_empty',
            `该分类下还有 ${used.c} 个角色，请先删除或移动到其他分类`,
          );
        }
        db.prepare('DELETE FROM character_categories WHERE code = ?').run(code);
        return send(res, 200, { ok: true });
      }
    }

    // ---------- 角色素材 ----------
    if (pathname === '/v1/characters' && method === 'GET') {
      const { pageSize, offset } = pageArgs(url);
      const category = (url.searchParams.get('category') || '').trim();
      const rows = category
        ? db
            .prepare(
              'SELECT * FROM characters WHERE category_code = ? ORDER BY sort, created_at LIMIT ? OFFSET ?',
            )
            .all(category, pageSize, offset)
        : db
            .prepare('SELECT * FROM characters ORDER BY sort, created_at LIMIT ? OFFSET ?')
            .all(pageSize, offset);
      return send(res, 200, rows.map(mapCharacter));
    }

    if (pathname === '/v1/characters' && method === 'POST') {
      const body = await readJson(req);
      const code = String(body.code || '').trim();
      const name = String(body.name || '').trim();
      const assetUrl = String(body.assetUrl || '').trim();
      if (!code || !name || !assetUrl) {
        return fail(res, 400, 'invalid_payload', 'code / 名称 / 素材地址 必填');
      }
      if (db.prepare('SELECT 1 AS x FROM characters WHERE code = ?').get(code)) {
        return fail(res, 409, 'duplicate_code', 'code 已存在');
      }
      const categoryCode = String(body.categoryCode || 'daily').trim();
      if (!db.prepare('SELECT 1 AS x FROM character_categories WHERE code = ?').get(categoryCode)) {
        return fail(res, 400, 'invalid_category', '角色分类不存在');
      }
      const now = nowIso();
      const id = crypto.randomUUID();
      db.prepare(
        `INSERT INTO characters
           (id, code, name, category_code, asset_url, thumbnail_url, member_only, sort, is_published, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(
        id,
        code,
        name,
        categoryCode,
        assetUrl,
        String(body.thumbnailUrl || '').trim() || null,
        boolInt(body.memberOnly),
        Number(body.sort ?? 0) || 0,
        boolInt(body.isPublished ?? true),
        now,
        now,
      );
      const row = db.prepare('SELECT * FROM characters WHERE id = ?').get(id);
      return send(res, 200, mapCharacter(row));
    }

    const characterMatch = pathname.match(/^\/v1\/characters\/([^/]+)$/);
    if (characterMatch) {
      const id = decodeURIComponent(characterMatch[1]);
      const row = db.prepare('SELECT * FROM characters WHERE id = ?').get(id);
      if (!row) return fail(res, 404, 'not_found', '角色不存在');

      if (method === 'DELETE') {
        db.prepare('DELETE FROM characters WHERE id = ?').run(id);
        return send(res, 200, { ok: true });
      }

      if (method === 'PATCH') {
        const body = await readJson(req);
        const code = body.code === undefined ? row.code : String(body.code).trim();
        const name = body.name === undefined ? row.name : String(body.name).trim();
        const assetUrl =
          body.assetUrl === undefined ? row.asset_url : String(body.assetUrl).trim();
        if (!code || !name || !assetUrl) {
          return fail(res, 400, 'invalid_payload', 'code / 名称 / 素材地址 必填');
        }
        const duplicated = db
          .prepare('SELECT 1 AS x FROM characters WHERE code = ? AND id <> ?')
          .get(code, id);
        if (duplicated) return fail(res, 409, 'duplicate_code', 'code 已存在');
        const categoryCode =
          body.categoryCode === undefined
            ? row.category_code || 'daily'
            : String(body.categoryCode).trim();
        if (!db.prepare('SELECT 1 AS x FROM character_categories WHERE code = ?').get(categoryCode)) {
          return fail(res, 400, 'invalid_category', '角色分类不存在');
        }

        db.prepare(
          `UPDATE characters
              SET code = ?, name = ?, category_code = ?, asset_url = ?, thumbnail_url = ?,
                  member_only = ?, in_daily_pool = ?, sort = ?, is_published = ?, updated_at = ?
            WHERE id = ?`,
        ).run(
          code,
          name,
          categoryCode,
          assetUrl,
          body.thumbnailUrl === undefined
            ? row.thumbnail_url
            : String(body.thumbnailUrl || '').trim() || null,
          body.memberOnly === undefined ? row.member_only : boolInt(body.memberOnly),
          body.inDailyPool === undefined
            ? row.in_daily_pool
            : boolInt(body.inDailyPool),
          body.sort === undefined ? row.sort : Number(body.sort),
          body.isPublished === undefined
            ? row.is_published
            : boolInt(body.isPublished),
          nowIso(),
          id,
        );
        const next = db.prepare('SELECT * FROM characters WHERE id = ?').get(id);
        return send(res, 200, mapCharacter(next));
      }
    }

    // ---------- 用户列表（支持搜索 + 会员状态） ----------
    if (pathname === '/v1/user' && method === 'GET') {
      const { pageSize, offset } = pageArgs(url);
      const q = (url.searchParams.get('q') || '').trim();
      const where = q ? 'WHERE (id LIKE ? OR nickname LIKE ? OR email LIKE ?)' : '';
      const params = q ? [`%${q}%`, `%${q}%`, `%${q}%`] : [];
      const rows = db
        .prepare(
          `SELECT id, nickname, email, phone, gender, weight_kg, height_cm,
                  daily_goal_ml, membership_expire_at, membership_permanent, created_at
             FROM users
            ${where}
            ORDER BY created_at DESC LIMIT ? OFFSET ?`,
        )
        .all(...params, pageSize, offset);
      return send(
        res,
        200,
        rows.map((r) => ({
          id: r.id,
          nickname: r.nickname,
          email: r.email,
          phone: r.phone,
          gender: r.gender,
          weightKg: r.weight_kg,
          heightCm: r.height_cm,
          dailyGoalMl: r.daily_goal_ml,
          membershipExpireAt: r.membership_expire_at,
          membershipPermanent: toBool(r.membership_permanent),
          createdAt: r.created_at,
        })),
      );
    }

    // ---------- 人工调整用户会员（赠送 / 延长） ----------
    const userMatch = pathname.match(/^\/v1\/user\/([^/]+)$/);
    if (userMatch && method === 'PATCH') {
      const id = decodeURIComponent(userMatch[1]);
      if (!db.prepare('SELECT 1 FROM users WHERE id = ?').get(id)) {
        return fail(res, 404, 'not_found', '用户不存在');
      }
      const body = await readJson(req);
      if (body.permanent === true) {
        grantMembership(id, 0);
      } else {
        const days = Number(body.membershipDays);
        if (!Number.isFinite(days) || days < 1 || days > 3650) {
          return fail(res, 400, 'invalid_days', '赠送天数需为 1-3650');
        }
        grantMembership(id, days);
      }
      const u = db
        .prepare(
          'SELECT membership_expire_at, membership_permanent FROM users WHERE id = ?',
        )
        .get(id);
      return send(res, 200, {
        id,
        membershipExpireAt: u.membership_expire_at,
        membershipPermanent: toBool(u.membership_permanent),
      });
    }

    // ---------- 单用户打卡数据（后台查看） ----------
    const userEntriesMatch = pathname.match(
      /^\/v1\/admin\/users\/([^/]+)\/entries$/,
    );
    if (userEntriesMatch && method === 'GET') {
      const id = decodeURIComponent(userEntriesMatch[1]);
      const userRow = db
        .prepare('SELECT id, nickname, email, daily_goal_ml FROM users WHERE id = ?')
        .get(id);
      if (!userRow) return fail(res, 404, 'not_found', '用户不存在');

      const days = Math.min(
        365,
        Math.max(7, Number(url.searchParams.get('days') || 30) || 30),
      );
      // 打卡时间是设备本地时间，按日期字符串前缀过滤
      const DAY_MS = 86400000;
      const SHIFT_MS = 8 * 3600000;
      const dayKey = (offset) =>
        new Date(Date.now() + SHIFT_MS - offset * DAY_MS).toISOString().slice(0, 10);
      const fromKey = dayKey(days - 1);
      const todayKey = dayKey(0);

      const rawRows = db
        .prepare(
          `SELECT client_id, drank_at, volume_ml, data
             FROM drink_entries
            WHERE user_id = ? AND deleted_at IS NULL
            ORDER BY drank_at DESC`,
        )
        .all(id);

      const goal = userRow.daily_goal_ml || 2000;
      // 按天细分：先按日期建好区间内的每一天（今天在最前），再累加打卡
      const daily = [];
      for (let offset = 0; offset < days; offset++) {
        daily.push({
          date: dayKey(offset),
          entries: 0,
          volumeMl: 0,
          effectiveMl: 0,
          reached: false,
        });
      }
      const dailyByDate = new Map(daily.map((d) => [d.date, d]));
      let entries = 0;
      let volumeMl = 0;
      let effectiveMl = 0;
      let lastDrankAt = null;
      const list = [];
      const beverageNutrition = new Map(
        db
          .prepare('SELECT id, caffeine_mg, alcohol_percent FROM beverages')
          .all()
          .map((b) => [b.id, b]),
      );

      for (const r of rawRows) {
        if (!lastDrankAt || r.drank_at > lastDrankAt) lastDrankAt = r.drank_at;
        const dateKey = String(r.drank_at || '').slice(0, 10);
        if (dateKey < fromKey) continue;
        let payload = {};
        try {
          payload = JSON.parse(r.data || '{}') || {};
        } catch {
          payload = {};
        }
        if (payload.deleted === 1 || payload.deleted === true) continue;

        // 咖啡因/酒精不在打卡快照里，按 beverage_id 关联饮品库当前配置
        const bev = beverageNutrition.get(String(payload.beverage_id ?? ""));

        const volume = Number(r.volume_ml || 0) || 0;
        const eff = Number(
          payload.effective_ml ?? payload.effectiveMl ?? volume,
        );
        const safeEff = Number.isFinite(eff) ? eff : 0;
        entries += 1;
        volumeMl += volume;
        effectiveMl += safeEff;
        const day = dailyByDate.get(dateKey);
        if (day) {
          day.entries += 1;
          day.volumeMl += volume;
          day.effectiveMl += safeEff;
        }
        if (list.length < 200) {
          list.push({
            clientId: r.client_id,
            drankAt: r.drank_at,
            beverageName: payload.beverage_name ?? payload.beverageName ?? null,
            volumeMl: volume,
            effectiveMl: safeEff,
            calories: Number(payload.calories ?? -1),
            caffeineMg: bev ? Number(bev.caffeine_mg || 0) : 0,
            alcoholPercent: bev ? Number(bev.alcohol_percent || 0) : 0,
          });
        }
      }

      let activeDays = 0;
      let reachedDays = 0;
      for (const day of daily) {
        day.volumeMl = Math.round(day.volumeMl);
        day.effectiveMl = Math.round(day.effectiveMl);
        day.reached = day.effectiveMl >= goal;
        if (day.entries > 0) activeDays += 1;
        if (day.reached) reachedDays += 1;
      }

      return send(res, 200, {
        user: {
          id: userRow.id,
          nickname: userRow.nickname,
          email: userRow.email,
          dailyGoalMl: goal,
        },
        days,
        from: fromKey,
        to: todayKey,
        daily,
        summary: {
          entries,
          activeDays,
          reachedDays,
          volumeMl: Math.round(volumeMl),
          effectiveMl: Math.round(effectiveMl),
          avgPerActiveDay:
            activeDays > 0 ? Math.round((entries / activeDays) * 100) / 100 : 0,
          lastDrankAt,
        },
        entries: list,
      });
    }

    // ---------- 订单查询 ----------
    if (pathname === '/v1/membership/orders' && method === 'GET') {
      const { pageSize, offset } = pageArgs(url);
      const status = url.searchParams.get('status') || '';
      const userId = url.searchParams.get('userId') || '';
      const where = [];
      const params = [];
      if (status) {
        where.push('o.status = ?');
        params.push(status);
      }
      if (userId) {
        where.push('o.user_id = ?');
        params.push(userId);
      }
      const rows = db
        .prepare(
          `SELECT o.*, u.nickname AS user_nickname, u.email AS user_email,
                  p.name AS plan_name_live
             FROM membership_orders o
             LEFT JOIN users u ON u.id = o.user_id
             LEFT JOIN membership_plans p ON p.code = o.plan_code
            ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
            ORDER BY o.created_at DESC LIMIT ? OFFSET ?`,
        )
        .all(...params, pageSize, offset);

      return send(
        res,
        200,
        rows.map((r) => ({
          id: r.id,
          userId: r.user_id,
          planId: r.plan_code,
          amountCents: r.amount_cents,
          status: r.status,
          externalTxId: r.external_tx_id,
          createdAt: r.created_at,
          paidAt: r.paid_at,
          user: {
            id: r.user_id,
            nickname: r.user_nickname,
            email: r.user_email,
          },
          plan: { name: r.plan_name || r.plan_name_live || r.plan_code },
        })),
      );
    }

    const paidMatch = pathname.match(/^\/v1\/membership\/orders\/([^/]+)\/paid$/);
    if (paidMatch && method === 'PATCH') {
      const id = decodeURIComponent(paidMatch[1]);
      const row = db.prepare('SELECT * FROM membership_orders WHERE id = ?').get(id);
      if (!row) return fail(res, 404, 'not_found', '订单不存在');
      if (row.status === 'paid') return fail(res, 409, 'already_paid', '订单已支付');
      const body = await readJson(req);
      db.exec('BEGIN');
      try {
        db.prepare(
          `UPDATE membership_orders
              SET status = 'paid', paid_at = ?, external_tx_id = ?
            WHERE id = ?`,
        ).run(nowIso(), String(body.externalTxId || `manual_${Date.now()}`), id);
        const granted = grantMembership(row.user_id, row.duration_days);
        db.exec('COMMIT');
        return send(res, 200, { ok: true, planCode: row.plan_code, ...granted });
      } catch (err) {
        db.exec('ROLLBACK');
        throw err;
      }
    }

    // 拒绝开通申请：仅 pending 可拒绝，状态置 rejected（与用户主动撤回区分）
    const rejectMatch = pathname.match(/^\/v1\/membership\/orders\/([^/]+)\/reject$/);
    if (rejectMatch && method === 'PATCH') {
      const id = decodeURIComponent(rejectMatch[1]);
      const row = db.prepare('SELECT * FROM membership_orders WHERE id = ?').get(id);
      if (!row) return fail(res, 404, 'not_found', '订单不存在');
      if (row.status !== 'pending') {
        return fail(res, 409, 'not_pending', '只有待确认的申请可以拒绝');
      }
      db.prepare(
        `UPDATE membership_orders SET status = 'rejected' WHERE id = ?`,
      ).run(id);
      return send(res, 200, { ok: true, status: 'rejected' });
    }

    // ---------- 内测版本发布 ----------
    if (pathname === '/v1/admin/releases' && method === 'GET') {
      const rows = db
        .prepare('SELECT * FROM app_releases ORDER BY created_at DESC')
        .all();
      return send(
        res,
        200,
        rows.map((r) => ({
          id: r.id,
          platform: r.platform,
          versionName: r.version_name,
          versionCode: r.version_code,
          downloadUrl: r.download_url,
          notes: r.notes,
          forceUpdate: toBool(r.force_update),
          isPublished: toBool(r.is_published),
          createdAt: r.created_at,
        })),
      );
    }

    if (pathname === '/v1/admin/releases' && method === 'POST') {
      const body = await readJson(req);
      const platform = String(body.platform || '').toLowerCase();
      const versionName = String(body.versionName || '').trim();
      const versionCode = Math.round(Number(body.versionCode));
      if (!['android', 'ios'].includes(platform)) {
        return fail(res, 400, 'invalid_platform', '平台只能是 android 或 ios');
      }
      if (!versionName) return fail(res, 400, 'invalid_version', '版本号不能为空');
      if (!Number.isFinite(versionCode) || versionCode <= 0) {
        return fail(res, 400, 'invalid_version', 'Build 号需为正整数');
      }
      const id = crypto.randomUUID();
      db.prepare(
        `INSERT INTO app_releases
           (id, platform, version_name, version_code, download_url, notes,
            force_update, is_published, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(
        id,
        platform,
        versionName,
        versionCode,
        String(body.downloadUrl || '').trim() || null,
        String(body.notes || '').trim() || null,
        boolInt(body.forceUpdate),
        body.isPublished === undefined ? 1 : boolInt(body.isPublished),
        nowIso(),
      );
      return send(res, 201, { id });
    }

    const releaseMatch = pathname.match(/^\/v1\/admin\/releases\/([^/]+)$/);
    if (releaseMatch && method === 'PATCH') {
      const id = decodeURIComponent(releaseMatch[1]);
      const row = db.prepare('SELECT * FROM app_releases WHERE id = ?').get(id);
      if (!row) return fail(res, 404, 'not_found', '版本不存在');
      const body = await readJson(req);
      db.prepare(
        `UPDATE app_releases
            SET version_name = ?, version_code = ?, download_url = ?, notes = ?,
                force_update = ?, is_published = ?
          WHERE id = ?`,
      ).run(
        body.versionName === undefined
          ? row.version_name
          : String(body.versionName).trim() || row.version_name,
        body.versionCode === undefined
          ? row.version_code
          : Math.round(Number(body.versionCode)) || row.version_code,
        body.downloadUrl === undefined
          ? row.download_url
          : String(body.downloadUrl).trim() || null,
        body.notes === undefined
          ? row.notes
          : String(body.notes).trim() || null,
        body.forceUpdate === undefined
          ? row.force_update
          : boolInt(body.forceUpdate),
        body.isPublished === undefined
          ? row.is_published
          : boolInt(body.isPublished),
        id,
      );
      return send(res, 200, { ok: true });
    }

    // ---------- 用户反馈 ----------
    if (pathname === '/v1/admin/feedback' && method === 'GET') {
      const { pageSize, offset } = pageArgs(url);
      const status = String(url.searchParams.get('status') || '');
      const rows = db
        .prepare(
          `SELECT f.*, u.nickname AS user_nickname
             FROM feedback f LEFT JOIN users u ON u.id = f.user_id
            ${status ? 'WHERE f.status = ?' : ''}
            ORDER BY f.created_at DESC LIMIT ? OFFSET ?`,
        )
        .all(...(status ? [status] : []), pageSize, offset);
      return send(
        res,
        200,
        rows.map((r) => ({
          id: r.id,
          userId: r.user_id,
          userNickname: r.user_nickname,
          content: r.content,
          contact: r.contact,
          appVersion: r.app_version,
          platform: r.platform,
          device: r.device,
          status: r.status,
          createdAt: r.created_at,
          resolvedAt: r.resolved_at,
        })),
      );
    }

    const feedbackMatch = pathname.match(/^\/v1\/admin\/feedback\/([^/]+)$/);
    if (feedbackMatch && method === 'PATCH') {
      const id = decodeURIComponent(feedbackMatch[1]);
      const row = db.prepare('SELECT * FROM feedback WHERE id = ?').get(id);
      if (!row) return fail(res, 404, 'not_found', '反馈不存在');
      const body = await readJson(req);
      const status = String(body.status || '');
      if (!['open', 'resolved'].includes(status)) {
        return fail(res, 400, 'invalid_status', '状态只能是 open 或 resolved');
      }
      db.prepare(
        'UPDATE feedback SET status = ?, resolved_at = ? WHERE id = ?',
      ).run(status, status === 'resolved' ? nowIso() : null, id);
      return send(res, 200, { ok: true, status });
    }

    // ---------- 贴士卡管理 ----------
    if (pathname === '/v1/admin/tips' && method === 'GET') {
      const rows = db
        .prepare('SELECT * FROM tips ORDER BY sort, created_at')
        .all();
      return send(
        res,
        200,
        rows.map((r) => ({
          id: r.id,
          groupCode: r.group_code,
          title: r.title,
          bgColor: r.bg_color,
          fgColor: r.fg_color,
          imageUrl: r.image_url,
          sort: r.sort,
          isPublished: toBool(r.is_published),
          createdAt: r.created_at,
        })),
      );
    }

    if (pathname === '/v1/admin/tips' && method === 'POST') {
      const body = await readJson(req);
      const groupCode = String(body.groupCode || '').trim();
      const title = String(body.title || '').trim();
      if (!TIP_GROUPS.has(groupCode)) {
        return fail(res, 400, 'invalid_group', '贴士分组不合法');
      }
      if (!title) return fail(res, 400, 'invalid_title', '标题不能为空');
      const id = crypto.randomUUID();
      const maxSort = db.prepare('SELECT COALESCE(MAX(sort), 0) AS n FROM tips').get().n;
      db.prepare(
        `INSERT INTO tips
           (id, group_code, title, bg_color, fg_color, image_url, sort, is_published, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(
        id,
        groupCode,
        title.slice(0, 200),
        String(body.bgColor || '').trim() || null,
        String(body.fgColor || '').trim() || null,
        String(body.imageUrl || '').trim() || null,
        maxSort + 1,
        body.isPublished === undefined ? 1 : boolInt(body.isPublished),
        nowIso(),
      );
      return send(res, 201, { id, sort: maxSort + 1 });
    }

    const tipMatch = pathname.match(/^\/v1\/admin\/tips\/([^/]+)$/);
    if (tipMatch) {
      const id = decodeURIComponent(tipMatch[1]);
      const row = db.prepare('SELECT * FROM tips WHERE id = ?').get(id);
      if (!row) return fail(res, 404, 'not_found', '贴士不存在');
      if (method === 'DELETE') {
        db.prepare('DELETE FROM tips WHERE id = ?').run(id);
        return send(res, 200, { ok: true });
      }
      if (method === 'PATCH') {
        const body = await readJson(req);
        if (body.groupCode !== undefined && !TIP_GROUPS.has(String(body.groupCode))) {
          return fail(res, 400, 'invalid_group', '贴士分组不合法');
        }
        db.prepare(
          `UPDATE tips
              SET group_code = ?, title = ?, bg_color = ?, fg_color = ?,
                  image_url = ?, sort = ?, is_published = ?
            WHERE id = ?`,
        ).run(
          body.groupCode === undefined ? row.group_code : String(body.groupCode),
          body.title === undefined
            ? row.title
            : String(body.title).trim().slice(0, 200) || row.title,
          body.bgColor === undefined
            ? row.bg_color
            : String(body.bgColor).trim() || null,
          body.fgColor === undefined
            ? row.fg_color
            : String(body.fgColor).trim() || null,
          body.imageUrl === undefined
            ? row.image_url
            : String(body.imageUrl).trim() || null,
          body.sort === undefined
            ? row.sort
            : Math.round(Number(body.sort)) || row.sort,
          body.isPublished === undefined
            ? row.is_published
            : boolInt(body.isPublished),
          id,
        );
        return send(res, 200, { ok: true });
      }
    }

    // ---------- 客户端异常上报 ----------
    if (pathname === '/v1/admin/errors' && method === 'GET') {
      const { pageSize, offset } = pageArgs(url);
      const rows = db
        .prepare(
          `SELECT e.*, u.nickname AS user_nickname
             FROM client_errors e LEFT JOIN users u ON u.id = e.user_id
            ORDER BY e.created_at DESC LIMIT ? OFFSET ?`,
        )
        .all(pageSize, offset);
      const total = db.prepare('SELECT COUNT(*) AS n FROM client_errors').get().n;
      return send(res, 200, {
        total,
        items: rows.map((r) => ({
          id: r.id,
          userId: r.user_id,
          userNickname: r.user_nickname,
          message: r.message,
          stack: r.stack,
          appVersion: r.app_version,
          platform: r.platform,
          device: r.device,
          createdAt: r.created_at,
        })),
      });
    }

    // ---------- 数据看板：运营统计 ----------
    if (pathname === '/v1/admin/stats/overview' && method === 'GET') {
      const days = Math.min(
        90,
        Math.max(7, Number(url.searchParams.get('days') || 30) || 30),
      );
      const DAY_MS = 86400000;
      // 展示口径按北京时间；客户端打卡时间本身就是设备本地时间，直接取日期部分
      const SHIFT_MS = 8 * 3600000;
      const dayOfUtc = (iso) => {
        const t = Date.parse(iso || '');
        return Number.isNaN(t)
          ? null
          : new Date(t + SHIFT_MS).toISOString().slice(0, 10);
      };
      const dayOfLocal = (iso) => {
        const s = String(iso || '');
        return /^\d{4}-\d{2}-\d{2}/.test(s) ? s.slice(0, 10) : dayOfUtc(s);
      };
      const todayKey = new Date(Date.now() + SHIFT_MS).toISOString().slice(0, 10);
      const dayList = [];
      for (let i = days - 1; i >= 0; i -= 1) {
        dayList.push(
          new Date(Date.now() + SHIFT_MS - i * DAY_MS).toISOString().slice(0, 10),
        );
      }
      const inRange = new Set(dayList);
      const addDays = (key, n) =>
        new Date(Date.parse(`${key}T00:00:00Z`) + n * DAY_MS)
          .toISOString()
          .slice(0, 10);

      const users = db
        .prepare('SELECT id, created_at, daily_goal_ml FROM users WHERE deleted_at IS NULL')
        .all();
      const goalOf = new Map(users.map((u) => [u.id, u.daily_goal_ml || 2000]));
      const createdDayOf = new Map(users.map((u) => [u.id, dayOfUtc(u.created_at)]));

      const entries = db
        .prepare(
          'SELECT user_id, drank_at, volume_ml, data FROM drink_entries WHERE deleted_at IS NULL',
        )
        .all();

      const newByDay = new Map(dayList.map((d) => [d, 0]));
      const activeByDay = new Map(dayList.map((d) => [d, new Set()]));
      const entriesByDay = new Map(dayList.map((d) => [d, 0]));
      // 用户 -> 有打卡的日期集合（全量，留存需要看窗口外的次日/7 日）
      const activeDatesOf = new Map();
      // 用户日有效饮水：`uid|day` -> ml，用于目标完成率
      const userDayMl = new Map();

      for (const u of users) {
        const d = createdDayOf.get(u.id);
        if (d && newByDay.has(d)) newByDay.set(d, newByDay.get(d) + 1);
      }

      for (const e of entries) {
        const uid = e.user_id;
        const day = dayOfLocal(e.drank_at);
        if (!day) continue;
        let payload = {};
        try {
          payload = JSON.parse(e.data || '{}') || {};
        } catch {
          payload = {};
        }
        if (payload.deleted === 1 || payload.deleted === true) continue;

        let dates = activeDatesOf.get(uid);
        if (!dates) {
          dates = new Set();
          activeDatesOf.set(uid, dates);
        }
        dates.add(day);
        if (!inRange.has(day)) continue;

        activeByDay.get(day).add(uid);
        entriesByDay.set(day, entriesByDay.get(day) + 1);

        const eff = Number(
          payload.effective_ml ?? payload.effectiveMl ?? e.volume_ml ?? 0,
        );
        const key = `${uid}|${day}`;
        userDayMl.set(key, (userDayMl.get(key) || 0) + (Number.isFinite(eff) ? eff : 0));
      }

      // 目标完成率 = 达标用户日 / 有打卡的用户日
      let activeUserDays = 0;
      let reachedUserDays = 0;
      for (const [key, ml] of userDayMl) {
        activeUserDays += 1;
        const uid = key.slice(0, key.indexOf('|'));
        if (ml >= (goalOf.get(uid) || 2000)) reachedUserDays += 1;
      }
      const entriesInRange = dayList.reduce(
        (sum, d) => sum + entriesByDay.get(d),
        0,
      );

      // 留存：按注册日分群，看次日 / 第 7 日是否再有打卡
      let cohortD1 = 0;
      let keptD1 = 0;
      let cohortD7 = 0;
      let keptD7 = 0;
      for (const u of users) {
        const cd = createdDayOf.get(u.id);
        if (!cd || !inRange.has(cd)) continue;
        const dates = activeDatesOf.get(u.id);
        const d1 = addDays(cd, 1);
        const d7 = addDays(cd, 7);
        if (d1 <= todayKey) {
          cohortD1 += 1;
          if (dates && dates.has(d1)) keptD1 += 1;
        }
        if (d7 <= todayKey) {
          cohortD7 += 1;
          if (dates && dates.has(d7)) keptD7 += 1;
        }
      }

      const orders = db
        .prepare(
          'SELECT user_id, status, amount_cents, created_at, paid_at FROM membership_orders',
        )
        .all();
      const orderStatus = new Map();
      const paidUsers = new Set();
      const revenueByDay = new Map(dayList.map((d) => [d, 0]));
      let revenueTotalCents = 0;
      let revenueRangeCents = 0;
      let revenueTodayCents = 0;

      for (const o of orders) {
        const st = o.status || 'pending';
        const cell =
          orderStatus.get(st) || { status: st, count: 0, amountCents: 0 };
        cell.count += 1;
        cell.amountCents += o.amount_cents || 0;
        orderStatus.set(st, cell);

        if (st !== 'paid') continue;
        paidUsers.add(o.user_id);
        const cents = o.amount_cents || 0;
        revenueTotalCents += cents;
        const day = dayOfUtc(o.paid_at || o.created_at);
        if (day === todayKey) revenueTodayCents += cents;
        if (day && revenueByDay.has(day)) {
          revenueRangeCents += cents;
          revenueByDay.set(day, revenueByDay.get(day) + cents);
        }
      }

      const sumLast = (map, n) => {
        let total = 0;
        for (let i = dayList.length - n; i < dayList.length; i += 1) {
          total += map.get(dayList[i]) || 0;
        }
        return total;
      };
      const activeLast = (n) => {
        const merged = new Set();
        for (let i = dayList.length - n; i < dayList.length; i += 1) {
          activeByDay.get(dayList[i]).forEach((uid) => merged.add(uid));
        }
        return merged.size;
      };
      const pct = (a, b) => (b > 0 ? Math.round((a / b) * 1000) / 10 : 0);

      return send(res, 200, {
        rangeDays: days,
        today: todayKey,
        generatedAt: nowIso(),
        summary: {
          totalUsers: users.length,
          newUsersToday: newByDay.get(todayKey) || 0,
          newUsers7d: sumLast(newByDay, 7),
          newUsersRange: sumLast(newByDay, days),
          activeToday: activeByDay.get(todayKey).size,
          active7d: activeLast(7),
          activeRange: activeLast(days),
          entriesRange: entriesInRange,
          // 人均日打卡次数 = 窗口内打卡次数 / 有打卡的用户日
          avgCheckinsPerUserDay:
            activeUserDays > 0
              ? Math.round((entriesInRange / activeUserDays) * 100) / 100
              : 0,
          targetRate: pct(reachedUserDays, activeUserDays),
          targetUserDays: activeUserDays,
          retentionD1: pct(keptD1, cohortD1),
          retentionD7: pct(keptD7, cohortD7),
          retentionCohortD1: cohortD1,
          retentionCohortD7: cohortD7,
          paidUsers: paidUsers.size,
          conversionRate: pct(paidUsers.size, users.length),
          revenueTotalCents,
          revenueRangeCents,
          revenueTodayCents,
        },
        trend: dayList.map((d) => ({
          date: d,
          newUsers: newByDay.get(d),
          activeUsers: activeByDay.get(d).size,
          entries: entriesByDay.get(d),
          revenueCents: revenueByDay.get(d),
        })),
        orderStatus: [...orderStatus.values()],
      });
    }

    // ---------- 数据看板：会员转化漏斗（按 actor 去重） ----------
    if (pathname === '/v1/admin/stats/funnel' && method === 'GET') {
      const days = Math.min(
        90,
        Math.max(7, Number(url.searchParams.get('days') || 30) || 30),
      );
      const since = new Date(Date.now() - (days - 1) * 86400000).toISOString();
      const rows = db
        .prepare(
          `SELECT event, COUNT(DISTINCT actor_id) AS users, COUNT(*) AS total
             FROM analytics_events
            WHERE created_at >= ?
            GROUP BY event`,
        )
        .all(since);
      const byEvent = new Map(rows.map((r) => [r.event, r]));
      const steps = FUNNEL_STEPS.map(([event, label]) => ({
        event,
        label,
        users: byEvent.get(event)?.users || 0,
        total: byEvent.get(event)?.total || 0,
      }));
      // 环节转化率：相对上一环节；整体转化率：相对第一环节
      const first = steps[0]?.users || 0;
      for (let i = 0; i < steps.length; i += 1) {
        const prev = i === 0 ? steps[0].users : steps[i - 1].users;
        steps[i].stepRate = prev > 0 ? Math.round((steps[i].users / prev) * 1000) / 10 : 0;
        steps[i].overallRate =
          first > 0 ? Math.round((steps[i].users / first) * 1000) / 10 : 0;
      }
      const extra = ['paywall_view', 'checkin'].map((event) => ({
        event,
        users: byEvent.get(event)?.users || 0,
        total: byEvent.get(event)?.total || 0,
      }));
      return send(res, 200, {
        rangeDays: days,
        generatedAt: nowIso(),
        steps,
        extra,
      });
    }

    return fail(res, 404, 'not_found', '接口不存在');
  }

  // 以下接口都需要登录
  const user = authenticate(req);
  if (pathname.startsWith('/v1/') && !user) {
    return fail(res, 401, 'unauthorized', '缺少或无效的访问令牌');
  }
  if (user && user.revoked) {
    return fail(res, 401, 'session_revoked', '账号已在其他设备登录');
  }

  // 会话实时通道：旧设备保持长连接，新设备登录时立即收到 session_revoked
  if (method === 'GET' && pathname === '/v1/session/stream') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
      ...corsHeaders,
    });
    res.write(': connected\n\n');
    const token = user.token;
    let streams = sessionStreams.get(token);
    if (!streams) {
      streams = new Set();
      sessionStreams.set(token, streams);
    }
    streams.add(res);
    const heartbeat = setInterval(() => {
      try {
        res.write(': ping\n\n');
      } catch {
        // 连接已断开
      }
    }, 20000);
    const cleanup = () => {
      clearInterval(heartbeat);
      const current = sessionStreams.get(token);
      if (!current) return;
      current.delete(res);
      if (!current.size) sessionStreams.delete(token);
    };
    req.on('close', cleanup);
    res.on('close', cleanup);
    res.on('error', cleanup);
    return;
  }

  if (method === 'GET' && pathname === '/v1/me') {
    const row = db
      .prepare(
        `SELECT id, nickname, email, rev_seq, created_at, avatar_url, daily_goal_ml,
                gender, weight_kg, height_cm, age, activity_level
           FROM users WHERE id = ?`,
      )
      .get(user.id);
    return send(res, 200, {
      userId: row.id,
      nickname: row.nickname,
      email: row.email,
      avatarUrl: row.avatar_url || null,
      dailyGoalMl: row.daily_goal_ml ?? null,
      profile: {
        gender: row.gender || null,
        weightKg: row.weight_kg ?? null,
        heightCm: row.height_cm ?? null,
        age: row.age ?? null,
        activityLevel: row.activity_level || null,
        dailyGoalMl: row.daily_goal_ml ?? null,
      },
      cursor: row.rev_seq,
      createdAt: row.created_at,
    });
  }

  if (method === 'PATCH' && pathname === '/v1/me') {
    const body = await readJson(req);
    const sets = [];
    const params = [];
    const columns = new Set();
    const setValue = (column, value) => {
      if (columns.has(column)) return;
      columns.add(column);
      sets.push(`${column} = ?`);
      params.push(value);
    };
    if (body.nickname !== undefined) {
      const nickname = String(body.nickname || '').trim();
      if (!nickname || nickname.length > 24) {
        return fail(res, 400, 'invalid_nickname', '昵称长度需为 1-24 个字符');
      }
      setValue('nickname', nickname);
    }

    // 账号档案整体同步：换设备登录后体重/身高/年龄/活动量/目标都跟着账号走
    const profile =
      body.profile && typeof body.profile === 'object' ? body.profile : {};
    const hasProfile =
      profile.gender !== undefined ||
      profile.weightKg !== undefined ||
      profile.heightCm !== undefined ||
      profile.age !== undefined ||
      profile.activityLevel !== undefined ||
      profile.dailyGoalMl !== undefined;

    if (profile.gender !== undefined) {
      const gender = String(profile.gender || '');
      if (!['male', 'female', 'other'].includes(gender)) {
        return fail(res, 400, 'invalid_gender', '性别取值不合法');
      }
      setValue('gender', gender);
    }
    if (profile.weightKg !== undefined) {
      const weight = Number(profile.weightKg);
      if (!Number.isFinite(weight) || weight < 20 || weight > 300) {
        return fail(res, 400, 'invalid_weight', '体重需为 20-300 kg');
      }
      setValue('weight_kg', Math.round(weight * 10) / 10);
    }
    if (profile.heightCm !== undefined) {
      const height = Number(profile.heightCm);
      if (!Number.isFinite(height) || height < 80 || height > 250) {
        return fail(res, 400, 'invalid_height', '身高需为 80-250 cm');
      }
      setValue('height_cm', Math.round(height * 10) / 10);
    }
    if (profile.age !== undefined) {
      const age = Number(profile.age);
      if (!Number.isFinite(age) || age < 5 || age > 120) {
        return fail(res, 400, 'invalid_age', '年龄需为 5-120 岁');
      }
      setValue('age', Math.round(age));
    }
    if (profile.activityLevel !== undefined) {
      const level = String(profile.activityLevel || '');
      if (!['low', 'medium', 'high'].includes(level)) {
        return fail(res, 400, 'invalid_activity', '活动量取值不合法');
      }
      setValue('activity_level', level);
    }
    if (profile.dailyGoalMl !== undefined) {
      const goal = Number(profile.dailyGoalMl);
      if (!Number.isFinite(goal) || goal < 500 || goal > 10000) {
        return fail(res, 400, 'invalid_goal', '饮水目标需为 500-10000 ml');
      }
      setValue('daily_goal_ml', Math.round(goal));
    }
    // 兼容旧客户端只传 dailyGoalMl
    if (body.dailyGoalMl !== undefined) {
      const goal = Number(body.dailyGoalMl);
      if (!Number.isFinite(goal) || goal < 500 || goal > 10000) {
        return fail(res, 400, 'invalid_goal', '饮水目标需为 500-10000 ml');
      }
      setValue('daily_goal_ml', Math.round(goal));
    }

    if (!sets.length) {
      return fail(res, 400, 'empty_update', '没有需要更新的字段');
    }
    params.push(user.id);
    db.prepare(`UPDATE users SET ${sets.join(', ')} WHERE id = ?`).run(...params);
    const row = db
      .prepare(
        `SELECT nickname, avatar_url, daily_goal_ml, gender, weight_kg, height_cm,
                age, activity_level
           FROM users WHERE id = ?`,
      )
      .get(user.id);
    return send(res, 200, {
      nickname: row.nickname,
      avatarUrl: row.avatar_url || null,
      dailyGoalMl: row.daily_goal_ml ?? null,
      profile: {
        gender: row.gender || null,
        weightKg: row.weight_kg ?? null,
        heightCm: row.height_cm ?? null,
        age: row.age ?? null,
        activityLevel: row.activity_level || null,
        dailyGoalMl: row.daily_goal_ml ?? null,
      },
      cursor: currentRev(user.id),
      updatedProfile: hasProfile,
    });
  }

  // 头像上传（跨设备同步）：原图直传，服务端落盘后返回可用相对地址
  if (method === 'POST' && pathname === '/v1/me/avatar') {
    const contentType = String(req.headers['content-type'] || '').toLowerCase();
    const ext = contentType.includes('png')
      ? '.png'
      : contentType.includes('webp')
        ? '.webp'
        : contentType.includes('jpeg') || contentType.includes('jpg')
          ? '.jpg'
          : '';
    if (!ext) {
      return fail(res, 400, 'invalid_image', '仅支持 jpg / png / webp 头像');
    }
    const raw = await readRaw(req, 2 * 1024 * 1024);
    if (!raw.length) return fail(res, 400, 'empty_image', '头像文件为空');

    const avatarDir = path.join(assetsDir, 'avatars');
    mkdirSync(avatarDir, { recursive: true });
    // 每个用户只保留一张，换头像时清掉旧文件
    try {
      for (const name of readdirSync(avatarDir)) {
        if (name.startsWith(`${user.id}.`)) {
          unlinkSync(path.join(avatarDir, name));
        }
      }
    } catch {}
    const fileName = `${user.id}${ext}`;
    writeFileSync(path.join(avatarDir, fileName), raw);
    const avatarUrl = `/static/avatars/${fileName}`;
    db.prepare('UPDATE users SET avatar_url = ? WHERE id = ?').run(
      avatarUrl,
      user.id,
    );
    return send(res, 200, { avatarUrl });
  }

  if (method === 'DELETE' && pathname === '/v1/me/avatar') {
    try {
      const avatarDir = path.join(assetsDir, 'avatars');
      for (const name of readdirSync(avatarDir)) {
        if (name.startsWith(`${user.id}.`)) {
          unlinkSync(path.join(avatarDir, name));
        }
      }
    } catch {}
    db.prepare('UPDATE users SET avatar_url = NULL WHERE id = ?').run(user.id);
    return send(res, 200, { avatarUrl: null });
  }

  // ==================== 会员开通（App，必须联网） ====================
  if (method === 'POST' && pathname === '/v1/membership/orders') {
    const body = await readJson(req);
    const planCode = String(body.planCode || '').trim();
    const plan = db
      .prepare(
        'SELECT * FROM membership_plans WHERE code = ? AND is_published = 1',
      )
      .get(planCode);
    if (!plan) return fail(res, 404, 'plan_not_found', '套餐不存在或已下架');

    // 同一时刻只允许存在一笔待确认申请：不论套餐，避免后台出现重复审核单
    const pending = db
      .prepare(
        `SELECT * FROM membership_orders
          WHERE user_id = ? AND status = 'pending'
          ORDER BY created_at DESC LIMIT 1`,
      )
      .get(user.id);
    if (pending) {
      return send(res, 200, {
        id: pending.id,
        planCode: pending.plan_code,
        planName: pending.plan_name || plan.name,
        amountCents: pending.amount_cents,
        durationDays: pending.duration_days,
        status: pending.status,
        createdAt: pending.created_at,
        reused: true,
      });
    }

    const now = nowIso();
    const id = crypto.randomUUID();
    db.prepare(
      `INSERT INTO membership_orders
         (id, user_id, plan_code, plan_name, duration_days, amount_cents, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?, 'pending', ?)`,
    ).run(
      id,
      user.id,
      plan.code,
      plan.name,
      plan.duration_days,
      plan.price_cents,
      now,
    );
    return send(res, 200, {
      id,
      planCode: plan.code,
      planName: plan.name,
      amountCents: plan.price_cents,
      durationDays: plan.duration_days,
      status: 'pending',
      createdAt: now,
    });
  }

  const orderStatusMatch = pathname.match(
    /^\/v1\/membership\/orders\/([^/]+)$/,
  );
  if (orderStatusMatch && orderStatusMatch[1] !== 'latest' && method === 'GET') {
    const row = db
      .prepare(
        `SELECT o.*, u.membership_expire_at, u.membership_permanent
           FROM membership_orders o JOIN users u ON u.id = o.user_id
          WHERE o.id = ? AND o.user_id = ?`,
      )
      .get(decodeURIComponent(orderStatusMatch[1]), user.id);
    if (!row) return fail(res, 404, 'not_found', '订单不存在');
    const paid = row.status === 'paid';
    return send(res, 200, {
      id: row.id,
      status: row.status,
      planCode: row.plan_code,
      planName: row.plan_name,
      durationDays: row.duration_days,
      amountCents: row.amount_cents,
      createdAt: row.created_at,
      paidAt: row.paid_at,
      expireAt: paid && !row.membership_permanent ? row.membership_expire_at : null,
      permanent: paid && !!row.membership_permanent,
    });
  }

  // 最新一笔申请（含已拒绝/已取消）：客户端轮询用，及时展示审核结果
  if (method === 'GET' && pathname === '/v1/membership/orders/latest') {
    const row = db
      .prepare(
        `SELECT o.*, u.membership_expire_at, u.membership_permanent
           FROM membership_orders o JOIN users u ON u.id = o.user_id
          WHERE o.user_id = ?
          ORDER BY o.created_at DESC LIMIT 1`,
      )
      .get(user.id);
    if (!row) return send(res, 200, { order: null });
    const paid = row.status === 'paid';
    return send(res, 200, {
      order: {
        id: row.id,
        status: row.status,
        planCode: row.plan_code,
        planName: row.plan_name,
        durationDays: row.duration_days,
        amountCents: row.amount_cents,
        createdAt: row.created_at,
        paidAt: row.paid_at,
        expireAt:
          paid && !row.membership_permanent ? row.membership_expire_at : null,
        permanent: paid && !!row.membership_permanent,
      },
    });
  }

  // 当前用户名下最新的待确认申请（会员页提示条 / 取消入口用）
  if (method === 'GET' && pathname === '/v1/membership/pending') {
    const row = db
      .prepare(
        `SELECT * FROM membership_orders
          WHERE user_id = ? AND status = 'pending'
          ORDER BY created_at DESC LIMIT 1`,
      )
      .get(user.id);
    if (!row) return send(res, 200, {});
    return send(res, 200, {
      id: row.id,
      planCode: row.plan_code,
      planName: row.plan_name,
      amountCents: row.amount_cents,
      durationDays: row.duration_days,
      createdAt: row.created_at,
    });
  }

  // 用户主动撤回开通申请（仅限自己的 pending 单）
  const cancelMatch = pathname.match(/^\/v1\/membership\/orders\/([^/]+)\/cancel$/);
  if (cancelMatch && method === 'POST') {
    const id = decodeURIComponent(cancelMatch[1]);
    const row = db
      .prepare('SELECT * FROM membership_orders WHERE id = ? AND user_id = ?')
      .get(id, user.id);
    if (!row) return fail(res, 404, 'not_found', '订单不存在');
    if (row.status !== 'pending') {
      return fail(res, 409, 'not_pending', '当前状态不可撤回');
    }
    db.prepare(
      `UPDATE membership_orders SET status = 'cancelled' WHERE id = ?`,
    ).run(id);
    return send(res, 200, { ok: true, status: 'cancelled' });
  }

  // 客户端异常上报：单条上报、内容限长，避免把日志表撑爆
  if (method === 'POST' && pathname === '/v1/client-errors') {
    const body = await readJson(req);
    const message = String(body.message || '').trim().slice(0, 1000);
    if (!message) return fail(res, 400, 'invalid_message', 'message 不能为空');
    db.prepare(
      `INSERT INTO client_errors
         (id, user_id, message, stack, app_version, platform, device, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      crypto.randomUUID(),
      user.id,
      message,
      String(body.stack || '').slice(0, 8000) || null,
      String(body.appVersion || '').slice(0, 32) || null,
      String(body.platform || '').slice(0, 16) || null,
      String(body.device || '').slice(0, 120) || null,
      nowIso(),
    );
    return send(res, 201, { ok: true });
  }

  // 用户反馈：内测阶段收集问题，内容必填
  if (method === 'POST' && pathname === '/v1/feedback') {
    const body = await readJson(req);
    const content = String(body.content || '').trim();
    if (content.length < 5) {
      return fail(res, 400, 'invalid_content', '请至少填写 5 个字的问题描述');
    }
    if (content.length > 2000) {
      return fail(res, 400, 'invalid_content', '反馈内容过长（最多 2000 字）');
    }
    const id = crypto.randomUUID();
    db.prepare(
      `INSERT INTO feedback
         (id, user_id, content, contact, app_version, platform, device, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?)`,
    ).run(
      id,
      user.id,
      content,
      String(body.contact || '').trim().slice(0, 100) || null,
      String(body.appVersion || '').trim().slice(0, 32) || null,
      String(body.platform || '').trim().slice(0, 16) || null,
      String(body.device || '').trim().slice(0, 120) || null,
      nowIso(),
    );
    return send(res, 201, { id });
  }

  if (method === 'GET' && pathname === '/v1/membership/status') {
    const row = db
      .prepare(
        'SELECT membership_expire_at, membership_permanent FROM users WHERE id = ?',
      )
      .get(user.id);
    const permanent = !!row.membership_permanent;
    const expireAt = row.membership_expire_at;
    const isMember = permanent || (!!expireAt && expireAt > nowIso());
    const lastPaid = db
      .prepare(
        `SELECT plan_code FROM membership_orders
          WHERE user_id = ? AND status = 'paid'
          ORDER BY paid_at DESC LIMIT 1`,
      )
      .get(user.id);
    return send(res, 200, {
      isMember,
      permanent: isMember && permanent,
      expireAt: permanent ? null : expireAt,
      planCode: lastPaid?.plan_code ?? null,
    });
  }

  if (method === 'POST' && pathname === '/v1/sync/push') {
    const body = await readJson(req);
    const entries = Array.isArray(body.entries) ? body.entries : [];
    const settings = Array.isArray(body.settings) ? body.settings : [];
    if (entries.length + settings.length > MAX_PUSH_ITEMS) {
      return fail(res, 400, 'too_many_items', `单次最多 ${MAX_PUSH_ITEMS} 条`);
    }

    const conflicts = [];
    let accepted = 0;

    db.exec('BEGIN');
    try {
      for (const raw of entries) {
        const clientId = String(raw?.clientId || '');
        if (!clientId || !isIso(raw?.updatedAt)) {
          throw new Error('entry 缺少 clientId 或 updatedAt 非法');
        }
        const updatedAt = raw.updatedAt;
        const deletedAt = raw.deletedAt ?? null;
        const data = raw.data && typeof raw.data === 'object' ? raw.data : {};

        const existing = db
          .prepare(
            'SELECT updated_at, data, server_rev FROM drink_entries WHERE user_id = ? AND client_id = ?',
          )
          .get(user.id, clientId);

        if (existing && existing.updated_at > updatedAt) {
          conflicts.push({
            type: 'entry',
            clientId,
            updatedAt: existing.updated_at,
            deletedAt: null,
            serverRev: existing.server_rev,
            data: JSON.parse(existing.data),
          });
          continue;
        }

        const rev = nextRev(user.id);
        db.prepare(
          `INSERT INTO drink_entries
             (user_id, client_id, drank_at, volume_ml, updated_at, deleted_at, server_rev, data)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(user_id, client_id) DO UPDATE SET
             drank_at = excluded.drank_at,
             volume_ml = excluded.volume_ml,
             updated_at = excluded.updated_at,
             deleted_at = excluded.deleted_at,
             server_rev = excluded.server_rev,
             data = excluded.data`,
        ).run(
          user.id,
          clientId,
          String(data.drankAt || data.drank_at || nowIso()),
          Number(data.volumeMl ?? data.volume_ml ?? 0),
          updatedAt,
          deletedAt,
          rev,
          JSON.stringify(data),
        );
        accepted += 1;
      }

      for (const raw of settings) {
        const key = String(raw?.key || '');
        if (!key || !isIso(raw?.updatedAt)) {
          throw new Error('setting 缺少 key 或 updatedAt 非法');
        }
        const updatedAt = raw.updatedAt;
        const deletedAt = raw.deletedAt ?? null;
        const value =
          raw.value === undefined || raw.value === null
            ? null
            : JSON.stringify(raw.value);

        const existing = db
          .prepare(
            'SELECT updated_at, value, server_rev FROM settings WHERE user_id = ? AND key = ?',
          )
          .get(user.id, key);

        if (existing && existing.updated_at > updatedAt) {
          conflicts.push({
            type: 'setting',
            key,
            updatedAt: existing.updated_at,
            deletedAt: null,
            serverRev: existing.server_rev,
            value: existing.value === null ? null : JSON.parse(existing.value),
          });
          continue;
        }

        const rev = nextRev(user.id);
        db.prepare(
          `INSERT INTO settings (user_id, key, updated_at, deleted_at, server_rev, value)
           VALUES (?, ?, ?, ?, ?, ?)
           ON CONFLICT(user_id, key) DO UPDATE SET
             updated_at = excluded.updated_at,
             deleted_at = excluded.deleted_at,
             server_rev = excluded.server_rev,
             value = excluded.value`,
        ).run(user.id, key, updatedAt, deletedAt, rev, value);
        accepted += 1;
      }

      db.exec('COMMIT');
    } catch (err) {
      db.exec('ROLLBACK');
      return fail(res, 400, 'invalid_item', err.message);
    }

    return send(res, 200, {
      accepted,
      conflicts,
      cursor: currentRev(user.id),
    });
  }

  if (method === 'GET' && pathname === '/v1/sync/pull') {
    const cursor = Number(url.searchParams.get('cursor') || 0);
    if (!Number.isFinite(cursor) || cursor < 0) {
      return fail(res, 400, 'invalid_cursor', 'cursor 必须是非负整数');
    }
    const limit = Math.min(
      Number(url.searchParams.get('limit') || MAX_PULL_ITEMS) || MAX_PULL_ITEMS,
      MAX_PULL_ITEMS,
    );

    const entryRows = db
      .prepare(
        `SELECT client_id, updated_at, deleted_at, server_rev, data
           FROM drink_entries
          WHERE user_id = ? AND server_rev > ?
          ORDER BY server_rev LIMIT ?`,
      )
      .all(user.id, cursor, limit + 1);

    const settingRows = db
      .prepare(
        `SELECT key, updated_at, deleted_at, server_rev, value
           FROM settings
          WHERE user_id = ? AND server_rev > ?
          ORDER BY server_rev LIMIT ?`,
      )
      .all(user.id, cursor, limit + 1);

    const items = [
      ...entryRows.map((r) => ({
        type: 'entry',
        clientId: r.client_id,
        updatedAt: r.updated_at,
        deletedAt: r.deleted_at,
        serverRev: r.server_rev,
        data: JSON.parse(r.data),
      })),
      ...settingRows.map((r) => ({
        type: 'setting',
        key: r.key,
        updatedAt: r.updated_at,
        deletedAt: r.deleted_at,
        serverRev: r.server_rev,
        value: r.value === null ? null : JSON.parse(r.value),
      })),
    ].sort((a, b) => a.serverRev - b.serverRev);

    const hasMore = items.length > limit;
    const page = hasMore ? items.slice(0, limit) : items;
    const nextCursor = page.length ? page[page.length - 1].serverRev : cursor;

    return send(res, 200, { cursor: nextCursor, hasMore, items: page });
  }

  return fail(res, 404, 'not_found', '接口不存在');
}

// ==================== 启动 ====================

function lanAddresses() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const it of list || []) {
      if (it.family === 'IPv4' && !it.internal) out.push(it.address);
    }
  }
  return out;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'OPTIONS') {
    res.writeHead(204, corsHeaders);
    return res.end();
  }

  try {
    await handle(req, res, url);
  } catch (err) {
    if (err.message === 'invalid_json') {
      return fail(res, 400, 'invalid_json', '请求体不是合法 JSON');
    }
    console.error(err);
    fail(res, 500, 'internal_error', '服务器内部错误');
  }
});

ensureDefaultAdmin();

server.listen(PORT, '0.0.0.0', () => {
  console.log(`water-server listening on http://127.0.0.1:${PORT}`);
  console.log(`  db: ${dbPath}`);
  console.log(`  App API:      http://127.0.0.1:${PORT}/v1`);
  console.log(`  Admin API:    http://127.0.0.1:${PORT}/api/v1`);
  console.log(`  admin: ${DEFAULT_ADMIN_EMAIL}（口令取自 ADMIN_PASSWORD 环境变量）`);
  for (const ip of lanAddresses()) {
    console.log(`  LAN: http://${ip}:${PORT}`);
  }
});
