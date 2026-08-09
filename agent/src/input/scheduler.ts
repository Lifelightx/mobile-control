/**
 * 240 Hz input scheduler.
 *
 * Each tick:
 *  1. Drain mouse delta → encode → send to IPC
 *  2. Drain click queue → send each to IPC
 *  3. Drain scroll delta → encode → send to IPC
 *
 * Keyboard events bypass this scheduler and are sent immediately on arrival.
 */

import { BinaryDecoder, Opcode } from './decoder';
import { getIpcClient } from './ipc';
import { ClickQueue, KeyboardQueue, MouseQueue, ScrollQueue } from './queue';

const TICK_HZ = 240;
const TICK_INTERVAL_MS = 1000 / TICK_HZ; // ~4.17 ms

const HEADER_SIZE = 12;
const VERSION = 1;

let _schedulerTimer: NodeJS.Timeout | null = null;
let _seq = 0;

/** Singleton queues shared by the handler */
export const mouseQueue    = new MouseQueue();
export const scrollQueue   = new ScrollQueue();
export const clickQueue    = new ClickQueue();
export const keyboardQueue = new KeyboardQueue();

// ─── Packet builder ──────────────────────────────────────────────────────────

function nextSeq(): number {
  _seq = (_seq + 1) % 65536;
  return _seq;
}

function buildPacket(opcode: Opcode, payload: Buffer): Buffer {
  const buf = Buffer.allocUnsafe(HEADER_SIZE + payload.length);
  buf.writeUInt8(VERSION, 0);
  buf.writeUInt8(opcode, 1);
  buf.writeUInt16BE(nextSeq(), 2);
  buf.writeUInt32BE(Date.now() % 4294967296, 4);
  buf.writeUInt32BE(payload.length, 8);
  payload.copy(buf, HEADER_SIZE);
  return buf;
}

function buildMouseMove(dx: number, dy: number): Buffer {
  const p = Buffer.allocUnsafe(4);
  p.writeInt16BE(dx, 0);
  p.writeInt16BE(dy, 2);
  return buildPacket(Opcode.MOUSE_MOVE, p);
}

function buildMouseScroll(dx: number, dy: number): Buffer {
  const p = Buffer.allocUnsafe(4);
  p.writeInt16BE(dx, 0);
  p.writeInt16BE(dy, 2);
  return buildPacket(Opcode.MOUSE_SCROLL, p);
}

// ─── Scheduler tick ──────────────────────────────────────────────────────────

function tick(): void {
  const ipc = getIpcClient();
  if (!ipc.isConnected) return;

  // 1. Mouse movement (coalesced)
  const mouse = mouseQueue.drain();
  if (mouse) {
    ipc.send(buildMouseMove(mouse.dx, mouse.dy));
  }

  // 2. Clicks (preserve every event, just gate by tick rate)
  for (const packet of clickQueue.drain()) {
    // Re-encode the packet (already decoded by handler)
    // We pass raw bytes directly — they are already valid packets
    ipc.send(packet.rawBuffer);
  }

  // 3. Scroll (coalesced)
  const scroll = scrollQueue.drain();
  if (scroll) {
    ipc.send(buildMouseScroll(scroll.dx, scroll.dy));
  }
}

// ─── Public API ──────────────────────────────────────────────────────────────

export function startScheduler(): void {
  if (_schedulerTimer) return;
  console.log(`[Scheduler] Starting at ${TICK_HZ} Hz (${TICK_INTERVAL_MS.toFixed(2)} ms/tick)`);
  // Use setInterval; for production, a native N-API timer would be more precise
  _schedulerTimer = setInterval(tick, TICK_INTERVAL_MS);
  // Keep the interval from blocking shutdown
  if (_schedulerTimer.unref) _schedulerTimer.unref();
}

export function stopScheduler(): void {
  if (_schedulerTimer) {
    clearInterval(_schedulerTimer);
    _schedulerTimer = null;
  }
}
