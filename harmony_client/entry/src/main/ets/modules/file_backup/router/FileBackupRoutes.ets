import { BackupTask } from '../models/FileBackupModels';

/**
 * 磁盘间备份模块路由（对齐 Flutter FileBackupView 移动端形态）：
 * 主页 = 备份任务列表；新增/编辑在 Flutter 中为对话框（_ServerBackupDialog），
 * 鸿蒙端按移动端「列表 → 编辑页」模式转为 NavDestination 编辑页，功能不变；
 * 备份记录与失败文件仍为居中弹窗（对齐 Flutter _BackupRecordsDialog）。
 */
export class FileBackupRoutes {
  /** 磁盘间备份主页（任务列表） */
  static readonly PAGE_MAIN: string = 'FileBackupPage';
  /** 备份任务 新增/编辑页（对齐 Flutter _ServerBackupDialog） */
  static readonly PAGE_EDIT: string = 'FileBackupEditPage';
}

/** 磁盘间备份主页路由参数（页面无数据参数，控制器随页面创建销毁） */
export class FileBackupPageParam {
  title: string = '';
}

/** 备份任务编辑页参数：initial 为空表示新增 */
export class FileBackupEditPageParam {
  initial: BackupTask | undefined = undefined;
}
