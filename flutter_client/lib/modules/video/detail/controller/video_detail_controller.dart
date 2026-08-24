import 'dart:convert';
import 'package:get/get.dart';
import '../service/video_detail_api_service.dart';

enum EpisodeViewMode { intro, file }

class VideoDetailController extends GetxController {
  final int _initIndexId;

  final RxBool loading = false.obs;
  final Rxn<Map<String, dynamic>> raw = Rxn<Map<String, dynamic>>();

  final RxBool episodeAsc = true.obs;
  final Rx<EpisodeViewMode> episodeViewMode = EpisodeViewMode.intro.obs;
  final RxBool episodeLoading = false.obs;
  final RxList<Map<String, dynamic>> episodes = <Map<String, dynamic>>[].obs;
  final RxInt episodeTotal = 0.obs;
  final RxInt episodePage = 1.obs;
  final int episodePageSize = 20;
  final RxBool discContentLoading = false.obs;
  final RxList<Map<String, dynamic>> discContents = <Map<String, dynamic>>[].obs;

  late final int indexId;

  VideoDetailController({int? indexId}) : _initIndexId = indexId ?? 0;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    final idx = _initIndexId > 0
        ? _initIndexId
        : ((args is Map ? args['index_id'] : null) as num?)?.toInt() ?? 0;
    indexId = idx;
    refreshDetail(showLoading: false);
  }

  Future<void> refreshDetail({bool showLoading = false}) async {
    if (loading.value) return;
    if (indexId <= 0) return;
    loading.value = true;
    try {
      final res = await VideoDetailApiService.instance.getDetail(
        indexId,
        showLoading: showLoading,
      );
      if (!res.success || res.data == null) {
        raw.value = null;
        episodes.clear();
        discContents.clear();
        episodeTotal.value = 0;
        episodePage.value = 1;
        update();
        return;
      }
      raw.value = Map<String, dynamic>.from(res.data!);
      await _refreshEpisodesAfterDetail();
      await _refreshDiscContentsAfterDetail();
      update();
    } finally {
      loading.value = false;
    }
  }

  Future<void> _refreshDiscContentsAfterDetail() async {
    if (!showDiscContentSection) {
      discContents.clear();
      return;
    }
    await fetchDiscContents(showLoading: false);
  }

  Future<void> _refreshEpisodesAfterDetail() async {
    if (!_needAutoLoadEpisodes()) {
      episodes.clear();
      episodeTotal.value = 0;
      episodePage.value = 1;
      return;
    }
    await fetchEpisodes(page: 1, showLoading: false);
  }

  bool _needAutoLoadEpisodes() {
    final t = mediaType;
    if (t == 'season') return true;
    if (t == 'tv') {
      final seasonCount = (item?['season_count'] as num?)?.toInt() ?? 0;
      return seasonCount <= 1;
    }
    return false;
  }

  bool _needAutoLoadDiscContents() {
    final t = mediaType;
    return t == 'bdmv' || t == 'video_ts';
  }

  int get episodeTotalPages =>
      episodePageSize <= 0 ? 0 : (episodeTotal.value / episodePageSize).ceil();

  Future<void> fetchEpisodes({int page = 1, bool showLoading = false}) async {
    if (episodeLoading.value) return;
    if (indexId <= 0) return;
    if (!_needAutoLoadEpisodes()) return;

    episodeLoading.value = true;
    try {
      final res = await VideoDetailApiService.instance.getEpisodes(
        indexId,
        page: page,
        pageSize: episodePageSize,
        sortOrder: episodeAsc.value ? 'asc' : 'desc',
        showLoading: showLoading,
      );
      if (!res.success || res.data == null) {
        episodes.clear();
        episodeTotal.value = 0;
        episodePage.value = 1;
        update();
        return;
      }

      final data = res.data!;
      final rawItems = data['items'];
      final list = rawItems is List ? rawItems : const [];
      final mapped = list
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();

      final p = data['pagination'];
      final pm = p is Map ? p.cast<String, dynamic>() : const {};
      final total = (pm['total'] as num?)?.toInt() ?? 0;
      final serverPage = (pm['page'] as num?)?.toInt() ?? page;

      episodes.assignAll(mapped);
      episodeTotal.value = total;
      episodePage.value = serverPage;
      update();
    } finally {
      episodeLoading.value = false;
    }
  }

  Future<void> toggleEpisodeSort() async {
    final totalPages = episodeTotalPages;
    final current = episodePage.value;
    episodeAsc.value = !episodeAsc.value;
    final mirrored = totalPages > 0
        ? (totalPages - current + 1).clamp(1, totalPages)
        : 1;
    await fetchEpisodes(page: mirrored, showLoading: false);
  }

  Future<void> jumpToEpisodePage(int page) async {
    final p = page.clamp(1, episodeTotalPages);
    await fetchEpisodes(page: p, showLoading: false);
  }

  Future<void> fetchDiscContents({bool showLoading = false}) async {
    if (discContentLoading.value) return;
    if (indexId <= 0) return;
    if (!_needAutoLoadDiscContents()) return;

    discContentLoading.value = true;
    try {
      final res = await VideoDetailApiService.instance.getDiscContents(
        indexId,
        showLoading: showLoading,
      );
      if (!res.success || res.data == null) {
        discContents.clear();
        update();
        return;
      }
      final rawItems = res.data!['items'];
      final list = rawItems is List ? rawItems : const [];
      final mapped = list
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      discContents.assignAll(mapped);
      update();
    } finally {
      discContentLoading.value = false;
    }
  }

  Map<String, dynamic>? get item {
    final m = raw.value;
    final it = m?['item'];
    return it is Map ? it.cast<String, dynamic>() : null;
  }

  String get mediaType => (item?['media_type']?.toString() ?? '').trim();

  int get openSkipStartSeconds =>
      (item?['open_skip_start_sec'] as num?)?.toInt() ?? 0;

  int get openSkipEndSeconds =>
      (item?['open_skip_end_sec'] as num?)?.toInt() ?? 0;

  bool get canEditOpenSkip => mediaType == 'tv' || mediaType == 'season';

  bool get showEpisodeSection => _needAutoLoadEpisodes();
  bool get showDiscContentSection => _needAutoLoadDiscContents();

  List<Map<String, dynamic>> get seasonList {
    final v = raw.value?['season_list'];
    final list = v is List ? v : const [];
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  List<Map<String, dynamic>> get episodeList =>
      episodes.toList(growable: false);

  List<Map<String, dynamic>> get discContentList =>
      discContents.toList(growable: false);

  List<Map<String, dynamic>> buildDiscPlaybackPlaylist() {
    return discContentList
        .map((item) {
          final rawPlaylist = item['playlist'];
          final first = rawPlaylist is List && rawPlaylist.isNotEmpty && rawPlaylist.first is Map
              ? (rawPlaylist.first as Map).cast<String, dynamic>()
              : const <String, dynamic>{};
          final path = (item['path']?.toString() ?? first['path']?.toString() ?? '').trim();
          final internalPath =
              (item['internal_path']?.toString() ?? first['internal_path']?.toString() ?? '').trim();
          return <String, dynamic>{
            'path': path,
            'internalPath': internalPath,
            'name': (item['title']?.toString() ?? '').trim().isNotEmpty
                ? item['title']?.toString() ?? ''
                : item['display_name']?.toString() ?? '',
          };
        })
        .where((item) => (item['path']?.toString() ?? '').trim().isNotEmpty)
        .toList(growable: false);
  }

  int findDiscPlaybackIndex(Map<String, dynamic>? currentItem) {
    if (currentItem == null) return 0;
    final currentPath = currentItem['path']?.toString() ?? '';
    final currentInternalPath =
        currentItem['internal_path']?.toString().trim() ?? '';
    final list = discContentList;
    final index = list.indexWhere((item) {
      final rawPlaylist = item['playlist'];
      final first = rawPlaylist is List && rawPlaylist.isNotEmpty && rawPlaylist.first is Map
          ? (rawPlaylist.first as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      final path = item['path']?.toString() ?? first['path']?.toString() ?? '';
      final internalPath =
          item['internal_path']?.toString().trim() ?? first['internal_path']?.toString().trim() ?? '';
      return path == currentPath && internalPath == currentInternalPath;
    });
    return index < 0 ? 0 : index;
  }

  List<Map<String, dynamic>> _parsePeopleJson(dynamic v) {
    if (v == null) return const [];
    try {
      final txt = v.toString();
      final decoded = jsonDecode(txt);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  List<Map<String, dynamic>> get directors =>
      _parsePeopleJson(item?['nfo_director_json']);
  List<Map<String, dynamic>> get actors =>
      _parsePeopleJson(item?['nfo_actor_json']);

  Map<String, dynamic>? get history {
    final h = raw.value?['history'];
    return h is Map ? h.cast<String, dynamic>() : null;
  }

  int get historySeconds =>
      (history?['playback_position'] as num?)?.toInt() ?? 0;

  int get historyDurationSeconds =>
      (history?['duration'] as num?)?.toInt() ??
      (item?['duration'] as num?)?.toInt() ??
      0;

  int get historyEpisodeNum => (history?['episod_num'] as num?)?.toInt() ?? 0;

  bool get hasHistory => historySeconds > 0;
}
