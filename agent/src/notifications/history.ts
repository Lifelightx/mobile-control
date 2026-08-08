import { getDb } from '../database/db';
import { NormalizedNotification } from './normalizer';

export async function storeNotification(notification: NormalizedNotification) {
  try {
    const db = await getDb();
    await db.run(
      'INSERT INTO notifications (id, source, title, body, severity, icon, timestamp, delivered, acknowledged) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0)',
      notification.id,
      notification.source,
      notification.title,
      notification.body,
      notification.severity,
      notification.icon,
      notification.timestamp
    );
  } catch (err) {
    console.error('[NotificationHistory] Failed to store notification:', err);
  }
}

export async function getMissedNotifications(sinceTimestamp: number): Promise<NormalizedNotification[]> {
  try {
    const db = await getDb();
    const rows = await db.all(
      'SELECT * FROM notifications WHERE timestamp > ? ORDER BY timestamp ASC',
      sinceTimestamp
    );
    return rows as NormalizedNotification[];
  } catch (err) {
    console.error('[NotificationHistory] Failed to get missed notifications:', err);
    return [];
  }
}

export async function markNotificationAcknowledged(id: string) {
  try {
    const db = await getDb();
    await db.run('UPDATE notifications SET acknowledged = 1 WHERE id = ?', id);
  } catch (err) {
    console.error('[NotificationHistory] Failed to acknowledge notification:', err);
  }
}
