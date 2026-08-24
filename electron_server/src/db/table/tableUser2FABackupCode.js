const dbUtil = require('../dbUtil');
const knexUtil = require('../knexUtil');
const Logger = require('../../utils/logger');

class tableUser2FABackupCode {
  async createTable() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable('user_2fa_backup_code');
    if (!tableExists) {
      await knex.schema.createTable('user_2fa_backup_code', table => {
        table.increments('id').primary();
        table.integer('user_id').notNullable();
        table.string('code_hash').notNullable();
        table.boolean('is_used').notNullable().defaultTo(false);
        table.timestamp('used_at').nullable();
        table.timestamp('create_time').defaultTo(knex.fn.now());
      });
      Logger.info('✅ user_2fa_backup_code table created');
    }
  }

  async createIndexes() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const existingIndexes = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='user_2fa_backup_code'");
    const indexNames = existingIndexes.map(row => row.name);

    const targetIndexes = [
      { columns: ['user_id'], name: 'idx_user_2fa_backup_user_id', unique: false },
      { columns: ['user_id', 'is_used'], name: 'idx_user_2fa_backup_used', unique: false },
      { columns: ['code_hash'], name: 'idx_user_2fa_backup_code_hash', unique: true },
    ];

    for (const index of targetIndexes) {
      if (!indexNames.includes(index.name)) {
        await knex.schema.alterTable('user_2fa_backup_code', table => {
          if (index.unique) {
            table.unique(index.columns, index.name);
          } else {
            table.index(index.columns, index.name);
          }
        });
        Logger.info(`✅ Created index ${index.name} on user_2fa_backup_code`);
      }
    }
  }
}

const tableUser2FABackupCodeInstance = new tableUser2FABackupCode();
module.exports = tableUser2FABackupCodeInstance;
