import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/rendering.dart';

import '../../../../../core/api/api_controller.dart';
import '../../../../../utils/http_util.dart';
import 'package:intl/intl.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../utils/cache_manager.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../../../../utils/device_utils.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../folder_view/folder_view_module_type.dart';
import '../../../gallery/controllers/custom_gallery_controller.dart';
import '../../../gallery/views/custom_gallery.dart';
import '../../../home/views/pc_home_controller.dart';
import '../../ai_faces/models/ai_faces_models.dart';
import '../../ai_faces/service/photo_ai_faces_api_service.dart';
import '../../photo_main/controller/photo_home_controller.dart';
import '../../album/models/photo_album_model.dart';
import '../../album/service/photo_album_api_service.dart';
import '../../album/view/photo_album_list_view.dart';
import '../../album/view/app_photo_album_list_page.dart';
import '../../app_setting/view/app_photo_settings_view.dart';
import '../../../transfer/controllers/download_controller.dart';
import '../models/photo_timeline_model.dart';
import '../service/photo_timeline_api_service.dart';
import '../../../video_player/views/app_video_player_page.dart';
import '../../../video_player/views/pc_video_player_view.dart';
part 'parts/photo_timeline_settings.dart';
part 'parts/photo_timeline_loading.dart';
part 'parts/photo_timeline_pagination.dart';
part 'parts/photo_timeline_scroll.dart';
part 'parts/photo_timeline_utils.dart';
part 'parts/photo_timeline_media.dart';
part 'parts/photo_timeline_selection.dart';

sealed class TimelineListItem {
  const TimelineListItem();
  String get id;
}

class TimelineListDateHeader extends TimelineListItem {
  final String date;

  const TimelineListDateHeader({required this.date});

  @override
  String get id => 'date_$date';
}

class TimelineListPhoto extends TimelineListItem {
  final TimelinePhotoItem photo;

  const TimelineListPhoto({required this.photo});

  @override
  String get id => 'photo_${photo.id}';
}

/// 照片时间轴页面的核心控制器。
///
/// 该控制器负责：
/// - 拉取日期列表与照片列表，并把扁平数据分组为 `photoGroups` 供 UI 渲染
/// - 监听滚动，在接近顶部/底部时触发分页加载
/// - 侧边栏点击日期后的跳转定位
/// - 多选/批量操作（下载、收藏、删除等）
///
/// 为了便于维护，本文件只保留“状态定义 + 生命周期”，具体逻辑按职责拆分到 `controller/parts` 目录中，
/// 通过 `part` + `extension` 组合实现同一库内的逻辑拆分。
class PhotoTimelineController extends GetxController {
  final PhotoTimelineSourceFilterStorage _sourceFilterStorage =
      PhotoTimelineSourceFilterStorage();
  final String initialListType;
  final int? initialAlbumId;
  final int? initialCollectionId;
  final int? initialSmartAlbumId;
  final int? initialFaceId;
  final String? initialPlaceName;
  final bool initialLoadTheDay;
  final String? initialGeohash;
  final int? initialYear;

  /// 未配置来源路径时是否弹出管理员提示（仅 PC 照片主页「时间轴」与 App 照片管理首页应开启）。
  final bool alertWhenNoSourcePath;

  PhotoTimelineController({
    this.initialListType = 'timeline',
    this.initialAlbumId,
    this.initialCollectionId,
    this.initialSmartAlbumId,
    this.initialFaceId,
    this.initialPlaceName,
    this.initialLoadTheDay = false,
    this.initialGeohash,
    this.initialYear,
    this.alertWhenNoSourcePath = false,
  });
  final int minItemSize = DeviceUtils.isMobile ? 60 : 120;
  final int maxItemSize = 400;

  /// 分页加载时，每次请求的照片数量下限。
  static final int minGetCount = 300;

  /// 时间轴接口服务（日期列表、照片列表）。
  final PhotoTimelineApiService _apiService = PhotoTimelineApiService();

  /// 日期列表（右侧时间轴与分组统计使用）。
  final RxList<TimelineDateItem> dateList = <TimelineDateItem>[].obs;

  /// UI 直接消费的扁平化渲染列表：包含日期 header、照片 item 与上下 loading。
  final RxList<TimelineListItem> photoItems = <TimelineListItem>[].obs;

  final RxMap<String, TimelineDateInfo> dateInfoMap =
      <String, TimelineDateInfo>{}.obs;

  /// 日期列表是否在加载中（首屏骨架/占位）。
  final RxBool isLoadingDates = false.obs;

  /// 向上分页加载标记（顶部 loading）。
  final RxBool isLoadingUp = false.obs;

  /// 向下分页加载标记（底部 loading）。
  final RxBool isLoadingDown = false.obs;

  /// 向上是否还有更多数据可加载。
  final RxBool hasMoreUp = true.obs;

  /// 向下是否还有更多数据可加载。
  final RxBool hasMoreDown = true.obs;

  /// 当前是否处于时间轴 hover 状态（用于 overlay 显示）。
  final RxBool isTimelineHovering = false.obs;

  /// 当前 hover 时展示的日期字符串。
  final RxString timelineHoverDate = ''.obs;

  /// 可用的路径列表 (从服务端获取)
  final RxList<TimelinePathItem> availablePaths = <TimelinePathItem>[].obs;

  /// 当前选中的路径过滤 (路径字符串)
  final RxList<String> selectedPaths = <String>[].obs;

  /// 搜索关键字
  final RxString searchKeyword = ''.obs;
  final TextEditingController searchController = TextEditingController();
  Timer? _searchDebounce;

  final RxString baseGeohash = ''.obs;
  final RxInt nearbyRangeKm = 2.obs;

  /// 列表类型：timeline (默认), favorite (收藏)
  final RxString listType = 'timeline'.obs;
  final RxnInt albumId = RxnInt();
  final RxnInt collectionId = RxnInt();
  final RxnInt smartAlbumId = RxnInt();
  final RxnInt faceId = RxnInt();
  final RxnString placeName = RxnString();
  final RxBool loadTheDay = false.obs;
  final RxnInt year = RxnInt();

  /// 排序方式：`desc` 为较新在前，`asc` 为较旧在前。
  final RxString sortOrder = 'desc'.obs;

  /// 文件类型过滤：`all` / 其他枚举值（由 UI 传入）。
  final RxString fileType = 'all'.obs;

  /// 网格单元最大宽度（影响列数与布局）。
  final RxDouble itemSize = 140.0.obs;

  /// 图片显示模式：true=cover (裁切), false=contain (缩放)
  final RxBool isCoverMode = true.obs;

  // --- Layout Constants (Must match View) ---
  static const double crossAxisSpacing = 8;
  static const double mainAxisSpacing = 8;
  static const double leftPadding = 16;
  static const double rightPadding = 40;
  static const double headerExtent = 50;
  static const double topLoadingExtent = 64.0;

  double layoutCrossAxisSpacing = PhotoTimelineController.crossAxisSpacing;
  double layoutMainAxisSpacing = PhotoTimelineController.mainAxisSpacing;
  double layoutLeftPadding = PhotoTimelineController.leftPadding;
  double layoutRightPadding = PhotoTimelineController.rightPadding;
  double layoutHeaderExtent = PhotoTimelineController.headerExtent;
  double layoutTopLoadingExtent = PhotoTimelineController.topLoadingExtent;

  double _viewportContentWidth = 0;
  int _crossAxisCount = 0;
  double _cellMainAxisExtent = 0;

  void updateLayoutInfo(
    double contentWidth,
    int crossAxisCount,
    double cellMainAxisExtent,
  ) {
    _viewportContentWidth = contentWidth;
    _crossAxisCount = crossAxisCount;
    _cellMainAxisExtent = cellMainAxisExtent;
  }

  /// 是否处于多选模式（影响底部栏显示与交互逻辑）。
  final RxBool isMultiSelectMode = false.obs;

  /// 已选中条目的 id 集合。
  final RxSet<int> selectedItems = <int>{}.obs;

  final selectionRect = Rxn<Rect>();
  final selectionRectContent = Rxn<Rect>();
  Offset? _dragStartViewport;
  double _dragStartScrollOffset = 0;
  Set<int>? _dragSelectionBaseline;

  /// 首次加载时的锚点 Item ID (用于加载上一页后回跳)
  String? savedAnchorItemId;

  /// 首次加载时的锚点 Item 相对偏移量
  double savedAnchorItemOffset = 0.0;

  /// 列表滚动控制器（统一管理滚动监听与跳转定位）。
  final ScrollController scrollController = ScrollController();

  /// 列表 key（预留：用于必要时触发 rebuild/定位）。
  final GlobalKey listViewKey = GlobalKey();

  /// 滚动触发分页的节流锁，防止边界抖动造成重复请求。
  bool _scrollLoadLock = false;

  /// 本地缓存 key：排序方式。
  static const String keySortOrder = 'timeline_sort_order';

  /// 本地缓存 key：文件类型过滤。
  static const String keyFileType = 'timeline_file_type';

  /// 本地缓存 key：缩略图尺寸。
  static const String keyItemSize = 'timeline_item_size';

  /// 本地缓存 key：图片显示模式。
  static const String keyIsCoverMode = 'timeline_is_cover_mode';

  /// 右侧时间轴是否显示（自动隐藏逻辑见 `photo_timeline_scroll.dart`）。
  final RxBool isTimelineVisible = false.obs;
  Timer? _timelineHideTimer;

  /// 最近一次拉取结果（目前主要用于调试/扩展，逻辑上不依赖它驱动 UI）。
  FetchResult _lastFetchResult = const FetchResult(
    hasData: false,
    incomingCount: 0,
    addedCount: 0,
  );

  /// 照片列表接口每页大小（与服务端约定）。
  static int defaultPageSize = 20;

  String? get geohashForRequest {
    final gh = baseGeohash.value.trim();
    if (gh.isEmpty) return null;
    final precision = switch (nearbyRangeKm.value) {
      2 => 6,
      5 => 5,
      10 => 4,
      50 => 3,
      80 => 2,
      _ => 6,
    };
    final len = precision.clamp(2, gh.length);
    return gh.substring(0, len);
  }

  void setNearbyRangeKm(int km) {
    nearbyRangeKm.value = km;
    refreshTimeline();
  }

  @override
  void onInit() {
    super.onInit();
    listType.value = initialListType;
    albumId.value = initialAlbumId;
    collectionId.value = initialCollectionId;
    smartAlbumId.value = initialSmartAlbumId;
    faceId.value = initialFaceId;
    if (initialPlaceName != null && initialPlaceName!.trim().isNotEmpty) {
      placeName.value = initialPlaceName!.trim();
    }
    loadTheDay.value = initialLoadTheDay;
    if (initialGeohash != null && initialGeohash!.trim().isNotEmpty) {
      baseGeohash.value = initialGeohash!.trim();
    }
    year.value = initialYear;
    if (Get.arguments != null && Get.arguments is Map) {
      if (Get.arguments['listType'] != null) {
        listType.value = Get.arguments['listType'];
      }
      if (Get.arguments['albumId'] != null) {
        final v = Get.arguments['albumId'];
        if (v is int) {
          albumId.value = v;
        } else if (v is num) {
          albumId.value = v.toInt();
        } else {
          albumId.value = int.tryParse(v.toString());
        }
      }
      if (Get.arguments['collectionId'] != null) {
        final v = Get.arguments['collectionId'];
        if (v is int) {
          collectionId.value = v;
        } else if (v is num) {
          collectionId.value = v.toInt();
        } else {
          collectionId.value = int.tryParse(v.toString());
        }
      }
      if (Get.arguments['smartAlbumId'] != null) {
        final v = Get.arguments['smartAlbumId'];
        if (v is int) {
          smartAlbumId.value = v;
        } else if (v is num) {
          smartAlbumId.value = v.toInt();
        } else {
          smartAlbumId.value = int.tryParse(v.toString());
        }
      }
      if (Get.arguments['faceId'] != null) {
        final v = Get.arguments['faceId'];
        if (v is int) {
          faceId.value = v;
        } else if (v is num) {
          faceId.value = v.toInt();
        } else {
          faceId.value = int.tryParse(v.toString());
        }
      }

      if (Get.arguments['placeName'] != null) {
        final v = Get.arguments['placeName'].toString().trim();
        if (v.isNotEmpty) {
          placeName.value = v;
        }
      }
      if (baseGeohash.value.isEmpty && Get.arguments['geohash'] != null) {
        final gh = Get.arguments['geohash'].toString().trim();
        if (gh.isNotEmpty) {
          baseGeohash.value = gh;
        }
      }
      if (Get.arguments['year'] != null) {
        final v = Get.arguments['year'];
        if (v is int) {
          year.value = v;
        } else if (v is num) {
          year.value = v.toInt();
        } else {
          year.value = int.tryParse(v.toString());
        }
      }
    }
    _loadSettings();
    _loadDateList();
    scrollController.addListener(_onScroll);
  }

  @override
  void onClose() {
    scrollController.dispose();
    searchController.dispose();
    _timelineHideTimer?.cancel();
    _searchDebounce?.cancel();
    super.onClose();
  }

  void onSearchChanged(String val) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      searchKeyword.value = val;
      refreshTimeline();
    });
  }

  void clearSearch() {
    searchKeyword.value = '';
    searchController.clear();
    refreshTimeline();
  }
}
