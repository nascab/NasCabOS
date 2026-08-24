import 'package:get/get.dart';
import '../../list/service/video_list_api_service.dart';

enum VideoFilterOverlayKind { genre, region, actor, director }

class VideoFilterOverlayArgs {
  final VideoFilterOverlayKind kind;
  final String value;
  final String mediaType;

  const VideoFilterOverlayArgs({
    required this.kind,
    required this.value,
    required this.mediaType,
  });

  String get title {
    final v = value.trim();
    if (v.isEmpty) return '';
    if (kind == VideoFilterOverlayKind.genre) return '风格：$v';
    if (kind == VideoFilterOverlayKind.region) return '地区：$v';
    if (kind == VideoFilterOverlayKind.actor) return '演员：$v';
    return '导演：$v';
  }
}

class VideoMainController extends GetxController {
  final RxString currentPageKey = 'library.home'.obs;
  final RxDouble leftWidth = 160.0.obs;
  final RxBool sidebarCollapsed = false.obs;

  final RxBool isLibraryExpanded = true.obs;
  final RxBool isAlbumExpanded = true.obs;
  final RxBool isSettingsExpanded = true.obs;

  final RxInt movieCount = 0.obs;
  final RxInt tvCount = 0.obs;

  final RxnInt activeDetailIndexId = RxnInt();
  final RxnInt activeSubDetailIndexId = RxnInt();
  final Rxn<VideoFilterOverlayArgs> activeFilterOverlay = Rxn();

  final VideoListApiService _api = VideoListApiService.instance;

  @override
  void onInit() {
    super.onInit();
    fetchIndexCounts();
  }

  Future<void> fetchIndexCounts() async {
    final res = await _api.getIndexCounts();
    final data = res.data;
    if (res.success && data != null) {
      movieCount.value = data.movie;
      tvCount.value = data.tv;
    }
  }

  void selectPage(String key) {
    currentPageKey.value = key;
  }

  void openDetail(int indexId) {
    if (indexId <= 0) return;
    activeDetailIndexId.value = indexId;
  }

  void closeDetail() {
    activeDetailIndexId.value = null;
    activeSubDetailIndexId.value = null;
  }

  void openSubDetail(int indexId) {
    print("打开季详情:$indexId");
    if (indexId <= 0) return;
    activeSubDetailIndexId.value = indexId;
  }

  void closeSubDetail() {
    activeSubDetailIndexId.value = null;
  }

  void openFilterOverlay({
    required VideoFilterOverlayKind kind,
    required String value,
    String? mediaType,
  }) {
    final v = value.trim();
    if (v.isEmpty) return;
    closeDetail();
    activeFilterOverlay.value = VideoFilterOverlayArgs(
      kind: kind,
      value: v,
      mediaType: (mediaType ?? '').trim(),
    );
  }

  void closeFilterOverlay() {
    activeFilterOverlay.value = null;
  }
}
