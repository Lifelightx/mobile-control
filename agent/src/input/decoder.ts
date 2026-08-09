export enum Opcode {
  MOUSE_MOVE = 0x01,
  MOUSE_DOWN = 0x02,
  MOUSE_UP = 0x03,
  MOUSE_SCROLL = 0x04,
  KEY_DOWN = 0x05,
  KEY_UP = 0x06,
}

export interface InputPacket {
  version: number;
  opcode: Opcode;
  sequence: number;
  timestamp: number;
  payloadLength: number;
  payload: Buffer;
  /** Original raw bytes — used for passthrough to IPC without re-encoding */
  rawBuffer: Buffer;
}

export class BinaryDecoder {
  static readonly HEADER_SIZE = 12;

  private lastSequence = -1;

  /**
   * Decodes a binary packet buffer into an InputPacket object.
   * Header Layout:
   * [0]    uint8  Version
   * [1]    uint8  Opcode
   * [2-3]  uint16 Sequence (Big Endian)
   * [4-7]  uint32 Timestamp (Big Endian)
   * [8-11] uint32 Payload Length (Big Endian)
   *
   * Returns null for duplicate or out-of-order packets (discard per phase 17 spec).
   * Keyboard events always pass through regardless of ordering.
   */
  decode(buffer: Buffer): InputPacket | null {
    if (buffer.length < BinaryDecoder.HEADER_SIZE) {
      throw new Error(`Packet too small: ${buffer.length} bytes. Expected at least ${BinaryDecoder.HEADER_SIZE} bytes.`);
    }

    const version      = buffer.readUInt8(0);
    const opcode       = buffer.readUInt8(1) as Opcode;
    const sequence     = buffer.readUInt16BE(2);
    const timestamp    = buffer.readUInt32BE(4);
    const payloadLength = buffer.readUInt32BE(8);

    if (buffer.length < BinaryDecoder.HEADER_SIZE + payloadLength) {
      throw new Error(`Incomplete packet: expected ${BinaryDecoder.HEADER_SIZE + payloadLength} bytes, got ${buffer.length}`);
    }

    // Discard duplicate or out-of-order for lossy channels (mouse/scroll)
    if (this.lastSequence !== -1) {
      const expected = (this.lastSequence + 1) % 65536;
      if (sequence !== expected) {
        const isKeyboard = opcode === Opcode.KEY_DOWN || opcode === Opcode.KEY_UP;
        if (!isKeyboard) {
          return null; // Discard per spec (Phase 17)
        }
      }
    }
    this.lastSequence = sequence;

    const payload   = buffer.subarray(BinaryDecoder.HEADER_SIZE, BinaryDecoder.HEADER_SIZE + payloadLength);
    const rawBuffer = buffer.subarray(0, BinaryDecoder.HEADER_SIZE + payloadLength);

    return { version, opcode, sequence, timestamp, payloadLength, payload, rawBuffer };
  }

  /** Static convenience — no sequence tracking. */
  static decode(buffer: Buffer): InputPacket {
    const result = new BinaryDecoder().decode(buffer);
    if (!result) throw new Error('Unexpected null from static decode');
    return result;
  }
}
