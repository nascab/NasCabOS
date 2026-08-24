import 'package:NasCabOS/core/api/api_controller.dart';
import 'package:get/get.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import '../service/file_api_service.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/toast_util.dart';
import '../../../utils/file_util.dart';
import '../../../utils/local_web_asset_server.dart';
import '../../../utils/device_utils.dart';
import 'package:NasCabOS/core/routes/app_routes.dart';
import '../../home/views/pc_home_controller.dart';
import '../../home/views/pc_components/pc_app_window.dart';
import '../../music/list/models/music_list_models.dart';
import '../../music/play_service/controller/music_play_service_controller.dart';
import '../../transfer/controllers/download_controller.dart';
import 'dart:async';
import 'file_clipboard_controller.dart';
import '../service/file_watcher_service.dart';
import '../views/folder_picker_dialog.dart';
import '../views/running_task_list_dialog.dart';
import '../../gallery/controllers/custom_gallery_controller.dart';
import '../../gallery/views/custom_gallery.dart';
import '../../book/reader/view/book_web_reader_page_stub.dart'
    if (dart.library.io) '../../book/reader/view/book_web_reader_page_io.dart'
    if (dart.library.html) '../../book/reader/view/book_web_reader_page_web.dart';
import '../../book/reader/view/book_txt_reader_page.dart';
import '../../book/list/service/book_local_cache_service_stub.dart'
    if (dart.library.io) '../../book/list/service/book_local_cache_service_io.dart';
import '../../user/service/user_api_service.dart';
import '../../../core/languages/language_service.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../editor/views/pc_text_editor_view.dart';
import '../../editor/views/text_editor_page.dart';
import '../../fileShareServer/views/file_share_server_view.dart';
import '../../../utils/pdf_viewer_util.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

part 'parts/lifecycle.dart';
part 'parts/directory.dart';
part 'parts/sort.dart';
part 'parts/selection.dart';
part 'parts/format.dart';
part 'parts/actions.dart';
part 'parts/open.dart';
part 'parts/favorites.dart';
part 'parts/clipboard.dart';

class FileController extends GetxController {
  FileController({
    this.autoLoadRoot = true,
    this.initialSourceType,
    this.listApiPath = '/api/file/list',
    this.searchApiPath = '/api/file/search',
    this.showRootCustomPathEntry = true,
  });

  final bool autoLoadRoot;
  final String? initialSourceType;
  final String listApiPath;
  final String searchApiPath;
  final bool showRootCustomPathEntry;

  final currentPath = RxnString();
  final currentSourceType = RxnString();
  final items = <Map<String, dynamic>>[].obs;
  final loading = false.obs;
  final segments = <Map<String, dynamic>>[].obs;
  final sep = RxString('/');
  final selected = <String>{}.obs;
  final sortMode = 'name_asc'.obs;
  final searchQuery = ''.obs; // 搜索关键字（用于本地过滤显示）
  final filterType =
      'all'.obs; // 文件类型筛选：all/dir/image/video/audio/document/archive/file
  final searchScope = 'current'.obs; // current/global
  final globalSearchItems = <Map<String, dynamic>>[].obs;
  final globalSearchLoading = false.obs;
  final viewMode = 'grid'.obs; // 视图模式：grid/large_grid/list
  final showHidden = false.obs; //是否显示隐藏文件
  final onlyShowDir = false.obs; //是否只拉取目录 选择模式下设置为true
  // 服务器根目录列表（始终显示在左侧树的“服务器”分组）
  final serverRoots = <Map<String, dynamic>>[].obs;
  static const String _sortKey = 'file_sort_mode';
  static const String _viewKey = 'file_view_mode';
  static const String _showHiddenKey = 'file_show_hidden';

  /// 当前所在模块：normal/favorites/recent
  final currentModule = 'normal'.obs;

  FileClipboardController get _clipboard => FileClipboardController.ensure();
  RxList<String> get clipboardItems => _clipboard.items;
  RxString get clipboardAction => _clipboard.action;

  final FileApiService _api = FileApiService();

  String? _lastTappedPath;
  DateTime? _lastTapAt;

  late final FileWatcherService _fileWatcher;
  Timer? _globalSearchDebounce;

  /// 并发 `listDirectory` 时只采纳最后一次请求的结果，避免先返回的旧响应覆盖 UI。
  int _listDirectorySeq = 0;

  @override
  void onInit() {
    super.onInit();
    _onControllerInit();
  }

  @override
  void onClose() {
    _onControllerClose();
    super.onClose();
  }
}
