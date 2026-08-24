const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableFileBackupRecord {
  static STATUS_RUNNING = 'running';
  static STATUS_SUCCESS = 'success';
  static STATUS_FAILED = 'failed';
  static STATUS_STOPPED = 'stopped';

  static MAX_ROWS_PER_TASK = 300;

  constructor() {
    this.tableName = 'file_backup_record';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.integer('task_id').notNullable();
        table.timestamp('start_time').notNullable();
        table.timestamp('end_time').nullable();
        table.text('status').notNullable();
        table.integer('files_copied_count').nullable();
        table.integer('files_skipped_count').nullable();
        table.integer('files_removed_count').nullable();
        table.integer('bytes_copied_count').nullable();
        table.text('error_file_list').nullable();
        table.integer('duration_ms').nullable();
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
      { columns: ['task_id'], name: 'idx_file_backup_record_task_id', unique: false },
      { columns: ['task_id', 'start_time'], name: 'idx_file_backup_record_task_start', unique: false },
    ];

    for (const index of targetIndexes) {
      if (indexNames.includes(index.name)) continue;
      await knex.schema.alterTable(this.tableName, table => {
        table.index(index.columns, index.name);
      });
      Logger.info(`✅ Created index ${index.name} on table ${this.tableName}`);
    }

    await this.createTriggers({ knex });
  }

  async createTriggers(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const triggerName = 'trg_file_backup_delete_records';
    const existing = await knex.raw("SELECT name FROM sqlite_master WHERE type='trigger' AND name=?", [triggerName]);
    const triggerExists = Array.isArray(existing) ? existing.length > 0 : (existing?.rows || []).length > 0;
    if (triggerExists) return;

    await knex.raw(`
      CREATE TRIGGER ${triggerName}
      AFTER DELETE ON file_backup
      FOR EACH ROW
      BEGIN
        DELETE FROM ${this.tableName} WHERE task_id = OLD.id;
      END;
    `);
    Logger.info(`✅ Created trigger ${triggerName} on file_backup`);
  }
}

const instance = new tableFileBackupRecord();
instance.STATUS_RUNNING = tableFileBackupRecord.STATUS_RUNNING;
instance.STATUS_SUCCESS = tableFileBackupRecord.STATUS_SUCCESS;
instance.STATUS_FAILED = tableFileBackupRecord.STATUS_FAILED;
instance.STATUS_STOPPED = tableFileBackupRecord.STATUS_STOPPED;
instance.MAX_ROWS_PER_TASK = tableFileBackupRecord.MAX_ROWS_PER_TASK;

module.exports = instance;
