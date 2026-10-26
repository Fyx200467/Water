import crypto from 'node:crypto';
import { appendFileSync } from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import { db, dbPath, nowIso } from './db.js';

const accessLog = process.env.ACCESS_LOG ||
  `${os.homedir()}/Documents/Trae-CN/default/.water-server/access.log`;
const logLine = (line) => {
  try {
    appendFileSync(accessLog, `${new Date().toISOString()} ${line}\n`);
  } catch {}
};

const PORT = Number(process.env.PORT || 3000);
const TOKEN_TTL_DAYS = 365;
const MAX_PUSH_ITEMS = 500;
const MAX_PULL_ITEMS = 500;

// ==================== HTTP 工具 ====================

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, OPTIONS',
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

const isIso = (v) => typeof v === 'string' && !Number.isNaN(Date.parse(v));

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

function nextRev(userId) {
  return db
    .prepare('UPDATE users SET rev_seq = rev_seq + 1 WHERE id = ? RETURNING rev_seq')
    .get(userId).rev_seq;
}

const currentRev = (userId) =>
  db.prepare('SELECT rev_seq FROM users WHERE id = ?').get(userId).rev_seq;

// ==================== 路由 ====================

async function handle(req, res, url) {
  const { pathname } = url;
  const method = req.method;
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

server.listen(PORT, '0.0.0.0', () => {
  console.log(`water-server listening on http://127.0.0.1:${PORT}`);
  console.log(`  db: ${dbPath}`);
  for (const ip of lanAddresses()) {
    console.log(`  LAN: http://${ip}:${PORT}`);
  }
});
