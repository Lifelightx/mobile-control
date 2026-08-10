const dbus = require('dbus-next');

async function main() {
  const bus = dbus.systemBus();
  console.log("Connected to system bus.");

  const bluez = await bus.getProxyObject('org.bluez', '/org/bluez');
  console.log("Got bluez proxy object", Object.keys(bluez.interfaces));

  const profileManager = bluez.getInterface('org.bluez.ProfileManager1');
  console.log("Got ProfileManager1");

  process.exit(0);
}

main().catch(console.error);
