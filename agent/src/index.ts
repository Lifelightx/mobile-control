import Fastify from 'fastify';
import fastifyWebSocket from '@fastify/websocket';
import fastifyJwt from '@fastify/jwt';
import fastifyStatic from '@fastify/static';
import { z } from 'zod';
import dotenv from 'dotenv';
import path from 'path';
import { getDb, addAuditLog } from './database/db';
import { getJwtSecret, getActivePairingSecret, generatePairingSecret, pairDevice, verifyDevice } from './auth/authService';
import { startDiscovery, stopDiscovery } from './services/discovery';
import { getLocalIpAddress } from './utils/network';
import { getStaticInfo, getDynamicInfo } from './services/systemService';
import { registerAppRoutes } from './routes/appRoutes';
import { registerTerminalRoutes } from './routes/terminalRoutes';
import { registerFileRoutes } from './routes/fileRoutes';
import { registerDockerRoutes } from './routes/dockerRoutes';
import { registerAutomationRoutes } from './routes/automationRoutes';
import { registerClipboardRoutes } from './routes/clipboardRoutes';
import { startAutomationEngine } from './services/automationService';
import { startNotificationEngine, eventBus } from './notifications/index';
import { NormalizedNotification } from './notifications/normalizer';
import { getMissedNotifications, markNotificationAcknowledged } from './notifications/history';
import { shouldDeliverNotification } from './notifications/filter';

dotenv.config();

const app = Fastify({ logger: true });

// Setup schemas
const pairSchema = z.object({
  deviceId: z.string().min(1),
  deviceName: z.string().min(1),
  secret: z.string().min(1),
  publicKey: z.string().optional(),
});

async function main() {
  // Ensure DB is initialized
  await getDb();

  // Retrieve JWT secret persistently
  const secretKey = await getJwtSecret();

  // Register JWT Plugin
  await app.register(fastifyJwt, {
    secret: secretKey,
  });

  // Register WebSocket Plugin with explicit options to prevent premature closes.
  // perMessageDeflate: false  → disables compression which can drop mobile connections.
  // clientTracking: true      → tracks connected clients for proper lifecycle management.
  await app.register(fastifyWebSocket, {
    options: {
      perMessageDeflate: false,
      clientTracking: true,
    },
  });

  // Register Static File serving
  await app.register(fastifyStatic, {
    root: path.join(__dirname, '../public'),
    prefix: '/public/',
  });

  // Serve landing page
  app.get('/setup', async (request, reply) => {
    return reply.sendFile('index.html');
  });

  // Download client app route
  app.get('/download', async (request, reply) => {
    return reply.sendFile('app.apk');
  });

  // Health endpoint
  app.get('/health', async () => {
    return { status: 'ok', uptime: process.uptime() };
  });

  // Setup pairing (generates a pairing code if none exists or is expired)
  app.get('/auth/pair-setup', async (request, reply) => {
    const active = getActivePairingSecret();
    let secret = active.secret;
    if (!secret) {
      secret = generatePairingSecret();
    }
    const ip = getLocalIpAddress();
    const port = (request.server.server.address() as any).port || 3000;
    return {
      ip,
      port,
      secret,
      pairingUrl: `devcontrol://pair?ip=${ip}&port=${port}&secret=${secret}`,
    };
  });

  // Pair device endpoint
  app.post('/auth/pair', async (request, reply) => {
    try {
      const body = pairSchema.parse(request.body);
      const result = await pairDevice(body.deviceId, body.deviceName, body.secret, body.publicKey);
      if (!result.success) {
        return reply.status(401).send({ error: result.message });
      }

      // Generate JWT token
      const token = app.jwt.sign({ deviceId: body.deviceId, deviceName: body.deviceName });
      return { success: true, token };
    } catch (err: any) {
      if (err instanceof z.ZodError) {
        return reply.status(400).send({ error: 'Invalid input schema', details: err.issues });
      }
      return reply.status(500).send({ error: 'Pairing failed', details: err.message });
    }
  });

  // Endpoint for mobile client to stream logs for diagnostics
  app.post('/auth/log', async (request, reply) => {
    const body = request.body as { message: string };
    console.log(`[Mobile Log] ${body.message}`);
    return { success: true };
  });

  // Authenticated route for static system info
  app.get('/system', {
    onRequest: [async (request, reply) => {
      try {
        await request.jwtVerify();
        const payload = request.user as { deviceId: string; deviceName: string };
        const valid = await verifyDevice(payload.deviceId);
        if (!valid) {
          throw new Error('Device not paired or disabled');
        }
      } catch (err) {
        reply.status(401).send({ error: 'Unauthorized device' });
      }
    }]
  }, async () => {
    const staticInfo = await getStaticInfo();
    const dynamicInfo = await getDynamicInfo();
    return { ...staticInfo, ...dynamicInfo };
  });

  // Register App Manager routes
  await registerAppRoutes(app);
  await registerTerminalRoutes(app);
  await registerFileRoutes(app);
  await registerDockerRoutes(app);
  await registerAutomationRoutes(app);
  await registerClipboardRoutes(app);

  const activeSockets = new Set<{ deviceId: string, socket: any }>();

  // Subscribe to Notification Engine
  eventBus.on('new_notification', async (notification: NormalizedNotification) => {
    const payload = JSON.stringify({ type: 'notification', data: notification });
    for (const client of activeSockets) {
      if (client.socket.readyState === 1) { // 1 = OPEN
        // Phase 8: Notification Filtering (Check per-device rules before delivery)
        const deliver = await shouldDeliverNotification(client.deviceId, notification);
        if (deliver) {
          client.socket.send(payload);
        }
      }
    }
  });

  // WebSocket connection for real-time monitoring
  app.get('/ws', { websocket: true }, (socket, req) => {
    let intervalId: NodeJS.Timeout | null = null;
    let deviceId = 'unknown';

    console.log('[WS] New socket connection request');

    // Simple custom token verification for WS since standard headers might not be present
    const query = req.query as { token?: string };
    const token = query.token;
    if (!token) {
      console.log('[WS] Connection rejected: No token provided');
      socket.send(JSON.stringify({ error: 'Unauthorized: Missing token' }));
      socket.close();
      return;
    }

    try {
      const decoded = app.jwt.verify(token) as { deviceId: string; deviceName: string };
      deviceId = decoded.deviceId;
      // Register socket with deviceId
      activeSockets.add({ deviceId, socket });
      console.log(`[WS] Connection authenticated for device ${decoded.deviceName} (${deviceId})`);
      console.log(`[WS] Socket readyState after auth: ${socket.readyState}`);
      addAuditLog('WS_CONNECT', deviceId, `Device connected to WebSockets.`);
    } catch (err) {
      console.log('[WS] Connection rejected: Invalid JWT token');
      socket.send(JSON.stringify({ error: 'Unauthorized: Invalid token' }));
      socket.close();
      return;
    }

    // Periodically send dynamic system updates
    intervalId = setInterval(async () => {
      try {
        const dynamicInfo = await getDynamicInfo();
        if (socket.readyState === socket.OPEN) {
          socket.send(JSON.stringify({ type: 'system_update', data: dynamicInfo }));
        }
      } catch (err) {
        console.error('[WS] Error fetching system updates:', err);
      }
    }, 2000);

    socket.on('message', async (message: any) => {
      try {
        const parsed = JSON.parse(message.toString());
        if (parsed.type === 'ping') {
          socket.send(JSON.stringify({ type: 'pong' }));
        } else if (parsed.type === 'sync_notifications') {
          const since = parsed.timestamp || 0;
          const missed = await getMissedNotifications(since);
          socket.send(JSON.stringify({ type: 'sync_notifications_result', data: missed }));
        } else if (parsed.type === 'ack_notification') {
          const id = parsed.id;
          if (id) await markNotificationAcknowledged(id);
        }
      } catch (err) {
        console.warn('[WS] Received invalid message format', err);
      }
    });

    socket.on('error', (err: any) => {
      console.error(`[WS] Socket error for device ${deviceId}:`, err);
    });

    socket.on('close', (code: any, reason: any) => {
      const reasonStr = reason ? reason.toString() : 'none';
      console.log(`[WS] Connection closed for device: ${deviceId} | code=${code} reason=${reasonStr}`);
      if (intervalId) clearInterval(intervalId);
      
      // Remove socket from active list
      for (const client of activeSockets) {
        if (client.socket === socket) {
          activeSockets.delete(client);
          break;
        }
      }
      
      addAuditLog('WS_DISCONNECT', deviceId, `Device disconnected. code=${code} reason=${reasonStr}`);
    });
  });

  // Start fastify server
  const port = Number(process.env.PORT) || 3000;
  const host = process.env.HOST || '0.0.0.0';
  await app.listen({ port, host });
  console.log(`[Server] Desktop Agent listening on http://${host}:${port}`);

  // Generate initial pairing secret on start
  const localIp = getLocalIpAddress() || '127.0.0.1';
  generatePairingSecret(localIp, port);

  // Start automation engine
  startAutomationEngine();

  // Start mDNS network discovery advertisement
  startDiscovery(port);

  // Start Notification Engine
  startNotificationEngine();
}

// Graceful shutdown
const signals = ['SIGINT', 'SIGTERM'];
signals.forEach((signal) => {
  process.on(signal, async () => {
    console.log(`\n[Server] Received ${signal}, shutting down gracefully...`);
    stopDiscovery();
    await app.close();
    process.exit(0);
  });
});

main().catch((err) => {
  app.log.error(err);
  process.exit(1);
});
