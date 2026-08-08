import si from 'systeminformation';
import { exec } from 'child_process';
import { addAuditLog } from '../database/db';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

export interface ProcessInfo {
  pid: number;
  name: string;
  cpu: number;
  mem: number;
  user: string;
  command: string;
}

export interface InstalledApp {
  key: string;
  name: string;
  category: string;
  icon: string; // Material/Lucide icon identifier
  color: string; // Accent color hex
  command: string;
  processPattern: string; // Pattern to search running processes
}

export interface AppPreset {
  key: string;
  name: string;
  icon: string;
  command: string;
}

// Comprehensive Installed Desktop Applications List
export const INSTALLED_APPS: InstalledApp[] = [
  { key: 'vscode', name: 'VS Code', category: 'Development', icon: 'code', color: '#007ACC', command: 'code', processPattern: 'code' },
  { key: 'chrome', name: 'Google Chrome', category: 'Browser', icon: 'web', color: '#EA4335', command: 'google-chrome || google-chrome-stable || chromium-browser || open -a "Google Chrome"', processPattern: 'chrome' },
  { key: 'terminal', name: 'Terminal', category: 'System', icon: 'terminal', color: '#4EC9B0', command: 'x-terminal-emulator || gnome-terminal || konsole || open -a Terminal', processPattern: 'terminal' },
  { key: 'files', name: 'File Manager', category: 'System', icon: 'folder', color: '#E5C07B', command: 'xdg-open . || open .', processPattern: 'nautilus|dolphin|thunar|explorer' },
  { key: 'firefox', name: 'Firefox', category: 'Browser', icon: 'browser', color: '#FF7139', command: 'firefox', processPattern: 'firefox' },
  { key: 'calculator', name: 'Calculator', category: 'Utilities', icon: 'calculator', color: '#C678DD', command: 'gnome-calculator || kcalc || open -a Calculator', processPattern: 'calculator' },
  { key: 'spotify', name: 'Spotify', category: 'Media', icon: 'music_note', color: '#1DB954', command: 'spotify', processPattern: 'spotify' },
  { key: 'vlc', name: 'VLC Media Player', category: 'Media', icon: 'movie', color: '#FF8800', command: 'vlc', processPattern: 'vlc' },
  { key: 'postman', name: 'Postman', category: 'Development', icon: 'api', color: '#FF6C37', command: 'postman', processPattern: 'postman' },
  { key: 'discord', name: 'Discord', category: 'Communication', icon: 'chat', color: '#5865F2', command: 'discord', processPattern: 'discord' },
  { key: 'slack', name: 'Slack', category: 'Communication', icon: 'forum', color: '#4A154B', command: 'slack', processPattern: 'slack' },
  { key: 'docker', name: 'Docker Desktop', category: 'Development', icon: 'view_in_ar', color: '#2496ED', command: 'docker-desktop || systemctl start docker', processPattern: 'docker' },
  { key: 'gimp', name: 'GIMP', category: 'Graphics', icon: 'palette', color: '#5C5543', command: 'gimp', processPattern: 'gimp' },
  { key: 'obsidian', name: 'Obsidian', category: 'Productivity', icon: 'note', color: '#7A3EE8', command: 'obsidian', processPattern: 'obsidian' },
  { key: 'studio', name: 'Android Studio', category: 'Development', icon: 'android', color: '#3DDC84', command: 'android-studio || studio.sh', processPattern: 'studio' },
];

export const PREDEFINED_APPS: AppPreset[] = INSTALLED_APPS.map(app => ({
  key: app.key,
  name: app.name,
  icon: app.icon,
  command: app.command,
}));

let cachedApps: InstalledApp[] | null = null;

/**
 * Get installed desktop applications list dynamically on Linux.
 */
export async function getInstalledApplications(): Promise<InstalledApp[]> {
  if (cachedApps) {
    return cachedApps;
  }

  if (os.platform() !== 'linux') {
    return INSTALLED_APPS;
  }

  const appDirectories = [
    '/usr/share/applications',
    path.join(os.homedir(), '.local/share/applications')
  ];

  const apps: InstalledApp[] = [];
  const seenNames = new Set<string>();

  for (const dir of appDirectories) {
    if (!fs.existsSync(dir)) continue;

    const files = fs.readdirSync(dir);
    for (const file of files) {
      if (!file.endsWith('.desktop')) continue;
      
      const filePath = path.join(dir, file);
      try {
        const content = fs.readFileSync(filePath, 'utf-8');
        
        const lines = content.split('\n');
        let isDesktopEntry = false;
        let name = '';
        let execCmd = '';
        let noDisplay = false;
        let type = '';
        let categories = '';

        for (const line of lines) {
          if (line.trim() === '[Desktop Entry]') {
            isDesktopEntry = true;
            continue;
          }
          if (line.startsWith('[')) {
            if (isDesktopEntry) break;
          }

          if (!isDesktopEntry) continue;

          if (line.startsWith('Name=')) name = line.substring(5).trim();
          if (line.startsWith('Exec=')) execCmd = line.substring(5).trim();
          if (line.startsWith('NoDisplay=true')) noDisplay = true;
          if (line.startsWith('Type=')) type = line.substring(5).trim();
          if (line.startsWith('Categories=')) categories = line.substring(11).trim();
        }

        if (type !== 'Application' || noDisplay || !name || !execCmd) continue;

        if (seenNames.has(name)) continue;
        seenNames.add(name);

        const cleanCmd = execCmd.replace(/%[a-zA-Z]/g, '').trim();
        
        const colors = ['#007ACC', '#EA4335', '#4EC9B0', '#E5C07B', '#FF7139', '#C678DD', '#1DB954', '#FF8800', '#FF6C37', '#5865F2', '#2496ED'];
        const color = colors[name.length % colors.length];

        const processPattern = cleanCmd.split(' ')[0].split('/').pop() || name.toLowerCase();

        apps.push({
          key: file.replace('.desktop', ''),
          name: name,
          category: categories.split(';')[0] || 'Application',
          icon: 'apps', 
          color: color,
          command: cleanCmd,
          processPattern: processPattern,
        });

      } catch (err) {
        // Ignore read errors
      }
    }
  }

  // Merge with predefined apps to keep curated icons/colors where they exist
  const finalApps = apps.map(app => {
    const predefined = INSTALLED_APPS.find(p => 
      p.name.toLowerCase() === app.name.toLowerCase() || 
      p.key.toLowerCase() === app.key.toLowerCase() ||
      p.processPattern.toLowerCase() === app.processPattern.toLowerCase()
    );
    if (predefined) {
      return {
        ...app,
        icon: predefined.icon,
        color: predefined.color,
      };
    }
    return app;
  });

  cachedApps = finalApps.sort((a, b) => a.name.localeCompare(b.name));
  return cachedApps;
}

/**
 * Fetch top running processes sorted by CPU or memory usage.
 */
export async function getRunningProcesses(sortBy: 'cpu' | 'mem' = 'cpu', limit = 100): Promise<{ processes: ProcessInfo[]; total: number }> {
  const data = await si.processes();
  
  let list = data.list.map((p) => ({
    pid: p.pid,
    name: p.name || p.command.split(' ')[0] || 'Unknown',
    cpu: Math.round(p.cpu * 10) / 10,
    mem: Math.round(p.mem * 10) / 10,
    user: p.user || 'system',
    command: p.command || '',
  }));

  if (sortBy === 'cpu') {
    list.sort((a, b) => b.cpu - a.cpu);
  } else if (sortBy === 'mem') {
    list.sort((a, b) => b.mem - a.mem);
  }

  if (limit > 0) {
    list = list.slice(0, limit);
  }

  return {
    processes: list,
    total: data.all,
  };
}

/**
 * Kill a running process by PID.
 */
export async function killProcessByPid(pid: number, deviceId: string): Promise<{ success: boolean; message: string }> {
  try {
    if (!pid || pid <= 1) {
      return { success: false, message: 'Invalid PID' };
    }

    process.kill(pid, 'SIGTERM');
    await addAuditLog('PROCESS_KILL', deviceId, `Killed PID ${pid}`);
    return { success: true, message: `Process ${pid} killed successfully.` };
  } catch (err: any) {
    try {
      exec(`kill -9 ${pid}`);
      await addAuditLog('PROCESS_KILL_FORCE', deviceId, `Force killed PID ${pid}`);
      return { success: true, message: `Process ${pid} force killed.` };
    } catch (forceErr: any) {
      return { success: false, message: `Failed to kill process ${pid}: ${err.message}` };
    }
  }
}

/**
 * Launch an application or arbitrary command safely.
 */
export async function launchApplication(command: string, deviceId: string): Promise<{ success: boolean; message: string }> {
  try {
    if (!command || command.trim().length === 0) {
      return { success: false, message: 'Command cannot be empty' };
    }

    const trimmed = command.trim();
    const child = exec(trimmed, { detached: true } as any);
    child.unref();

    await addAuditLog('APP_LAUNCH', deviceId, `Launched command: ${trimmed}`);
    return { success: true, message: `Launched ${trimmed}` };
  } catch (err: any) {
    return { success: false, message: `Failed to launch ${command}: ${err.message}` };
  }
}

/**
 * Perform Window action (open, close, minimize, maximize) on a specific app.
 */
export async function performWindowAction(
  appName: string,
  action: 'open' | 'close' | 'minimize' | 'maximize',
  command?: string,
  deviceId: string = 'system'
): Promise<{ success: boolean; message: string }> {
  try {
    const apps = await getInstalledApplications();
    const app = apps.find(a => a.name.toLowerCase() === appName.toLowerCase() || a.key.toLowerCase() === appName.toLowerCase());
    const cmdToUse = command || app?.command || appName;
    const processPattern = app?.processPattern || appName.toLowerCase();

    if (action === 'open') {
      return await launchApplication(cmdToUse, deviceId);
    }

    if (action === 'close') {
      exec(`pkill -i -f "${processPattern}" || killall -i "${processPattern}"`);
      await addAuditLog('APP_WINDOW_CLOSE', deviceId, `Closed app ${appName}`);
      return { success: true, message: `Sent close signal to ${appName}` };
    }

    if (action === 'minimize') {
      // Use xdotool or wmctrl on Linux if available, or fallback safely
      const script = `xdotool search --onlyvisible --class "${processPattern}" windowminimize || wmctrl -r "${appName}" -b add,hidden`;
      exec(script);
      await addAuditLog('APP_WINDOW_MINIMIZE', deviceId, `Minimized app ${appName}`);
      return { success: true, message: `Minimized window for ${appName}` };
    }

    if (action === 'maximize') {
      const script = `xdotool search --class "${processPattern}" windowactivate --sync windowsize 100% 100% || wmctrl -r "${appName}" -b add,maximized_vert,maximized_horz`;
      exec(script);
      await addAuditLog('APP_WINDOW_MAXIMIZE', deviceId, `Maximized app ${appName}`);
      return { success: true, message: `Maximized window for ${appName}` };
    }

    return { success: false, message: `Unknown window action: ${action}` };
  } catch (err: any) {
    return { success: false, message: `Failed to perform ${action} on ${appName}: ${err.message}` };
  }
}
