import crypto from 'crypto';
import qrcode from 'qrcode-terminal';
import { createVerifier } from 'fast-jwt';
import { getSetting, setSetting, getDevice, saveDevice, addAuditLog } from '../database/db';

let jwtSecret: string | null = null;
let currentPairingSecret: string | null = null;
let pairingSecretExpiresAt: number = 0;

export async function getJwtSecret(): Promise<string> {
  if (jwtSecret) return jwtSecret;

  jwtSecret = await getSetting('jwt_secret');

  if (!jwtSecret) {
    // Generate a secure random secret
    jwtSecret = crypto.randomBytes(32).toString('hex');
    await setSetting('jwt_secret', jwtSecret);
    console.log('[Auth] Generated and saved a new JWT secret.');
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

  // Register or update device
  await saveDevice({
    id: deviceId,
    name: deviceName,
    public_key: publicKey || null,
    paired_at: Date.now(),
    status: 'paired'
  });

  // Invalidate pairing code after successful pairing (disabled for development convenience)
  // currentPairingSecret = null;

  await addAuditLog('DEVICE_PAIRED', deviceId, `Device ${deviceName} successfully paired.`);
  console.log(`[Auth] Device "${deviceName}" (ID: ${deviceId}) successfully paired.`);

  return { success: true, message: 'Device paired successfully' };
}

export async function verifyDevice(deviceId: string): Promise<boolean> {
  const device = await getDevice(deviceId);
  return !!device && device.status === 'paired';
}

let jwtVerifier: any = null;

export async function verifyToken(token: string): Promise<{ deviceId: string; deviceName: string }> {
  if (!jwtVerifier) {
    const secret = await getJwtSecret();
    jwtVerifier = createVerifier({ key: secret });
  }
  return jwtVerifier(token);
}
