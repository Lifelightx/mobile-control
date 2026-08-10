export class FrameEncoder {
  public static encode(payload: Buffer | string): Buffer {
    const buffer = typeof payload === 'string' ? Buffer.from(payload) : payload;
    const lengthBuffer = Buffer.alloc(4);
    lengthBuffer.writeUInt32BE(buffer.length, 0);
    return Buffer.concat([lengthBuffer, buffer]);
  }
}

export class FrameDecoder {
  private buffer: Buffer = Buffer.alloc(0);
  private onFrameCallback?: (frame: Buffer) => void;

  public onFrame(callback: (frame: Buffer) => void) {
    this.onFrameCallback = callback;
  }

  public push(data: Buffer) {
    this.buffer = Buffer.concat([this.buffer, data]);
    this.processBuffer();
  }

  private processBuffer() {
    while (this.buffer.length >= 4) {
      const length = this.buffer.readUInt32BE(0);
      const totalLength = 4 + length;

      if (this.buffer.length >= totalLength) {
        const frame = this.buffer.subarray(4, totalLength);
        if (this.onFrameCallback) {
          this.onFrameCallback(Buffer.from(frame)); // Copy to prevent mutation
        }
        this.buffer = this.buffer.subarray(totalLength);
      } else {
        break; // Wait for more data
      }
    }
  }
}
