const knexUtil = require('../../../db/knexUtil');
const dbUtil = require('../../../db/dbUtil');
const tableConfig = require('../../../db/table/tableConfig');
const nascabAccountUtil = require('../../../api/modules/service/utils/nascabAccountUtil');

function createConfigStore() {
  let knex = null;

  const ensureServerId = async () => {
    const sid = await nascabAccountUtil.ensureServerId(tableConfig);
    if (sid) process.env.SERVER_ID = String(sid);
    return sid || '';
  };

  const initDb = async () => {
    if (knex) return knex;
    await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
    knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    await ensureServerId();
    return knex;
  };

  const getKnex = () => knex;

  const getConfigValue = async key => {
    await initDb();
    const v = await nascabAccountUtil.getDecryptedConfigValue(knex, tableConfig, key);
    return v ? v : null;
  };

  const setConfigValue = async (key, value, { encrypt = true } = {}) => {
    await initDb();
    await knex.transaction(async trx => {
      if (encrypt) {
        await nascabAccountUtil.setEncryptedConfigValue(trx, tableConfig, key, value == null ? null : String(value));
        return;
      }
      await nascabAccountUtil.setConfigValue(trx, key, value == null ? null : String(value));
    });
  };

  const clearConfigValue = async key => {
    await setConfigValue(key, null, { encrypt: false });
  };

  return { ensureServerId, initDb, getKnex, getConfigValue, setConfigValue, clearConfigValue };
}

const configStore = createConfigStore();

module.exports = configStore;
module.exports.createConfigStore = createConfigStore;

