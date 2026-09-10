/**
 * 安全中心路由（对齐 Flutter AppSecurityCenterPage / SecurityCenterView）。
 * 移动端为单入口页：底部 4 标签（最佳实践/安全设置/IP黑名单/设备管理），
 * 非管理员仅设备管理（对齐 controller.selectPage 的权限收敛）。
 * 页面本身无需携带数据参数，控制器随页面创建（对齐 Flutter SecurityCenterScope 生命周期）。
 */
export class SecurityRoutes {
  /** 安全中心主页（管理员 4 标签，非管理员直达设备管理） */
  static readonly PAGE_MAIN: string = 'SecurityCenterPage';
}

/** 安全中心面板 key（对齐 Flutter currentPageKey 常量） */
export class SecurityPageKeys {
  static readonly BEST_PRACTICES: string = 'security.best_practices';
  static readonly SETTINGS: string = 'security.settings';
  static readonly IP_BLACKLIST: string = 'security.ip_blacklist';
  static readonly DEVICES: string = 'security.devices';
}

/** 安全中心主页路由参数 */
export class SecurityCenterPageParam {
  title: string = '';
}
