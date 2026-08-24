const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableMediaToolImgBatchCompress {
  static STATUS_STOPPED = 'stopped';
  static STATUS_RUNNING = 'running';
  static STATUS_DISABLED = 'disabled';
  static STATUS_ERROR = 'error';

  static NON_IMAGE_SKIP = 'skip';
  static NON_IMAGE_COPY = 'copy';

  static OUT_FORMAT_JPEG = 'jpeg';
  static OUT_FORMAT_PNG = 'png';
  static OUT_FORMAT_WEBP = 'webp';

  constructor() {
    this.tableName = 'media_tool_img_batch_compress';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.text('source_path').notNullable();
        table.text('target_path').notNullable();
        table
          .enu('out_format', [tableMediaToolImgBatchCompress.OUT_FORMAT_JPEG, tableMediaToolImgBatchCompress.OUT_FORMAT_PNG, tableMediaToolImgBatchCompress.OUT_FORMAT_WEBP])
          .notNullable()
          .defaultTo(tableMediaToolImgBatchCompress.OUT_FORMAT_JPEG);
        table.integer('quality').notNullable().defaultTo(80);
        table.integer('out_size').nullable();
        table
          .enu('non_image_policy', [tableMediaToolImgBatchCompress.NON_IMAGE_SKIP, tableMediaToolImgBatchCompress.NON_IMAGE_COPY])
          .notNullable()
          .defaultTo(tableMediaToolImgBatchCompress.NON_IMAGE_SKIP);

        table
          .enu('status', [
            tableMediaToolImgBatchCompress.STATUS_STOPPED,
            tableMediaToolImgBatchCompress.STATUS_RUNNING,
            tableMediaToolImgBatchCompress.STATUS_DISABLED,
            tableMediaToolImgBatchCompress.STATUS_ERROR,
          ])
          .notNullable()
          .defaultTo(tableMediaToolImgBatchCompress.STATUS_STOPPED);

        table.text('last_error').nullable();
        table.text('progress').notNullable().defaultTo('');

        table.integer('total_files').notNullable().defaultTo(0);
        table.integer('done_files').notNullable().defaultTo(0);
        table.bigInteger('handled_input_bytes').notNullable().defaultTo(0);
        table.bigInteger('handled_output_bytes').notNullable().defaultTo(0);
        table.integer('processed_count').notNullable().defaultTo(0);
        table.integer('skipped_count').notNullable().defaultTo(0);
        table.integer('non_image_count').notNullable().defaultTo(0);

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
      { columns: ['status'], name: 'idx_media_tool_img_batch_compress_status', unique: false },
      { columns: ['create_time'], name: 'idx_media_tool_img_batch_compress_create_time', unique: false },
      { columns: ['update_time'], name: 'idx_media_tool_img_batch_compress_update_time', unique: false },
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

const instance = new tableMediaToolImgBatchCompress();
instance.STATUS_STOPPED = tableMediaToolImgBatchCompress.STATUS_STOPPED;
instance.STATUS_RUNNING = tableMediaToolImgBatchCompress.STATUS_RUNNING;
instance.STATUS_DISABLED = tableMediaToolImgBatchCompress.STATUS_DISABLED;
instance.STATUS_ERROR = tableMediaToolImgBatchCompress.STATUS_ERROR;

instance.NON_IMAGE_SKIP = tableMediaToolImgBatchCompress.NON_IMAGE_SKIP;
instance.NON_IMAGE_COPY = tableMediaToolImgBatchCompress.NON_IMAGE_COPY;

instance.OUT_FORMAT_JPEG = tableMediaToolImgBatchCompress.OUT_FORMAT_JPEG;
instance.OUT_FORMAT_PNG = tableMediaToolImgBatchCompress.OUT_FORMAT_PNG;
instance.OUT_FORMAT_WEBP = tableMediaToolImgBatchCompress.OUT_FORMAT_WEBP;

module.exports = instance;
