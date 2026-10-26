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
`);

export const nowIso = () => new Date().toISOString();
export { dbPath };
