import * as pty from 'node-pty';
import os from 'os';
import { addAuditLog } from '../database/db';

export interface TerminalSession {
  id: string;
  ptyProcess: pty.IPty;
  outputBuffer: string[];
}

const sessions = new Map<string, TerminalSession>();
const shell = os.platform() === 'win32' ? 'powershell.exe' : process.env.SHELL || 'bash';

export function createSession(deviceId: string, cols: number = 80, rows: number = 24): string {
  const id = Math.random().toString(36).substring(2, 15);
  
  const ptyProcess = pty.spawn(shell, [], {
    name: 'xterm-color',
    cols: cols,
    rows: rows,
    cwd: os.homedir(),
    env: process.env as Record<string, string>
  });

  const session: TerminalSession = {
    id,
    ptyProcess,
    outputBuffer: []
  };

  ptyProcess.onData((data) => {
    session.outputBuffer.push(data);
    if (session.outputBuffer.length > 1000) {
      session.outputBuffer.shift();
    }
  });

  sessions.set(id, session);
  addAuditLog('TERMINAL_START', deviceId, `Started terminal session ${id}`);
  return id;
}

export function getSession(id: string): TerminalSession | undefined {
  return sessions.get(id);
}

export function killSession(id: string, deviceId: string) {
  const session = sessions.get(id);
  if (session) {
    session.ptyProcess.kill();
    sessions.delete(id);
    addAuditLog('TERMINAL_END', deviceId, `Ended terminal session ${id}`);
  }
}
