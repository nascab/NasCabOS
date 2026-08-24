import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../core/api/base_api_service.dart';

class BookListApiService extends BaseApiService {
  static BookListApiService get instance =>
      Get.isRegistered<BookListApiService>()
      ? Get.find<BookListApiService>()
      : BookListApiService();

  String buildTinyUrl({required String fileHash, int size = 500}) {
    final fh = fileHash.trim();
    final safeSize = size.clamp(50, 2000);
    final token = ApiController.instance.accessToken;
    final uri = Uri.parse('${ApiController.instance.baseUrl}/api/book/tiny')
        .replace(
          queryParameters: <String, String>{
            'file_hash': fh,
            'size': safeSize.toString(),
            if (token != null && token.trim().isNotEmpty)
              'accessToken': token.trim(),
          },
        );
    return uri.toString();
  }

  Future<ApiResponse<BookIndexCountResult>> getIndexCounts({
    List<String>? sourceList,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/book/list/count',
      body: {if (sourceList != null) 'sourceList': sourceList},
      showLoading: false,
    );

    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }

    final data = res.data ?? <String, dynamic>{};
    final parsed = BookIndexCountResult.fromJson(data);
    return ApiResponse.success(
      parsed,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<BookListPagedResult>> listPaged({
    required int page,
    required int pageSize,
    required String type,
    int? listId,
    int? seriesIndexId,
    int? collectionId,
    bool isFavorite = false,
    String? search,
    List<String>? sourceList,
    String? sortBy,
    String? sortOrder,
    bool showLoading = false,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/book/list',
      body: {
        'page': page,
        'page_size': pageSize,
        'type': type.trim(),
        if (listId != null && listId > 0) 'list_id': listId,
        if (seriesIndexId != null && seriesIndexId > 0)
          'series_index_id': seriesIndexId,
        if (collectionId != null && collectionId > 0)
          'collection_id': collectionId,
        if (isFavorite) 'is_favorite': 1,
        if (search != null) 'search': search,
        if (sourceList != null) 'sourceList': sourceList,
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
      },
      showLoading: showLoading,
    );

    if (!res.success) {
      return ApiResponse.failure(res.message ?? 'request_failed');
    }
    final data = res.data ?? <String, dynamic>{};
    return ApiResponse.success(BookListPagedResult.fromJson(data));
  }

  Future<BookListPagedResult> listHistory({bool showLoading = false}) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/book/history/list',
      body: {},
      showLoading: showLoading,
    );
    if (!res.success) return const BookListPagedResult.empty();
    final data = res.data ?? <String, dynamic>{};
    return BookListPagedResult.fromJson(data);
  }

  Future<int> clearHistory({bool showLoading = false}) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/book/history/clear',
      body: {},
      showLoading: showLoading,
    );
    if (!res.success) return 0;
    final data = res.data ?? <String, dynamic>{};
    return (data['deleted'] as num?)?.toInt() ?? 0;
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteEntries(
    List<String> paths, {
    bool recycle = false,
    bool showLoading = true,
  }) {
    final targets =
        paths.map((e) => e.trim()).where((e) => e.isNotEmpty).toList()..sort();
    if (targets.isEmpty) {
      return Future.value(ApiResponse.failure('network_failure'));
    }
    return apiPost<Map<String, dynamic>>(
      '/api/book/delete',
      body: {'paths': targets, 'recycle': recycle},
      showLoading: showLoading,
    );
  }
}

class BookIndexCountResult {
  final int book;
  final int comic;

  const BookIndexCountResult({required this.book, required this.comic});

  int get total => book + comic;

  factory BookIndexCountResult.fromJson(Map<String, dynamic> json) {
    final rawBook = json['book'];
    final rawComic = json['comic'];
    final book = rawBook is num
        ? rawBook.toInt()
        : int.tryParse(rawBook?.toString() ?? '') ?? 0;
    final comic = rawComic is num
        ? rawComic.toInt()
        : int.tryParse(rawComic?.toString() ?? '') ?? 0;
    return BookIndexCountResult(book: book, comic: comic);
  }
}

class BookListItem {
  final int id;
  final String type;
  final String path;
  final String filename;
  final String fileHash;
  final String title;
  final String artist;
  final String year;
  final String ext;
  final int size;
  final int coverState;
  final int viewTime;
  final String createTime;
  final String fullPath;
  final String showType;
  final String firstFilePath;
  final int totalPage;
  final int bookCount;
  final bool isFavorite;
  final int currentPage;
  final double fraction;
  final String lastReadAt;

  const BookListItem({
    required this.id,
    required this.type,
    required this.path,
    required this.filename,
    required this.fileHash,
    required this.title,
    required this.artist,
    required this.year,
    required this.ext,
    required this.size,
    required this.coverState,
    required this.viewTime,
    required this.createTime,
    required this.fullPath,
    required this.showType,
    required this.firstFilePath,
    required this.totalPage,
    required this.bookCount,
    required this.isFavorite,
    required this.currentPage,
    required this.fraction,
    required this.lastReadAt,
  });

  String get displayTitle => title.trim().isNotEmpty ? title.trim() : filename;

  BookListItem copyWith({bool? isFavorite}) => BookListItem(
    id: id,
    type: type,
    path: path,
    filename: filename,
    fileHash: fileHash,
    title: title,
    artist: artist,
    year: year,
    ext: ext,
    size: size,
    coverState: coverState,
    viewTime: viewTime,
    createTime: createTime,
    fullPath: fullPath,
    showType: showType,
    firstFilePath: firstFilePath,
    totalPage: totalPage,
    bookCount: bookCount,
    isFavorite: isFavorite ?? this.isFavorite,
    currentPage: currentPage,
    fraction: fraction,
    lastReadAt: lastReadAt,
  );

  String get extLabel {
    final e = ext.trim();
    if (e.isEmpty) return '';
    final noDot = e.startsWith('.') ? e.substring(1) : e;
    return noDot.toUpperCase();
  }

  factory BookListItem.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
    double parseDouble(dynamic v) {
      if (v is num) return v.toDouble();
      final s = (v?.toString() ?? '').trim();
      return double.tryParse(s) ?? 0;
    }

    String parseString(dynamic v) => (v?.toString() ?? '').trim();
    bool parseBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v.toInt() == 1;
      final s = (v?.toString() ?? '').trim().toLowerCase();
      if (s == '1' || s == 'true') return true;
      return false;
    }

    return BookListItem(
      id: parseInt(json['id']),
      type: parseString(json['type']),
      path: parseString(json['path']),
      filename: parseString(json['filename']),
      fileHash: parseString(json['file_hash'] ?? json['fileHash']),
      title: parseString(json['title']),
      artist: parseString(json['artist']),
      year: parseString(json['year']),
      ext: parseString(json['ext']),
      size: parseInt(json['size']),
      coverState: parseInt(json['cover_state'] ?? json['coverState']),
      viewTime: parseInt(json['view_time'] ?? json['viewTime']),
      createTime: parseString(json['create_time'] ?? json['createTime']),
      fullPath: parseString(json['full_path'] ?? json['fullPath']),
      showType: parseString(json['show_type'] ?? json['showType']),
      firstFilePath: parseString(
        json['first_file_path'] ?? json['firstFilePath'],
      ),
      totalPage: parseInt(json['total_page'] ?? json['totalPage']),
      bookCount: parseInt(json['book_count'] ?? json['bookCount']),
      isFavorite: parseBool(json['is_favorite'] ?? json['isFavorite']),
      currentPage: parseInt(json['current_page'] ?? json['currentPage']),
      fraction: parseDouble(json['fraction']),
      lastReadAt: parseString(json['last_read_at'] ?? json['lastReadAt']),
    );
  }
}

class BookListPagination {
  final int total;
  final int page;
  final int limit;
  final int totalPages;
  final bool hasNextPage;
  final bool hasPrevPage;

  const BookListPagination({
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
    required this.hasNextPage,
    required this.hasPrevPage,
  });

  const BookListPagination.empty()
    : total = 0,
      page = 1,
      limit = 30,
      totalPages = 0,
      hasNextPage = false,
      hasPrevPage = false;

  factory BookListPagination.fromJson(Map<String, dynamic> json) {
    return BookListPagination(
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 30,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      hasNextPage: (json['hasNextPage'] as bool?) ?? false,
      hasPrevPage: (json['hasPrevPage'] as bool?) ?? false,
    );
  }
}

class BookListPathItem {
  final String path;
  final bool valid;

  const BookListPathItem({required this.path, required this.valid});

  factory BookListPathItem.fromJson(Map<String, dynamic> json) {
    return BookListPathItem(
      path: (json['path']?.toString() ?? '').trim(),
      valid: (json['valid'] as bool?) ?? false,
    );
  }
}

class BookListPagedResult {
  final List<BookListItem> items;
  final BookListPagination pagination;
  final List<BookListPathItem> validPaths;

  const BookListPagedResult({
    required this.items,
    required this.pagination,
    required this.validPaths,
  });

  const BookListPagedResult.empty()
    : items = const <BookListItem>[],
      pagination = const BookListPagination.empty(),
      validPaths = const <BookListPathItem>[];

  factory BookListPagedResult.fromJson(Map<String, dynamic> json) {
    List<BookListItem> parseItems(dynamic v) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .whereType<Map>()
          .map((e) => BookListItem.fromJson(e.cast<String, dynamic>()))
          .toList();
    }

    List<BookListPathItem> parsePathItems(dynamic v) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .whereType<Map>()
          .map((e) => BookListPathItem.fromJson(e.cast<String, dynamic>()))
          .toList();
    }

    final paginationRaw = json['pagination'] is Map
        ? (json['pagination'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    return BookListPagedResult(
      items: parseItems(json['items']),
      pagination: BookListPagination.fromJson(paginationRaw),
      validPaths: parsePathItems(json['validPaths']),
    );
  }
}
