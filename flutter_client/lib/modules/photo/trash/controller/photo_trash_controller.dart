import 'dart:async';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import '../../../../../core/api/api_controller.dart';
import '../../timeline/models/photo_timeline_model.dart';
import '../../timeline/service/photo_timeline_api_service.dart';
import '../../../../utils/toast_util.dart';
import '../../../../utils/dialog_util.dart';

part './parts/photo_trash_base.dart';
part './parts/photo_trash_data.dart';
part './parts/photo_trash_selection.dart';
part './parts/photo_trash_restore.dart';
part './parts/photo_trash_delete.dart';
part './parts/photo_trash_view_settings.dart';

/// 照片回收站控制器
class PhotoTrashController extends GetxController {
  /// 照片时间轴API服务
  final PhotoTimelineApiService _apiService = PhotoTimelineApiService();

  /// 当前页码
  final RxInt currentPage = 1.obs;

  /// 每页数量
  final RxInt pageSize = 200.obs;

  /// 总记录数
  final RxInt total = 0.obs;

  /// 是否正在加载
  final RxBool isLoading = false.obs;

  /// 是否还有更多数据
  final RxBool hasMore = true.obs;

  /// 照片列表
  final RxList<TimelinePhotoItem> photoItems = <TimelinePhotoItem>[].obs;

  /// 搜索关键字
  final RxString searchKeyword = ''.obs;

  /// 搜索框控制器
  final TextEditingController searchController = TextEditingController();

  /// 搜索防抖定时器
  Timer? _searchDebounce;

  /// 文件类型过滤
  final RxString fileType = 'all'.obs;

  /// 排序字段
  final RxString sortField = 'in_trash_time'.obs;

  /// 排序顺序
  final RxString sortOrder = 'desc'.obs;

  /// 是否处于多选模式
  final RxBool isMultiSelectMode = false.obs;

  /// 已选中的照片ID集合
  final RxSet<int> selectedItems = <int>{}.obs;

  /// 列表滚动控制器
  final ScrollController scrollController = ScrollController();

  // --- Drag Selection State ---
  Offset? dragStartViewport;
  double dragStartScrollOffset = 0;
  Set<int>? dragSelectionBaseline;
  final Rx<Rect?> selectionRect = Rx<Rect?>(null);
  final Rx<Rect?> selectionRectContent = Rx<Rect?>(null);

  /// 网格单元最大宽度（影响列数与布局）
  final RxDouble itemSize = 140.0.obs;

  /// 图片显示模式：true=cover (裁切), false=contain (缩放)
  final RxBool isCoverMode = true.obs;

  /// 最小缩略图大小
  final int minItemSize = 120;

  /// 最大缩略图大小
  final int maxItemSize = 400;

  // --- Layout Constants (Must match View) ---
  static const double crossAxisSpacing = 8;
  static const double mainAxisSpacing = 8;
  static const double leftPadding = 16;
  static const double rightPadding = 16;

  @override
  void onInit() {
    super.onInit();
    _initBase();
  }

  @override
  void onClose() {
    _disposeBase();
    super.onClose();
  }
}
