import { addNotificationRaw, getMissedNotificationsRaw, markNotificationAcknowledgedRaw } from '../database/db';
import { NormalizedNotification } from './normalizer';

export async function storeNotification(notification: NormalizedNotification) {
  try {
    await addNotificationRaw({ ...notification, delivered: 0, acknowledged: 0, read: 0 });
  } catch (err) {
    console.error('[NotificationHistory] Failed to store notification:', err);
  }
}

export async function getMissedNotifications(sinceTimestamp: number): Promise<NormalizedNotification[]> {
  try {
    const raw = await getMissedNotificationsRaw(sinceTimestamp);
    return raw as NormalizedNotification[];
  } catch (err) {
    console.error('[NotificationHistory] Failed to get missed notifications:', err);
    return [];
  }
}

export async function markNotificationAcknowledged(id: string) {
  try {
    await markNotificationAcknowledgedRaw(id);
  } catch (err) {
    console.error('[NotificationHistory] Failed to acknowledge notification:', err);
  }
}
