import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import 'package:NasCabOS/core/api/api_controller.dart';
import 'package:NasCabOS/modules/book/list/service/book_local_cache_service_stub.dart'
    if (dart.library.io) 'package:NasCabOS/modules/book/list/service/book_local_cache_service_io.dart';
import 'package:NasCabOS/modules/files/views/file_pdf_rx_viewer_page.dart';
import 'package:NasCabOS/utils/toast_util.dart';
import 'package:NasCabOS/utils/web_p2p_pdf_load_dialog.dart';

/// 文件浏览、图书等模块共用的 PDF 打开（pdfrx）。
///
/// **非 Web**：与 TXT 等一致，先 [BookLocalCacheService.ensureCached] 下载到本地缓存，再 [PdfViewer.file] 打开。
///
/// **Web + P2P**：同源 `__p2p__` 代理流式下载到内存，带进度对话框（可取消），再以 [FilePdfRxViewerPage] 打开。
///
/// **Web 直连**：[PdfViewer.uri] 打开直链。
class PdfViewerUtil {
  PdfViewerUtil._();

  /// 与 [BookTxtReaderPage] 一致：浏览器无法直接请求 `p2p.local`，需走当前站点的 `__p2p__` 代理。
  static String _webP2pBasePath() {
    final p = Uri.base.path;
    return p.endsWith('/') ? p : '$p/';
  }

  /// 将 `http://p2p.local/...` 转为 `origin[/base]/__p2p__/...`，供 Web 主线程下载使用。
  static String _toWebP2pProxyUrl(String url) {
    final raw = url.trim();
    if (!kIsWeb || raw.isEmpty) return raw;
    final basePath = _webP2pBasePath();
    final prefix = '${Uri.base.origin}${basePath}__p2p__/';
    if (raw.startsWith(prefix)) return raw;
    final uri = Uri.tryParse(raw);
    if (uri == null) return raw;
    if (uri.origin.trim() != ApiController.p2pBaseUrl) return raw;
    final path = uri.path;
    final pathNorm = path.startsWith('/') ? path.substring(1) : path;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '${Uri.base.origin}${basePath}__p2p__/$pathNorm$query';
  }

  /// 缓存目录使用的 key：有图书 [fileHash] 用其值，否则用路径 MD5（仅缓存，不影响服务器进度）。
  static String cacheKeyForPdf(String filePath, String? fileHash) {
    final h = fileHash?.trim() ?? '';
    if (h.isNotEmpty) {
      return h;
    }
    return md5.convert(utf8.encode(filePath.trim())).toString();
  }

  /// 使用 pdfrx 打开 PDF（图书列表、文件浏览等）。
  ///
  /// [fileHash] 非空时：通过 `/api/book/history` 从服务器恢复进度并定时回写（须已在图书索引中）。
  ///
  /// [expectedSize] 用于缓存下载校验（字节），未知时可传 0。
  static Future<bool> openPdfInViewer({
    required String filePath,
    required String title,
    String? accessTokenOverride,
    String? p2pChannel,
    String? fileHash,
    int expectedSize = 0,
  }) async {
    final fileUrl = ApiController.instance.getRawFileUrl(
      filePath,
      withAccessToken: true,
      accessTokenOverride: accessTokenOverride,
      isRawFile: true,
      p2pChannel: p2pChannel ?? 'download',
    );
    final fh = fileHash?.trim();
    final fhArg = (fh != null && fh.isNotEmpty) ? fh : null;

    if (kIsWeb && ApiController.instance.isP2pMode) {
      final fetchUrl = _toWebP2pProxyUrl(fileUrl);
      final bytes = await showWebP2pPdfLoadDialog(
        fetchUrl,
        hintTotalBytes: expectedSize > 0 ? expectedSize : null,
      );
      if (bytes == null) {
        return false;
      }
      if (bytes.isEmpty) {
        ToastUtil.show('operation_failed'.tr);
        return false;
      }
      Get.to(
        () => FilePdfRxViewerPage(
          pdfBytes: bytes,
          title: title,
          progressStorageKey: filePath,
          fileHash: fhArg,
        ),
        preventDuplicates: false,
      );
      return true;
    }

    if (!kIsWeb) {
      final cacheHash = cacheKeyForPdf(filePath, fileHash);
      final nameForCache = p.basename(filePath.trim());
      final safeName = nameForCache.isNotEmpty ? nameForCache : 'document.pdf';
      final ok = await BookLocalCacheService.instance.ensureCached(
        fileHash: cacheHash,
        fileName: safeName,
        ext: 'pdf',
        remoteUrl: fileUrl,
        expectedSize: expectedSize,
      );
      if (!ok) {
        ToastUtil.show('operation_failed'.tr);
        return false;
      }
      final localPath = BookLocalCacheService.instance.cachedFilePathOf(
        cacheHash,
      );
      if (localPath == null || localPath.trim().isEmpty) {
        ToastUtil.show('operation_failed'.tr);
        return false;
      }
      Get.to(
        () => FilePdfRxViewerPage(
          localFilePath: localPath,
          title: title,
          progressStorageKey: filePath,
          fileHash: fhArg,
        ),
        preventDuplicates: false,
      );
      return true;
    }

    final u = Uri.tryParse(fileUrl.trim());
    if (u == null) {
      ToastUtil.show('operation_failed'.tr);
      return false;
    }
    Get.to(
      () => FilePdfRxViewerPage(
        pdfUri: u,
        title: title,
        progressStorageKey: filePath,
        fileHash: fhArg,
      ),
      preventDuplicates: false,
    );
    return true;
  }
}
