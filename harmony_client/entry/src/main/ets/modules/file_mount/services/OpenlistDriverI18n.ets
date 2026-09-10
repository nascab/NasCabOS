import { L10n } from '../../../core/localization/L10n';
import { DriverField } from '../models/FileMountModels';

/**
 * OpenList 网盘驱动显示名与字段名 i18n（对齐 Flutter OpenlistDriverI18n）。
 * 驱动名采用内置中/英两套映射（与 Flutter 一致，不走语言包）；字段名走 openlist_field_* 语言 key。
 */
export class OpenlistDriverI18n {
  private constructor() {
  }

  /** 驱动名 slug（小写 + 非 [a-z0-9] 归并为 '_'，对齐 Flutter _slug） */
  static slug(raw: string): string {
    return raw.toLowerCase().replace(/[^a-z0-9]+/g, '_')
      .replace(/^_+/, '').replace(/_+$/, '');
  }

  private static isZh(): boolean {
    return L10n.locale.toLowerCase().startsWith('zh');
  }

  static driverName(raw: string): string {
    const key = OpenlistDriverI18n.slug(raw.trim());
    if (key.length === 0) {
      return raw;
    }
    const map = OpenlistDriverI18n.isZh()
      ? OpenlistDriverI18n.ZH_DRIVERS : OpenlistDriverI18n.EN_DRIVERS;
    const name = map[key];
    return name !== undefined ? name : raw;
  }

  /**
   * 驱动字段显示名：openlist_field_<name> 语言 key → help（≤120 字符）→ 原始字段名。
   * （对齐 Flutter OpenlistDriverI18n.fieldLabel）
   */
  static fieldLabel(field: DriverField): string {
    const name = field.name;
    if (name.length === 0) {
      return '';
    }
    const key = `openlist_field_${name}`;
    const translated = L10n.t(key);
    if (translated !== key) {
      return translated;
    }
    const help = field.help.trim();
    if (help.length > 0 && help.length <= 120) {
      return help;
    }
    return name;
  }

  /** 支持跳转 api.oplist.org 授权页的驱动（与后端固定列表一致） */
  private static readonly ONLINE_AUTH_DRIVERS: string[] =
    ['baidunetdisk', 'aliyundriveopen', 'onedrive', '115_open'];

  static usesOnlineAuth(driver: string): boolean {
    return OpenlistDriverI18n.ONLINE_AUTH_DRIVERS.indexOf(OpenlistDriverI18n.slug(driver)) >= 0;
  }

  /** OpenList 官方驱动文档（与后端 openlistDriverCatalog 一致） */
  private static readonly DRIVER_DOC_URLS: Record<string, string> = {
    'baidunetdisk': 'https://doc.oplist.org/guide/drivers/baidu',
    '123pan': 'https://doc.oplist.org/guide/drivers/123',
    '115_open': 'https://doc.oplist.org/guide/drivers/115_open',
    'onedrive': 'https://doc.oplist.org/guide/drivers/onedrive',
    'aliyundriveopen': 'https://doc.oplist.org/guide/drivers/aliyundrive_open',
    's3': 'https://doc.oplist.org/guide/drivers/s3'
  };

  static driverDocUrl(driver: string): string {
    const url = OpenlistDriverI18n.DRIVER_DOC_URLS[OpenlistDriverI18n.slug(driver.trim())];
    return url !== undefined ? url : '';
  }

  /** 授权页需预选网盘类型时附加 hash（api.oplist.org，对齐 Flutter oauthUrlForDriver） */
  static oauthUrlForDriver(driver: string): string {
    const hashBySlug: Record<string, string> = {
      'baidunetdisk': 'baidu_oauth',
      'aliyundriveopen': 'aliyun_open',
      'onedrive': 'onedrive',
      '115_open': '115_open'
    };
    const slug = OpenlistDriverI18n.slug(driver);
    const hash = hashBySlug[slug];
    if (hash !== undefined && hash.length > 0) {
      return `https://api.oplist.org/#${hash}`;
    }
    return 'https://api.oplist.org/';
  }

  private static readonly ZH_DRIVERS: Record<string, string> = {
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
    'yandexdisk': 'Yandex 磁盘'
  };

  private static readonly EN_DRIVERS: Record<string, string> = {
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
    'yandexdisk': 'YandexDisk'
  };
}
