import si from 'systeminformation';

export interface SystemStaticInfo {
  os: {
    platform: string;
    distro: string;
    release: string;
    arch: string;
    hostname: string;
  };
  cpu: {
    manufacturer: string;
    brand: string;
    speed: number;
    cores: number;
    physicalCores: number;
  };
  mem: {
    total: number;
  };
}

export interface SystemDynamicInfo {
  cpuLoad: number;
  cpuTemp: number;
  mem: {
    used: number;
    free: number;
    active: number;
    available: number;
  };
  battery: {
    hasBattery: boolean;
    percent: number;
    isCharging: boolean;
  };
  uptime: number;
}

export async function getStaticInfo(): Promise<SystemStaticInfo> {
  const osInfo = await si.osInfo();
  const cpuInfo = await si.cpu();
  const memInfo = await si.mem();

  return {
    os: {
      platform: osInfo.platform,
      distro: osInfo.distro,
      release: osInfo.release,
      arch: osInfo.arch,
      hostname: osInfo.hostname,
    },
    cpu: {
      manufacturer: cpuInfo.manufacturer,
      brand: cpuInfo.brand,
      speed: cpuInfo.speed,
      cores: cpuInfo.cores,
      physicalCores: cpuInfo.physicalCores,
    },
    mem: {
      total: memInfo.total,
    },
  };
}

export async function getDynamicInfo(): Promise<SystemDynamicInfo> {
  const currentLoad = await si.currentLoad();
  const cpuTemp = await si.cpuTemperature();
  const memInfo = await si.mem();
  const battery = await si.battery();
  const time = si.time();

  return {
    cpuLoad: Math.round(currentLoad.currentLoad * 100) / 100,
    cpuTemp: cpuTemp.main || 0,
    mem: {
      used: memInfo.used,
      free: memInfo.free,
      active: memInfo.active,
      available: memInfo.available,
    },
    battery: {
      hasBattery: battery.hasBattery,
      percent: battery.percent,
      isCharging: battery.isCharging,
    },
    uptime: time.uptime,
  };
}
