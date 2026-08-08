import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { verifyDevice } from '../auth/authService';
import { listDirectory, deleteFileOrDirectory, renameFileOrDirectory } from '../services/fileService';
import { addAuditLog } from '../database/db';
import os from 'os';

const listSchema = z.object({
  path: z.string().optional().default(os.homedir()),
});

const renameSchema = z.object({
  path: z.string().min(1),
  newName: z.string().min(1),
});

const deleteSchema = z.object({
  path: z.string().min(1),
});

export async function registerFileRoutes(app: FastifyInstance) {
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

  app.post('/files/list', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const body = listSchema.parse(request.body);
      const files = await listDirectory(body.path);
      return { path: body.path, files };
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to list directory', details: err.message });
    }
  });

  app.post('/files/rename', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const body = renameSchema.parse(request.body);
      const user = request.user as { deviceId: string };
      const newPath = await renameFileOrDirectory(body.path, body.newName);
      addAuditLog('FILE_RENAME', user.deviceId, `Renamed ${body.path} to ${newPath}`);
      return { success: true, newPath };
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to rename', details: err.message });
    }
  });

  app.post('/files/delete', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const body = deleteSchema.parse(request.body);
      const user = request.user as { deviceId: string };
      await deleteFileOrDirectory(body.path);
      addAuditLog('FILE_DELETE', user.deviceId, `Deleted ${body.path}`);
      return { success: true };
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to delete', details: err.message });
    }
  });
}
