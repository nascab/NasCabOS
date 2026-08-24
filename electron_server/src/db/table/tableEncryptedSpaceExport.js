const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableEncryptedSpaceExport {
  static STATUS_PENDING = 'pending';
  static STATUS_RUNNING = 'running';
  static STATUS_SUCCESS = 'success';
  static STATUS_ERROR = 'error';

  constructor() {
    this.tableName = 'encrypted_space_export';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.integer('uid').notNullable();
        table.integer('space_id').notNullable();
        table.text('space_path').notNullable();
        table.text('target_path').notNullable();

        table
          .enu('status', [tableEncryptedSpaceExport.STATUS_PENDING, tableEncryptedSpaceExport.STATUS_RUNNING, tableEncryptedSpaceExport.STATUS_SUCCESS, tableEncryptedSpaceExport.STATUS_ERROR])
          .notNullable()
          .defaultTo(tableEncryptedSpaceExport.STATUS_PENDING);

        table.text('last_error').nullable();
        table.text('progress').notNullable().defaultTo('');

        table.integer('total_files').notNullable().defaultTo(0);
        table.integer('done_files').notNullable().defaultTo(0);
        table.bigInteger('handled_input_bytes').notNullable().defaultTo(0);
        table.bigInteger('handled_output_bytes').notNullable().defaultTo(0);
        table.integer('processed_count').notNullable().defaultTo(0);
        table.integer('skipped_count').notNullable().defaultTo(0);

        table.timestamp('create_time').defaultTo(knex.fn.now());
        table.timestamp('update_time').defaultTo(knex.fn.now());
        table.timestamp('last_start_time').nullable();
        table.timestamp('last_end_time').nullable();
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
      { columns: ['uid'], name: 'idx_encrypted_space_export_uid', unique: false },
      { columns: ['space_id'], name: 'idx_encrypted_space_export_space_id', unique: false },
      { columns: ['status'], name: 'idx_encrypted_space_export_status', unique: false },
      { columns: ['create_time'], name: 'idx_encrypted_space_export_create_time', unique: false },
      { columns: ['update_time'], name: 'idx_encrypted_space_export_update_time', unique: false },
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

const instance = new tableEncryptedSpaceExport();
instance.STATUS_PENDING = tableEncryptedSpaceExport.STATUS_PENDING;
instance.STATUS_RUNNING = tableEncryptedSpaceExport.STATUS_RUNNING;
instance.STATUS_SUCCESS = tableEncryptedSpaceExport.STATUS_SUCCESS;
instance.STATUS_ERROR = tableEncryptedSpaceExport.STATUS_ERROR;

module.exports = instance;
