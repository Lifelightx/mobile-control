// Direct WebSocket test — bypasses Flutter to isolate server behaviour.
const WebSocket = require('ws');
const sqlite3 = require('sqlite3');
const { createSigner } = require('fast-jwt');

async function runTest() {
  // Read JWT secret from DB
  const secret = await new Promise((resolve, reject) => {
    const db = new sqlite3.Database('./data/control_hub.db');
    db.get("SELECT value FROM settings WHERE key = 'jwt_secret'", [], (err, row) => {
      db.close();
      if (err || !row) reject(new Error('Cannot read JWT secret: ' + err));
      else resolve(row.value);
    });
  });

  const sign = createSigner({ key: secret });
  const token = await sign({
    deviceId: 'b072953f-a035-41e1-aa57-5c2940552816',
    deviceName: 'TestScript',
  });

  console.log('[Test] Connecting to ws://172.17.93.38:3000/ws ...');
  const ws = new WebSocket(`ws://172.17.93.38:3000/ws?token=${token}`);

  ws.on('open', () => {
    console.log('[Test] ✅ Connection OPEN — server accepted it');
    setInterval(() => {
      ws.send(JSON.stringify({ type: 'ping' }));
      console.log('[Test] → ping sent');
    }, 5000);
  });

  ws.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    if (msg.type === 'pong') {
      console.log('[Test] ← pong received');
    } else if (msg.type === 'system_update') {
      console.log('[Test] ← system_update: CPU=' + msg.data?.cpuLoad + '%');
    } else {
      console.log('[Test] ← msg:', JSON.stringify(msg).substring(0, 80));
    }
  });

  ws.on('error', (err) => {
    console.error('[Test] ❌ WS error:', err.message);
  });

  ws.on('close', (code, reason) => {
    console.log(`[Test] ❌ Connection CLOSED — code=${code} reason="${reason.toString()}"`);
    process.exit(1);
  });

  // If still connected after 15s → server is stable, issue is client-side
  setTimeout(() => {
    console.log('[Test] ✅ 15 seconds — connection STABLE. Server is fine. Bug is client-side.');
    ws.close();
    process.exit(0);
  }, 15000);
}

runTest().catch(e => { console.error(e); process.exit(1); });
