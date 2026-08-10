const dbus = require('dbus-next');
const { Interface, property, method, signal } = dbus.interface;

class BluezProfile extends Interface {
  constructor() {
    super('org.bluez.Profile1');
  }

  @method({ inSignature: '', outSignature: '' })
  Release() {
    console.log('Profile released');
  }

  @method({ inSignature: 'oha{sv}', outSignature: '' })
  NewConnection(devicePath, fd, fdProperties) {
    console.log('New connection:', devicePath, fd, fdProperties);
  }

  @method({ inSignature: 'o', outSignature: '' })
  RequestDisconnection(devicePath) {
    console.log('Request disconnection:', devicePath);
  }
}

async function main() {
  const bus = dbus.systemBus();
  console.log("Connected to system bus.");

  const profile = new BluezProfile();
  bus.export('/org/devcontrol/Profile', profile);
  console.log("Exported profile object.");

  const bluez = await bus.getProxyObject('org.bluez', '/org/bluez');
  const profileManager = bluez.getInterface('org.bluez.ProfileManager1');
  
  await profileManager.RegisterProfile('/org/devcontrol/Profile', '1101', {
    Name: 'DevControl Profile',
    Role: 'server',
    Channel: 1
  });
  console.log("Registered profile with BlueZ.");

  // Keep alive
  setTimeout(() => {
    console.log("Test finished");
    process.exit(0);
  }, 2000);
}

main().catch(console.error);
