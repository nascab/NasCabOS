import 'package:get/get.dart';

class BookLocalServeSession {
  final String url;
  const BookLocalServeSession(this.url);
  Future<void> close() async {}
}

class BookCacheEntry {
  final String fileHash;
  final String filePath;
  final int size;

  const BookCacheEntry({
    required this.fileHash,
    required this.filePath,
    required this.size,
  });
}

class BookLocalCacheService extends GetxService {
  static BookLocalCacheService get instance =>
      Get.isRegistered<BookLocalCacheService>()
      ? Get.find<BookLocalCacheService>()
      : Get.put(BookLocalCacheService(), permanent: true);

  final RxMap<String, double> downloadProgress = <String, double>{}.obs;
  final RxSet<String> cachedFileHashes = <String>{}.obs;

  bool isCached(String fileHash) => cachedFileHashes.contains(fileHash.trim());

  double? progressOf(String fileHash) =>
      downloadProgress[fileHash.trim().isEmpty ? fileHash : fileHash.trim()];

  String? cachedFilePathOf(String fileHash) => null;

  Future<bool> ensureCached({
    required String fileHash,
    required String fileName,
    required String ext,
    required String remoteUrl,
    required int expectedSize,
  }) async {
    return false;
  }

  Future<BookLocalServeSession?> openLocalServeSession({
    required String fileHash,
  }) async {
    return null;
  }

  Future<bool> deleteCache({required String fileHash}) async {
    cachedFileHashes.remove(fileHash.trim());
    downloadProgress.remove(fileHash.trim());
    return false;
  }

  Future<List<BookCacheEntry>> listCacheEntries() async {
    return const <BookCacheEntry>[];
  }

  Future<int> clearAllCaches() async {
    cachedFileHashes.clear();
    downloadProgress.clear();
    return 0;
  }
}
