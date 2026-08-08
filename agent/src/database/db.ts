import sq from 'sqlite3';
import { open, Database } from 'sqlite';
import path from 'path';
import fs from 'fs';

let db: Database | null = null;

export async function getDb(): Promise<Database> {
  if (db) return db;

  const dbDir = path.join(__dirname, '../../data');
  if (!fs.existsSync(dbDir)) {
    fs.mkdirSync(dbDir, { recursive: true });
  }

  const dbPath = path.join(dbDir, 'control_hub.db');

  db = await open({
    filename: dbPath,
    driver: sq.Database,
  });

  // Enable foreign keys
  await db.run('PRAGMA foreign_keys = ON');

  // Initialize schemas
  await initializeSchema(db);

  return db;
}

async function initializeSchema(database: Database) {
  // Devices table
  await database.exec(`
    CREATE TABLE IF NOT EXISTS devices (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      public_key TEXT,
      paired_at INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'paired'
    )
  `);

  // Users table (for future login/authentication management if needed)
  await database.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      username TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )
  `);

  // Audit Logs
  await database.exec(`
    CREATE TABLE IF NOT EXISTS audit_logs (
      id TEXT PRIMARY KEY,
      event TEXT NOT NULL,
      device_id TEXT,
      timestamp INTEGER NOT NULL,
      details TEXT,
      FOREIGN KEY(device_id) REFERENCES devices(id) ON DELETE SET NULL
    )
  `);

  // Settings
  await database.exec(`
    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  `);

  // Terminal Sessions
  await database.exec(`
    CREATE TABLE IF NOT EXISTS terminal_sessions (
      id TEXT PRIMARY KEY,
      created_at INTEGER NOT NULL,
      ended_at INTEGER,
      status TEXT NOT NULL
    )
  `);

  // Automation Rules
  await database.exec(`
    CREATE TABLE IF NOT EXISTS automation_rules (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      trigger_type TEXT NOT NULL,
      trigger_config TEXT NOT NULL,
      action_type TEXT NOT NULL,
      action_config TEXT NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 1
    )
  `);

  // Saved Commands
  await database.exec(`
    CREATE TABLE IF NOT EXISTS saved_commands (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      command TEXT NOT NULL,
      category TEXT
    )
  `);

  // Notifications (Updated for Mirroring Architecture)
  await database.exec(`
    CREATE TABLE IF NOT EXISTS notifications (
      id TEXT PRIMARY KEY,
      source TEXT NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      severity TEXT NOT NULL DEFAULT 'normal',
      icon TEXT,
      timestamp INTEGER NOT NULL,
      delivered INTEGER NOT NULL DEFAULT 0,
      acknowledged INTEGER NOT NULL DEFAULT 0
    )
  `);
  
  // Add columns to existing table if it exists to prevent errors during migration
  try { await database.exec("ALTER TABLE notifications ADD COLUMN source TEXT NOT NULL DEFAULT 'system';"); } catch (e) {}
  try { await database.exec("ALTER TABLE notifications ADD COLUMN body TEXT NOT NULL DEFAULT '';"); } catch (e) {}
  try { await database.exec("ALTER TABLE notifications ADD COLUMN severity TEXT NOT NULL DEFAULT 'normal';"); } catch (e) {}
  try { await database.exec("ALTER TABLE notifications ADD COLUMN icon TEXT;"); } catch (e) {}
  try { await database.exec("ALTER TABLE notifications ADD COLUMN delivered INTEGER NOT NULL DEFAULT 0;"); } catch (e) {}
  try { await database.exec("ALTER TABLE notifications ADD COLUMN acknowledged INTEGER NOT NULL DEFAULT 0;"); } catch (e) {}

  // Notification Filters
  await database.exec(`
    CREATE TABLE IF NOT EXISTS notification_filters (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL,
      filter_type TEXT NOT NULL,
      filter_value TEXT NOT NULL,
      action TEXT NOT NULL DEFAULT 'allow',
      FOREIGN KEY(device_id) REFERENCES devices(id) ON DELETE CASCADE
    )
  `);
}

export async function addAuditLog(event: string, deviceId: string | null, details: string) {
  try {
    const database = await getDb();
    const id = Math.random().toString(36).substring(2, 15);
    await database.run(
      'INSERT INTO audit_logs (id, event, device_id, timestamp, details) VALUES (?, ?, ?, ?, ?)',
      id,
      event,
      deviceId,
      Date.now(),
      details
    );
  } catch (err) {
    console.error('Failed to write audit log:', err);
  }
}
