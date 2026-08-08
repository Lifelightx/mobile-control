import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { verifyDevice } from '../auth/authService';
import { readClipboard, writeClipboard } from '../services/clipboardService';
import { addAuditLog } from '../database/db';

const writeSchema = z.object({
  text: z.string()
});

export async function registerClipboardRoutes(app: FastifyInstance) {
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

  app.get('/clipboard', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const text = await readClipboard();
      return { success: true, text };
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to read clipboard', details: err.message });
    }
  });

  app.post('/clipboard', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const body = writeSchema.parse(request.body);
      const user = request.user as { deviceId: string };
      await writeClipboard(body.text);
      addAuditLog('CLIPBOARD_WRITE', user.deviceId, `Updated laptop clipboard`);
      return { success: true };
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to write clipboard', details: err.message });
    }
  });
}
