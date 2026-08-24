const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableUserPermission {
  constructor() {
    this.ACTIONS = {
      VIEW: 'view',
      DOWNLOAD: 'download',
      UPDATE: 'update',
      DELETE: 'delete',
      UPLOAD: 'upload',
    };
    this.RES_TYPES = {
      FILE: 'file',
    };
  }
  /**
   * 创建用户权限表
   */
  async createTable() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable('user_permission');
    if (!tableExists) {
      await knex.schema.createTable('user_permission', table => {
        table.increments('id').primary();
        table.integer('uid').notNullable().index('idx_user_permission_uid');
        table.string('res_type').notNullable();
        table.string('res_path').notNullable();
        table.string('action').notNullable();
        table.timestamp('create_time').defaultTo(knex.fn.now());
      });
      Logger.info('✅ user_permission table created');
    }
  }

  /**
   * 创建用户表索引
   */
  async createIndexes() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const existingIndexes = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='user_permission'").then(res => res);
    const indexNames = Array.isArray(existingIndexes) ? existingIndexes.map(row => row.name) : (existingIndexes?.rows || []).map(row => row.name);

    const targetIndexes = [
      {
        columns: ['uid', 'res_type', 'action', 'res_path'],
        name: 'uid_res_type_action_res_path_unique',
        unique: true,
      },
      { columns: ['uid', 'res_type', 'action'], name: 'idx_uid_res_type_action' },
      { columns: ['uid'], name: 'idx_uid' },
    ];

    for (const index of targetIndexes) {
      if (!indexNames.includes(index.name)) {
        await knex.schema.alterTable('user_permission', table => {
          if (index.unique) {
            table.unique(index.columns, index.name);
          } else {
            table.index(index.columns, index.name);
          }
        });
        Logger.info(`✅ Created index ${index.name} on user_permission`);
      }
    }
  }
}
// 创建单例实例
const tableUserPermissionInstance = new tableUserPermission();
// 导出单例实例
module.exports = tableUserPermissionInstance;
