import { EventEmitter } from 'events';
import { desktopEvents, startDesktopCollector } from './collectors/desktopCollector';
import { normalizeDesktopNotification, NormalizedNotification } from './normalizer';
import { storeNotification } from './history';

// Event Bus
export const eventBus = new EventEmitter();

// Setup Notification Engine
export function startNotificationEngine() {
  console.log('[NotificationEngine] Starting...');

  // Start Collectors
  startDesktopCollector();

  // Listen to Collectors & Normalize
  desktopEvents.on('desktop_notification', (raw) => {
    const normalized = normalizeDesktopNotification(raw);
    eventBus.emit('new_notification', normalized);
  });

  // Event Bus Subscribers (The Notification Engine Delivery)
  eventBus.on('new_notification', (notification: NormalizedNotification) => {
    console.log(`[NotificationEngine] Routing notification: [${notification.source}] ${notification.title}`);
    
    // Phase 6: Store in History
    storeNotification(notification);

    // Handled by index.ts subscribing to eventBus
  });
}
