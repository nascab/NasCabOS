const dbUtil = require('../dbUtil');
const knexUtil = require('../knexUtil');
const Logger = require('../../utils/logger');

class tableUser2FAVerifyLog {
  async createTable() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable('user_2fa_verify_log');
    if (!tableExists) {
      await knex.schema.createTable('user_2fa_verify_log', table => {
        table.increments('id').primary();
        table.integer('user_id').nullable();
        table.string('action').notNullable().defaultTo('login');
        table.string('method').notNullable().defaultTo('totp');
        table.string('client_ip').nullable();
        table.string('device_id').nullable();
        table.boolean('ok').notNullable().defaultTo(false);
        table.string('reason_code').nullable();
        table.timestamp('create_time').defaultTo(knex.fn.now());
      });
      Logger.info('✅ user_2fa_verify_log table created');
    } else {
      const hasDeviceId = await knex.schema.hasColumn('user_2fa_verify_log', 'device_id');
      if (!hasDeviceId) {
        await knex.schema.alterTable('user_2fa_verify_log', table => {
          table.string('device_id').nullable();
        });
        Logger.info('✅ user_2fa_verify_log: added device_id column');
      }
    }
  }

  async createIndexes() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const existingIndexes = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='user_2fa_verify_log'");
    const indexNames = existingIndexes.map(row => row.name);

    const targetIndexes = [
      { columns: ['user_id'], name: 'idx_user_2fa_verify_user_id', unique: false },
      { columns: ['create_time'], name: 'idx_user_2fa_verify_create_time', unique: false },
      { columns: ['client_ip'], name: 'idx_user_2fa_verify_ip', unique: false },
      { columns: ['device_id'], name: 'idx_user_2fa_verify_device_id', unique: false },
    ];

    for (const index of targetIndexes) {
      if (!indexNames.includes(index.name)) {
        await knex.schema.alterTable('user_2fa_verify_log', table => {
          if (index.unique) {
            table.unique(index.columns, index.name);
          } else {
            table.index(index.columns, index.name);
          }
        });
        Logger.info(`✅ Created index ${index.name} on user_2fa_verify_log`);
      }
    }
  }
}

const tableUser2FAVerifyLogInstance = new tableUser2FAVerifyLog();
module.exports = tableUser2FAVerifyLogInstance;
