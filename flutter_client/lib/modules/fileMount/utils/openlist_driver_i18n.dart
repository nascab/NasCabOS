import 'package:get/get.dart';

/// OpenList 网盘驱动显示名（中/英）
class OpenlistDriverI18n {
  OpenlistDriverI18n._();

  static String _slug(String raw) {
    return raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  }

  static bool get _isZh {
    final code = Get.locale?.languageCode ?? 'zh';
    return code.startsWith('zh');
  }

  static String driverName(String raw) {
    final key = _slug(raw.trim());
    if (key.isEmpty) return raw;
    final map = _isZh ? _zhDrivers : _enDrivers;
    return map[key] ?? raw;
  }

  static String fieldLabel(Map<String, dynamic> field) {
    final name = (field['name'] ?? '').toString();
    if (name.isEmpty) return '';
    final key = 'openlist_field_$name';
    final translated = key.tr;
    if (translated != key) return translated;
    final help = (field['help'] ?? '').toString().trim();
    if (help.isNotEmpty && help.length <= 120) return help;
    return name;
  }

  /// 支持跳转 api.oplist.org 授权页的驱动（与后端固定列表一致）
  static const _onlineAuthDrivers = {
    'baidunetdisk',
    'aliyundriveopen',
    'onedrive',
    '115_open',
  };

  static bool usesOnlineAuth(String driver) {
    return _onlineAuthDrivers.contains(_slug(driver));
  }

  /// OpenList 官方驱动文档（与后端 openlistDriverCatalog 一致）
  static const _driverDocUrls = <String, String>{
    'baidunetdisk': 'https://doc.oplist.org/guide/drivers/baidu',
    '123pan': 'https://doc.oplist.org/guide/drivers/123',
    '115_open': 'https://doc.oplist.org/guide/drivers/115_open',
    'onedrive': 'https://doc.oplist.org/guide/drivers/onedrive',
    'aliyundriveopen': 'https://doc.oplist.org/guide/drivers/aliyundrive_open',
    's3': 'https://doc.oplist.org/guide/drivers/s3',
  };

  static String? driverDocUrl(String driver) {
    final url = _driverDocUrls[_slug(driver.trim())];
    if (url == null || url.isEmpty) return null;
    return url;
  }

  /// 授权页需预选网盘类型时附加 hash（api.oplist.org）
  static String oauthUrlForDriver(String driver) {
    const hashBySlug = {
      'baidunetdisk': 'baidu_oauth',
      'aliyundriveopen': 'aliyun_open',
      'onedrive': 'onedrive',
      '115_open': '115_open',
    };
    final slug = _slug(driver);
    final hash = hashBySlug[slug];
    if (hash != null && hash.isNotEmpty) {
      return 'https://api.oplist.org/#$hash';
    }
    return 'https://api.oplist.org/';
  }

  static const _zhDrivers = <String, String>{
    '115_cloud': '115网盘',
    '115_open': '115网盘 Open',
    '115_share': '115网盘分享',
    '123_open': '123 Open',
    '123pan': '123云盘',
    '123panlink': '123云盘链接',
    '123panshare': '123云盘分享',
    '139yun': '139Yun',
    '189cloud': '天翼云盘',
    '189cloudpc': '天翼云盘 PC',
    '189cloudtv': '天翼云盘 TV',
    'alist_v3': 'AList V3',
    'alias': '别名',
    'aliyundrive': '阿里云盘',
    'aliyundriveopen': '阿里云盘 Open',
    'aliyundriveshare': '阿里云盘分享',
    'autoindex': '自动索引',
    'azure_blob_storage': 'Azure Blob Storage',
    'baidunetdisk': '百度网盘',
    'baiduphoto': '百度相册',
    'cnb_releases': 'CNB Releases',
    'chaoxinggroupdrive': 'ChaoXingGroupDrive',
    'chunk': '分块',
    'cloudreve': 'Cloudreve',
    'cloudreve_v4': 'Cloudreve V4',
    'crypt': '加密',
    'degoo': 'Degoo',
    'doge': 'Doge',
    'doubao': '豆包',
    'doubaonew': '豆包（新）',
    'doubaoshare': '豆包分享',
    'dropbox': 'Dropbox',
    'ftp': 'FTP',
    'febbox': 'FebBox',
    'feijipan': 'FeijiPan',
    'github_api': 'GitHub API',
    'github_releases': 'GitHub Releases',
    'googledrive': 'Google 云端硬盘',
    'googlephoto': 'Google 相册',
    'halalcloud': 'HalalCloud',
    'halalcloudopen': 'HalalCloud Open',
    'ilanzou': 'ILanZou',
    'ipfs_api': 'IPFS API',
    'kodbox': 'KodBox',
    'lanzou': '蓝奏云',
    'lenovonasshare': 'LenovoNasShare',
    'local': '本地',
    'mediafire': 'MediaFire',
    'mediatrack': 'MediaTrack',
    'mega_nz': 'MEGA',
    'misskey': 'Misskey',
    'mopan': 'MoPan',
    'neteasemusic': 'NeteaseMusic',
    'onedrive': 'OneDrive',
    'onedrive_sharelink': 'OneDrive 分享链接',
    'onedriveapp': 'OneDrive 应用',
    'openlist': 'OpenList',
    'openlistshare': 'OpenList 分享',
    'pikpak': 'PikPak',
    'pikpakshare': 'PikPak 分享',
    'protondrive': 'ProtonDrive',
    'quark': '夸克网盘',
    'quarkopen': '夸克网盘 Open',
    'quarktv': '夸克网盘 TV',
    's3': '对象存储(S3)',
    'sftp': 'SFTP',
    'smb': 'SMB',
    'seafile': 'Seafile',
    'strm': 'Strm',
    'teambition': 'Teambition',
    'teldrive': 'Teldrive',
    'terabox': 'TeraBox',
    'thunder': '迅雷',
    'thunderbrowser': '迅雷浏览器',
    'thunderbrowserexpert': 'ThunderBrowserExpert',
    'thunderexpert': 'ThunderExpert',
    'thunderx': '迅雷X',
    'thunderxexpert': 'ThunderXExpert',
    'uc': 'UC网盘',
    'uctv': 'UC网盘 TV',
    'uss': 'USS',
    'urltree': 'UrlTree',
    'virtual': '虚拟',
    'wps': 'WPS',
    'webdav': 'WebDAV',
    'weiyun': '微云',
    'wopan': 'WoPan',
    'yandexdisk': 'Yandex 磁盘',
  };

  static const _enDrivers = <String, String>{
    '115_cloud': '115 Cloud',
    '115_open': '115 Open',
    '115_share': '115 Share',
    '123_open': '123 Open',
    '123pan': '123Pan',
    '123panlink': '123PanLink',
    '123panshare': '123PanShare',
    '139yun': '139Yun',
    '189cloud': '189Cloud',
    '189cloudpc': '189CloudPC',
    '189cloudtv': '189CloudTV',
    'alist_v3': 'AList V3',
    'alias': 'Alias',
    'aliyundrive': 'Aliyundrive',
    'aliyundriveopen': 'AliyundriveOpen',
    'aliyundriveshare': 'AliyundriveShare',
    'autoindex': 'AutoIndex',
    'azure_blob_storage': 'Azure Blob Storage',
    'baidunetdisk': 'BaiduNetdisk',
    'baiduphoto': 'BaiduPhoto',
    'cnb_releases': 'CNB Releases',
    'chaoxinggroupdrive': 'ChaoXingGroupDrive',
    'chunk': 'Chunk',
    'cloudreve': 'Cloudreve',
    'cloudreve_v4': 'Cloudreve V4',
    'crypt': 'Crypt',
    'degoo': 'Degoo',
    'doge': 'Doge',
    'doubao': 'Doubao',
    'doubaonew': 'DoubaoNew',
    'doubaoshare': 'DoubaoShare',
    'dropbox': 'Dropbox',
    'ftp': 'FTP',
    'febbox': 'FebBox',
    'feijipan': 'FeijiPan',
    'github_api': 'GitHub API',
    'github_releases': 'GitHub Releases',
    'googledrive': 'GoogleDrive',
    'googlephoto': 'GooglePhoto',
    'halalcloud': 'HalalCloud',
    'halalcloudopen': 'HalalCloudOpen',
    'ilanzou': 'ILanZou',
    'ipfs_api': 'IPFS API',
    'kodbox': 'KodBox',
    'lanzou': 'Lanzou',
    'lenovonasshare': 'LenovoNasShare',
    'local': 'Local',
    'mediafire': 'MediaFire',
    'mediatrack': 'MediaTrack',
    'mega_nz': 'Mega_nz',
    'misskey': 'Misskey',
    'mopan': 'MoPan',
    'neteasemusic': 'NeteaseMusic',
    'onedrive': 'Onedrive',
    'onedrive_sharelink': 'Onedrive Sharelink',
    'onedriveapp': 'OnedriveAPP',
    'openlist': 'OpenList',
    'openlistshare': 'OpenListShare',
    'pikpak': 'PikPak',
    'pikpakshare': 'PikPakShare',
    'protondrive': 'ProtonDrive',
    'quark': 'Quark',
    'quarkopen': 'QuarkOpen',
    'quarktv': 'QuarkTV',
    's3': 'Object Storage (S3)',
    'sftp': 'SFTP',
    'smb': 'SMB',
    'seafile': 'Seafile',
    'strm': 'Strm',
    'teambition': 'Teambition',
    'teldrive': 'Teldrive',
    'terabox': 'Terabox',
    'thunder': 'Thunder',
    'thunderbrowser': 'ThunderBrowser',
    'thunderbrowserexpert': 'ThunderBrowserExpert',
    'thunderexpert': 'ThunderExpert',
    'thunderx': 'ThunderX',
    'thunderxexpert': 'ThunderXExpert',
    'uc': 'UC',
    'uctv': 'UCTV',
    'uss': 'USS',
    'urltree': 'UrlTree',
    'virtual': 'Virtual',
    'wps': 'WPS',
    'webdav': 'WebDav',
    'weiyun': 'WeiYun',
    'wopan': 'WoPan',
    'yandexdisk': 'YandexDisk',
  };
}

