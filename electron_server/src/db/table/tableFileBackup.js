const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableFileBackup {
  static TYPE_COPY = 'copy';
  static TYPE_SYNC = 'sync';

  static STATUS_STOPPED = 'stopped';
  static STATUS_RUNNING = 'running';
  static STATUS_DISABLED = 'disabled';
  static STATUS_ERROR = 'error';

  constructor() {
    this.tableName = 'file_backup';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.text('source_path').notNullable();
        table.enu('type', [tableFileBackup.TYPE_COPY, tableFileBackup.TYPE_SYNC]).notNullable();
        table.text('target_path').notNullable();
        table.text('task_config').nullable();
        table.timestamp('create_time').defaultTo(knex.fn.now());
        table
          .enu('status', [tableFileBackup.STATUS_STOPPED, tableFileBackup.STATUS_RUNNING, tableFileBackup.STATUS_DISABLED, tableFileBackup.STATUS_ERROR])
          .notNullable()
          .defaultTo(tableFileBackup.STATUS_STOPPED);
        table.text('last_error').nullable();
        table.integer('frenquence').notNullable().defaultTo(24);
        table.text('progress').notNullable().defaultTo('');
        table.timestamp('last_success_time').nullable();
        table.text('exclude_list').notNullable().defaultTo('[]');
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
      { columns: ['status'], name: 'idx_file_backup_status', unique: false },
      { columns: ['type'], name: 'idx_file_backup_type', unique: false },
      { columns: ['target_path'], name: 'idx_file_backup_target_path', unique: false },
      { columns: ['frenquence'], name: 'idx_file_backup_frenquence', unique: false },
      { columns: ['create_time'], name: 'idx_file_backup_create_time', unique: false },
      { columns: ['last_success_time'], name: 'idx_file_backup_last_success_time', unique: false },
      { columns: ['status', 'type'], name: 'idx_file_backup_status_type', unique: false },
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

const instance = new tableFileBackup();
instance.TYPE_COPY = tableFileBackup.TYPE_COPY;
instance.TYPE_SYNC = tableFileBackup.TYPE_SYNC;
instance.STATUS_STOPPED = tableFileBackup.STATUS_STOPPED;
instance.STATUS_RUNNING = tableFileBackup.STATUS_RUNNING;
instance.STATUS_DISABLED = tableFileBackup.STATUS_DISABLED;
instance.STATUS_ERROR = tableFileBackup.STATUS_ERROR;

module.exports = instance;
