const dbUtil = require('../dbUtil');
const knexUtil = require('../knexUtil');
const Logger = require('../../utils/logger');

class tableUser2FA {
  async createTable() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable('user_2fa');
    if (!tableExists) {
      await knex.schema.createTable('user_2fa', table => {
        table.increments('id').primary();
        table.integer('user_id').notNullable();
        table.boolean('is_enabled').notNullable().defaultTo(false);
        table.text('secret_enc').nullable();
        table.string('issuer').notNullable().defaultTo('NasCabOS');
        table.integer('period').notNullable().defaultTo(30);
        table.integer('digits').notNullable().defaultTo(6);
        table.string('algorithm').notNullable().defaultTo('sha1');
        table.timestamp('secret_created_at').nullable();
        table.timestamp('enabled_at').nullable();
        table.timestamp('last_verified_at').nullable();
        table.timestamp('create_time').defaultTo(knex.fn.now());
        table.timestamp('update_time').defaultTo(knex.fn.now());
      });
      Logger.info('✅ user_2fa table created');
    }
  }

  async createIndexes() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const existingIndexes = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='user_2fa'");
    const indexNames = existingIndexes.map(row => row.name);

    const targetIndexes = [
      { columns: ['user_id'], name: 'idx_user_2fa_user_id', unique: true },
      { columns: ['is_enabled'], name: 'idx_user_2fa_is_enabled', unique: false },
    ];

    for (const index of targetIndexes) {
      if (!indexNames.includes(index.name)) {
        await knex.schema.alterTable('user_2fa', table => {
          if (index.unique) {
            table.unique(index.columns, index.name);
          } else {
            table.index(index.columns, index.name);
          }
        });
        Logger.info(`✅ Created index ${index.name} on user_2fa`);
      }
    }
  }
}

const tableUser2FAInstance = new tableUser2FA();
module.exports = tableUser2FAInstance;
