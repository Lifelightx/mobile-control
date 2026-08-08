export type Severity = 'low' | 'info' | 'normal' | 'high' | 'critical';

export interface NotificationAction {
  id: string;
  label: string;
}

export interface NormalizedNotification {
  id: string;
  source: string;
  title: string;
  body: string;
  severity: Severity;
  icon: string;
  timestamp: number;
  actions?: NotificationAction[];
}

export function normalizeDesktopNotification(raw: any): NormalizedNotification {
  let severity: Severity = 'normal';
  if (raw.urgency === 0) severity = 'low';
  else if (raw.urgency === 1) severity = 'normal';
  else if (raw.urgency === 2) severity = 'critical';

  // Parse actions (even index is ID, odd index is label)
  const actions: NotificationAction[] = [];
  if (Array.isArray(raw.actions)) {
    for (let i = 0; i < raw.actions.length; i += 2) {
      if (raw.actions[i] && raw.actions[i + 1]) {
        actions.push({ id: raw.actions[i], label: raw.actions[i + 1] });
      }
    }
  }

  return {
    id: Math.random().toString(36).substring(2, 15),
    source: raw.appName || 'desktop',
    title: raw.summary || 'Notification',
    body: raw.body || '',
    severity,
    icon: raw.appIcon || 'desktop_mac',
    timestamp: raw.timestamp || Date.now(),
    actions
  };
}
