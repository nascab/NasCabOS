import { FolderViewModuleType } from '../models/FolderViewModuleType';

/** 文件视图页面路由参数（对齐 Flutter AppFolderViewPage 构造参数） */
export class FolderViewPageParam {
  /** FolderViewModuleType 枚举值（字符串形式，跨路由传递） */
  moduleType: string = FolderViewModuleType.Photo;
  initialPath: string = '';
  initFolderName: string = '';
  isRootPage: boolean = true;
}
