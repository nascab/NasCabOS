import '../../core/api/api_controller.dart';
import '../../utils/server_version_util.dart';

enum FolderViewModuleType { photo, video, book, music }

extension FolderViewModuleTypeX on FolderViewModuleType {
  bool isServerVersionAtLeast(int majorVersion) {
    return ServerVersionUtil.isAtLeast(
      ApiController.instance.serverVersion,
      majorVersion,
    );
  }

  bool get isServerVersionSupported {
    return isServerVersionAtLeast(3);
  }

  String get sourceType {
    switch (this) {
      case FolderViewModuleType.photo:
        return 'photo';
      case FolderViewModuleType.video:
        return 'video';
      case FolderViewModuleType.book:
        return 'book';
      case FolderViewModuleType.music:
        return 'music';
    }
  }

  String get listApiPath {
    switch (this) {
      case FolderViewModuleType.photo:
        return '/api/photo/file_view/list';
      case FolderViewModuleType.video:
        return '/api/video/file_view/list';
      case FolderViewModuleType.book:
        return '/api/book/file_view/list';
      case FolderViewModuleType.music:
        return '/api/music/file_view/list';
    }
  }

  String get searchApiPath {
    switch (this) {
      case FolderViewModuleType.photo:
        return '/api/photo/file_view/search';
      case FolderViewModuleType.video:
        return '/api/video/file_view/search';
      case FolderViewModuleType.book:
        return '/api/book/file_view/search';
      case FolderViewModuleType.music:
        return '/api/music/file_view/search';
    }
  }

  String get titleKey => 'photo_menu_all_file_view';
}
