const Logger = require('../utils/logger');
const dbUtil = require('../db/dbUtil');
const knexUtil = require('../db/knexUtil');
const tableFileLog = require('../db/table/tableFileLog');

module.exports = {
  //将之前未成功的文件操作设置为失败
  async resetPendingFileOperations() {
    try {
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      const affectedRows = await knex('file_log').whereIn('state', [tableFileLog.STATE_WAIT, tableFileLog.STATE_PROCESSING]).update({
        state: tableFileLog.STATE_INTERRUPTED,
        message: 'STATE_INTERRUPTED',
      });
      if (affectedRows > 0) {
        Logger.info(`🔄 Marked ${affectedRows} stale file tasks as failed`);
      }
    } catch (err) {
      Logger.error('❌  reset file op task status failed:', err);
    }
  },
};
