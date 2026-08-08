import { getDb } from '../database/db';
import { getDynamicInfo } from './systemService';
import { listContainers } from './dockerService';
import { exec } from 'child_process';
import util from 'util';

const execPromise = util.promisify(exec);

export interface AutomationRule {
  id: string;
  name: string;
  trigger_type: string; // 'cpu_threshold', 'ram_threshold', 'docker_stopped'
  trigger_config: string; // JSON string
  action_type: string; // 'notify', 'execute_command', 'restart_docker'
  action_config: string; // JSON string
  enabled: number;
}

let evaluationInterval: NodeJS.Timeout | null = null;
const recentlyTriggered = new Map<string, number>();

export async function getRules(): Promise<AutomationRule[]> {
  const db = await getDb();
  return db.all('SELECT * FROM automation_rules');
}

export async function addRule(rule: Omit<AutomationRule, 'id'>): Promise<string> {
  const db = await getDb();
  const id = Math.random().toString(36).substring(2, 15);
  await db.run(
    'INSERT INTO automation_rules (id, name, trigger_type, trigger_config, action_type, action_config, enabled) VALUES (?, ?, ?, ?, ?, ?, ?)',
    id, rule.name, rule.trigger_type, rule.trigger_config, rule.action_type, rule.action_config, rule.enabled
  );
  return id;
}

export async function updateRule(id: string, enabled: boolean): Promise<void> {
  const db = await getDb();
  await db.run('UPDATE automation_rules SET enabled = ? WHERE id = ?', enabled ? 1 : 0, id);
}

export async function deleteRule(id: string): Promise<void> {
  const db = await getDb();
  await db.run('DELETE FROM automation_rules WHERE id = ?', id);
}

export async function createNotification(title: string, message: string): Promise<void> {
  const db = await getDb();
  const id = Math.random().toString(36).substring(2, 15);
  await db.run(
    'INSERT INTO notifications (id, title, message, timestamp, read) VALUES (?, ?, ?, ?, ?)',
    id, title, message, Date.now(), 0
  );
  // Emit to WS (to be handled in index.ts or websocket layer)
}

export async function getNotifications(onlyUnread: boolean = false) {
  const db = await getDb();
  if (onlyUnread) {
    return db.all('SELECT * FROM notifications WHERE read = 0 ORDER BY timestamp DESC');
  }
  return db.all('SELECT * FROM notifications ORDER BY timestamp DESC LIMIT 50');
}

export async function markNotificationsRead(): Promise<void> {
  const db = await getDb();
  await db.run('UPDATE notifications SET read = 1 WHERE read = 0');
}

export function startAutomationEngine() {
  if (evaluationInterval) return;
  
  evaluationInterval = setInterval(async () => {
    try {
      const rules = await getRules();
      const enabledRules = rules.filter(r => r.enabled === 1);
      if (enabledRules.length === 0) return;

      const dynamicInfo = await getDynamicInfo();
      const cpuLoad = dynamicInfo.cpuLoad;
      const mem = dynamicInfo.mem;
      const memPercent = (mem.used / (mem.used + mem.free)) * 100;
      
      let containers: any[] | null = null;

      for (const rule of enabledRules) {
        // Prevent rapid re-triggering (cooldown of 60 seconds)
        const lastTrigger = recentlyTriggered.get(rule.id) || 0;
        if (Date.now() - lastTrigger < 60000) continue;

        let shouldTrigger = false;
        try {
          const config = JSON.parse(rule.trigger_config);
          
          if (rule.trigger_type === 'cpu_threshold') {
            if (cpuLoad > (config.threshold || 90)) shouldTrigger = true;
          } else if (rule.trigger_type === 'ram_threshold') {
            if (memPercent > (config.threshold || 90)) shouldTrigger = true;
          } else if (rule.trigger_type === 'docker_stopped') {
            if (!containers) containers = await listContainers(true);
            const containerName = config.containerName;
            const c = containers.find((x: any) => x.names.some((n: string) => n.includes(containerName)));
            if (c && c.state !== 'running') {
              shouldTrigger = true;
            }
          }

          if (shouldTrigger) {
            recentlyTriggered.set(rule.id, Date.now());
            await executeAction(rule);
          }
        } catch (err) {
          console.error(`Error evaluating rule ${rule.name}:`, err);
        }
      }
    } catch (err) {
      console.error('Automation engine error:', err);
    }
  }, 5000); // Check every 5 seconds
}

async function executeAction(rule: AutomationRule) {
  try {
    const config = JSON.parse(rule.action_config);
    if (rule.action_type === 'notify') {
      await createNotification(`Automation Triggered: ${rule.name}`, config.message || 'Rule conditions met.');
    } else if (rule.action_type === 'execute_command') {
      await execPromise(config.command);
      await createNotification(`Command Executed: ${rule.name}`, `Successfully ran: ${config.command}`);
    } else if (rule.action_type === 'restart_docker') {
      const { restartContainer } = require('./dockerService');
      await restartContainer(config.containerId);
      await createNotification(`Docker Restarted`, `Container ${config.containerId} restarted by rule ${rule.name}`);
    }
  } catch (err: any) {
    console.error(`Failed to execute action for rule ${rule.name}:`, err);
    await createNotification(`Automation Failed: ${rule.name}`, err.message);
  }
}
