const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tablePhotoFace2Filehash {
  constructor() {
    this.tableName = 'photo_face2filehash';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.string('file_hash').notNullable();
        table.integer('face_id').notNullable();
        table.integer('box_left').notNullable().defaultTo(0);
        table.integer('box_top').notNullable().defaultTo(0);
        table.integer('box_width').notNullable().defaultTo(0);
        table.integer('box_height').notNullable().defaultTo(0);
        table.integer('is_cover').notNullable().defaultTo(0);
        table.timestamp('create_time').defaultTo(knex.fn.now());
      });
      Logger.info(`✅ Table ${this.tableName} created`);
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const indexNames = Array.isArray(existingIndexes) ? existingIndexes.map(row => row.name) : (existingIndexes?.rows || []).map(row => row.name);

    const targetIndexes = [
      { columns: ['file_hash'], name: 'idx_photo_face2filehash_file_hash', unique: false },
      { columns: ['face_id'], name: 'idx_photo_face2filehash_face_id', unique: false },
      { columns: ['face_id', 'file_hash'], name: 'idx_photo_face2filehash_face_id_file_hash', unique: false },
      { columns: ['file_hash', 'face_id'], name: 'uniq_photo_face2filehash_file_hash_face_id', unique: true },
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

const tablePhotoFace2FilehashInstance = new tablePhotoFace2Filehash();
module.exports = tablePhotoFace2FilehashInstance;
