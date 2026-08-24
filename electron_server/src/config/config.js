const path = require('path');
const os = require('os');
const fs = require('fs');

let packageJson = {};
try {
  packageJson = require(path.join(__dirname, '../../package.json'));
} catch (e) {
  // 忽略
}
let app = null;
let isElectronAvailable = false;
let isPackaged = false;

function isPackagedRuntimeDir(dir) {
  const normalized = path.normalize(String(dir || ''));
  if (!normalized) return false;
  if (normalized.includes(`app.asar${path.sep}`) || normalized.endsWith(`app.asar`)) {
    return true;
  }
  // 大小写不敏感匹配：macOS 打包后路径为 .../Contents/Resources/app/...（Resources 首字母大写），Windows/Linux 为小写 resources
  const lower = normalized.toLowerCase();
  return lower.includes(`${path.sep}resources${path.sep}app${path.sep}`);
}

// 安全地检测并使用 Electron
try {
  // 检测是否在 Electron 环境中运行
  if (typeof process !== 'undefined' && process.versions && process.versions.electron) {
    let elec = require('electron');
    app = elec.app;
    isElectronAvailable = true;
    isPackaged = app.isPackaged || false;
  }
} catch (err) {
  // Electron 不可用，运行在纯 Node.js 环境（如 Worker 线程）
  // 这是正常的，不需要报错
}

// 检测是否已打包（生产环境）
// 在 Worker 线程中，通过检查是否在 asar 包中来判断
if (!isElectronAvailable) {
  isPackaged = isPackagedRuntimeDir(__dirname);
}

// 环境配置
const env = process.env.NODE_ENV || 'development';
const defaultApps = [
  'folder',
  'photo',
  'movie',
  'book',
  'music',
  'note',
  'encrypted',
  'media_tool',
  'user',
  'terminal',
  'mounts',
  'docker',
  'backup',
  'nascab_service',
  'security',
  'share',
  'monitor',
  'task_center',
  'transmission',
  'setting',
  'process'
];
const normalUserNoShowApps = ['transmission','terminal', 'user', 'mounts', 'docker', 'nascab_service', 'monitor', 'process'];
const imgTypeList = ['.jpeg', '.jpg', '.png', '.heic', '.heif', '.hif', '.gif', '.webp', '.tiff', '.svg', '.bmp'];
const rawImgTypeList = ['.dng', '.cr2', '.nef', '.orf', '.raf', '.raw', '.x3f', '.rw2', '.nrw', '.arw'];
const videoTypeList = ['.mov', '.mp4', '.avi', '.rm', '.mkv', '.f4v', '.vob', '.mpg', '.rmvb', '.asf', '.mts', '.ts', '.wmv', '.m4v', '.m2ts', '.ogg', '.3gp', '.flv'];
const bookTypeList = ['.txt', '.epub', '.pdf', '.mobi', '.azw3', '.cbz', '.cbr', '.rar', '.zip'];
const musicTypeList = ['.mp3', '.flac', '.aac', '.wav', '.ogg', '.opus', '.wma', '.ape','.m4a'];
//禁用端口
let forbiddenPorts = [
  1, 7, 9, 11, 13, 15, 17, 19, 20, 23, 25, 37, 42, 43, 53, 77, 79, 87, 95, 101, 102, 103, 104, 109, 110, 111, 113, 115, 117, 119, 123, 135, 139, 143, 179, 389, 465, 512, 513, 514, 515, 526,
  530, 531, 532, 540, 556, 563, 587, 601, 636, 993, 995, 2049, 3659, 4045, 6000, 6665, 6666, 6667, 6668, 6669, 3389,
];
/**
 * 获取应用根目录
 */
function getRootPath() {
  let rootPath = '';

  if (isElectronAvailable && isPackaged) {
    // Electron 生产环境
    rootPath = path.dirname(app.getPath('exe'));
    // 兼容性适配：mac 的 appPath 在 MacOS 目录下，必须去父目录
    if (os.platform() == 'darwin') {
      rootPath = path.dirname(rootPath);
    }
  } else if (isPackaged) {
    // 生产环境 或 非主线程
    rootPath = path.join(__dirname, '../../../../');
  } else {
    // 开发环境
    rootPath = path.join(__dirname, '../../');
  }
  return rootPath;
}

/**
 * 获取 foliate-js-main 根目录（项目根目录下的 libs/foliate-js-main）
 */
function getFoliateRootPath() {
  return path.join(getRootPath(), 'libs', 'foliate-js-main');
}

/**
 * 非 Electron 环境下的默认用户数据目录（Worker / Docker / 纯 Node）
 */
function getDefaultNonElectronUserDataPath() {
  if (process.env['userDataFolder']) {
    return process.env['userDataFolder'];
  }
  // Docker 镜像内不能使用项目工作目录下的 data，改用根目录下的 /nascabos_data（便于挂载卷）
  if (packageJson.isDocker && os.platform() === 'linux') {
    const folder = path.join('/', 'nascabos_data');
    try {
      fs.mkdirSync(folder, { recursive: true });
    } catch (err) {
      console.warn('----------Create /nascabos_data Failed: ' + (err && err.message) + ' ----------');
    }
    console.log('----------Docker  userDataFolder : ' + folder + ' ----------');
    return folder;
  }
  const folder = path.join(process.cwd(), 'data');
  console.log('----------Not set userDataFolder, use default directory: ' + folder + ' ----------');
  return folder;
}

/**
 * 获取用户数据目录 如果 app 不存在则返回程序当前目录
 */
function getUserDataPath() {
  if (process.env['userDataFolder']) {
    return process.env['userDataFolder'];
  }
  if (isElectronAvailable && app && typeof app.getPath === 'function') {
    // Electron 环境
    return app.getPath('userData');
  } else {
    return getDefaultNonElectronUserDataPath();
  }
}

/** 远程资源下载已停用：onnx 模型与 sftpgo/rclone 等 libs 均打包在应用中 */
function shouldUseRemoteAssets() {
  return false;
}

function getRemoteAssetsManifestUrl() {
  return process.env.NASCAB_LIBS_MANIFEST_URL || 'https://download.nas.cab/libs/manifest.json';
}

/**
 * 获取缓存目录
 */
function getCachePath() {
  const cacheFolder = 'nascabos_cache';
  return path.join(getUserDataPath(), cacheFolder);
}
/**
 * 获取nfo头像目录
 */
function getNfoAvatarPath() {
  const nfoAvatarFolder = 'nfoAvatar';
  return path.join(getCachePath(), nfoAvatarFolder);
}
/**
 * 获取nfo海报目录
 */
function getNfoPosterPath() {
  const nfoPosterFolder = 'nfoPoster';
  return path.join(getCachePath(), nfoPosterFolder);
}
/**
 * 获取上传临时目录
 */
function getUploadTempDir() {
  const uploadTempFolder = 'uploadTemp';
  return path.join(getCachePath(), uploadTempFolder);
}
/**
 * 获取转码临时目录
 */
function getTranscodeTempPath() {
  const transcodeTempFolder = 'transcode';
  return path.join(getCachePath(), transcodeTempFolder);
}
/**
 * 获取压缩图片使用的临时目录
 */
function getZipImgTempPath() {
  const zipImgTempFolder = 'imgZipTmpUpload';
  const result = path.join(getCachePath(), zipImgTempFolder);
  const normalized = path.normalize(result);
  if (!normalized.includes('nascabos_cache') || !normalized.includes('imgZipTmpUpload')) {
    throw new Error(`Invalid zipImgTempPath: ${result}`);
  }
  return result;
}
function getTranscodeTempSafeFolderName() {
  return 'nascab_transcode_temp';
}
/**
 * 获取数据库目录
 */
function getDatabasePath() {
  const databaseFolder = 'database';
  return path.join(getUserDataPath(), databaseFolder);
}
/**
 * 获取缩略图缓存目录
 */
function getTinyCachePath() {
  const tinyFolder = 'tinyCache';
  return path.join(getCachePath(), tinyFolder);
}
/**
 * 获取音乐封面缓存目录
 */
function getMusicCoverCachePath() {
  const musicInnerCoverFolder = 'musicInnerCover';
  return path.join(getCachePath(), musicInnerCoverFolder);
}
/**
 * 获取缩略图生成临时文件的目录
 */
function getTinyCacheTempPath() {
  const tinyFolder = 'tinyCache';
  return path.join(getCachePath(), tinyFolder, 'temp');
}

function getSubtitleUploadPath() {
  const subtitleUploadPath = 'subtitleUpload';
  return path.join(getCachePath(), subtitleUploadPath);
}
/**
 * 获取自定义壁纸目录
 */
function getCustomWallpaperPath() {
  const customWallpaperFolder = 'customWallpaper';
  return path.join(getCachePath(), customWallpaperFolder);
}
/**
 * 获取地图瓦片缓存目录
 */
function getMapTileCachePath() {
  const mapTileFolder = 'mapTiles';
  return path.join(getCachePath(), mapTileFolder);
}

function getOpenListDataPath() {
  const openListFolder = 'openListData';
  return path.join(getUserDataPath(), openListFolder);
}
/**
 * 判断是否为图片文件
 */
function isImg(ext) {
  return imgTypeList.includes(ext) || rawImgTypeList.includes(ext);
}

let appRootPath = path.join(__dirname, '../../');
if (!appRootPath) {
  try {
    const { app } = require('electron');
    if (app && app.isPackaged) {
      appRootPath = path.dirname(app.getPath('exe'));
      //兼容性适配 mac的apppath在macos目录下 必须去父目录 否则崩溃
      if (os.platform() == 'darwin') {
        appRootPath = path.dirname(appRootPath);
      }
    } else {
      appRootPath = path.join(__dirname, '../../');
    }
  } catch (err) {}
}

/**
 * 获取文件类型
 */
function getFileType(ext) {
  if (imgTypeList.includes(ext)) return 'image';
  if (rawImgTypeList.includes(ext)) return 'raw';
  if (videoTypeList.includes(ext)) return 'video';
  return 'file';
}
/**
 * 获取默认的tmdb配置
 */
function getDefaultTmdbConfig() {
  return {
    tmdbApiToken:
      'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiI0Njc2MGM2MjE0OWY2MDUxMDQ5ZTUwZDU2NDg1NWU2MiIsIm5iZiI6MTcyNjcxNTQwNC43NTM1NDMsInN1YiI6IjYyZjM3ZjdlMWY3NDhiMDA4MTE2Y2MyZSIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.3bjuEGwVsCjgrWHiFsta7NDsuRQG_9mX59ExRUWeeVY',
    tmdbApiUrl: 'https://api.tmdb.org',
  };
}
function getDefaultTileServer() {
  return [
    {
      name: 'GaoDe',
      server: 'https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=7&x={x}&y={y}&z={z}',
      maxLevel: 18,
      coordinate: 'GCJ-02',
    },
    {
      name: 'NasCab',
      isDefault: true,
      server: 'https://down.nascab.cn/mapTiles/{z}/{x}/{y}/tile.png',
      maxLevel: 12,
      coordinate: 'GCJ-02',
    },
    {
      name: 'ArcGIS',
      server: 'https://server.arcgisonline.com/arcgis/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}.png',
      maxLevel: 13,
      coordinate: 'WGS-84',
    },
  ];
}
const config = {
  getOpenListDataPath:getOpenListDataPath,//
  getSubtitleUploadPath:getSubtitleUploadPath, //字幕上传目录
  getDefaultTileServer: getDefaultTileServer, //默认的地图瓦片服务器
  getDefaultTmdbConfig: getDefaultTmdbConfig, //默认的tmdb配置
  getCustomWallpaperPath: getCustomWallpaperPath, //自定义壁纸目录
  getZipImgTempPath: getZipImgTempPath, //压缩图片使用的临时目录
  defaultApps: defaultApps, //默认应用
  normalUserNoShowApps: normalUserNoShowApps, //普通用户不显示的应用
  forbiddenPorts: forbiddenPorts, //禁用端口
  getMusicCoverCachePath: getMusicCoverCachePath, //音乐封面缓存目录
  getNfoPosterPath: getNfoPosterPath,
  getNfoAvatarPath: getNfoAvatarPath,
  getTinyCacheTempPath: getTinyCacheTempPath, //缩略图生成临时文件的目录
  appRootPath: appRootPath, //应用根目录
  getMapTileCachePath: getMapTileCachePath, //地图瓦片缓存目录
  getTranscodeTempPath: getTranscodeTempPath, //转码临时目录
  getTranscodeTempSafeFolderName: getTranscodeTempSafeFolderName,
  isImg: isImg, //判断是否为图片文件
  copyTempFilePrefix: '.copyTemp_', //复制临时文件前缀
  uploadTempFilePrefix: '.uploadTemp_', //上传临时文件前缀
  uploadTempPartPrefix: '.uploadTempPart_', //上传临时分块文件前缀
  getUploadTempDir: getUploadTempDir, //上传临时目录
  getRootPath: getRootPath, //获取应用根目录
  getFoliateRootPath: getFoliateRootPath, // foliate-js-main 根目录
  getFileType: getFileType, //获取文件类型
  getDatabasePath: getDatabasePath, //数据库目录
  getCachePath: getCachePath, //缓存目录
  getUserDataPath: getUserDataPath, //用户数据目录
  shouldUseRemoteAssets: shouldUseRemoteAssets,
  getRemoteAssetsManifestUrl: getRemoteAssetsManifestUrl,
  getTinyCachePath: getTinyCachePath, //缩略图缓存目录
  appRootPath: getRootPath(),
  // 应用配置
  app: {
    port: process.env.PORT || 6789,
    httpsPort: process.env.HTTPS_PORT || 6799,
    env: env,
    isProduction: env === 'production',
    isDevelopment: env === 'development',
    isTest: env === 'test',
  },

  // JWT配置（密钥仅从 process.env.JWT_SECRET 读取，不在此暴露以防注入）
  jwt: {
    accessTokenExpiresIn: process.env.ACCESS_TOKEN_EXPIRES_IN || '12h',
    refreshTokenExpiresIn: process.env.REFRESH_TOKEN_EXPIRES_IN || '7d',
  },

  // 上传配置
  upload: {
    maxFileSize: process.env.MAX_FILE_SIZE || '100gb',
  },

  // 日志配置
  logging: {
    level: process.env.LOG_LEVEL || 'info',
    file: {
      enabled: true, //是否启用文件输出
      path: path.join(getRootPath(), 'logs'),
    },
  },

  fileServer: {
    defaultPorts: {
      SFTP: { http_port: 2022, https_port: null },
      FTP: { http_port: 2121, https_port: null },
      WebDav: { http_port: 10080, https_port: 10443 },
    },
  },

  transmission: {
    defaultRpcPort: 52019,
    defaultPeerPort: 37291,
    defaultPeerLimitGlobal: 200,
    defaultPeerLimitPerTorrent: 50,
  },

  // File Types
  imgTypeList: imgTypeList,
  rawImgTypeList: rawImgTypeList,
  videoTypeList: videoTypeList,
  bookTypeList: bookTypeList,
  musicTypeList: musicTypeList,
};

// 开发环境特定配置
if (config.app.isDevelopment) {
  config.logging.level = 'debug';
  config.logging.file.enabled = false;
}

// 生产环境特定配置
if (config.app.isProduction) {
  config.logging.file.enabled = true;
}

module.exports = config;
