/**
 * Unix Domain Socket IPC client.
 *
 * Connects to the Rust input daemon at /run/devcontrol/input.sock.
 * Sends length-framed binary packets (4-byte BE length prefix + packet bytes).
 * Reconnects automatically on socket close or error.
 */

import net from 'net';
import { EventEmitter } from 'events';

const SOCKET_PATH = '/run/devcontrol/input.sock';
const RECONNECT_DELAY_MS = 1000;

export class IpcClient extends EventEmitter {
  private socket: net.Socket | null = null;
  private connected = false;
  private reconnectTimer: NodeJS.Timeout | null = null;
  private destroyed = false;

  constructor() {
    super();
    this.connect();
  }

  private connect(): void {
    if (this.destroyed) return;

    const sock = new net.Socket();
    this.socket = sock;

    sock.connect(SOCKET_PATH, () => {
      this.connected = true;
      console.log('[IPC] Connected to Rust input daemon.');
      this.emit('connected');
    });

    sock.on('error', (err: NodeJS.ErrnoException) => {
      // ENOENT / ECONNREFUSED = daemon not running yet, silently retry
      if (err.code !== 'ENOENT' && err.code !== 'ECONNREFUSED') {
        console.error('[IPC] Socket error:', err.message);
      }
    });

    sock.on('close', () => {
      this.connected = false;
      this.socket = null;
      this.scheduleReconnect();
    });
  }

  private scheduleReconnect(): void {
    if (this.destroyed) return;
    if (this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connect();
    }, RECONNECT_DELAY_MS);
  }

  /**
   * Send a raw InputPacket buffer to the daemon.
   * Prefixes with a 4-byte big-endian length frame.
   * Silently drops the packet if the daemon is not connected.
   */
  send(packetBuffer: Buffer): boolean {
    if (!this.connected || !this.socket) return false;

    const lenBuf = Buffer.allocUnsafe(4);
    lenBuf.writeUInt32BE(packetBuffer.length, 0);

    try {
      this.socket.write(Buffer.concat([lenBuf, packetBuffer]));
      return true;
    } catch (err) {
      console.error('[IPC] Write error:', err);
      return false;
    }
  }

  get isConnected(): boolean {
    return this.connected;
  }

  destroy(): void {
    this.destroyed = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.socket?.destroy();
    this.socket = null;
  }
}

// Singleton so the whole agent shares one IPC connection
let _ipcClient: IpcClient | null = null;

export function getIpcClient(): IpcClient {
  if (!_ipcClient) {
    _ipcClient = new IpcClient();
  }
  return _ipcClient;
}
