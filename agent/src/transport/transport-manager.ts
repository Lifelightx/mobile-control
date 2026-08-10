import { Transport, TransportType } from './transport';

export class TransportManager {
  private transports: Map<string, Set<Transport>> = new Map();
  private dataHandlers: Array<(deviceId: string, data: Buffer | string, transportType: TransportType) => void> = [];

  constructor() {}

  public addTransport(transport: Transport) {
    const { deviceId } = transport;
    if (!this.transports.has(deviceId)) {
      this.transports.set(deviceId, new Set());
    }
    
    this.transports.get(deviceId)!.add(transport);

    transport.onData((data) => {
      this.dataHandlers.forEach(h => h(deviceId, data, transport.type));
    });

    transport.onClose(() => {
      this.removeTransport(transport);
    });

    transport.onError((err) => {
      console.error(`[TransportManager] Error on transport ${transport.type} for device ${deviceId}:`, err);
    });
  }

  public removeTransport(transport: Transport) {
    const { deviceId } = transport;
    if (this.transports.has(deviceId)) {
      this.transports.get(deviceId)!.delete(transport);
      if (this.transports.get(deviceId)!.size === 0) {
        this.transports.delete(deviceId);
      }
    }
  }

  public getActiveTransports(deviceId?: string): Transport[] {
    if (deviceId) {
      return Array.from(this.transports.get(deviceId) || []);
    }
    const all: Transport[] = [];
    for (const set of this.transports.values()) {
      all.push(...set);
    }
    return all;
  }

  public onData(handler: (deviceId: string, data: Buffer | string, transportType: TransportType) => void) {
    this.dataHandlers.push(handler);
  }

  public async broadcast(deviceId: string, data: Buffer | string): Promise<void> {
    const transports = this.getActiveTransports(deviceId);
    
    // Send over the preferred transport if available. Right now we just send over the first available or all.
    // For now, send to all active transports for this device to ensure delivery.
    const promises = transports
      .filter(t => t.isConnected())
      .map(t => t.send(data).catch(err => {
        console.error(`[TransportManager] Failed to send data to ${deviceId} over ${t.type}:`, err);
      }));

    await Promise.allSettled(promises);
  }

  public async broadcastAll(data: Buffer | string): Promise<void> {
    const transports = this.getActiveTransports();
    
    const promises = transports
      .filter(t => t.isConnected())
      .map(t => t.send(data).catch(err => {
        console.error(`[TransportManager] Failed to broadcast over ${t.type}:`, err);
      }));

    await Promise.allSettled(promises);
  }
}

export const transportManager = new TransportManager();
