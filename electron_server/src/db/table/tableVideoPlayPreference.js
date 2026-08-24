const dbUtil = require('../dbUtil');
const knexUtil = require('../knexUtil');
const Logger = require('../../utils/logger');

class tableVideoPlayPreference {
  constructor() {
    this.tableName = 'video_play_preference';
  }

  async createTable(connection = null) {
    let knex;
    if (connection && connection.knex) {
      knex = connection.knex;
    } else {
      knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    }
    const exists = await knex.schema.hasTable(this.tableName);
    if (!exists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.integer('uid').notNullable();
        table.text('file_hash').notNullable();
        table.integer('playback_position').defaultTo(0);
        table.string('subtitle_label').nullable();
        table.string('audio_label').nullable();
        table.timestamp('last_watched_at').defaultTo(knex.fn.now());
      });
      Logger.info(`✅ video_play_preference table created`);
    }
  }

  async createIndexes(connection = null) {
    let knex;
    if (connection && connection.knex) {
      knex = connection.knex;
    } else {
      knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    }
    const idxName = 'idx_preference_uid_hash_unique';
    const existing = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND name=?", [idxName]);
    if (existing.length === 0) {
      await knex.schema.alterTable(this.tableName, table => {
        table.unique(['uid', 'file_hash'], idxName);
      });
      Logger.info(`✅ video_play_preference unique index created`);
    }
  }
}

module.exports = new tableVideoPlayPreference();
