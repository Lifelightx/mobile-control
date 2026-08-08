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
}

export class BinaryDecoder {
  static readonly HEADER_SIZE = 12;

  /**
   * Decodes a binary packet buffer into an InputPacket object.
   * Header Layout:
   * [0]    uint8  Version
   * [1]    uint8  Opcode
   * [2-3]  uint16 Sequence (Big Endian)
   * [4-7]  uint32 Timestamp (Big Endian)
   * [8-11] uint32 Payload Length (Big Endian)
   */
  static decode(buffer: Buffer): InputPacket {
    if (buffer.length < this.HEADER_SIZE) {
      throw new Error(`Packet too small: ${buffer.length} bytes. Expected at least ${this.HEADER_SIZE} bytes.`);
    }

    const version = buffer.readUInt8(0);
    const opcode = buffer.readUInt8(1) as Opcode;
    const sequence = buffer.readUInt16BE(2);
    const timestamp = buffer.readUInt32BE(4);
    const payloadLength = buffer.readUInt32BE(8);

    if (buffer.length < this.HEADER_SIZE + payloadLength) {
      throw new Error(`Incomplete packet: expected ${this.HEADER_SIZE + payloadLength} bytes, got ${buffer.length}`);
    }

    const payload = buffer.subarray(this.HEADER_SIZE, this.HEADER_SIZE + payloadLength);

    return {
      version,
      opcode,
      sequence,
      timestamp,
      payloadLength,
      payload,
    };
  }
}
