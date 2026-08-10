import crypto from 'crypto';
import qrcode from 'qrcode-terminal';
import { createVerifier } from 'fast-jwt';
import { getDb, addAuditLog } from '../database/db';

let jwtSecret: string | null = null;
let currentPairingSecret: string | null = null;
let pairingSecretExpiresAt: number = 0;

export async function getJwtSecret(): Promise<string> {
  if (jwtSecret) return jwtSecret;

  const db = await getDb();
  const row = await db.get('SELECT value FROM settings WHERE key = ?', 'jwt_secret');

  if (row) {
    jwtSecret = row.value;
  } else {
    // Generate a secure random secret
    jwtSecret = crypto.randomBytes(32).toString('hex');
    await db.run('INSERT INTO settings (key, value) VALUES (?, ?)', 'jwt_secret', jwtSecret);
    console.log('[Auth] Generated and saved a new JWT secret.');
  }

  if (!jwtSecret) {
    throw new Error('JWT secret was not successfully loaded or generated.');
  }

  return jwtSecret;
}

export function generatePairingSecret(ip?: string, port?: number): string {
  // Generate a 6-digit or 8-character numeric/alphanumeric code
  const secret = crypto.randomBytes(4).toString('hex').toUpperCase(); // e.g. "A1B2C3D4"
  currentPairingSecret = secret;
  pairingSecretExpiresAt = Date.now() + 5 * 60 * 1000; // 5 minutes validity
  
  console.log('\n=============================================');
  console.log('   DEVELOPER CONTROL HUB - DEVICE PAIRING    ');
  console.log('=============================================');
  console.log(`   Pairing Code: ${secret}`);
  
  if (ip && port) {
    const setupUrl = `http://${ip}:${port}/setup`;
    console.log(`   Scan the QR Code below to download and connect:`);
    console.log(`   URL: ${setupUrl}\n`);
    qrcode.generate(setupUrl, { small: true });
  } else {
    console.log('   Scan the QR Code on your mobile app or enter');
    console.log('   the pairing code manually to connect.');
  }
  console.log('=============================================\n');

  return secret;
}

export function getActivePairingSecret(): { secret: string | null; expiresAt: number } {
  if (Date.now() > pairingSecretExpiresAt) {
    currentPairingSecret = null;
  }
  return { secret: currentPairingSecret, expiresAt: pairingSecretExpiresAt };
}

export async function pairDevice(
  deviceId: string,
  deviceName: string,
  secret: string,
  publicKey?: string
): Promise<{ success: boolean; message: string }> {
  const active = getActivePairingSecret();
  if (!active.secret || active.secret !== secret.toUpperCase()) {
    await addAuditLog('PAIRING_FAILED', null, `Failed pairing attempt from ${deviceName} (ID: ${deviceId}): Invalid or expired code`);
    return { success: false, message: 'Invalid or expired pairing code' };
  }

  const db = await getDb();
  
  // Register or update device
  await db.run(
    `INSERT OR REPLACE INTO devices (id, name, public_key, paired_at, status) 
     VALUES (?, ?, ?, ?, 'paired')`,
    deviceId,
    deviceName,
    publicKey || null,
    Date.now()
  );

  // Invalidate pairing code after successful pairing (disabled for development convenience)
  // currentPairingSecret = null;

  await addAuditLog('DEVICE_PAIRED', deviceId, `Device ${deviceName} successfully paired.`);
  console.log(`[Auth] Device "${deviceName}" (ID: ${deviceId}) successfully paired.`);

  return { success: true, message: 'Device paired successfully' };
}

export async function verifyDevice(deviceId: string): Promise<boolean> {
  const db = await getDb();
  const device = await db.get('SELECT id FROM devices WHERE id = ? AND status = ?', deviceId, 'paired');
  return !!device;
}

let jwtVerifier: any = null;

export async function verifyToken(token: string): Promise<{ deviceId: string; deviceName: string }> {
  if (!jwtVerifier) {
    const secret = await getJwtSecret();
    jwtVerifier = createVerifier({ key: secret });
  }
  return jwtVerifier(token);
}
