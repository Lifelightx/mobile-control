import fs from 'fs';
import path from 'path';
import os from 'os';

function resolvePath(p: string): string {
  if (p.startsWith('~')) {
    return path.join(os.homedir(), p.slice(1));
  }
  return path.resolve(p);
}

export interface FileInfo {
  name: string;
  path: string;
  isDirectory: boolean;
  size: number;
  modifiedAt: Date | null;
}

export async function listDirectory(dirPath: string): Promise<FileInfo[]> {
  const fullPath = resolvePath(dirPath);
  const files = await fs.promises.readdir(fullPath, { withFileTypes: true });
  
  const results = await Promise.all(files.map(async (file) => {
    const filePath = path.join(fullPath, file.name);
    let size = 0;
    let modifiedAt: Date | null = null;
    try {
      const stat = await fs.promises.stat(filePath);
      size = stat.size;
      modifiedAt = stat.mtime;
    } catch(e) {
      // Ignore permission errors
    }

    return {
      name: file.name,
      path: filePath,
      isDirectory: file.isDirectory(),
      size,
      modifiedAt
    };
  }));

  // Sort directories first, then alphabetically
  results.sort((a, b) => {
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;
    return a.name.localeCompare(b.name);
  });

  return results;
}

export async function deleteFileOrDirectory(targetPath: string): Promise<void> {
  const fullPath = resolvePath(targetPath);
  const stat = await fs.promises.stat(fullPath);
  if (stat.isDirectory()) {
    await fs.promises.rm(fullPath, { recursive: true, force: true });
  } else {
    await fs.promises.unlink(fullPath);
  }
}

export async function renameFileOrDirectory(oldPath: string, newName: string): Promise<string> {
  const fullOldPath = resolvePath(oldPath);
  const directory = path.dirname(fullOldPath);
  const fullNewPath = path.join(directory, newName);
  await fs.promises.rename(fullOldPath, fullNewPath);
  return fullNewPath;
}
