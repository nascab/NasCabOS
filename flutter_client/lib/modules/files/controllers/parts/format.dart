part of '../file_controller.dart';

extension FileControllerFormat on FileController {
  String iconFor(String name, String filePath, String type) {
    if (type == 'image' || type == 'video' || type == 'raw') {
      //需要返回缩略图
      return ApiController.instance.getTinyUrl(filePath);
    }
    if (type == 'dir') return 'assets/icons/file/folder.png';
    final parts = name.split('.');
    final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
    switch (ext) {
      case 'epub':
      case 'mobi':
      case 'azw3':
        return 'assets/icons/file/ebook.png';
      case 'zip':
        return 'assets/icons/file/zip.png';
      case 'rar':
        return 'assets/icons/file/rar.png';
      case 'tar':
        return 'assets/icons/file/tar.png';
      case 'doc':
        return 'assets/icons/file/doc.png';
      case 'docx':
        return 'assets/icons/file/docx.png';
      case 'ppt':
        return 'assets/icons/file/ppt.png';
      case 'md':
        return 'assets/icons/file/md.png';
      case 'pdf':
        return 'assets/icons/file/pdf.png';
      case 'pptx':
        return 'assets/icons/file/pptx.png';
      case 'xls':
        return 'assets/icons/file/xls.png';
      case 'xlsx':
        return 'assets/icons/file/xlsx.png';
      case 'xml':
        return 'assets/icons/file/xml.png';
      case 'txt':
        return 'assets/icons/file/txt.png';
      case 'log':
        return 'assets/icons/file/log.png';
      case 'mp3':
      case 'flac':
      case 'aac':
      case 'wav':
      case 'ogg':
      case 'opus':
      case 'wma':
      case 'ape':
      case 'm4a':
        return 'assets/icons/file/audio.png';
      default:
        return 'assets/icons/file/file.png';
    }
  }

  String formatMtime(num? ms) {
    if (ms == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms.toInt()).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  bool _isVideo(Map<String, dynamic> item) {
    if (item['type'] == 'video') return true;
    final ext = item['ext']?.toString().toLowerCase() ?? '';
    return ['mp4', 'avi', 'mov', 'mkv', 'flv', 'wmv'].contains(ext);
  }
}
