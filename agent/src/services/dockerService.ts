import Docker from 'dockerode';

const docker = new Docker();

export async function listContainers(all: boolean = true) {
  try {
    const containers = await docker.listContainers({ all });
    return containers.map(c => ({
      id: c.Id,
      names: c.Names,
      image: c.Image,
      state: c.State,
      status: c.Status,
      ports: c.Ports,
      created: c.Created
    }));
  } catch (error: any) {
    throw new Error(`Failed to list containers: ${error.message}`);
  }
}

export async function startContainer(id: string) {
  const container = docker.getContainer(id);
  await container.start();
}

export async function stopContainer(id: string) {
  const container = docker.getContainer(id);
  await container.stop();
}

export async function restartContainer(id: string) {
  const container = docker.getContainer(id);
  await container.restart();
}

export async function getContainerLogs(id: string, tail: number = 100): Promise<string> {
  const container = docker.getContainer(id);
  const logs = await container.logs({
    stdout: true,
    stderr: true,
    tail,
    timestamps: false
  });
  
  // Docker logs format: 8 byte header (1 byte stream type, 3 bytes zero, 4 bytes size) followed by payload.
  // When using dockerode logs() with stdout/stderr as true (not stream), it returns a raw buffer.
  // However, dockerode sometimes returns string directly or handles muxing depending on version.
  // We can strip multiplexing headers manually if it's a buffer.
  if (Buffer.isBuffer(logs)) {
    return stripDockerMultiplexing(logs);
  } else {
    return (logs as any).toString();
  }
}

function stripDockerMultiplexing(buffer: Buffer): string {
  let output = '';
  let offset = 0;
  while (offset < buffer.length) {
    if (offset + 8 > buffer.length) break;
    // const streamType = buffer.readUInt8(offset); // 1 = stdout, 2 = stderr
    const payloadSize = buffer.readUInt32BE(offset + 4);
    offset += 8; // skip header
    if (offset + payloadSize > buffer.length) break;
    output += buffer.toString('utf8', offset, offset + payloadSize);
    offset += payloadSize;
  }
  return output;
}
