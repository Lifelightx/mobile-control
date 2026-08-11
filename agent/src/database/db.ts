import path from 'path';
import fs from 'fs';
import os from 'os';

const dbDir = path.join(os.homedir(), '.devcontrol', 'data');
const dbPath = path.join(dbDir, 'store.json');

// Memory store
const memStore = {
  notifications: [] as any[],
  auditLogs: [] as any[],
};

// Persistent store
let store = {
  settings: {} as Record<string, string>,
  devices: {} as Record<string, any>,
  automation_rules: [] as any[],
  notification_filters: [] as any[]
};

let isLoaded = false;

export async function initStore() {
  if (isLoaded) return;
  if (!fs.existsSync(dbDir)) {
    fs.mkdirSync(dbDir, { recursive: true });
  }
  if (fs.existsSync(dbPath)) {
    try {
      const data = fs.readFileSync(dbPath, 'utf8');
      store = { ...store, ...JSON.parse(data) };
    } catch (e) {
      console.error('Failed to load store.json:', e);
    }
  }
  isLoaded = true;
}

export async function saveStore() {
  await initStore();
  fs.writeFileSync(dbPath, JSON.stringify(store, null, 2));
}

// Settings
export async function getSetting(key: string): Promise<string | null> {
  await initStore();
  return store.settings[key] || null;
}

export async function setSetting(key: string, value: string): Promise<void> {
  await initStore();
  store.settings[key] = value;
  await saveStore();
}

// Devices
export async function getDevice(id: string): Promise<any> {
  await initStore();
  return store.devices[id] || null;
}

export async function saveDevice(device: any): Promise<void> {
  await initStore();
  store.devices[device.id] = device;
  await saveStore();
}

// Audit Logs
export async function addAuditLog(event: string, deviceId: string | null, details: string) {
  const id = Math.random().toString(36).substring(2, 15);
  memStore.auditLogs.push({ id, event, deviceId, timestamp: Date.now(), details });
  if (memStore.auditLogs.length > 1000) memStore.auditLogs.shift();
}

// Automation Rules
export async function getAutomationRules(): Promise<any[]> {
  await initStore();
  return store.automation_rules || [];
}

export async function saveAutomationRule(rule: any): Promise<void> {
  await initStore();
  const idx = store.automation_rules.findIndex(r => r.id === rule.id);
  if (idx >= 0) {
    store.automation_rules[idx] = rule;
  } else {
    store.automation_rules.push(rule);
  }
  await saveStore();
}

export async function deleteAutomationRule(id: string): Promise<void> {
  await initStore();
  store.automation_rules = store.automation_rules.filter(r => r.id !== id);
  await saveStore();
}

// Notification Filters
export async function getNotificationFilters(deviceId: string): Promise<any[]> {
  await initStore();
  return store.notification_filters.filter((f: any) => f.device_id === deviceId);
}

// Notifications (Memory)
export async function addNotificationRaw(n: any) {
  memStore.notifications.push(n);
  if (memStore.notifications.length > 200) memStore.notifications.shift();
}

export async function getMissedNotificationsRaw(sinceTimestamp: number) {
  return memStore.notifications.filter(n => n.timestamp > sinceTimestamp);
}

export async function markNotificationAcknowledgedRaw(id: string) {
  const n = memStore.notifications.find(n => n.id === id);
  if (n) {
    n.acknowledged = 1;
    n.read = 1;
  }
}

export async function getAllNotificationsRaw(onlyUnread: boolean = false) {
  if (onlyUnread) return memStore.notifications.filter(n => !n.read && !n.acknowledged);
  return [...memStore.notifications].reverse().slice(0, 50);
}

export async function markAllNotificationsReadRaw() {
  memStore.notifications.forEach(n => { n.read = 1; n.acknowledged = 1; });
}
