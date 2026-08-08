import Bonjour from 'bonjour-service';

let bonjour: Bonjour | null = null;
let advertisedService: any = null;

export function startDiscovery(port: number, name: string = 'Developer Control Agent') {
  try {
    bonjour = new Bonjour();
    advertisedService = bonjour.publish({
      name,
      type: 'devcontrol',
      protocol: 'tcp',
      port,
      txt: {
        version: '1.0.0',
        platform: process.platform,
      },
    });

    console.log(`[mDNS] Advertising service "${name}" (_devcontrol._tcp.local) on port ${port}`);

    advertisedService.on('error', (err: Error) => {
      console.error('[mDNS] Bonjour advertisement error:', err);
    });
  } catch (err) {
    console.error('[mDNS] Failed to start Bonjour discovery:', err);
  }
}

export function stopDiscovery() {
  if (advertisedService) {
    advertisedService.stop(() => {
      console.log('[mDNS] Discovery stopped.');
    });
  }
  if (bonjour) {
    bonjour.destroy();
  }
}
