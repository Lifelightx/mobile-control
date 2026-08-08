import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { verifyDevice } from '../auth/authService';
import {
  getRunningProcesses,
  killProcessByPid,
  launchApplication,
  getInstalledApplications,
  performWindowAction,
  PREDEFINED_APPS,
} from '../services/processService';

const launchSchema = z.object({
  command: z.string().min(1),
});

const killSchema = z.object({
  pid: z.number().int().positive(),
});

const windowActionSchema = z.object({
  appName: z.string().min(1),
  action: z.enum(['open', 'close', 'minimize', 'maximize']),
  command: z.string().optional(),
});

export async function registerAppRoutes(app: FastifyInstance) {
  // Common authentication hook for /apps/* routes
  const authenticate = async (request: any, reply: any) => {
    try {
      await request.jwtVerify();
      const payload = request.user as { deviceId: string; deviceName: string };
      const valid = await verifyDevice(payload.deviceId);
      if (!valid) {
        reply.status(401).send({ error: 'Unauthorized or disabled device' });
        return;
      }
    } catch (err) {
      reply.status(401).send({ error: 'Unauthorized request' });
    }
  };

  // Get installed applications list
  app.get('/apps/installed', { onRequest: [authenticate] }, async () => {
    const apps = await getInstalledApplications();
    return { apps };
  });

  // Get running processes
  app.get('/apps/processes', { onRequest: [authenticate] }, async (request, reply) => {
    const query = request.query as { sortBy?: 'cpu' | 'mem'; limit?: string };
    const sortBy = query.sortBy === 'mem' ? 'mem' : 'cpu';
    const limit = query.limit ? parseInt(query.limit, 10) : 100;

    const result = await getRunningProcesses(sortBy, limit);
    return result;
  });

  // Get preset shortcuts
  app.get('/apps/presets', { onRequest: [authenticate] }, async () => {
    return { presets: PREDEFINED_APPS };
  });

  // Launch application
  app.post('/apps/launch', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const body = launchSchema.parse(request.body);
      const user = request.user as { deviceId: string };
      const result = await launchApplication(body.command, user.deviceId);
      
      if (!result.success) {
        return reply.status(400).send(result);
      }
      return result;
    } catch (err: any) {
      if (err instanceof z.ZodError) {
        return reply.status(400).send({ error: 'Invalid schema', details: err.issues });
      }
      return reply.status(500).send({ error: 'Launch error', message: err.message });
    }
  });

  // Perform window actions (open, close, minimize, maximize)
  app.post('/apps/window-action', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const body = windowActionSchema.parse(request.body);
      const user = request.user as { deviceId: string };
      const result = await performWindowAction(body.appName, body.action, body.command, user.deviceId);

      if (!result.success) {
        return reply.status(400).send(result);
      }
      return result;
    } catch (err: any) {
      if (err instanceof z.ZodError) {
        return reply.status(400).send({ error: 'Invalid schema', details: err.issues });
      }
      return reply.status(500).send({ error: 'Window action error', message: err.message });
    }
  });

  // Kill running process
  app.post('/apps/kill', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const body = killSchema.parse(request.body);
      const user = request.user as { deviceId: string };
      const result = await killProcessByPid(body.pid, user.deviceId);

      if (!result.success) {
        return reply.status(400).send(result);
      }
      return result;
    } catch (err: any) {
      if (err instanceof z.ZodError) {
        return reply.status(400).send({ error: 'Invalid schema', details: err.issues });
      }
      return reply.status(500).send({ error: 'Kill error', message: err.message });
    }
  });
}
