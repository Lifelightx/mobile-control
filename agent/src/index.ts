import Fastify from 'fastify';
import fastifyWebSocket from '@fastify/websocket';
import fastifyJwt from '@fastify/jwt';
import fastifyStatic from '@fastify/static';
import { z } from 'zod';
import dotenv from 'dotenv';
import path from 'path';
import { initStore, addAuditLog } from './database/db';
import { getJwtSecret, getActivePairingSecret, generatePairingSecret, pairDevice, verifyDevice } from './auth/authService';
import { startDiscovery, stopDiscovery } from './services/discovery';
import { getLocalIpAddress } from './utils/network';
import { getStaticInfo, getDynamicInfo } from './services/systemService';
import { registerAppRoutes } from './routes/appRoutes';
import { registerTerminalRoutes } from './routes/terminalRoutes';
import { createSession, getSession, killSession } from './services/terminalService';
import { registerFileRoutes } from './routes/fileRoutes';
import { registerDockerRoutes } from './routes/dockerRoutes';
import { listContainers, startContainer, stopContainer, restartContainer, getContainerLogs } from './services/dockerService';
import { registerAutomationRoutes } from './routes/automationRoutes';
import { registerClipboardRoutes } from './routes/clipboardRoutes';
import { startAutomationEngine } from './services/automationService';
import { startNotificationEngine, eventBus } from './notifications/index';
import { NormalizedNotification } from './notifications/normalizer';
import { getMissedNotifications, markNotificationAcknowledged } from './notifications/history';
import { shouldDeliverNotification } from './notifications/filter';
import { handleUnlockRequest } from './auth/unlockService';
import { startScheduler } from './input/scheduler';
import { getIpcClient } from './input/ipc';
import { handleInputPacket } from './input/handler';
import { transportManager } from './transport/transport-manager';
import { WebSocketTransport } from './transport/wifi/websocket-transport';


dotenv.config();

export const app = Fastify({ logger: true });

// Setup schemas
const pairSchema = z.object({
  deviceId: z.string().min(1),
  deviceName: z.string().min(1),
  secret: z.string().min(1),
  publicKey: z.string().optional(),
});

async function main() {
  // Ensure DB is initialized
  await initStore();

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

  // Phase 13: Biometric Laptop Unlock endpoint
  app.post('/auth/unlock', {
    onRequest: [async (request: any, reply: any) => {
      try {
        await request.jwtVerify();
        const payload = request.user as { deviceId: string };
        const valid = await verifyDevice(payload.deviceId);
        if (!valid) throw new Error('Device not paired');
      } catch (err) {
        reply.status(401).send({ error: 'Unauthorized device' });
      }
    }]
  }, async (request: any, reply: any) => {
    try {
      // Extract the raw JWT token from the Authorization header
      const authHeader = request.headers['authorization'] ?? '';
      const jwtToken = authHeader.replace('Bearer ', '');
      const body = request.body as {
        deviceId: string;
        timestamp: number;
        nonce: string;
        signature: string;
      };
      const result = await handleUnlockRequest(body, jwtToken);
      if (!result.success) {
        return reply.status(403).send({ error: result.error });
      }
      return { success: true };
    } catch (err: any) {
      return reply.status(500).send({ error: 'Internal server error', details: err.message });
    }
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

  // Subscribe to Notification Engine
  eventBus.on('new_notification', async (notification: NormalizedNotification) => {
    const payload = JSON.stringify({ type: 'notification', data: notification });
    const transports = transportManager.getActiveTransports();
    const sentTo = new Set<string>();
    
    for (const t of transports) {
      if (t.isConnected() && !sentTo.has(t.deviceId)) {
        const deliver = await shouldDeliverNotification(t.deviceId, notification);
        if (deliver) {
          transportManager.broadcast(t.deviceId, payload);
          sentTo.add(t.deviceId);
        }
      }
    }
  });

  // Global dynamic info interval
  setInterval(async () => {
    const transports = transportManager.getActiveTransports();
    if (transports.length === 0) return;
    
    try {
      const dynamicInfo = await getDynamicInfo();
      transportManager.broadcastAll(JSON.stringify({ type: 'system_update', data: dynamicInfo }));
    } catch (err) {
      console.error('[System] Error fetching system updates:', err);
    }
  }, 2000);

  // Handle incoming messages from transports
  transportManager.onData(async (deviceId, message, transportType) => {
    try {
      const parsed = JSON.parse(message.toString());
      if (parsed.type === 'ping') {
        transportManager.broadcast(deviceId, JSON.stringify({ type: 'pong' }));
      } else if (parsed.type === 'get_system_info') {
        const staticInfo = await getStaticInfo();
        const dynamicInfo = await getDynamicInfo();
        transportManager.broadcast(deviceId, JSON.stringify({ type: 'system_info', data: { ...staticInfo, ...dynamicInfo } }));
      } else if (parsed.type === 'sync_notifications') {
        const since = parsed.timestamp || 0;
        const missed = await getMissedNotifications(since);
        transportManager.broadcast(deviceId, JSON.stringify({ type: 'sync_notifications_result', data: missed }));
      } else if (parsed.type === 'ack_notification') {
        const id = parsed.id;
        if (id) await markNotificationAcknowledged(id);
      } else if (parsed.type === 'terminal_start') {
        const id = createSession(deviceId, parsed.cols || 80, parsed.rows || 24);
        const session = getSession(id);
        if (session) {
          session.ptyProcess.onData((data: string) => {
            transportManager.broadcast(deviceId, JSON.stringify({ type: 'terminal_output', id, data }));
          });
          transportManager.broadcast(deviceId, JSON.stringify({ type: 'terminal_session', id }));
        }
      } else if (parsed.type === 'terminal_input') {
        const session = getSession(parsed.id);
        if (session) session.ptyProcess.write(parsed.data);
      } else if (parsed.type === 'terminal_resize') {
        const session = getSession(parsed.id);
        if (session) session.ptyProcess.resize(parsed.cols || 80, parsed.rows || 24);
      } else if (parsed.type === 'terminal_kill') {
        killSession(parsed.id, deviceId);
      } else if (parsed.type === 'request') {
        const requestId = parsed.requestId;
        try {
          if (parsed.action === 'docker.list_containers') {
            const containers = await listContainers(parsed.payload?.all ?? true);
            transportManager.broadcast(deviceId, JSON.stringify({ type: 'response', requestId, status: 'success', payload: { containers } }));
          } else if (parsed.action === 'docker.start') {
            await startContainer(parsed.payload.id);
            addAuditLog('DOCKER_START', deviceId, `Started container ${parsed.payload.id}`);
            transportManager.broadcast(deviceId, JSON.stringify({ type: 'response', requestId, status: 'success' }));
          } else if (parsed.action === 'docker.stop') {
            await stopContainer(parsed.payload.id);
            addAuditLog('DOCKER_STOP', deviceId, `Stopped container ${parsed.payload.id}`);
            transportManager.broadcast(deviceId, JSON.stringify({ type: 'response', requestId, status: 'success' }));
          } else if (parsed.action === 'docker.restart') {
            await restartContainer(parsed.payload.id);
            addAuditLog('DOCKER_RESTART', deviceId, `Restarted container ${parsed.payload.id}`);
            transportManager.broadcast(deviceId, JSON.stringify({ type: 'response', requestId, status: 'success' }));
          } else if (parsed.action === 'docker.logs') {
            const logs = await getContainerLogs(parsed.payload.id, parsed.payload.tail || 100);
            transportManager.broadcast(deviceId, JSON.stringify({ type: 'response', requestId, status: 'success', payload: { logs } }));
          } else {
            transportManager.broadcast(deviceId, JSON.stringify({ type: 'response', requestId, status: 'error', error: 'Unknown action' }));
          }
        } catch (err: any) {
          transportManager.broadcast(deviceId, JSON.stringify({ type: 'response', requestId, status: 'error', error: err.message }));
        }
      }
    } catch (err) {
      console.warn(`[Transport] Received invalid message format from ${deviceId}`, err);
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
      
      const transport = new WebSocketTransport(socket, deviceId);
      transportManager.addTransport(transport);
      
      console.log(`[WS] Connection authenticated for device ${decoded.deviceName} (${deviceId})`);
      console.log(`[WS] Socket readyState after auth: ${socket.readyState}`);
      addAuditLog('WS_CONNECT', deviceId, `Device connected to WebSockets.`);
    } catch (err) {
      console.log('[WS] Connection rejected: Invalid JWT token');
      socket.send(JSON.stringify({ error: 'Unauthorized: Invalid token' }));
      socket.close();
      return;
    }

    socket.on('close', (code: any, reason: any) => {
      const reasonStr = reason ? reason.toString() : 'none';
      console.log(`[WS] Connection closed for device: ${deviceId} | code=${code} reason=${reasonStr}`);
      addAuditLog('WS_DISCONNECT', deviceId, `Device disconnected. code=${code} reason=${reasonStr}`);
    });
  });

  // ── Binary input WebSocket ────────────────────────────────────────────────
  // Accepts raw binary frames from the Flutter gesture engine.
  // JWT token passed as query param: /ws/input?token=...
  // No JSON, no text, pure binary.
  app.get('/ws/input', { websocket: true }, (socket, req) => {
    const query = req.query as { token?: string };
    const token = query.token;

    if (!token) {
      socket.close(1008, 'Unauthorized: Missing token');
      return;
    }

    let deviceId = 'unknown';
    try {
      const decoded = app.jwt.verify(token) as { deviceId: string; deviceName: string };
      deviceId = decoded.deviceId;
      console.log(`[InputWS] Connected: ${decoded.deviceName} (${deviceId})`);
    } catch {
      socket.close(1008, 'Unauthorized: Invalid token');
      return;
    }

    socket.on('message', (data: Buffer) => {
      // Each WebSocket frame = exactly one binary InputPacket
      handleInputPacket(data);
    });

    socket.on('error', (err: Error) => {
      console.error(`[InputWS] Error for ${deviceId}:`, err.message);
    });

    socket.on('close', () => {
      console.log(`[InputWS] Disconnected: ${deviceId}`);
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



  // ── Input Subsystem ────────────────────────────────────────────────────────
  
  // Spawn the Rust daemon automatically
  const { spawn } = require('child_process');
  const daemonPath = path.join(__dirname, '../bin/devcontrol-input');
  
  // First ensure the socket directory exists (requires sudo if running as non-root)
  // Usually the udev rules and socket dir /run/devcontrol are configured by the user.
  // We'll just spawn it and let it run.
  const daemon = spawn(daemonPath, [], { stdio: 'inherit' });
  daemon.on('error', (err: any) => {
    console.warn('[Server] Could not start Rust input daemon automatically. Ensure it is installed and /run/devcontrol exists.', err.message);
  });
  daemon.on('exit', (code: any) => {
    console.warn(`[Server] Rust daemon exited with code ${code}`);
  });

  // Pre-connect IPC client so it's ready before the first packet arrives
  getIpcClient();
  // Start 240 Hz scheduler for mouse/scroll coalescing
  startScheduler();
  console.log('[Server] Input subsystem ready.');
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
