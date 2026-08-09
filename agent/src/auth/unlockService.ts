import crypto from 'crypto';
import { exec } from 'child_process';
import { getDb, addAuditLog } from '../database/db';

// Track used nonces to prevent replay attacks (in-memory, cleared on restart)
const usedNonces = new Set<string>();

interface UnlockRequest {
  deviceId: string;
  timestamp: number;
  nonce: string;
  signature: string;
}

/**
 * Verify the signed unlock request from the mobile device.
 * The mobile signs: `deviceId:nonce:timestamp` using HMAC-SHA256 with the JWT as key.
 */
function verifySignature(req: UnlockRequest, jwtToken: string): boolean {
  const payload = `${req.deviceId}:${req.nonce}:${req.timestamp}`;
  const expected = crypto
    .createHmac('sha256', jwtToken)
    .update(payload)
    .digest('hex');
  // Timing-safe comparison to prevent timing attacks
  try {
    return crypto.timingSafeEqual(
      Buffer.from(expected, 'hex'),
      Buffer.from(req.signature, 'hex')
    );
  } catch {
    return false;
  }
}

/**
 * Unlock the current desktop session via D-Bus (no polkit, no password needed).
 * Uses the session D-Bus socket directly — same bus the agent runs on.
 */
function unlockDesktop(): void {
  // Resolve the D-Bus session bus. The agent runs as the same user so
  // process.env.DBUS_SESSION_BUS_ADDRESS is already set. Fall back to
  // the well-known socket path using our UID.
  const uid = process.getuid ? process.getuid() : 0;
  const dbusAddr = process.env.DBUS_SESSION_BUS_ADDRESS || `unix:path=/run/user/${uid}/bus`;
  const display  = process.env.DISPLAY || ':0';

  const env = {
    ...process.env,
    DISPLAY: display,
    DBUS_SESSION_BUS_ADDRESS: dbusAddr,
  };

  // Primary: GNOME ScreenSaver D-Bus interface — no password, no polkit
  const primary = `dbus-send --session --type=method_call \
    --dest=org.gnome.ScreenSaver \
    /org/gnome/ScreenSaver \
    org.gnome.ScreenSaver.SetActive \
    boolean:false`;

  // Fallback: freedesktop screensaver interface (KDE, XFCE, etc.)
  const fallback = `dbus-send --session --type=method_call \
    --dest=org.freedesktop.ScreenSaver \
    /ScreenSaver \
    org.freedesktop.ScreenSaver.SetActive \
    boolean:false`;

  // Final fallback: xdg-screensaver
  const xdg = 'xdg-screensaver reset';

  // Fire primary, then chain fallbacks — all fire-and-forget (no await in caller)
  exec(primary, { env }, (err) => {
    if (!err) {
      console.log('[Unlock] Screen unlocked via GNOME ScreenSaver D-Bus');
      return;
    }
    exec(fallback, { env }, (err2) => {
      if (!err2) {
        console.log('[Unlock] Screen unlocked via freedesktop ScreenSaver D-Bus');
        return;
      }
      exec(xdg, { env }, (err3) => {
        if (!err3) {
          console.log('[Unlock] Screen unlocked via xdg-screensaver');
        } else {
          console.error('[Unlock] All unlock methods failed:', err3.message);
        }
      });
    });
  });
}

export async function handleUnlockRequest(
  req: UnlockRequest,
  jwtToken: string
): Promise<{ success: boolean; error?: string }> {
  const db = await getDb();

  // 1. Validate timestamp (reject requests older than 30 seconds)
  const now = Date.now();
  if (Math.abs(now - req.timestamp) > 30_000) {
    await addAuditLog('UNLOCK_REJECTED', req.deviceId, 'Timestamp expired or too far in future');
    return { success: false, error: 'Request timestamp expired' };
  }

  // 2. Check for replay attack (duplicate nonce)
  if (usedNonces.has(req.nonce)) {
    await addAuditLog('UNLOCK_REJECTED', req.deviceId, `Replay attack detected with nonce: ${req.nonce}`);
    return { success: false, error: 'Duplicate request detected' };
  }

  // 3. Verify device is paired and active
  const device = await db.get(
    'SELECT id, name FROM devices WHERE id = ? AND status = ?',
    req.deviceId,
    'paired'
  );
  if (!device) {
    await addAuditLog('UNLOCK_REJECTED', req.deviceId, 'Device not found or not paired');
    return { success: false, error: 'Device not authorized' };
  }

  // 4. Verify cryptographic signature
  if (!verifySignature(req, jwtToken)) {
    await addAuditLog('UNLOCK_REJECTED', req.deviceId, `Signature verification failed for device ${device.name}`);
    return { success: false, error: 'Invalid signature' };
  }

  // 5. Mark nonce as used (expire after 60 seconds to bound memory growth)
  usedNonces.add(req.nonce);
  setTimeout(() => usedNonces.delete(req.nonce), 60_000);

  // 6. Fire-and-forget: respond immediately so mobile doesn't time out,
  //    then execute the unlock in the background.
  addAuditLog('UNLOCK_SUCCESS', req.deviceId, `Laptop unlocked by device: ${device.name}`);
  console.log(`[Unlock] Laptop unlocked by device "${device.name}" (${req.deviceId})`);
  unlockDesktop(); // non-blocking — runs in background

  return { success: true };
}
