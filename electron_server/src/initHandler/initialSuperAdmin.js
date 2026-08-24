const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const knexUtil = require('../db/knexUtil');
const dbUtil = require('../db/dbUtil');
const tableConfig = require('../db/table/tableConfig');
const tableUser = require('../db/table/tableUser');
const jwtUtil = require('../utils/jwtUtil');
const config = require('../config/config');

let packageJson = {};
try {
  packageJson = require(path.join(__dirname, '../../package.json'));
} catch (_) {}

function generateCredential(length = 6) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  const bytes = crypto.randomBytes(length);
  let out = '';
  for (let i = 0; i < length; i++) {
    out += chars[bytes[i] % chars.length];
  }
  return out;
}

function toClientPasswordObfuscated(value) {
  return `b64:${Buffer.from(String(value), 'utf8').toString('base64')}`;
}

module.exports = {
  async ensureInitialSuperAdmin() {
    const knexMain = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const authService = require('../api/modules/auth/authService');
    const has = await authService.hasSuperAdmin({ knexMain });
    if (has) return { created: false };

    const question = 'init';
    for (let i = 0; i < 20; i++) {
      const username = generateCredential(6);
      const passwordPlain = generateCredential(6);
      const answer = generateCredential(16);
      try {
        await authService.createSuperAdmin(
          { knexMain },
          {
            username,
            password: toClientPasswordObfuscated(passwordPlain),
            question,
            answer,
            language: 'zh-CN',
          }
        );
        await tableConfig.setConfigByKey(tableConfig.KEY_IS_INITIAL_ADMIN, '1', 0);
        return { created: true, username, password: passwordPlain };
      } catch (e) {
        if (e && e.message === 'auth.USERNAME_EXISTS') continue;
        throw e;
      }
    }
    throw new Error('auth.SUPER_ADMIN_CREATE_FAILED');
  },

  async getInitialSuperAdminInfo() {
    try {
      const enabled = await tableConfig.getConfigByKey(tableConfig.KEY_IS_INITIAL_ADMIN, 0);
      if (enabled !== '1') return { isInitialAdmin: false, username: null, password: null };

      const knexMain = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      const row = await knexMain('user').where({ type: tableUser.TYPE_SUPER_ADMIN }).first();
      if (!row) return { isInitialAdmin: false, username: null, password: null };

      const password = jwtUtil.isEncryptedPassword(row.password) ? jwtUtil.decryptPassword(row.password) : jwtUtil.decodeClientPassword(row.password);
      if (!password) return { isInitialAdmin: true, username: row.username || null, password: null };
      return { isInitialAdmin: true, username: row.username || null, password };
    } catch {
      return { isInitialAdmin: false, username: null, password: null };
    }
  },

  /**
   * Linux 无界面（无 Electron app）时，将 super_admin 解密后的用户名与密码明文写入
   * getUserDataPath()/nascabos_admin_account。
   * 默认跳过「仍为初始随机管理员」(is_initial_admin=1)，避免落盘；Docker 镜像需可读卷取密，故 isDocker 时仍写入。
   */
  async writeLinuxHeadlessAdminAccountFileIfNeeded() {
    try {
      if (process.platform !== 'linux') return;
      let electronApp;
      try {
        electronApp = require('electron').app;
      } catch (e) {}
      if (electronApp) return;

      const isInitialFlag = await tableConfig.getConfigByKey(tableConfig.KEY_IS_INITIAL_ADMIN, 0);
      if (isInitialFlag === '1' && !packageJson.isDocker) return;

      const knexMain = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      const row = await knexMain('user').where({ type: tableUser.TYPE_SUPER_ADMIN }).first();
      if (!row || !row.username) return;

      const password = jwtUtil.isEncryptedPassword(row.password)
        ? jwtUtil.decryptPassword(row.password)
        : jwtUtil.decodeClientPassword(row.password);
      if (!password) return;

      const userDataDir = config.getUserDataPath();
      try {
        fs.mkdirSync(userDataDir, { recursive: true });
      } catch (e) {}
      const filePath = path.join(userDataDir, 'nascabos_admin_account');
      const content = `username:${row.username} password:${password}`;
      fs.writeFileSync(filePath, content, { encoding: 'utf8', mode: 0o600 });
    } catch (e) {
      // 忽略：无界面启动不应因写备忘文件失败而中断
    }
  },
};
