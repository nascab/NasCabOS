const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tablePhotoFaces {
  constructor() {
    this.tableName = 'photo_faces';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('face_id').primary();
        table.binary('feature').notNullable();
        table.binary('name').notNullable();
        table.integer('feature_dim').notNullable().defaultTo(512);
        table.integer('belong_face_id').nullable();
        table.integer('face_count').notNullable().defaultTo(0);
        table.timestamp('create_time').defaultTo(knex.fn.now());
        table.timestamp('update_time').defaultTo(knex.fn.now());
        table.integer('proto_sample_count').notNullable().defaultTo(0);
        table.integer('is_hide').notNullable().defaultTo(0);
        table.timestamp('proto_rebuild_time').nullable();
        table.integer('proto_best_quality_score').notNullable().defaultTo(0);
        table.string('proto_best_file_hash').nullable();
      });
      Logger.info(`✅ Table ${this.tableName} created`);
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const indexNames = Array.isArray(existingIndexes) ? existingIndexes.map(row => row.name) : (existingIndexes?.rows || []).map(row => row.name);

    const targetIndexes = [
      { columns: ['belong_face_id'], name: 'idx_photo_faces_belong_face_id', unique: false },
      { columns: ['is_hide'], name: 'idx_photo_faces_is_hide', unique: false },
    ];

    for (const index of targetIndexes) {
      if (!indexNames.includes(index.name)) {
        await knex.schema.alterTable(this.tableName, table => {
          if (index.unique) table.unique(index.columns, index.name);
          else table.index(index.columns, index.name);
        });
        Logger.info(`✅ Created index ${index.name} on table ${this.tableName}`);
      }
    }
  }
}

const tablePhotoFacesInstance = new tablePhotoFaces();
module.exports = tablePhotoFacesInstance;
