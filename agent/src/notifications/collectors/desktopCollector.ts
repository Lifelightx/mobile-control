import dbus from 'dbus-next';
import { EventEmitter } from 'events';

export const desktopEvents = new EventEmitter();

// Deduplication cache to prevent double-firing due to dbus routing (eavesdrop='true')
let lastNotifHash = '';
let lastNotifTime = 0;

export async function startDesktopCollector() {
  try {
    const bus = dbus.sessionBus();
    
    // Add match to listen to all Notify method calls on the org.freedesktop.Notifications interface
    const obj = await bus.getProxyObject('org.freedesktop.DBus', '/org/freedesktop/DBus');
    const dbusInterface = obj.getInterface('org.freedesktop.DBus');
    await dbusInterface.AddMatch("interface='org.freedesktop.Notifications',member='Notify',type='method_call',eavesdrop='true'");
    
    bus.on('message', (msg: any) => {
      if (msg.interface === 'org.freedesktop.Notifications' && msg.member === 'Notify') {
        const args = msg.body;
        if (!args || args.length < 8) return;
        
        const appName = args[0] as string;
        // args[1] replacesId
        const appIcon = args[2] as string;
        const summary = args[3] as string;
        const body = args[4] as string;
        const actions = args[5] || [];

        let urgency = 1; // 0 = low, 1 = normal, 2 = critical
        const hints = args[6];
        if (hints) {
          const urgencyHint = hints['urgency'];
          if (urgencyHint && urgencyHint.value !== undefined) {
            urgency = urgencyHint.value;
          }
        }

        // Deduplicate
        const hash = `${appName}|${summary}|${body}`;
        const now = Date.now();
        if (hash === lastNotifHash && (now - lastNotifTime) < 1000) {
          return; // Skip duplicate
        }
        lastNotifHash = hash;
        lastNotifTime = now;

        desktopEvents.emit('desktop_notification', {
          appName,
          appIcon,
          summary,
          body,
          actions,
          urgency,
          timestamp: Date.now()
        });
      }
    });
    
    console.log('[NotificationCollector] Desktop (D-Bus) collector started');
  } catch (err) {
    console.error('[NotificationCollector] Failed to start Desktop collector:', err);
  }
}
