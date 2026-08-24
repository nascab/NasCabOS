const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableMediaToolAudioTrans {
  static STATUS_STOPPED = 'stopped';
  static STATUS_RUNNING = 'running';
  static STATUS_DISABLED = 'disabled';
  static STATUS_ERROR = 'error';

  static NON_AUDIO_SKIP = 'skip';
  static NON_AUDIO_COPY = 'copy';

  constructor() {
    this.tableName = 'media_tool_audio_trans';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.text('source_path').notNullable();
        table.text('target_path').notNullable();
        table.text('trans_config').notNullable().defaultTo('');
        table.enu('non_audio_policy', [tableMediaToolAudioTrans.NON_AUDIO_SKIP, tableMediaToolAudioTrans.NON_AUDIO_COPY]).notNullable().defaultTo(tableMediaToolAudioTrans.NON_AUDIO_SKIP);

        table
          .enu('status', [tableMediaToolAudioTrans.STATUS_STOPPED, tableMediaToolAudioTrans.STATUS_RUNNING, tableMediaToolAudioTrans.STATUS_DISABLED, tableMediaToolAudioTrans.STATUS_ERROR])
          .notNullable()
          .defaultTo(tableMediaToolAudioTrans.STATUS_STOPPED);

        table.text('last_error').nullable();
        table.text('progress').notNullable().defaultTo('');

        table.integer('total_files').notNullable().defaultTo(0);
        table.integer('done_files').notNullable().defaultTo(0);
        table.bigInteger('handled_input_bytes').notNullable().defaultTo(0);
        table.bigInteger('handled_output_bytes').notNullable().defaultTo(0);
        table.integer('processed_count').notNullable().defaultTo(0);
        table.integer('skipped_count').notNullable().defaultTo(0);
        table.integer('non_audio_count').notNullable().defaultTo(0);

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
      { columns: ['status'], name: 'idx_media_tool_audio_trans_status', unique: false },
      { columns: ['create_time'], name: 'idx_media_tool_audio_trans_create_time', unique: false },
      { columns: ['update_time'], name: 'idx_media_tool_audio_trans_update_time', unique: false },
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

const instance = new tableMediaToolAudioTrans();
instance.STATUS_STOPPED = tableMediaToolAudioTrans.STATUS_STOPPED;
instance.STATUS_RUNNING = tableMediaToolAudioTrans.STATUS_RUNNING;
instance.STATUS_DISABLED = tableMediaToolAudioTrans.STATUS_DISABLED;
instance.STATUS_ERROR = tableMediaToolAudioTrans.STATUS_ERROR;

instance.NON_AUDIO_SKIP = tableMediaToolAudioTrans.NON_AUDIO_SKIP;
instance.NON_AUDIO_COPY = tableMediaToolAudioTrans.NON_AUDIO_COPY;

module.exports = instance;
