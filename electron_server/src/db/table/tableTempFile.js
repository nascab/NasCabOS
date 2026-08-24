const dbUtil = require('../dbUtil');
const knexUtil = require('../knexUtil');
const Logger = require('../../utils/logger');
class tableTempFile {
  constructor() {}
  /**
   * 创建临时文件表
   */
  async createTable() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    // 检查表是否已存在
    const tableExists = await knex.schema.hasTable('temp_file');
    if (!tableExists) {
      await knex.schema.createTable('temp_file', table => {
        table.increments('id').primary();
        table.string('path').notNullable();
        table.string('type').notNullable();
        table.bigInteger('create_time').notNullable(); // Store as timestamp in milliseconds
      });
      Logger.info('✅ temp_file table created');
    }
  }

  /**
   * 创建临时文件表索引
   */
  async createIndexes() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    // 检查索引是否已存在
    const existingIndexes = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='temp_file'");
    const indexNames = existingIndexes.map(row => row.name);

    const targetIndexes = [
      { columns: ['path'], name: 'idx_temp_file_path', unique: false },
      { columns: ['create_time'], name: 'idx_temp_file_create_time', unique: false },
    ];

    for (const index of targetIndexes) {
      if (!indexNames.includes(index.name)) {
        await knex.schema.alterTable('temp_file', table => {
          if (index.unique) {
            table.unique(index.columns, index.name);
          } else {
            table.index(index.columns, index.name);
          }
        });
        Logger.info(`✅ Created index ${index.name} on temp_file`);
      }
    }
  }
}
// 创建单例实例
const tableTempFileInstance = new tableTempFile();
// 导出单例实例
module.exports = tableTempFileInstance;
