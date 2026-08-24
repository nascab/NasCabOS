const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableFileIndex {
  constructor() {
    this.tableName = 'file_index_fts';
  }
  /**
   * 创建文件索引FTS5表
   */
  async createTable(connection = null) {
    let knex;
    if (connection) {
      knex = connection.knex;
    } else {
      knex = knexUtil.getInstance(dbUtil.DB_PATHS.FILE_DB);
    }

    function _toRows(raw) {
      if (!raw) return [];
      if (Array.isArray(raw)) return raw;
      if (Array.isArray(raw?.rows)) return raw.rows;
      return [];
    }

    const existsRaw = await knex.raw(`SELECT name FROM sqlite_master WHERE type='table' AND name=?`, [this.tableName]);
    let exists = _toRows(existsRaw).length > 0;
    if (!exists) {
      await knex.raw(`
        CREATE VIRTUAL TABLE ${this.tableName} USING fts5(
          path,
          filename,
          ext UNINDEXED,
          isDir UNINDEXED,
          size UNINDEXED,
          mtimeMs UNINDEXED,
          scanId UNINDEXED,
          tokenize="unicode61 separators '/\\.' remove_diacritics 1"
        );
      `);
    }
  }

  /**
   * 创建索引（FTS5表不需要额外索引）
   */
  async createIndexes(connection = null) {
    // FTS5表不需要额外创建索引，它本身就是全文索引
  }
}

// 创建单例实例
const tableFileIndexInstance = new tableFileIndex();

// 导出单例实例
module.exports = tableFileIndexInstance;
