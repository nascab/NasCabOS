const dbUtil = require('../dbUtil');
const knexUtil = require('../knexUtil');
const Logger = require('../../utils/logger');

class tableFileLog {
  static STATE_WAIT = 'WAIT';
  static STATE_PROCESSING = 'PROCESSING';
  static STATE_SUCCESS = 'SUCCESS';
  static STATE_ERROR = 'ERROR';
  static STATE_CANCELLED = 'CANCELLED';
  static STATE_INTERRUPTED = 'INTERRUPTED';

  static TYPE_COPY = 'copy';
  static TYPE_MOVE = 'move';
  static TYPE_DELETE = 'delete';
  static TYPE_RENAME = 'rename';

  constructor() {}

  /**
   * 创建文件操作日志表
   */
  async createTable() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    // 检查表是否已存在
    const tableExists = await knex.schema.hasTable('file_log');
    if (!tableExists) {
      await knex.schema.createTable('file_log', table => {
        table.increments('id').primary();
        table.string('type').notNullable(); // copy, move, delete
        table.text('source_path').notNullable(); // JSON string of array
        table.string('target_path').nullable();
        table.integer('uid').notNullable();
        table.string('state').notNullable().defaultTo(tableFileLog.STATE_WAIT);
        table.text('message').nullable();
        table.bigInteger('total_size').nullable().defaultTo(0);
        table.bigInteger('copied_size').nullable().defaultTo(0);
        table.timestamp('create_time').defaultTo(knex.fn.now());
      });
      Logger.info('✅ file_log table created');
    }
  }

  /**
   * 创建文件操作日志表索引
   */
  async createIndexes() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    // 检查索引是否已存在
    const existingIndexes = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='file_log'");
    const indexNames = existingIndexes.map(row => row.name);

    const targetIndexes = [
      { columns: ['uid', 'type', 'state'], name: 'idx_file_log_uid_type_state', unique: false },
      { columns: ['create_time'], name: 'idx_file_log_create_time', unique: false },
    ];

    for (const index of targetIndexes) {
      if (!indexNames.includes(index.name)) {
        await knex.schema.alterTable('file_log', table => {
          if (index.unique) {
            table.unique(index.columns, index.name);
          } else {
            table.index(index.columns, index.name);
          }
        });
        Logger.info(`✅ Created index ${index.name} on file_log`);
      }
    }
  }
}

// 创建单例实例
const tableFileLogInstance = new tableFileLog();
tableFileLogInstance.STATE_WAIT = tableFileLog.STATE_WAIT;
tableFileLogInstance.STATE_PROCESSING = tableFileLog.STATE_PROCESSING;
tableFileLogInstance.STATE_SUCCESS = tableFileLog.STATE_SUCCESS;
tableFileLogInstance.STATE_ERROR = tableFileLog.STATE_ERROR;
tableFileLogInstance.STATE_INTERRUPTED = tableFileLog.STATE_INTERRUPTED;
tableFileLogInstance.STATE_CANCELLED = tableFileLog.STATE_CANCELLED;

tableFileLogInstance.TYPE_COPY = tableFileLog.TYPE_COPY;
tableFileLogInstance.TYPE_MOVE = tableFileLog.TYPE_MOVE;
tableFileLogInstance.TYPE_DELETE = tableFileLog.TYPE_DELETE;
tableFileLogInstance.TYPE_RENAME = tableFileLog.TYPE_RENAME;

// 导出单例实例
module.exports = tableFileLogInstance;
