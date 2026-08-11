export enum TransportType {
  WIFI = 'wifi',
}

export interface Transport {
  readonly type: TransportType;
  deviceId: string;

  connect(): Promise<void>;
  disconnect(): Promise<void>;

  send(data: Buffer | string): Promise<void>;

  onData(handler: (data: Buffer | string) => void): void;
  onClose(handler: () => void): void;
  onError(handler: (err: Error) => void): void;

  isConnected(): boolean;
}
