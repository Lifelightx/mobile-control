import { getDb } from '../database/db';
import { NormalizedNotification } from './normalizer';

export async function shouldDeliverNotification(deviceId: string, notification: NormalizedNotification): Promise<boolean> {
  try {
    const db = await getDb();
    // In the future, query actual device preferences from SQLite table 'notification_filters'
    // For now, allow all by default, but we can block based on rules.
    const filters = await db.all('SELECT * FROM notification_filters WHERE device_id = ?', deviceId);
    
    for (const filter of filters) {
      if (filter.filter_type === 'source' && notification.source.toLowerCase().includes(filter.filter_value.toLowerCase())) {
        return filter.action === 'allow';
      }
      if (filter.filter_type === 'app' && notification.title.toLowerCase().includes(filter.filter_value.toLowerCase())) {
        return filter.action === 'allow';
      }
    }
  } catch (err) {
    // Table might not exist yet, or query failed. Fail open.
  }
  return true; // Default allow
}
