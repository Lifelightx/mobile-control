import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { verifyDevice } from '../auth/authService';
import { getRules, addRule, updateRule, deleteRule, getNotifications, markNotificationsRead } from '../services/automationService';

const ruleSchema = z.object({
  name: z.string().min(1),
  trigger_type: z.string(),
  trigger_config: z.string(),
  action_type: z.string(),
  action_config: z.string(),
  enabled: z.number().int().min(0).max(1)
});

export async function registerAutomationRoutes(app: FastifyInstance) {
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

  app.get('/automation/rules', { onRequest: [authenticate] }, async (request, reply) => {
    const rules = await getRules();
    return { rules };
  });

  app.post('/automation/rules', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const body = ruleSchema.parse(request.body);
      const id = await addRule(body);
      return { success: true, id };
    } catch (err: any) {
      return reply.status(400).send({ error: 'Failed to add rule', details: err.message });
    }
  });

  app.put('/automation/rules/:id', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const id = (request.params as any).id;
      const enabled = (request.body as any).enabled;
      await updateRule(id, !!enabled);
      return { success: true };
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to update rule', details: err.message });
    }
  });

  app.delete('/automation/rules/:id', { onRequest: [authenticate] }, async (request, reply) => {
    const id = (request.params as any).id;
    await deleteRule(id);
    return { success: true };
  });

  app.get('/notifications', { onRequest: [authenticate] }, async (request, reply) => {
    const notifications = await getNotifications();
    return { notifications };
  });

  app.post('/notifications/read', { onRequest: [authenticate] }, async (request, reply) => {
    await markNotificationsRead();
    return { success: true };
  });
}
