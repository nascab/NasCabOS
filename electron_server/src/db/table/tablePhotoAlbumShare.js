const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tablePhotoAlbumShare {
  constructor() {
    this.tableName = 'photo_album_share';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);

    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.integer('owner_id').notNullable();
        table.integer('album_id').notNullable();
        table.integer('uid').notNullable();
        table.integer('can_add').notNullable().defaultTo(1);
        table.integer('can_delete').notNullable().defaultTo(1);
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
      {
        columns: ['album_id', 'uid'],
        name: 'idx_photo_album_share_album_uid_unique',
        unique: true,
      },
      { columns: ['album_id'], name: 'idx_photo_album_share_album_id', unique: false },
      { columns: ['uid'], name: 'idx_photo_album_share_uid', unique: false },
      { columns: ['owner_id'], name: 'idx_photo_album_share_owner_id', unique: false },
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
        Logger.info(`✅ Created index ${index.name} on table ${this.tableName}`);
      }
    }
  }
}

module.exports = new tablePhotoAlbumShare();
