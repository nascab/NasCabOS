const dbUtil = require('../dbUtil');
const knexUtil = require('../knexUtil');
const Logger = require('../../utils/logger');
class tableUser {
  static TYPE_SUPER_ADMIN = 'super_admin';
  static TYPE_ADMIN = 'admin';
  static TYPE_USER = 'user';
  constructor() {}
  /**
   * 创建用户表
   */
  async createTable() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    // 检查表是否已存在
    const tableExists = await knex.schema.hasTable('user');
    if (!tableExists) {
      await knex.schema.createTable('user', table => {
        table.increments('id').primary();
        table.string('username').notNullable().unique();
        table.string('phone').nullable();
        table.string('password').notNullable();
        table.string('language').notNullable().defaultTo('zh-CN');
        table.string('question').notNullable();
        table.string('answer').notNullable();
        table.string('avatar').nullable();
        table.string('user_remark').nullable();
        table.string('type').notNullable().defaultTo('user'); //super_admin,admin,user
        table.boolean('is_active').notNullable().defaultTo(true);
        table.string('last_login_ip').nullable();
        table.timestamp('last_login_time').defaultTo(knex.fn.now());
        table.timestamp('create_time').defaultTo(knex.fn.now());
        table.string('last_login_client_info').nullable();
      });
      Logger.info('✅ user table created');
    }
  }

  /**
   * 创建用户表索引
   */
  async createIndexes() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    // 检查索引是否已存在
    const existingIndexes = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='user'");
    const indexNames = existingIndexes.map(row => row.name);

    const targetIndexes = [{ columns: ['username', 'type', 'phone'], name: 'username_type_phone', unique: true }];

    for (const index of targetIndexes) {
      if (!indexNames.includes(index.name)) {
        await knex.schema.alterTable('user', table => {
          if (index.unique) {
            table.unique(index.columns, index.name);
          } else {
            table.index(index.columns, index.name);
          }
        });
        Logger.info(`✅ Created index ${index.name} on user table`);
      }
    }
  }
}
// 创建单例实例
const tableUserInstance = new tableUser();
tableUserInstance.TYPE_SUPER_ADMIN = tableUser.TYPE_SUPER_ADMIN;
tableUserInstance.TYPE_ADMIN = tableUser.TYPE_ADMIN;
tableUserInstance.TYPE_USER = tableUser.TYPE_USER;
// 导出单例实例
module.exports = tableUserInstance;
