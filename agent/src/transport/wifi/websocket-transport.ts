import { Transport, TransportType } from '../transport';

export class WebSocketTransport implements Transport {
  public readonly type = TransportType.WIFI;
  
  private dataHandlers: Array<(data: Buffer | string) => void> = [];
  private closeHandlers: Array<() => void> = [];
  private errorHandlers: Array<(err: Error) => void> = [];

  constructor(private socket: any, public deviceId: string) {
    this.socket.on('message', (message: any) => {
      this.dataHandlers.forEach(h => h(message));
    });

    this.socket.on('close', (code: any, reason: any) => {
      this.closeHandlers.forEach(h => h());
    });

    this.socket.on('error', (err: any) => {
      this.errorHandlers.forEach(h => h(err));
    });
  }

  public async connect(): Promise<void> {
    // For the server, the socket is already connected when we instantiate this class.
    return Promise.resolve();
  }

  public async disconnect(): Promise<void> {
    this.socket.close();
    return Promise.resolve();
  }

  public async send(data: Buffer | string): Promise<void> {
    if (!this.isConnected()) {
      throw new Error('Socket is not connected');
    }
    
    return new Promise((resolve, reject) => {
      this.socket.send(data, (err: any) => {
        if (err) reject(err);
        else resolve();
      });
    });
  }

  public onData(handler: (data: Buffer | string) => void): void {
    this.dataHandlers.push(handler);
  }

  public onClose(handler: () => void): void {
    this.closeHandlers.push(handler);
  }

  public onError(handler: (err: Error) => void): void {
    this.errorHandlers.push(handler);
  }

  public isConnected(): boolean {
    return this.socket.readyState === 1; // 1 = OPEN
  }
}
