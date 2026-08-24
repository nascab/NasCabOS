const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableFileServer {
  constructor() {
    this.tableName = 'file_server';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.string('uid').notNullable();
        table.string('root_path').notNullable();
        table.string('server_type').notNullable();
        table.string('status').notNullable().defaultTo('stopped');
        table.integer('http_port').nullable();
        table.integer('https_port').nullable();
        table.text('config').nullable();
        table.text('last_error').nullable();
        table.timestamp('create_time').defaultTo(knex.fn.now());
        table.timestamp('update_time').defaultTo(knex.fn.now());
      });
      Logger.info(`✅ Table ${this.tableName} created`);
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const indexNames = existingIndexes.map(row => row.name);

    const targetIndexes = [
      { columns: ['server_type', 'uid'], name: 'server_type_uid', unique: true },
      { columns: ['uid'], name: 'uid' },
      { columns: ['server_type'], name: 'server_type' },
      { columns: ['status'], name: 'status' },
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
        Logger.info(`✅ Created ${index.unique ? 'unique ' : ''}index ${index.name} on table ${this.tableName}`);
      }
    }
  }
}

const tableFileServerInstance = new tableFileServer();
module.exports = tableFileServerInstance;
