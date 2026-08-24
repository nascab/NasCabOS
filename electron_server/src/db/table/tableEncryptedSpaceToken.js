const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableEncryptedSpaceToken {
  constructor() {
    this.tableName = 'encrypted_space_token';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.string('uid').notNullable();
        table.integer('space_id').notNullable();
        table.text('token').notNullable();
        table.text('space_pwd').notNullable();
        table.timestamp('create_time').defaultTo(knex.fn.now());
        table.timestamp('update_time').defaultTo(knex.fn.now());
      });
      Logger.info(`✅ Table ${this.tableName} created`);
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const rows = Array.isArray(existingIndexes) ? existingIndexes : existingIndexes?.rows || [];
    const indexNames = rows.map(row => row.name);

    const targetIndexes = [
      { columns: ['uid'], name: 'idx_encrypted_space_token_uid', unique: false },
      { columns: ['token'], name: 'uidx_encrypted_space_token_token', unique: true },
      { columns: ['uid', 'space_id'], name: 'uidx_encrypted_space_token_uid_space_id', unique: true },
    ];

    for (const index of targetIndexes) {
      if (indexNames.includes(index.name)) continue;
      await knex.schema.alterTable(this.tableName, table => {
        if (index.unique) {
          table.unique(index.columns, index.name);
        } else {
          table.index(index.columns, index.name);
        }
      });
      Logger.info(`✅ Created ${index.unique ? 'unique ' : ''}index ${index.name} on table ${this.tableName}`);
    }
  }
}

module.exports = new tableEncryptedSpaceToken();
