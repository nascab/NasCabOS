import { PhotoBackupTask } from '../models/PhotoBackupModels';
import { PhotoAlbumInfo } from '../models/PhotoBackupModels';

/**
 * 相册备份模块路由（对齐 Flutter AppPhotoBackupView 移动端形态）：
 * 主页 = 备份任务列表；新增/编辑在 Flutter 中为全屏页（_PhotoBackupTaskFormView）；
 * 相册选择在 Flutter 中为全屏页（_PhotoBackupAlbumPickerPage），鸿蒙端同样以路由页承载。
 */
export class PhotoBackupRoutes {
  /** 相册备份主页（任务列表） */
  static readonly PAGE_MAIN: string = 'PhotoBackupPage';
  /** 备份任务 新增/编辑页（对齐 Flutter _PhotoBackupTaskFormView） */
  static readonly PAGE_EDIT: string = 'PhotoBackupTaskFormPage';
  /** 相册选择页（对齐 Flutter showPhotoBackupAlbumPicker） */
  static readonly PAGE_ALBUM_PICKER: string = 'PhotoBackupAlbumPickerPage';
}

/** 相册备份主页路由参数（页面无数据参数，控制器为模块级单例） */
export class PhotoBackupPageParam {
  title: string = '';
}

/** 备份任务编辑页参数：initial 为空表示新增 */
export class PhotoBackupTaskFormPageParam {
  initial: PhotoBackupTask | undefined = undefined;
}

/** 相册选择页参数：选中相册通过 onPicked 回传（对齐 Flutter Navigator.pop(path)） */
export class PhotoBackupAlbumPickerPageParam {
  onPicked: (album: PhotoAlbumInfo) => void = (_album: PhotoAlbumInfo): void => {
  };
}
