/**
 * 终端模块页面名常量与路由参数（对齐 Flutter TerminalPage，移动端全屏交互页）。
 * 主线程在 AppRouter/Index 接线时使用 TERMINAL_PAGE 注册 NavDestination。
 */
export const TERMINAL_PAGE: string = 'TerminalPage';

/** 终端页路由参数（对齐 Flutter TerminalPage 的 instanceId） */
export class TerminalMainPageParam {
  /** 实例 ID：单窗口固定 'terminal'，用于 UI 配置存储 key 与连接去重 */
  instanceId: string = 'terminal';
}
