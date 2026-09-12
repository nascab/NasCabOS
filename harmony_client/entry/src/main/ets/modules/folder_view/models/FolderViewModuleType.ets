import { L10n } from '../../../core/localization/L10n';
import { APIClient } from '../../../core/network/APIClient';
import { ServerVersionUtil } from '../../media_tool/models/MediaToolModels';

/**
 * 文件视图模块类型（对齐 Flutter folder_view_module_type.dart）：
 * 照片/影音/图书/音乐四个模块的"文件视图"页面共用一套文件夹浏览 UI，
 * 仅列表/搜索 API 路径与 sourceType 不同。
 */
export enum FolderViewModuleType {
  Photo = 'photo',
  Video = 'video',
  Book = 'book',
  Music = 'music'
}

export class FolderViewModuleTypes {
  /** 列表 API 路径（对齐 Flutter FolderViewModuleTypeX.listApiPath） */
  static listApiPath(t: FolderViewModuleType): string {
    switch (t) {
      case FolderViewModuleType.Photo:
        return '/api/photo/file_view/list';
      case FolderViewModuleType.Video:
        return '/api/video/file_view/list';
      case FolderViewModuleType.Book:
        return '/api/book/file_view/list';
      case FolderViewModuleType.Music:
        return '/api/music/file_view/list';
      default:
        return '/api/photo/file_view/list';
    }
  }

  /** 搜索 API 路径（对齐 Flutter FolderViewModuleTypeX.searchApiPath） */
  static searchApiPath(t: FolderViewModuleType): string {
    switch (t) {
      case FolderViewModuleType.Photo:
        return '/api/photo/file_view/search';
      case FolderViewModuleType.Video:
        return '/api/video/file_view/search';
      case FolderViewModuleType.Book:
        return '/api/book/file_view/search';
      case FolderViewModuleType.Music:
        return '/api/music/file_view/search';
      default:
        return '/api/photo/file_view/search';
    }
  }

  /** sourceType（对齐 Flutter FolderViewModuleTypeX.sourceType） */
  static sourceType(t: FolderViewModuleType): string {
    switch (t) {
      case FolderViewModuleType.Photo:
        return 'photo';
      case FolderViewModuleType.Video:
        return 'video';
      case FolderViewModuleType.Book:
        return 'book';
      case FolderViewModuleType.Music:
        return 'music';
      default:
        return 'photo';
    }
  }

  /** 页面标题 key（对齐 Flutter FolderViewModuleTypeX.titleKey，四个模块共用） */
  static title(t: FolderViewModuleType): string {
    return L10n.t('photo_menu_all_file_view', '文件视图');
  }

  /** 文件视图要求服务端主版本 >= 3（对齐 Flutter FolderViewModuleTypeX.isServerVersionSupported） */
  static isServerVersionSupported(): boolean {
    return ServerVersionUtil.isAtLeast(
      APIClient.getInstance().state.serverVersion, 3);
  }
}
