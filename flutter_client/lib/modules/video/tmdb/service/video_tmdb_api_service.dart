import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';

class VideoTmdbSearchItem {
  final int id;
  final String mediaType;
  final String title;
  final String originalTitle;
  final String overview;
  final int year;
  final String posterUrl;
  final String backdropUrl;
  final double voteAverage;
  final List<String> actors;
  final List<String> genres;

  const VideoTmdbSearchItem({
    required this.id,
    required this.mediaType,
    required this.title,
    required this.originalTitle,
    required this.overview,
    required this.year,
    required this.posterUrl,
    required this.backdropUrl,
    required this.voteAverage,
    required this.actors,
    required this.genres,
  });

  factory VideoTmdbSearchItem.fromJson(Map<String, dynamic> json) {
    final actors = json['actors'];
    final genres = json['genres'];
    return VideoTmdbSearchItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      mediaType: (json['media_type']?.toString() ?? '').trim(),
      title: (json['title']?.toString() ?? '').trim(),
      originalTitle: (json['original_title']?.toString() ?? '').trim(),
      overview: (json['overview']?.toString() ?? '').trim(),
      year: (json['year'] as num?)?.toInt() ?? 0,
      posterUrl: (json['poster_url']?.toString() ?? '').trim(),
      backdropUrl: (json['backdrop_url']?.toString() ?? '').trim(),
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0,
      actors: actors is List
          ? actors
                .map((e) => e?.toString() ?? '')
                .where((e) => e.trim().isNotEmpty)
                .map((e) => e.trim())
                .toList(growable: false)
          : const [],
      genres: genres is List
          ? genres
                .map((e) => e?.toString() ?? '')
                .where((e) => e.trim().isNotEmpty)
                .map((e) => e.trim())
                .toList(growable: false)
          : const [],
    );
  }
}

class VideoTmdbSearchResult {
  final int page;
  final int totalPages;
  final List<VideoTmdbSearchItem> results;

  const VideoTmdbSearchResult({
    required this.page,
    required this.totalPages,
    required this.results,
  });

  factory VideoTmdbSearchResult.fromJson(Map<String, dynamic> json) {
    final rawList = json['results'];
    final list = rawList is List
        ? rawList
              .whereType<Map>()
              .map(
                (e) => VideoTmdbSearchItem.fromJson(e.cast<String, dynamic>()),
              )
              .toList(growable: false)
        : const <VideoTmdbSearchItem>[];
    return VideoTmdbSearchResult(
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 0,
      results: list,
    );
  }
}

class VideoTmdbApiService extends BaseApiService {
  static VideoTmdbApiService get instance =>
      Get.isRegistered<VideoTmdbApiService>()
      ? Get.find<VideoTmdbApiService>()
      : VideoTmdbApiService();

  Future<VideoTmdbSearchResult> search({
    required String mediaType,
    required String searchMode,
    String query = '',
    String tmdbId = '',
    int page = 1,
    bool showLoading = false,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/video/tmdb/search',
      body: {
        'media_type': mediaType,
        'search_mode': searchMode,
        if (query.trim().isNotEmpty) 'query': query.trim(),
        if (tmdbId.trim().isNotEmpty) 'tmdb_id': tmdbId.trim(),
        'page': page,
      },
      showLoading: showLoading,
    );

    if (!res.success) {
      return const VideoTmdbSearchResult(page: 1, totalPages: 0, results: []);
    }
    final data = res.data ?? <String, dynamic>{};
    return VideoTmdbSearchResult.fromJson(data);
  }
}
