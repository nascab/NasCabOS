const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableMessage {
  constructor() {
    this.tableName = 'message';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.integer('uid').notNullable().defaultTo(0);
        table.text('title').notNullable().defaultTo('');
        table.text('message').notNullable();
        table.text('action').nullable();
        table.integer('read_status').notNullable().defaultTo(0);
        table.integer('level').notNullable().defaultTo(0);
        table.integer('is_public').notNullable().defaultTo(1);
        table.timestamp('create_time').defaultTo(knex.fn.now());
      });
      Logger.info(`✅ Table ${this.tableName} created`);
      return;
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const rows = Array.isArray(existingIndexes) ? existingIndexes : existingIndexes?.rows || [];
    const indexNames = rows.map(row => row.name);
    const targetIndexes = [
      { columns: ['uid'], name: 'message_uid', unique: false },
      { columns: ['create_time'], name: 'message_create_time', unique: false },
      { columns: ['read_status'], name: 'message_read_status', unique: false },
      { columns: ['level'], name: 'message_level', unique: false },
      { columns: ['is_public'], name: 'message_is_public', unique: false },
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
      Logger.info(`✅ Created index ${index.name} on table ${this.tableName}`);
    }
  }
}

module.exports = new tableMessage();
