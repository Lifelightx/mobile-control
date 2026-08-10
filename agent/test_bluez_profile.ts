import dbus from 'dbus-next';
const { Interface, method } = dbus.interface;

class BluezProfile extends Interface {
  constructor() {
    super('org.bluez.Profile1');
  }
  Release() {
    console.log('Profile released');
  }
  NewConnection(devicePath: any, fd: any, fdProperties: any) {
    console.log('New connection:', devicePath, fd, fdProperties);
  }
  RequestDisconnection(devicePath: any) {
    console.log('Request disconnection:', devicePath);
  }
}

BluezProfile.configureMembers({
  methods: {
    Release: { inSignature: '', outSignature: '' },
    NewConnection: { inSignature: 'oha{sv}', outSignature: '' },
    RequestDisconnection: { inSignature: 'o', outSignature: '' }
  }
});

async function main() {
  const bus = dbus.systemBus();
  console.log("Connected to system bus.");

  const profile = new BluezProfile();
  bus.export('/org/devcontrol/Profile', profile);
  console.log("Exported profile object.");

  const bluez = await bus.getProxyObject('org.bluez', '/org/bluez');
  const profileManager = bluez.getInterface('org.bluez.ProfileManager1');
  
  await profileManager.RegisterProfile('/org/devcontrol/Profile', '00001101-0000-1000-8000-00805f9b34fb', {
    Name: new dbus.Variant('s', 'DevControl Profile'),
    Role: new dbus.Variant('s', 'server'),
    Channel: new dbus.Variant('q', 1)
  });
  console.log("Registered profile with BlueZ.");

  // Keep alive
  setTimeout(async () => {
    console.log("Test finished");
    await profileManager.UnregisterProfile('/org/devcontrol/Profile');
    process.exit(0);
  }, 2000);
}

main().catch(console.error);
