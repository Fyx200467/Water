import crypto from 'node:crypto';
import {
  appendFileSync,
  createReadStream,
  existsSync,
  mkdirSync,
  statSync,
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
  const existing = db.prepare('SELECT id FROM admins WHERE email = ?').get(email);

  if (!existing) {
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

  // 显式设置 ADMIN_PASSWORD 时重置口令并踢掉旧会话（公网暴露前改密用）
  if (process.env.ADMIN_PASSWORD) {
    db.prepare('UPDATE admins SET password_hash = ? WHERE id = ?').run(
      hashPassword(DEFAULT_ADMIN_PASSWORD),
      existing.id,
    );
    db.prepare('DELETE FROM admin_sessions WHERE admin_id = ?').run(existing.id);
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

function mapBeverage(r) {
  return {
    id: r.id,
    name: r.name,
    category: r.category,
    defaultMl: r.default_ml,
    hydrationRatio: r.hydration_ratio,
    iconUrl: r.icon_url,
    liquidColor: r.liquid_color,
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
    assetUrl: r.asset_url,
    thumbnailUrl: r.thumbnail_url,
    memberOnly: toBool(r.member_only),
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

function mapPlan(r) {
  return {
    code: r.code,
    name: r.name,
    priceCents: r.price_cents,
    durationDays: r.duration_days,
    badge: r.badge,
    isPublished: toBool(r.is_published),
    sort: r.sort,
    updatedAt: r.updated_at,
  };
}

// ==================== 账号与令牌 ====================

function createSession(userId) {
  const token = crypto.randomUUID();
  const created = new Date();
  const expires = new Date(
    created.getTime() + TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000,
  );
  db.prepare(
    'INSERT INTO sessions (token, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)',
  ).run(token, userId, created.toISOString(), expires.toISOString());
  return { token, expiresAt: expires.toISOString() };
}

function authenticate(req) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) return null;
  const row = db
    .prepare(
      `SELECT s.expires_at, u.id, u.nickname, u.deleted_at
         FROM sessions s JOIN users u ON u.id = s.user_id
        WHERE s.token = ?`,
    )
    .get(token);
  if (!row || row.deleted_at) return null;
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
        'POST /v1/auth/login',
        'GET|POST /v1/beverages',
        'GET|POST /v1/characters',
        'GET /v1/user',
        'GET /v1/membership/orders',
      ],
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
      ...corsHeaders,
    });
    return createReadStream(file).pipe(res);
  }

  // ==================== 饮品目录（App 拉取，公开，按登录态标记会员锁） ====================
  if (method === 'GET' && pathname === '/v1/catalog/beverages') {
    const rows = db
      .prepare(
        'SELECT * FROM beverages WHERE is_published = 1 ORDER BY sort, created_at',
      )
      .all();
    const viewer = authenticate(req);
    const member = isMemberUser(viewer?.id);
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
    return send(res, 200, rows.map(mapPlan));
  }

  // ==================== 管理后台：登录 ====================
  if (method === 'POST' && pathname === '/v1/auth/login') {
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

  // 仅在还没有管理员时允许自助注册，避免开放注册口
  if (method === 'POST' && pathname === '/v1/auth/register') {
    const body = await readJson(req);
    const email = String(body.email || '').trim().toLowerCase();
    const password = String(body.password || '');
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return fail(res, 400, 'invalid_email', '邮箱格式不合法');
    }
    if (password.length < 8) {
      return fail(res, 400, 'weak_password', '密码至少 8 位');
    }
    if (db.prepare('SELECT COUNT(*) AS n FROM admins').get().n > 0) {
      return fail(res, 403, 'register_closed', '已存在管理员账号，不能开放注册');
    }
    const id = crypto.randomUUID();
    db.prepare(
      'INSERT INTO admins (id, email, password_hash, role, created_at) VALUES (?, ?, ?, ?, ?)',
    ).run(id, email, hashPassword(password), 'admin', nowIso());
    return send(res, 200, { userId: id, email });
  }

  // ==================== 管理后台：业务数据 ====================
  const isAdminRoute =
    pathname === '/v1/user' ||
    pathname.startsWith('/v1/beverages') ||
    pathname.startsWith('/v1/characters') ||
    (pathname === '/v1/membership/orders' && method === 'GET') ||
    /^\/v1\/membership\/orders\/[^/]+\/paid$/.test(pathname) ||
    pathname.startsWith('/v1/admin/');

  if (isAdminRoute) {
    const admin = authenticateAdmin(req);
    if (!admin) return fail(res, 401, 'unauthorized', '管理员登录已过期');

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
      writeFileSync(path.join(assetsDir, name), buffer);
      return send(res, 200, { url: `/static/${name}` });
    }

    // ---------- 饮品库 ----------
    if (pathname === '/v1/beverages' && method === 'GET') {
      const { pageSize, offset } = pageArgs(url);
      const rows = db
        .prepare('SELECT * FROM beverages ORDER BY sort, created_at LIMIT ? OFFSET ?')
        .all(pageSize, offset);
      return send(res, 200, rows.map(mapBeverage));
    }

    if (pathname === '/v1/beverages' && method === 'POST') {
      const body = await readJson(req);
      const name = String(body.name || '').trim();
      if (!name) return fail(res, 400, 'invalid_name', '名称不能为空');
      const now = nowIso();
      const id = crypto.randomUUID();
      db.prepare(
        `INSERT INTO beverages
           (id, name, category, default_ml, hydration_ratio, icon_url, liquid_color, member_only, sort, is_published, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(
        id,
        name,
        String(body.category || 'water'),
        Number(body.defaultMl ?? 250) || 250,
        Number(body.hydrationRatio ?? 1),
        String(body.iconUrl || '').trim() || null,
        String(body.liquidColor || '').trim() || null,
        boolInt(body.memberOnly),
        Number(body.sort ?? 0) || 0,
        boolInt(body.isPublished ?? true),
        now,
        now,
      );
      const row = db.prepare('SELECT * FROM beverages WHERE id = ?').get(id);
      return send(res, 200, mapBeverage(row));
    }

    const beverageMatch = pathname.match(/^\/v1\/beverages\/([^/]+)$/);
    if (beverageMatch) {
      const id = decodeURIComponent(beverageMatch[1]);
      const row = db.prepare('SELECT * FROM beverages WHERE id = ?').get(id);
      if (!row) return fail(res, 404, 'not_found', '饮品不存在');

      if (method === 'DELETE') {
        db.prepare('DELETE FROM beverages WHERE id = ?').run(id);
        return send(res, 200, { ok: true });
      }

      if (method === 'PATCH') {
        const body = await readJson(req);
        const name = body.name === undefined ? row.name : String(body.name).trim();
        if (!name) return fail(res, 400, 'invalid_name', '名称不能为空');
        db.prepare(
          `UPDATE beverages
              SET name = ?, category = ?, default_ml = ?, hydration_ratio = ?,
                  icon_url = ?, liquid_color = ?,
                  member_only = ?, sort = ?, is_published = ?, updated_at = ?
            WHERE id = ?`,
        ).run(
          name,
          body.category === undefined ? row.category : String(body.category),
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
          body.memberOnly === undefined ? row.member_only : boolInt(body.memberOnly),
          body.sort === undefined ? row.sort : Number(body.sort),
          body.isPublished === undefined
            ? row.is_published
            : boolInt(body.isPublished),
          nowIso(),
          id,
        );
        const next = db.prepare('SELECT * FROM beverages WHERE id = ?').get(id);
        return send(res, 200, mapBeverage(next));
      }
    }

    // ---------- 角色素材 ----------
    if (pathname === '/v1/characters' && method === 'GET') {
      const { pageSize, offset } = pageArgs(url);
      const rows = db
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
      const now = nowIso();
      const id = crypto.randomUUID();
      db.prepare(
        `INSERT INTO characters
           (id, code, name, asset_url, thumbnail_url, member_only, sort, is_published, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(
        id,
        code,
        name,
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

        db.prepare(
          `UPDATE characters
              SET code = ?, name = ?, asset_url = ?, thumbnail_url = ?,
                  member_only = ?, sort = ?, is_published = ?, updated_at = ?
            WHERE id = ?`,
        ).run(
          code,
          name,
          assetUrl,
          body.thumbnailUrl === undefined
            ? row.thumbnail_url
            : String(body.thumbnailUrl || '').trim() || null,
          body.memberOnly === undefined ? row.member_only : boolInt(body.memberOnly),
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

    // ---------- 用户列表（只读） ----------
    if (pathname === '/v1/user' && method === 'GET') {
      const { pageSize, offset } = pageArgs(url);
      const rows = db
        .prepare(
          `SELECT id, nickname, email, phone, gender, weight_kg, height_cm,
                  daily_goal_ml, membership_expire_at, created_at
             FROM users
            ORDER BY created_at DESC LIMIT ? OFFSET ?`,
        )
        .all(pageSize, offset);
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
          createdAt: r.created_at,
        })),
      );
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

    return fail(res, 404, 'not_found', '接口不存在');
  }

  // 以下接口都需要登录
  const user = authenticate(req);
  if (pathname.startsWith('/v1/') && !user) {
    return fail(res, 401, 'unauthorized', '缺少或无效的访问令牌');
  }

  if (method === 'GET' && pathname === '/v1/me') {
    const row = db
      .prepare(
        'SELECT id, nickname, rev_seq, created_at FROM users WHERE id = ?',
      )
      .get(user.id);
    return send(res, 200, {
      userId: row.id,
      nickname: row.nickname,
      cursor: row.rev_seq,
      createdAt: row.created_at,
    });
  }

  if (method === 'PATCH' && pathname === '/v1/me') {
    const body = await readJson(req);
    const nickname = String(body.nickname || '').trim();
    if (!nickname || nickname.length > 24) {
      return fail(res, 400, 'invalid_nickname', '昵称长度需为 1-24 个字符');
    }
    db.prepare('UPDATE users SET nickname = ? WHERE id = ?').run(
      nickname,
      user.id,
    );
    return send(res, 200, { nickname, cursor: currentRev(user.id) });
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

    // 同套餐重复点击时复用未支付订单，避免刷单
    const pending = db
      .prepare(
        `SELECT * FROM membership_orders
          WHERE user_id = ? AND plan_code = ? AND status = 'pending'
          ORDER BY created_at DESC LIMIT 1`,
      )
      .get(user.id, plan.code);
    if (pending) {
      return send(res, 200, {
        id: pending.id,
        planCode: pending.plan_code,
        planName: pending.plan_name || plan.name,
        amountCents: pending.amount_cents,
        durationDays: pending.duration_days,
        status: pending.status,
        createdAt: pending.created_at,
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

  const orderStatusMatch = pathname.match(/^\/v1\/membership\/orders\/([^/]+)$/);
  if (orderStatusMatch && method === 'GET') {
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
