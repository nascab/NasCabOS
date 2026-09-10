/**
 * 服务模块数据模型（对齐 Flutter ServiceMainController 内的 Map<String,String> 结构）。
 */

/** P2P 中继节点（对齐 Flutter p2pServers 列表项 Map：chinese_name/english_name/name/host/domain） */
export class P2pServer {
  chineseName: string = '';
  englishName: string = '';
  name: string = '';
  host: string = '';
  domain: string = '';

  static fromJson(rec: Record<string, Object>): P2pServer {
    const s = new P2pServer();
    s.chineseName = svcStr(rec['chinese_name']);
    s.englishName = svcStr(rec['english_name']);
    s.name = svcStr(rec['name']);
    s.host = svcStr(rec['host']);
    s.domain = svcStr(rec['domain']);
    return s;
  }
}

/** 设备绑定结果（对齐 Flutter bindP2pDevice 返回 {'success': bool, 'errorCode': String?}） */
export class BindP2pDeviceResult {
  success: boolean = false;
  errorCode: string = '';

  static ok(): BindP2pDeviceResult {
    const r = new BindP2pDeviceResult();
    r.success = true;
    return r;
  }

  static fail(errorCode: string = ''): BindP2pDeviceResult {
    const r = new BindP2pDeviceResult();
    r.success = false;
    r.errorCode = errorCode;
    return r;
  }
}

/** JSON 边界字段转字符串（null/undefined → ''，其余 String()） */
export function svcStr(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  return `${v}`;
}

/** JSON 边界字段转 Record（非对象/数组 → 空对象） */
export function svcRecord(v: Object | undefined | null): Record<string, Object> {
  if (v !== undefined && v !== null && typeof v === 'object' && !Array.isArray(v)) {
    return v as Record<string, Object>;
  }
  return {} as Record<string, Object>;
}
