import dbus from 'dbus-next';
import net from 'net';
import { BluetoothTransport } from './bluetooth-transport';
import { transportManager } from '../transport-manager';
import { verifyDevice, verifyToken, pairDevice, getActivePairingSecret } from '../../auth/authService';
import { addAuditLog } from '../../database/db';
import { app } from '../../index';

const { Interface } = dbus.interface;

class BluezProfile extends Interface {
  constructor(private onConnection: (devicePath: string, fd: number, fdProperties: any) => void) {
    super('org.bluez.Profile1');
  }

  Release() {
    console.log('[BluetoothServer] Profile released by BlueZ');
  }

  NewConnection(devicePath: string, fd: number, fdProperties: any) {
    console.log('[BluetoothServer] New incoming connection from:', devicePath);
    this.onConnection(devicePath, fd, fdProperties);
  }

  RequestDisconnection(devicePath: string) {
    console.log('[BluetoothServer] Disconnect requested for:', devicePath);
  }
}

BluezProfile.configureMembers({
  methods: {
    Release: { inSignature: '', outSignature: '' },
    NewConnection: { inSignature: 'oha{sv}', outSignature: '' },
    RequestDisconnection: { inSignature: 'o', outSignature: '' }
  }
});

export class BluetoothServer {
  private bus: dbus.MessageBus;
  private profileManager: any = null;
  private readonly profilePath = '/org/devcontrol/BluetoothProfile';

  constructor() {
    this.bus = dbus.systemBus();
  }

  public async start(): Promise<void> {
    try {
      const profile = new BluezProfile((devicePath, fd, properties) => {
        this.handleNewConnection(devicePath, fd, properties);
      });

      this.bus.export(this.profilePath, profile);

      const bluez = await this.bus.getProxyObject('org.bluez', '/org/bluez');
      this.profileManager = bluez.getInterface('org.bluez.ProfileManager1');

      // Common RFCOMM UUID
      const uuid = '00001101-0000-1000-8000-00805f9b34fb';
      
      await this.profileManager.RegisterProfile(this.profilePath, uuid, {
        Name: new dbus.Variant('s', 'DevControl Hub'),
        Role: new dbus.Variant('s', 'server'),
        Channel: new dbus.Variant('q', 1)
      });
      
      console.log('[BluetoothServer] Listening for incoming RFCOMM connections.');
    } catch (err) {
      console.error('[BluetoothServer] Failed to start Bluetooth server:', err);
    }
  }

  public async stop(): Promise<void> {
    if (this.profileManager) {
      try {
        await this.profileManager.UnregisterProfile(this.profilePath);
      } catch (err) {
        console.warn('[BluetoothServer] Error unregistering profile:', err);
      }
    }
    this.bus.disconnect();
  }

  private handleNewConnection(devicePath: string, fd: number, properties: any) {
    const socket = new net.Socket({ fd });
    
    // Create a temporary ID until we implement the protocol handshake
    const tempDeviceId = 'temp-bt-' + Math.random().toString(36).substring(7);
    
    const transport = new BluetoothTransport(socket, tempDeviceId);
    let authenticated = false;
    
    socket.on('error', (err) => {
        console.error(`[BluetoothServer] Socket error on ${transport.deviceId}:`, err);
    });

    // We must wait for auth packet before adding to transportManager
    const authTimeout = setTimeout(() => {
      if (!authenticated) {
        console.warn(`[BluetoothServer] Disconnecting ${tempDeviceId}: Auth timeout.`);
        transport.disconnect();
      }
    }, 10000); // 10s to authenticate

    transport.onData(async (data) => {
      if (authenticated) {
        // Forward manually since it's already added to transportManager? 
        // transportManager listens to transport.onData when added. 
        // Wait, transportManager adds its own listener on onData, but dataHandlers array pushes.
        // If we just add it to transportManager AFTER auth, it will receive future packets.
        // This current packet might be dropped from transportManager if we don't do something, but
        // this packet is just 'auth', so we don't need transportManager to see it.
        return; 
      }

      try {
        const payload = JSON.parse(data.toString());
        if (payload.type === 'auth') {
          try {
            const decoded = await verifyToken(payload.token);
            const valid = await verifyDevice(decoded.deviceId);
            if (!valid) throw new Error('Device not paired');

            // Success
            authenticated = true;
            clearTimeout(authTimeout);
            
            // Update device ID
            transport.deviceId = decoded.deviceId;
            
            // Register active transport
            transportManager.addTransport(transport);
            
            console.log(`[BluetoothServer] Device ${decoded.deviceName} (${decoded.deviceId}) authenticated over Bluetooth.`);
            addAuditLog('BLUETOOTH_CONNECT', decoded.deviceId, `Device connected to Bluetooth Server.`);
            
            // Send auth success
            transport.send(JSON.stringify({ type: 'auth_success' }));
          } catch (e: any) {
            console.error(`[BluetoothServer] Auth failed for ${tempDeviceId}:`, e.message);
            transport.send(JSON.stringify({ type: 'auth_failure', error: 'Invalid token' })).finally(() => {
              transport.disconnect();
            });
          }
        } else if (payload.type === 'pair') {
          try {
            const { deviceId, deviceName, secret, publicKey } = payload;
            const result = await pairDevice(deviceId, deviceName, secret, publicKey);
            if (!result.success) throw new Error(result.message);

            // Generate JWT token
            const token = app.jwt.sign({ deviceId, deviceName });

            authenticated = true;
            clearTimeout(authTimeout);
            transport.deviceId = deviceId;
            transportManager.addTransport(transport);
            
            console.log(`[BluetoothServer] Device ${deviceName} (${deviceId}) PAIRED natively over Bluetooth.`);
            addAuditLog('BLUETOOTH_PAIR', deviceId, `Device paired natively over Bluetooth.`);

            transport.send(JSON.stringify({ type: 'pair_success', token }));
          } catch (e: any) {
            console.error(`[BluetoothServer] Pair failed for ${tempDeviceId}:`, e.message);
            transport.send(JSON.stringify({ type: 'pair_failure', error: e.message })).finally(() => {
              transport.disconnect();
            });
          }
        }
      } catch (e) {
        console.warn(`[BluetoothServer] Invalid JSON in auth phase for ${tempDeviceId}`);
      }
    });
  }
}

export const bluetoothServer = new BluetoothServer();
