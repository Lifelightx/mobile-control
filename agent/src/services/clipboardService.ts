export async function readClipboard(): Promise<string> {
  try {
    const clipboard = (await import('clipboardy')).default;
    return await clipboard.read();
  } catch (err: any) {
    throw new Error(`Failed to read clipboard: ${err.message}`);
  }
}

export async function writeClipboard(text: string): Promise<void> {
  try {
    const clipboard = (await import('clipboardy')).default;
    await clipboard.write(text);
  } catch (err: any) {
    throw new Error(`Failed to write clipboard: ${err.message}`);
  }
}
