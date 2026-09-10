/**
 * 服务模块路由（对齐 Flutter ServiceMobileView / ServiceMainView）。
 * 移动端为单入口页：底部 3 标签（NasCab账号/远程访问/DDNS），
 * PC 独有左侧二级菜单布局分支不实现（对齐迁移范围约定）。
 * 页面本身无需携带数据参数，控制器为全局单例（对齐 Flutter Get.put permanent: true）。
 */
export class ServiceRoutes {
  /** 服务主页（3 标签：NasCab账号/远程访问/DDNS） */
  static readonly PAGE_MAIN: string = 'ServiceMainPage';
}

/** 服务页内 tab key（对齐 Flutter currentPageKey 常量） */
export class ServicePageKeys {
  static readonly ACCOUNT_NASCAB: string = 'account.nascab';
  static readonly REMOTE_ACCESS: string = 'account.remote_access';
  static readonly DDNS: string = 'account.ddns';
}

/** 服务主页路由参数 */
export class ServiceMainPageParam {
  title: string = '';
  /** 初始页签 key（对齐 Flutter ServiceMainView.initialPageKey，空 = 默认账号页） */
  initialPageKey: string = '';
}
