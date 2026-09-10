/**
 * 监控模块模型（对齐 Flutter core/bg_task/hw_metrics_controller.dart 消费的
 * /api/hw/metrics 数据结构与 modules/monitor/monitor_view.dart 的取值逻辑）。
 * 数值类字段缺失时用 -1 哨兵（对齐 Flutter null 判断分支）。
 */

export function mStr(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  return `${v}`;
}

/** 浮点解析（解析失败返回 0，对齐 Flutter `x ?? 0.0` 取值） */
export function mFloat(v: Object | undefined | null): number {
  if (v === undefined || v === null) {
    return 0;
  }
  if (typeof v === 'number') {
    return Number.isFinite(v) ? v : 0;
  }
  const n = Number(`${v}`);
  return Number.isFinite(n) ? n : 0;
}

/** 浮点解析（解析失败返回 -1 哨兵，对齐 Flutter null 判断分支） */
export function mFloatOrNull(v: Object | undefined | null): number {
  if (v === undefined || v === null) {
    return -1;
  }
  if (typeof v === 'number') {
    return Number.isFinite(v) ? v : -1;
  }
  const n = Number(`${v}`);
  return Number.isFinite(n) ? n : -1;
}

function mRecord(v: Object | undefined | null): Record<string, Object> {
  if (v === undefined || v === null || typeof v !== 'object' || Array.isArray(v)) {
    return {} as Record<string, Object>;
  }
  return v as Record<string, Object>;
}

function mArray(v: Object | undefined | null): Object[] {
  if (v === undefined || v === null || !Array.isArray(v)) {
    return [];
  }
  return v as Object[];
}

/** 解析 "12.5 GB" 形式的容量字符串为字节（对齐 Flutter FileUtil.parseSizeToBytes） */
export function parseSizeToBytes(sizeFormatted: string): number {
  try {
    const parts = sizeFormatted.trim().split(' ');
    if (parts.length !== 2) {
      return -1;
    }
    const value = Number(parts[0]);
    const unit = parts[1].toUpperCase();
    if (!Number.isFinite(value)) {
      return -1;
    }
    switch (unit) {
      case 'TB':
        return value * 1024 * 1024 * 1024 * 1024;
      case 'GB':
        return value * 1024 * 1024 * 1024;
      case 'MB':
        return value * 1024 * 1024;
      case 'KB':
        return value * 1024;
      case 'B':
        return value;
      default:
        return -1;
    }
  } catch (_e) {
    return -1;
  }
}

export class MonitorCpu {
  /** 使用率百分比（0~100） */
  usage: number = 0;
  /** 温度（摄氏度；<=0 表示服务器未提供，不展示） */
  temperature: number = -1;

  static fromJson(data: Record<string, Object> | undefined | null): MonitorCpu {
    const c = new MonitorCpu();
    const d = data ?? {};
    c.usage = mFloat(d['usage']);
    c.temperature = mFloatOrNull(d['temperature']);
    return c;
  }
}

export class MonitorCpuInfo {
  manufacturer: string = '';
  brand: string = '';
  cores: number = 0;
  /** 性能核心数（缺失为 -1） */
  performanceCores: number = -1;
  /** 能效核心数（缺失为 -1） */
  efficiencyCores: number = -1;

  static fromJson(data: Record<string, Object> | undefined | null): MonitorCpuInfo {
    const c = new MonitorCpuInfo();
    const d = data ?? {};
    c.manufacturer = mStr(d['manufacturer']);
    c.brand = mStr(d['brand']);
    c.cores = mFloat(d['cores']);
    c.performanceCores = mFloatOrNull(d['performanceCores']);
    c.efficiencyCores = mFloatOrNull(d['efficiencyCores']);
    return c;
  }
}

export class MonitorGpuController {
  model: string = '';

  static fromJson(data: Record<string, Object> | undefined | null): MonitorGpuController {
    const g = new MonitorGpuController();
    const d = data ?? {};
    g.model = mStr(d['model']);
    return g;
  }
}

export class MonitorGpu {
  controllers: MonitorGpuController[] = [];

  static fromJson(data: Record<string, Object> | undefined | null): MonitorGpu {
    const g = new MonitorGpu();
    const d = data ?? {};
    const list = mArray(d['controllers']);
    list.forEach((item: Object): void => {
      g.controllers.push(MonitorGpuController.fromJson(mRecord(item)));
    });
    return g;
  }
}

export class MonitorMemory {
  /** 使用率百分比（0~100） */
  usage: number = 0;
  usedFormatted: string = '';
  totalFormatted: string = '';

  static fromJson(data: Record<string, Object> | undefined | null): MonitorMemory {
    const m = new MonitorMemory();
    const d = data ?? {};
    m.usage = mFloat(d['usage']);
    m.usedFormatted = mStr(d['usedFormatted']);
    m.totalFormatted = mStr(d['totalFormatted']);
    return m;
  }
}

export class MonitorNetwork {
  uploadSpeed: string = '0 B/s';
  downloadSpeed: string = '0 B/s';

  static fromJson(data: Record<string, Object> | undefined | null): MonitorNetwork {
    const n = new MonitorNetwork();
    const d = data ?? {};
    const upload = mStr(d['uploadSpeed']);
    const download = mStr(d['downloadSpeed']);
    n.uploadSpeed = upload.length > 0 ? upload : '0 B/s';
    n.downloadSpeed = download.length > 0 ? download : '0 B/s';
    return n;
  }
}

export class MonitorDisk {
  mount: string = '';
  /** 设备路径（对齐 Flutter disk['fs']，如 /dev/disk3s1s1） */
  fs: string = '';
  type: string = 'Unknown';
  sizeFormatted: string = '';
  availableFormatted: string = '';
  /** 使用率 0~1（无法计算时为 -1，对齐 Flutter usagePercent == null 分支） */
  usagePercent: number = -1;

  static fromJson(data: Record<string, Object> | undefined | null): MonitorDisk {
    const disk = new MonitorDisk();
    const d = data ?? {};
    disk.mount = mStr(d['mount']);
    disk.fs = mStr(d['fs']);
    const type = mStr(d['type']);
    disk.type = type.length > 0 ? type : 'Unknown';
    disk.sizeFormatted = mStr(d['sizeFormatted']);
    disk.availableFormatted = mStr(d['availableFormatted']);

    // 使用率计算（对齐 Flutter _buildDiskCard）：size 缺失时回退解析 sizeFormatted
    let totalBytes = mFloatOrNull(d['size']);
    if (totalBytes < 0) {
      totalBytes = parseSizeToBytes(disk.sizeFormatted);
    }
    const availableBytes = mFloatOrNull(d['available']);
    if (totalBytes > 0 && availableBytes >= 0) {
      let percent = 1.0 - (availableBytes / totalBytes);
      if (percent < 0) {
        percent = 0;
      }
      if (percent > 1) {
        percent = 1;
      }
      disk.usagePercent = percent;
    }
    return disk;
  }
}

export class MonitorMetrics {
  cpu: MonitorCpu | undefined = undefined;
  cpuInfo: MonitorCpuInfo | undefined = undefined;
  gpu: MonitorGpu | undefined = undefined;
  memory: MonitorMemory | undefined = undefined;
  network: MonitorNetwork | undefined = undefined;
  disks: MonitorDisk[] = [];

  static fromJson(data: Record<string, Object> | undefined | null): MonitorMetrics {
    const m = new MonitorMetrics();
    const d = data ?? {};
    if (d['cpu'] !== undefined && d['cpu'] !== null) {
      m.cpu = MonitorCpu.fromJson(mRecord(d['cpu']));
    }
    if (d['cpuInfo'] !== undefined && d['cpuInfo'] !== null) {
      m.cpuInfo = MonitorCpuInfo.fromJson(mRecord(d['cpuInfo']));
    }
    if (d['gpu'] !== undefined && d['gpu'] !== null) {
      m.gpu = MonitorGpu.fromJson(mRecord(d['gpu']));
    }
    if (d['memory'] !== undefined && d['memory'] !== null) {
      m.memory = MonitorMemory.fromJson(mRecord(d['memory']));
    }
    if (d['network'] !== undefined && d['network'] !== null) {
      m.network = MonitorNetwork.fromJson(mRecord(d['network']));
    }
    const disksRec = mRecord(d['disks']);
    const diskList = mArray(disksRec['usage']);
    diskList.forEach((item: Object): void => {
      m.disks.push(MonitorDisk.fromJson(mRecord(item)));
    });
    return m;
  }
}
