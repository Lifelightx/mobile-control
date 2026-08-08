import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { verifyDevice } from '../auth/authService';
import { listContainers, startContainer, stopContainer, restartContainer, getContainerLogs } from '../services/dockerService';
import { addAuditLog } from '../database/db';

const containerActionSchema = z.object({
  id: z.string().min(1)
});

export async function registerDockerRoutes(app: FastifyInstance) {
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

  app.get('/docker/containers', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const all = (request.query as any).all !== 'false';
      const containers = await listContainers(all);
      return { success: true, containers };
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to list containers', details: err.message });
    }
  });

  app.post('/docker/start', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const body = containerActionSchema.parse(request.body);
      const user = request.user as { deviceId: string };
      await startContainer(body.id);
      addAuditLog('DOCKER_START', user.deviceId, `Started container ${body.id}`);
      return { success: true };
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to start container', details: err.message });
    }
  });

  app.post('/docker/stop', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const body = containerActionSchema.parse(request.body);
      const user = request.user as { deviceId: string };
      await stopContainer(body.id);
      addAuditLog('DOCKER_STOP', user.deviceId, `Stopped container ${body.id}`);
      return { success: true };
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to stop container', details: err.message });
    }
  });

  app.post('/docker/restart', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const body = containerActionSchema.parse(request.body);
      const user = request.user as { deviceId: string };
      await restartContainer(body.id);
      addAuditLog('DOCKER_RESTART', user.deviceId, `Restarted container ${body.id}`);
      return { success: true };
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to restart container', details: err.message });
    }
  });

  app.get('/docker/logs/:id', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const id = (request.params as any).id;
      const tail = parseInt((request.query as any).tail) || 100;
      const logs = await getContainerLogs(id, tail);
      return { success: true, logs };
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to fetch logs', details: err.message });
    }
  });
}
