/**
 * Input event queues.
 *
 * Mouse / Scroll queues are LOSSY  — only the latest accumulated delta matters.
 * Keyboard / Shortcut queues are RELIABLE — every event is preserved in order.
 */

import { InputPacket, Opcode } from './decoder';

// ─── Mouse / Scroll accumulator ────────────────────────────────────────────

export interface MouseDelta {
  dx: number;
  dy: number;
}

export interface ScrollDelta {
  dx: number;
  dy: number;
}

/**
 * Lossy mouse movement queue.
 * Incoming move events are accumulated into a running delta.
 * The scheduler drains and resets it every tick.
 */
export class MouseQueue {
  private dx = 0;
  private dy = 0;
  private hasPending = false;

  push(dx: number, dy: number): void {
    this.dx += dx;
    this.dy += dy;
    this.hasPending = true;
  }

  /** Returns accumulated delta and resets. Returns null if nothing pending. */
  drain(): MouseDelta | null {
    if (!this.hasPending) return null;
    const delta: MouseDelta = { dx: this.dx, dy: this.dy };
    this.dx = 0;
    this.dy = 0;
    this.hasPending = false;
    return delta;
  }
}

/**
 * Lossy scroll queue.
 */
export class ScrollQueue {
  private dx = 0;
  private dy = 0;
  private hasPending = false;

  push(dx: number, dy: number): void {
    this.dx += dx;
    this.dy += dy;
    this.hasPending = true;
  }

  drain(): ScrollDelta | null {
    if (!this.hasPending) return null;
    const delta: ScrollDelta = { dx: this.dx, dy: this.dy };
    this.dx = 0;
    this.dy = 0;
    this.hasPending = false;
    return delta;
  }
}

/**
 * Lossy click queue — we still send every click but as a small fixed queue.
 * Clicks bypass coalescing (they must not be merged) but are gated by the scheduler.
 */
export class ClickQueue {
  private queue: InputPacket[] = [];

  push(packet: InputPacket): void {
    this.queue.push(packet);
  }

  drain(): InputPacket[] {
    const items = this.queue;
    this.queue = [];
    return items;
  }
}

/**
 * Reliable keyboard queue — every event is preserved FIFO.
 * Keyboard events bypass the scheduler and are sent immediately.
 */
export class KeyboardQueue {
  private queue: InputPacket[] = [];

  push(packet: InputPacket): void {
    this.queue.push(packet);
  }

  drain(): InputPacket[] {
    const items = this.queue;
    this.queue = [];
    return items;
  }

  get length(): number {
    return this.queue.length;
  }
}
