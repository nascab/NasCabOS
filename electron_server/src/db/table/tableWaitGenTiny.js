const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableWaitGenTiny {
  constructor() {
    this.tableName = 'wait_gen_tiny';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.text('source_path').notNullable().unique();
      });
      Logger.info(`✅ Table ${this.tableName} created`);
    }
  }

  async createIndexes() {}
}

const tableWaitGenTinyInstance = new tableWaitGenTiny();

module.exports = tableWaitGenTinyInstance;
