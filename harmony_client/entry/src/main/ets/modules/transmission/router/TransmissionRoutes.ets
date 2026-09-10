/**
 * Transmission 模块路由（对齐 Flutter TransmissionView(appMode: true) 移动端单页形态）：
 * 单入口页 + 底部 3 标签（总览/任务/设置），控制器随页面创建销毁（对齐 GetBuilder 生命周期）。
 */
export class TransmissionRoutes {
  /** Transmission 主页（底部 3 标签：总览/任务/设置） */
  static readonly PAGE_MAIN: string = 'TransmissionPage';
}

/** Transmission 主页路由参数 */
export class TransmissionMainPageParam {
  title: string = '';
}
