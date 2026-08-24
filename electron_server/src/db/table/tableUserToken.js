const dbUtil = require('../dbUtil');
const knexUtil = require('../knexUtil');
const Logger = require('../../utils/logger');

class tableUserToken {
  constructor() {}
  /**
   * 创建用户token表
   * 存储用户的refresh token及会话信息
   */
  async createTable() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    // 检查表是否已存在
    const tableExists = await knex.schema.hasTable('user_token');
    if (!tableExists) {
      await knex.schema.createTable('user_token', table => {
        table.increments('id').primary();
        table.integer('user_id').notNullable(); // 关联user表
        table.string('token').notNullable(); // refresh token
        table.string('client_ip').nullable(); // 登录IP
        table.string('device_info').nullable(); // 设备信息
        table.string('browser').nullable(); // 浏览器信息
        table.string('os').nullable(); // 操作系统信息
        table.string('device_id').nullable(); // 设备ID
        table.boolean('is_valid').notNullable().defaultTo(true); // 是否有效
        table.timestamp('expire_time').notNullable(); // 过期时间
        table.timestamp('create_time').defaultTo(knex.fn.now());
        table.timestamp('last_active_time').defaultTo(knex.fn.now()); // 最后活跃时间
        table.string('type').notNullable().defaultTo('refresh'); // 类型 refresh login
        table.string('allow_path').notNullable().defaultTo('ANY'); // 允许访问的路径
        table.string('allow_api').notNullable().defaultTo('ANY'); // 允许访问的API
        // 外键关联
        // table.foreign('user_id').references('id').inTable('user').onDelete('CASCADE');
      });
      Logger.info('✅ user_token table created');
    } else {
      const hasDeviceId = await knex.schema.hasColumn('user_token', 'device_id');
      if (!hasDeviceId) {
        await knex.schema.alterTable('user_token', table => {
          table.string('device_id').nullable();
        });
        Logger.info('✅ user_token: added device_id column');
      }
    }
  }

  /**
   * 创建索引
   */
  async createIndexes() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    // 检查索引是否已存在
    const existingIndexes = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='user_token'");
    const indexNames = existingIndexes.map(row => row.name);

    const targetIndexes = [
      { columns: ['user_id'], name: 'idx_user_token_user_id', unique: false },
      { columns: ['token', 'is_valid'], name: 'idx_user_token_token', unique: false },
      { columns: ['expire_time'], name: 'idx_user_token_expire_time', unique: false },
      { columns: ['device_id'], name: 'idx_user_token_device_id', unique: false },
    ];

    for (const index of targetIndexes) {
      if (!indexNames.includes(index.name)) {
        await knex.schema.alterTable('user_token', table => {
          if (index.unique) {
            table.unique(index.columns, index.name);
          } else {
            table.index(index.columns, index.name);
          }
        });
        Logger.info(`✅ Created index ${index.name} on user_token`);
      }
    }
  }
}
// 创建单例实例
const tableUserTokenInstance = new tableUserToken();
// 导出单例实例
module.exports = tableUserTokenInstance;
