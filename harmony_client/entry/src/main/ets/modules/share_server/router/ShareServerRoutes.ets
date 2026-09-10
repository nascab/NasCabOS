/**
 * 分享管理模块路由（对齐 Flutter FileShareServerView 移动端形态 + 端口设置独立页）。
 * - 主页面：底部 5 标签（快速分享/WebDAV/FTP/SFTP/用户共享），非管理员仅快速分享。
 * - 端口设置：Flutter 移动端经 Get.to 打开的独立页（_FileSharePortsSettingsPage）。
 * 主线程接线：在 AppRouter 增加 PAGE_MAIN / PAGE_PORTS 两个页面名，页面组件为
 * ShareServerMainPage / SharePortsSettingsPage（@Param param + @Param popPage）。
 */
export class ShareServerRoutes {
  /** 分享管理主页（底部 5 标签） */
  static readonly PAGE_MAIN: string = 'ShareServerMainPage';
  /** 端口设置页（管理员） */
  static readonly PAGE_PORTS: string = 'SharePortsSettingsPage';
}

/** 面板 key（对齐 Flutter currentPageKey 常量） */
export class ShareServerPageKeys {
  static readonly QUICK: string = 'share.quick';
  static readonly WEBDAV: string = 'share.webdav';
  static readonly FTP: string = 'share.ftp';
  static readonly SFTP: string = 'share.sftp';
  static readonly USER_FOLDERS: string = 'share.user_folders';
  /** 端口设置（Flutter settings.ports；移动端转独立页打开） */
  static readonly PORTS: string = 'settings.ports';
}

/** 分享管理主页路由参数（pageKey 对齐 Flutter initialPageKey/arguments['pageKey']） */
export class ShareServerMainPageParam {
  pageKey: string = '';
  /** 创建分享预填路径（对齐 Flutter arguments['quickShareCreatePath']） */
  quickShareCreatePath: string = '';
}

/** 端口设置页路由参数 */
export class SharePortsPageParam {
  title: string = '';
}
