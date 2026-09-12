import { FileController } from '../../../files/controllers/FileController';
import { FolderViewModuleType, FolderViewModuleTypes } from '../models/FolderViewModuleType';

/**
 * 文件视图控制器（对齐 Flutter AppFolderViewController）：
 * 继承文件浏览器控制器，固定模块专属的列表/搜索 API 路径与 sourceType，
 * 禁用"添加自定义根路径"入口，不自动加载根目录（由页面显式加载指定路径）。
 */
@ObservedV2
export class FolderViewController extends FileController {
  readonly moduleType: FolderViewModuleType;

  constructor(moduleType: FolderViewModuleType) {
    super(false, FolderViewModuleTypes.listApiPath(moduleType),
      FolderViewModuleTypes.searchApiPath(moduleType), false);
    this.moduleType = moduleType;
    this.currentSourceType = FolderViewModuleTypes.sourceType(moduleType);
  }
}
