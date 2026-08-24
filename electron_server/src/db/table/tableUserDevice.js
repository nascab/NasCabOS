const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableUserDevice {
  constructor() {
    this.tableName = 'user_device';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.integer('user_id').notNullable();
        table.string('device_id').notNullable();
        table.string('device_name').nullable();
        table.string('os_version').nullable();
        table.timestamp('first_seen_at').defaultTo(knex.fn.now());
        table.timestamp('last_seen_at').defaultTo(knex.fn.now());
        table.integer('risk_score').notNullable().defaultTo(0);
        table.boolean('trusted_flag').notNullable().defaultTo(false);
      });
      Logger.info('✅ user_device table created');
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const existingIndexes = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='user_device'");
    const indexNames = existingIndexes.map(row => row.name);

    const targetIndexes = [
      { columns: ['user_id'], name: 'idx_user_device_user_id', unique: false },
      { columns: ['user_id', 'device_id'], name: 'uid_device_id', unique: true },
      { columns: ['last_seen_at'], name: 'idx_user_device_last_seen', unique: false },
    ];

    for (const index of targetIndexes) {
      if (!indexNames.includes(index.name)) {
        await knex.schema.alterTable(this.tableName, table => {
          if (index.unique) {
            table.unique(index.columns, index.name);
          } else {
            table.index(index.columns, index.name);
          }
        });
        Logger.info(`✅ Created index ${index.name} on user_device`);
      }
    }
  }
}

const tableUserDeviceInstance = new tableUserDevice();
module.exports = tableUserDeviceInstance;
