import { getNotificationFilters } from '../database/db';
import { NormalizedNotification } from './normalizer';

export async function shouldDeliverNotification(deviceId: string, notification: NormalizedNotification): Promise<boolean> {
  try {
    const filters = await getNotificationFilters(deviceId);
    
    for (const filter of filters) {
      if (filter.filter_type === 'source' && notification.source.toLowerCase().includes(filter.filter_value.toLowerCase())) {
        return filter.action === 'allow';
      }
      if (filter.filter_type === 'app' && notification.title.toLowerCase().includes(filter.filter_value.toLowerCase())) {
        return filter.action === 'allow';
      }
    }
  } catch (err) {
    // Fail open
  }
  return true; // Default allow
}
