import net from 'net';
import { Transport, TransportType } from '../transport';
import { FrameEncoder, FrameDecoder } from './bluetooth-framing';

export class BluetoothTransport implements Transport {
  public readonly type = TransportType.BLUETOOTH;
  
  private dataHandlers: Array<(data: Buffer | string) => void> = [];
  private closeHandlers: Array<() => void> = [];
  private errorHandlers: Array<(err: Error) => void> = [];
  private decoder = new FrameDecoder();

  constructor(private socket: net.Socket, public deviceId: string) {
    this.decoder.onFrame((frame) => {
      this.dataHandlers.forEach(h => h(frame));
    });

    this.socket.on('data', (data) => {
      const buffer = typeof data === 'string' ? Buffer.from(data) : data;
      this.decoder.push(buffer);
    });

    this.socket.on('close', () => {
      this.closeHandlers.forEach(h => h());
    });

    this.socket.on('error', (err) => {
      this.errorHandlers.forEach(h => h(err));
    });
  }

  public async connect(): Promise<void> {
    return Promise.resolve();
  }

  public async disconnect(): Promise<void> {
    this.socket.destroy();
    return Promise.resolve();
  }

  public async send(data: Buffer | string): Promise<void> {
    if (!this.isConnected()) throw new Error('Socket disconnected');
    
    return new Promise((resolve, reject) => {
      const framedData = FrameEncoder.encode(data);
      this.socket.write(framedData, (err) => {
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
    return !this.socket.destroyed && this.socket.writable;
  }
}
