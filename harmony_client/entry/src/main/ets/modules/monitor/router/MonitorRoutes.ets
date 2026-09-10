/** 监控模块页面名常量（主线程 Index.pageMap / AppRouter 接线用） */
export class MonitorRoutes {
  static readonly MONITOR_PAGE: string = 'MonitorPage';
}

/** 监控页路由参数（对齐 Flutter AppMonitorView：无业务参数，仅预留标题） */
export class MonitorPageParam {
  title: string = '';
}
