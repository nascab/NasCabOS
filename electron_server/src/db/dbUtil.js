const knexUtil = require('./knexUtil');
const path = require('path');
const fs = require('fs');
const Logger = require('../utils/logger');
const config = require('../config/config');
/**
 * 数据库工具类
 * 提供数据库连接管理、初始化、表结构创建等功能，数据库位置等等
 * 主进程用 子进程如果只需要操作某一个数据库 可以直接使用knexUtil
 * 每次添加新的表操作文件 要扩展tableFileNameList列表，以确保初始化时创建所有表
 */
//数据库根目录
const dbFolder = process.env.PATH_DATABASE ? path.resolve(process.env.PATH_DATABASE) : path.join(__dirname, '../../database/');
// 静态全局变量 - 常用数据库路径配置
const DB_PATHS = {
  MAIN_DB: path.join(dbFolder, 'nascab_main.db'), // 主数据库路径
  PHOTO_DB: path.join(dbFolder, 'nascab_photo.db'), // 照片数据库
  VIDEO_DB: path.join(dbFolder, 'nascab_video.db'), // 影音模块数据库
  BOOK_DB: path.join(dbFolder, 'nascab_book.db'), // 图书模块数据库
  MUSIC_DB: path.join(dbFolder, 'nascab_music.db'), // 音乐模块数据库
  FILE_DB: path.join(dbFolder, 'nascab_file.db'), // 文件模块数据库
  GEO_DB_INNER: path.join(config.appRootPath, 'database', 'geonames.sqlite'), // 内部geonames数据库路径
};

/**
 * 数据库初始化工具类（支持多数据库连接）
 * 负责创建所有必要的数据库表和索引，支持在多个数据库文件中操作
 */
class DbUtil {
  // 多数据库连接管理
  constructor() {
    this._connections = new Map(); // 存储不同数据库路径的连接实例
    this._defaultDbPath = null; // 默认数据库路径
    this._currentDbPath = null; // 当前使用的数据库路径
  }
  //初始化数据库链接
  async init(createTableAndIndex = false) {
    //获取所有数据库文件并循环初始化 必须调用 否则无法使用数据库
    const allDbPath = DbUtil.getAllDbPaths();
    for (const dbPath of Object.values(allDbPath)) {
      await this.initConnect(dbPath);
    }
    if (createTableAndIndex) {
      await this.createAllTablesAndIndexes(); // 创建所有表和索引
    }
  }
  /**
   * 创建所有表和索引 调用此函数前必须先init初始化数据库连接
   * @param {string} dbPath - 数据库文件路径（可选，默认使用当前连接）
   */
  async createAllTablesAndIndexes() {
    Logger.info(`🚀 Creating database schema`);
    try {
      const knexMain = this.getConnectMainDb() && this.getConnectMainDb().knex ? this.getConnectMainDb().knex : null;
      if (knexMain) {
        const has = await knexMain.schema.hasTable('file_backup_log');
        if (has) {
          await knexMain.schema.dropTable('file_backup_log');
        }
      }
    } catch (_) {}
    //表操作文件信息列表  如果加新表 扩充这个list就可以
    const tableFileNameList = [
      {
        fileName: 'tableUser', //用户表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableUser2FA', //用户2FA表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableUser2FABackupCode', //用户2FA备份码表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableUser2FAVerifyLog', //用户2FA验证记录表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableUserPermission', //用户权限表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableConfig', //配置表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableUserToken', //用户会话表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableUserDevice', //用户设备表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableFileFavorite', //文件收藏表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableFileRecent', //文件最近查看表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableFileLog', //文件操作日志表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableTempFile', //临时文件表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableFileServer', //文件分享服务配置表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableQuickShare', //快速分享表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableMessage', //消息中心表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableFileMount', //文件挂载配置表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableOpenlistMount', //OpenList 网盘挂载配置表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableEncryptedSpace', //加密空间表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableEncryptedSpaceToken', //加密空间token表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableEncryptedSpaceExport', //加密空间导出任务表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableFileBackup', //磁盘间备份任务表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableFileBackupRecord', //磁盘间备份运行记录表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableMediaToolImgBatchCompress', //媒体工具-图片批量压缩任务表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableMediaToolVideoTrans', //媒体工具-视频转换任务表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableMediaToolAudioTrans', //媒体工具-音频转换任务表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableMediaToolArrange', //媒体工具-媒体整理任务表
        connection: this.getConnectMainDb(),
      },
      {
        fileName: 'tableFileIndex', //文件索引FTS5表
        connection: this.getConnectFileDb(),
      },
      {
        fileName: 'tableFfmpegVideoInfo', //视频流信息表
        connection: this.getConnectVideoDb(),
      },
      {
        fileName: 'tableVideoPlayPreference', //视频播放偏好表
        connection: this.getConnectVideoDb(),
      },
      {
        fileName: 'tableVideoTranscodeSession', //视频转码会话表
        connection: this.getConnectVideoDb(),
      },
      {
        fileName: 'tablePhotoSource', //照片来源表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoScanTask', //照片扫描任务表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoIndex', //照片索引表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tableWaitGenTiny', //缩略图待生成队列表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoSimilar', //照片去重表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoGpsAdd', //照片GPS补充批次表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoInfoFts', //照片信息FTS表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoFavorite', //照片收藏表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoAlbum', //普通相册表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoAlbumShare', //相册分享表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoAlbumIndex', //相册索引表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoSmartAlbum', //智能相册表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoCollection', //照片合集表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoPlaces', //照片场景表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoPlaces2Filehash', //照片场景-文件哈希表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoFaces', //照片人脸表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoFaceSamples', //照片人脸样本表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tablePhotoFace2Filehash', //照片人脸-文件哈希表
        connection: this.getConnectPhotoDb(),
      },
      {
        fileName: 'tableVideoSource', //视频来源表
        connection: this.getConnectVideoDb(),
      },
      {
        fileName: 'tableVideoScanTask', //影音扫描任务表
        connection: this.getConnectVideoDb(),
      },
      {
        fileName: 'tableVideoIndex2Key', //影音索引-类型映射表
        connection: this.getConnectVideoDb(),
      },
      {
        fileName: 'tableVideoFavorite', //影音收藏表
        connection: this.getConnectVideoDb(),
      },
      {
        fileName: 'tableVideoCollection', //影音合集表
        connection: this.getConnectVideoDb(),
      },
      {
        fileName: 'tableVideoSmartAlbum', //智能影集表
        connection: this.getConnectVideoDb(),
      },
      {
        fileName: 'tableVideoAlbum', //普通影集表
        connection: this.getConnectVideoDb(),
      },
      {
        fileName: 'tableVideoAlbumIndex', //影集索引表
        connection: this.getConnectVideoDb(),
      },
      {
        fileName: 'tableVideoIndex', //影音库索引表
        connection: this.getConnectVideoDb(),
      },
      {
        fileName: 'tableBookSource', //图书来源表
        connection: this.getConnectBookDb(),
      },
      {
        fileName: 'tableBookScanTask', //图书扫描任务表
        connection: this.getConnectBookDb(),
      },
      {
        fileName: 'tableBookList2Index', //书单-索引映射表
        connection: this.getConnectBookDb(),
      },
      {
        fileName: 'tableBookList', //书单表
        connection: this.getConnectBookDb(),
      },
      {
        fileName: 'tableBookHistory', //图书阅读进度表
        connection: this.getConnectBookDb(),
      },
      {
        fileName: 'tableBookPreference', //图书阅读偏好表
        connection: this.getConnectBookDb(),
      },
      {
        fileName: 'tableBookFavorite', //图书收藏表
        connection: this.getConnectBookDb(),
      },
      {
        fileName: 'tableBookCollection', //图书合集表
        connection: this.getConnectBookDb(),
      },
      {
        fileName: 'tableBookIndex', //图书索引表
        connection: this.getConnectBookDb(),
      },
      {
        fileName: 'tableMusicSource', //音乐来源表
        connection: this.getConnectMusicDb(),
      },
      {
        fileName: 'tableMusicScanTask', //音乐扫描任务表
        connection: this.getConnectMusicDb(),
      },
      {
        fileName: 'tableMusicPlayList2Index', //歌单-索引映射表
        connection: this.getConnectMusicDb(),
      },
      {
        fileName: 'tableMusicPlayList', //歌单表
        connection: this.getConnectMusicDb(),
      },
      {
        fileName: 'tableMusicIndex2Key', //音乐索引-类型映射表
        connection: this.getConnectMusicDb(),
      },
      {
        fileName: 'tableMusicCollection', //音乐合集表
        connection: this.getConnectMusicDb(),
      },
      {
        fileName: 'tableMusicFavorite', //音乐收藏表
        connection: this.getConnectMusicDb(),
      },
      {
        fileName: 'tableMusicIndex', //音乐索引表
        connection: this.getConnectMusicDb(),
      },
      {
        fileName: 'tableMusicHistory', //音乐播放历史
        connection: this.getConnectMusicDb(),
      },
      {
        fileName: 'tableMusicLyricSearchLog', //歌词搜索缓存记录
        connection: this.getConnectMusicDb(),
      },
    ];
    //循环require并创建相关表和索引
    for (const tableFileName of tableFileNameList) {
      const tableClass = require(`./table/${tableFileName.fileName}`); //require进来
      await tableClass.createTable(tableFileName.connection); //创建表（如果不存在）
      await tableClass.createIndexes(tableFileName.connection); //创建索引（如果不存在）
    }
    Logger.info(`✅ Database schema ready`);
  }

  // 静态方法 - 获取预定义的数据库路径
  static get DB_PATHS() {
    return DB_PATHS;
  }

  getConnectMainDb() {
    return this.getConnection(DB_PATHS.MAIN_DB);
  }

  getConnectGeoDb() {
    return this.getConnection(DB_PATHS.GEO_DB_INNER);
  }

  getConnectPhotoDb() {
    return this.getConnection(DB_PATHS.PHOTO_DB);
  }

  getConnectVideoDb() {
    return this.getConnection(DB_PATHS.VIDEO_DB);
  }

  getConnectBookDb() {
    return this.getConnection(DB_PATHS.BOOK_DB);
  }

  getConnectMusicDb() {
    return this.getConnection(DB_PATHS.MUSIC_DB);
  }

  getConnectFileDb() {
    return this.getConnection(DB_PATHS.FILE_DB);
  }

  // 静态方法 - 获取所有数据库路径
  static getAllDbPaths() {
    return { ...DB_PATHS };
  }

  /**
   * 初始化数据库连接（支持多数据库）
   * @param {string} dbPath - 数据库文件路径
   * @param {boolean} setAsDefault - 是否设置为默认数据库
   * @returns {Promise<Object>} 返回包含knex实例和dbPath的对象
   */
  async initConnect(dbPath, setAsDefault = true) {
    // 检查连接是否已存在
    if (this._connections.has(dbPath)) {
      Logger.debug(`📁 数据库连接已存在: ${dbPath}`);
      const connection = this._connections.get(dbPath);
      if (setAsDefault) {
        this._defaultDbPath = dbPath;
        this._currentDbPath = dbPath;
      }
      return connection;
    }

    // 目录不存在则创建
    if (!fs.existsSync(dbPath)) {
      fs.mkdirSync(path.dirname(dbPath), { recursive: true });
    }

    // 初始化数据库连接
    const knex = await knexUtil.init(dbPath);
    await knex.raw('SELECT 1');
    await knex.raw('PRAGMA journal_mode = WAL;');
    // 存储连接
    const connection = { knex, dbPath };
    this._connections.set(dbPath, connection);

    if (setAsDefault || !this._defaultDbPath) {
      this._defaultDbPath = dbPath;
      this._currentDbPath = dbPath;
    }

    return connection;
  }

  /**
   * 获取指定数据库的连接
   * @param {string} dbPath - 数据库文件路径（可选，默认使用当前连接）
   * @returns {Object} 返回包含knex实例和dbPath的对象
   */
  getConnection(dbPath = null) {
    const targetDbPath = dbPath || this._currentDbPath || this._defaultDbPath;
    if (!targetDbPath) {
      throw new Error('未找到可用的数据库连接，请先调用init方法初始化数据库');
    }

    const connection = this._connections.get(targetDbPath);
    if (!connection) {
      throw new Error(`数据库连接不存在: ${targetDbPath}`);
    }

    return connection;
  }

  /**
   * 切换到指定数据库
   * @param {string} dbPath - 数据库文件路径
   */
  switchDatabase(dbPath) {
    if (!this._connections.has(dbPath)) {
      throw new Error(`数据库连接不存在: ${dbPath}`);
    }
    this._currentDbPath = dbPath;
    Logger.info(`🔄 Switched database: ${dbPath}`);
  }

  /**
   * 获取所有已初始化的数据库路径
   * @returns {Array<string>} 数据库路径数组
   */
  getAllDbPaths() {
    return Array.from(this._connections.keys());
  }

  /**
   * 检查数据库连接是否存在
   * @param {string} dbPath - 数据库文件路径
   * @returns {boolean} 是否存在
   */
  hasConnection(dbPath) {
    return this._connections.has(dbPath);
  }
  /**
   * 关闭数据库连接
   * @param {string} dbPath - 数据库文件路径（可选，默认关闭所有连接）
   */
  async destroy(dbPath = null) {
    if (dbPath) {
      // 关闭指定连接
      if (this._connections.has(dbPath)) {
        await knexUtil.destroy(dbPath);
        this._connections.delete(dbPath);

        // 如果关闭的是默认连接，重新设置默认连接
        if (this._defaultDbPath === dbPath) {
          const remainingPaths = this.getAllDbPaths();
          this._defaultDbPath = remainingPaths.length > 0 ? remainingPaths[0] : null;
          this._currentDbPath = this._defaultDbPath;
        }

        info(`✅ 数据库连接已关闭: ${dbPath}`);
      }
    } else {
      // 关闭所有连接
      const destroyPromises = [];
      for (const [path, connection] of this._connections) {
        destroyPromises.push(knexUtil.destroy(path));
      }

      await Promise.all(destroyPromises);
      this._connections.clear();
      this._defaultDbPath = null;
      this._currentDbPath = null;
      info('✅ 所有数据库连接已关闭');
    }
  }

  /**
   * 获取连接状态信息
   * @returns {Object} 连接状态信息
   */
  getConnectionStatus() {
    return {
      totalConnections: this._connections.size,
      defaultDbPath: this._defaultDbPath,
      currentDbPath: this._currentDbPath,
      allDbPaths: this.getAllDbPaths(),
      connections: Object.fromEntries(this._connections),
    };
  }
}

// 创建单例实例
const dbUtilInstance = new DbUtil();

// 手动将静态方法和属性附加到实例上
dbUtilInstance.DB_PATHS = DbUtil.DB_PATHS;

// 导出单例实例
module.exports = dbUtilInstance;
