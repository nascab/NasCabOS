/**
 * Docker 模块路由（对齐 Flutter DockerManagerView(appMode: true) 移动端单页形态）：
 * 单入口页 + 底部 4 标签（总览/镜像/容器/任务），控制器随页面创建销毁（对齐 GetBuilder 生命周期）。
 */
export class DockerRoutes {
  /** Docker 主页（底部 4 标签：总览/镜像/容器/任务） */
  static readonly PAGE_MAIN: string = 'DockerPage';
}

/** Docker 主页路由参数 */
export class DockerMainPageParam {
  title: string = '';
}
