import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { verifyDevice } from '../auth/authService';
import { createSession, getSession, killSession } from '../services/terminalService';

const createSessionSchema = z.object({
  cols: z.number().optional().default(80),
  rows: z.number().optional().default(24),
});

const inputSchema = z.object({
  id: z.string(),
  input: z.string(),
});

export async function registerTerminalRoutes(app: FastifyInstance) {
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

  app.post('/terminal/session', { onRequest: [authenticate] }, async (request, reply) => {
    try {
      const body = createSessionSchema.parse(request.body);
      const user = request.user as { deviceId: string };
      const id = createSession(user.deviceId, body.cols, body.rows);
      return { id };
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to create session' });
    }
  });

  app.post('/terminal/input', { onRequest: [authenticate] }, async (request, reply) => {
    const body = inputSchema.parse(request.body);
    const session = getSession(body.id);
    if (!session) return reply.status(404).send({ error: 'Session not found' });
    
    session.ptyProcess.write(body.input);
    return { success: true };
  });

  app.get('/terminal/history/:id', { onRequest: [authenticate] }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const session = getSession(id);
    if (!session) return reply.status(404).send({ error: 'Session not found' });
    
    return { history: session.outputBuffer.join('') };
  });

  app.delete('/terminal/session/:id', { onRequest: [authenticate] }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const user = request.user as { deviceId: string };
    killSession(id, user.deviceId);
    return { success: true };
  });

  // WebSocket for live interaction
  app.get('/terminal/ws/:id', { websocket: true }, (socket, req) => {
    const { id } = req.params as { id: string };
    const query = req.query as { token?: string };
    const token = query.token;
    
    if (!token) {
      socket.send(JSON.stringify({ error: 'Missing token' }));
      socket.close();
      return;
    }
    
    try {
      app.jwt.verify(token);
    } catch (e) {
      socket.send(JSON.stringify({ error: 'Invalid token' }));
      socket.close();
      return;
    }

    const session = getSession(id);
    if (!session) {
      socket.send(JSON.stringify({ error: 'Session not found' }));
      socket.close();
      return;
    }

    const listener = session.ptyProcess.onData((data: string) => {
      if (socket.readyState === 1) { // OPEN
        socket.send(JSON.stringify({ type: 'data', data }));
      }
    });

    socket.on('message', (msg: any) => {
      try {
        const parsed = JSON.parse(msg.toString());
        if (parsed.type === 'input') {
          session.ptyProcess.write(parsed.data);
        } else if (parsed.type === 'resize') {
          session.ptyProcess.resize(parsed.cols || 80, parsed.rows || 24);
        }
      } catch (e) {
        console.warn('Invalid terminal ws message', e);
      }
    });

    socket.on('close', () => {
      listener.dispose(); // stop listening when socket closes
    });
  });
}
