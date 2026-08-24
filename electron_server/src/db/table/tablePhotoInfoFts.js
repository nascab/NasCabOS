const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tablePhotoInfoFts {
  constructor() {
    this.tableName = 'photo_info_fts';
  }

  /**
   * 创建 photo_info_fts FTS5表
   * @param {Object} connection 数据库连接对象
   */
  async createTable(connection = null) {
    let knex;
    if (connection) {
      knex = connection.knex;
    } else {
      knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
    }

    // 检查表是否已存在
    const tableExists = await knex.raw(`
      SELECT name FROM sqlite_master 
      WHERE type='table' AND name='${this.tableName}'
    `);

    if (tableExists.length === 0) {
      // 创建FTS5虚拟表
      await knex.raw(`
        CREATE VIRTUAL TABLE ${this.tableName} USING fts5(
          file_hash,
          filename,
          describe,
          tags,
          ocr,
          tokenize="unicode61 separators '/\\.' remove_diacritics 1"
        );
      `);
      Logger.info(`✅ FTS5 table ${this.tableName} created`);
    }
  }

  /**
   * 创建索引
   * @param {Object} connection 数据库连接对象
   */
  async createIndexes(connection = null) {
    // FTS5表不需要额外创建索引
  }
}

// 创建单例实例
const tablePhotoInfoFtsInstance = new tablePhotoInfoFts();

// 导出单例实例
module.exports = tablePhotoInfoFtsInstance;
