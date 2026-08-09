/**
 * Input handler — the glue between the binary WebSocket and the queues.
 *
 * Routing:
 *   MOUSE_MOVE   → mouseQueue (lossy)
 *   MOUSE_DOWN   → clickQueue (gated by scheduler)
 *   MOUSE_UP     → clickQueue (gated by scheduler)
 *   MOUSE_SCROLL → scrollQueue (lossy)
 *   KEY_DOWN     → IPC directly (reliable, bypass scheduler)
 *   KEY_UP       → IPC directly (reliable, bypass scheduler)
 */

import { BinaryDecoder, Opcode } from './decoder';
import { getIpcClient } from './ipc';
import { clickQueue, mouseQueue, scrollQueue } from './scheduler';

const decoder = new BinaryDecoder();

export function handleInputPacket(data: Buffer): void {
  let packet;
  try {
    packet = decoder.decode(data);
  } catch (err) {
    console.warn('[InputHandler] Decode error:', err);
    return;
  }

  if (!packet) return; // Discarded (duplicate/out-of-order)

  const ipc = getIpcClient();

  switch (packet.opcode) {
    case Opcode.MOUSE_MOVE: {
      const dx = packet.payload.readInt16BE(0);
      const dy = packet.payload.readInt16BE(2);
      mouseQueue.push(dx, dy);
      break;
    }

    case Opcode.MOUSE_DOWN:
    case Opcode.MOUSE_UP: {
      // Clicks go through the scheduler's click queue (not coalesced, just gated)
      clickQueue.push(packet);
      break;
    }

    case Opcode.MOUSE_SCROLL: {
      const dx = packet.payload.readInt16BE(0);
      const dy = packet.payload.readInt16BE(2);
      scrollQueue.push(dx, dy);
      break;
    }

    case Opcode.KEY_DOWN:
    case Opcode.KEY_UP: {
      // Keyboard bypasses scheduler — send immediately for lossless delivery
      if (ipc.isConnected) {
        ipc.send(packet.rawBuffer);
      }
      break;
    }

    default:
      console.warn('[InputHandler] Unknown opcode:', packet.opcode);
  }
}
