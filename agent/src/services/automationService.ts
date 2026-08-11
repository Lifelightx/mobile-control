import { getAutomationRules, saveAutomationRule, deleteAutomationRule, addNotificationRaw, getAllNotificationsRaw, markAllNotificationsReadRaw } from '../database/db';
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
  return getAutomationRules();
}

export async function addRule(rule: Omit<AutomationRule, 'id'>): Promise<string> {
  const id = Math.random().toString(36).substring(2, 15);
  const newRule = { ...rule, id };
  await saveAutomationRule(newRule);
  return id;
}

export async function updateRule(id: string, enabled: boolean): Promise<void> {
  const rules = await getAutomationRules();
  const rule = rules.find(r => r.id === id);
  if (rule) {
    rule.enabled = enabled ? 1 : 0;
    await saveAutomationRule(rule);
  }
}

export async function deleteRule(id: string): Promise<void> {
  await deleteAutomationRule(id);
}

export async function createNotification(title: string, message: string): Promise<void> {
  const id = Math.random().toString(36).substring(2, 15);
  await addNotificationRaw({
    id, title, message, timestamp: Date.now(), read: 0, acknowledged: 0
  });
  // Emit to WS (to be handled in index.ts or websocket layer)
}

export async function getNotifications(onlyUnread: boolean = false) {
  return getAllNotificationsRaw(onlyUnread);
}

export async function markNotificationsRead(): Promise<void> {
  await markAllNotificationsReadRaw();
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
