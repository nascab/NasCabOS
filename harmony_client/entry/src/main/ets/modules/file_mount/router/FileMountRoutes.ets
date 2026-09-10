import { MountItem } from '../models/FileMountModels';

/**
 * 远程挂载模块路由（对齐 Flutter FileMountView 移动端形态）：
 * 主页 = 底部 2 标签（文件协议管理 / 网盘挂载）；新增与编辑在 Flutter 中为对话框，
 * 鸿蒙端按移动端「列表 → 编辑页」模式转为两个 NavDestination 编辑页，功能不变。
 */
export class FileMountRoutes {
  /** 远程挂载主页（底部 2 标签） */
  static readonly PAGE_MAIN: string = 'FileMountPage';
  /** 文件协议挂载 新增/编辑页（对齐 Flutter _MountDialog） */
  static readonly PAGE_MOUNT_EDIT: string = 'FileMountEditPage';
  /** 网盘挂载 新增/编辑页（对齐 Flutter _OpenlistMountDialog） */
  static readonly PAGE_OPENLIST_EDIT: string = 'OpenlistMountEditPage';
}

/** 主页面板 key（对齐 Flutter currentPageKey 常量） */
export class MountPageKeys {
  static readonly LIST: string = 'mount.list';
  static readonly OPENLIST: string = 'mount.openlist';
}

/** 远程挂载主页路由参数（页面无数据参数，控制器为模块级单例） */
export class FileMountPageParam {
  title: string = '';
}

/** 文件协议挂载编辑页参数：initial 为空表示新增 */
export class FileMountEditPageParam {
  initial: MountItem | undefined = undefined;
}

/** 网盘挂载编辑页参数：initial 为空表示新增 */
export class OpenlistMountEditPageParam {
  initial: MountItem | undefined = undefined;
}
