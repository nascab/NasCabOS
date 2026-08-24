// IPC 处理器：统一管理与渲染进程的通信
// 提供服务状态、日志、设置、管理员信息等接口
const fs = require('fs');
const knexUtil = require('../db/knexUtil');
const dbUtil = require('../db/dbUtil');
const tableUser = require('../db/table/tableUser');
const { getSnapshotDatabaseTotalBytes, refreshDatabaseTotalBytesCache } = require('../utils/databaseDirUiUtil');
const NetUtil = require('../utils/netUtil');
const autoLaunchUtil = require('../utils/autoLaunchUtil');
const jwtUtil = require('../utils/jwtUtil');
const { validateUsername, validatePassword } = require('../utils/adminCredentialValidation');
const {
  ACCESS_SCOPE_ALL,
  ACCESS_SCOPE_SPECIFIED,
  getAppAccessScopeConfig,
  setAppAccessScopeConfig,
} = require('../utils/appAccessScopeUtil');

function register(ipcMain, app, shell, tableConfig, Logger, getExpressState, getProcessList, getInitUtil) {
  // 服务状态：返回当前 IPv4 列表、Express 是否已启动、HTTP/HTTPS 端口等
  ipcMain.handle('service:getStatus', async () => {
    const { expressStarted, expressHttpPort, expressHttpsPort } = getExpressState();
    const ips = NetUtil.getIPv4Addresses();
    const httpAddresses = expressHttpPort ? ips.map(ip => `http://${ip}:${expressHttpPort}`) : [];
    const httpsAddresses = expressHttpsPort ? ips.map(ip => `https://${ip}:${expressHttpsPort}`) : [];
    return {
      ipAddresses: ips,
      expressStarted,
      httpPort: expressHttpPort,
      httpAddresses,
      httpsPort: expressHttpsPort,
      httpsAddresses,
      databaseDir: process.env.PATH_DATABASE || '',
      cacheDir: process.env.PATH_CACHE || '',
      databaseTotalBytes: getSnapshotDatabaseTotalBytes(),
    };
  });

  ipcMain.handle('database:vacuumAll', async () => {
    const uniquePaths = [...new Set(Object.values(dbUtil.DB_PATHS))];
    const failures = [];
    for (const dbPath of uniquePaths) {
      try {
        if (!fs.existsSync(dbPath)) {
          continue;
        }
        const knex = knexUtil.getInstance(dbPath);
        await knex.raw('VACUUM');
      } catch (e) {
        const msg = e && e.message ? String(e.message) : String(e);
        failures.push({ path: dbPath, error: msg });
        Logger.warn(`database:vacuumAll failed for ${dbPath}: ${msg}`);
      }
    }
    refreshDatabaseTotalBytesCache();
    return { success: failures.length === 0, failures };
  });

  ipcMain.handle('process:getList', async () => {
    try {
      const list = typeof getProcessList === 'function' ? getProcessList() : [];
      if (!Array.isArray(list)) return [];
      return list.map(item => {
        if (!item || typeof item !== 'object') return item;
        const cloned = { ...item };
        delete cloned.memoryBytes;
        delete cloned.memoryMB;
        return cloned;
      });
    } catch (_) {
      return [];
    }
  });

  // 日志：返回最近缓冲的日志行（主进程内存中维护）
  ipcMain.handle('logs:getRecent', async () => {
    return Logger.getRecentLogs();
  });

  // 打开外部网址（如官网）
  ipcMain.handle('open:external', async (evt, url) => {
    try {
      await shell.openExternal(url);
      return true;
    } catch (e) {
      return false;
    }
  });

  // 应用信息（版本号等）
  ipcMain.handle('app:getInfo', async () => {
    return { version: app.getVersion ? app.getVersion() : '' };
  });

  ipcMain.handle('open:path', async (evt, p) => {
    try {
      if (!p) {
        return false;
      }
      const fs = require('fs');
      const path = require('path');

      // 规范化路径
      const normalizedPath = path.resolve(p);

      const isExist = fs.existsSync(normalizedPath);
      if (!isExist) {
        return false;
      }
      // 优先使用showItemInFolder来打开目录
      try {
        await shell.showItemInFolder(normalizedPath);
        return true;
      } catch (error1) {
        // 如果showItemInFolder失败，尝试openPath
        try {
          const result = await shell.openPath(normalizedPath);
          if (typeof result === 'string' && result.trim().length > 0) {
            return false;
          }
          return true;
        } catch (error2) {
          return false;
        }
      }
    } catch (e) {
      return false;
    }
  });


  // 启动选项：开机自启与最小化启动
  ipcMain.handle('settings:getStartupOptions', async () => {
    let openAtLogin = false;
    let minimizeOnStart = false;
    let autoDiscoverServer = true;
    try {
      const confOpen = await tableConfig.getConfigByKey(tableConfig.KEY_OPEN_AT_LOGIN);
      if (confOpen !== null && confOpen !== undefined) {
        openAtLogin = confOpen === 'true';
      } else {
        openAtLogin = autoLaunchUtil.getOpenAtLogin(app);
      }
    } catch {
      openAtLogin = autoLaunchUtil.getOpenAtLogin(app);
    }
    try {
      const v = await tableConfig.getConfigByKey(tableConfig.KEY_MINIMIZE_ON_START);
      minimizeOnStart = v === 'true';
    } catch {}
    try {
      autoDiscoverServer = await tableConfig.getAutoDiscoverServerEnabled();
    } catch {}
    return { openAtLogin, minimizeOnStart, autoDiscoverServer };
  });

  ipcMain.handle('settings:setStartupOptions', async (evt, payload) => {
    try {
      const openAtLogin = !!payload.openAtLogin;
      const minimizeOnStart = !!payload.minimizeOnStart;
      const hasAutoDiscover = payload && Object.prototype.hasOwnProperty.call(payload, 'autoDiscoverServer');
      const autoDiscoverServer = hasAutoDiscover ? !!payload.autoDiscoverServer : true;
      await tableConfig.setConfigByKey(tableConfig.KEY_OPEN_AT_LOGIN, openAtLogin ? 'true' : 'false');
      await tableConfig.setConfigByKey(tableConfig.KEY_MINIMIZE_ON_START, minimizeOnStart ? 'true' : 'false');
      if (hasAutoDiscover) {
        await tableConfig.setAutoDiscoverServerEnabled(autoDiscoverServer);
      }
      autoLaunchUtil.setOpenAtLogin(app, openAtLogin, minimizeOnStart);
      if (hasAutoDiscover) {
        const initUtil = typeof getInitUtil === 'function' ? getInitUtil() : null;
        if (initUtil && initUtil.expressStarted) {
          if (autoDiscoverServer) {
            initUtil.startExpressBroadcastWorker(initUtil.expressHttpPort, process.env.SERVER_ID || '');
          } else {
            await initUtil.stopExpressBroadcastWorker();
          }
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  });

  ipcMain.handle('settings:getFeatureAccessScope', async () => {
    try {
      return await getAppAccessScopeConfig();
    } catch (_) {
      return { mode: ACCESS_SCOPE_ALL, dirs: [], terminalEnabled: true };
    }
  });

  ipcMain.handle('settings:setFeatureAccessScope', async (evt, payload) => {
    try {
      const mode = payload && payload.mode === ACCESS_SCOPE_SPECIFIED ? ACCESS_SCOPE_SPECIFIED : ACCESS_SCOPE_ALL;
      const dirs = payload && Array.isArray(payload.dirs) ? payload.dirs : [];
      const terminalEnabled = !(payload && Object.prototype.hasOwnProperty.call(payload, 'terminalEnabled'))
        ? true
        : !!payload.terminalEnabled;
      return await setAppAccessScopeConfig({ mode, dirs, terminalEnabled });
    } catch (_) {
      return false;
    }
  });

  ipcMain.handle('settings:selectDirectories', async evt => {
    try {
      const { dialog, BrowserWindow } = require('electron');
      const currentWindow = BrowserWindow.fromWebContents(evt.sender);
      const result = await dialog.showOpenDialog(currentWindow, {
        properties: ['openDirectory', 'createDirectory', 'multiSelections'],
      });
      if (result.canceled) return null;
      return Array.isArray(result.filePaths) ? result.filePaths : [];
    } catch (_) {
      return null;
    }
  });

  // UI 语言：获取与设置
  ipcMain.handle('ui:getLanguage', async () => {
    try {
      const val = await tableConfig.getConfigByKey(tableConfig.KEY_SERVER_UI_LANGUAGE);
      // 支持所有语言（含韩语、越南语、印尼语）
      const validLanguages = ['zh-CN', 'en-US', 'ja-JP', 'es-ES', 'de-DE', 'fr-FR', 'pt-BR', 'ru-RU', 'ar-SA', 'th-TH', 'ko-KR', 'vi-VN', 'id-ID'];
      if (validLanguages.includes(val)) return val;
      return null;
    } catch {}
    return null;
  });

  ipcMain.handle('ui:setLanguage', async (evt, lang) => {
    try {
      const valueRaw = String(lang || '').trim();
      let value = valueRaw;
      if (value === 'system') {
        const systemLocale = (app && typeof app.getLocale === 'function' ? app.getLocale() : 'en-US') || 'en-US';
        const lang = (systemLocale || '').toLowerCase();
        if (lang.startsWith('zh')) value = 'zh-CN';
        else if (lang.startsWith('ja')) value = 'ja-JP';
        else if (lang.startsWith('ko')) value = 'ko-KR';
        else if (lang.startsWith('vi')) value = 'vi-VN';
        else if (lang.startsWith('id')) value = 'id-ID';
        else if (lang.startsWith('es')) value = 'es-ES';
        else if (lang.startsWith('de')) value = 'de-DE';
        else if (lang.startsWith('fr')) value = 'fr-FR';
        else if (lang.startsWith('pt')) value = 'pt-BR';
        else if (lang.startsWith('ru')) value = 'ru-RU';
        else if (lang.startsWith('ar')) value = 'ar-SA';
        else if (lang.startsWith('th')) value = 'th-TH';
        else value = 'en-US';
      }
      // 支持所有语言（含韩语、越南语、印尼语）
      const validLanguages = ['zh-CN', 'en-US', 'ja-JP', 'es-ES', 'de-DE', 'fr-FR', 'pt-BR', 'ru-RU', 'ar-SA', 'th-TH', 'ko-KR', 'vi-VN', 'id-ID'];
      if (!validLanguages.includes(value)) {
        return false;
      }
      await tableConfig.setConfigByKey(tableConfig.KEY_SERVER_UI_LANGUAGE, value);
      try {
        const { refreshServerUiLanguageCache } = require('../utils/i18nUtil');
        await refreshServerUiLanguageCache();
      } catch (_) {}
      return true;
    } catch (e) {
      return false;
    }
  });

  // 管理员信息：返回超级管理员用户名
  ipcMain.handle('user:getAdmin', async () => {
    try {
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      const row = await knex('user').where({ type: tableUser.TYPE_SUPER_ADMIN }).first();
      if (!row) return { username: null };
      return { username: row.username };
    } catch {
      return { username: null };
    }
  });

  ipcMain.handle('user:getInitialAdmin', async () => {
    try {
      const flag = await tableConfig.getConfigByKey(tableConfig.KEY_IS_INITIAL_ADMIN, 0);
      if (flag !== '1') return { isInitialAdmin: false, username: null, password: null };
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      const row = await knex('user').where({ type: tableUser.TYPE_SUPER_ADMIN }).first();
      if (!row) return { isInitialAdmin: false, username: null, password: null };
      const password = jwtUtil.isEncryptedPassword(row.password) ? jwtUtil.decryptPassword(row.password) : jwtUtil.decodeClientPassword(row.password);
      return { isInitialAdmin: true, username: row.username || null, password: password || null };
    } catch {
      return { isInitialAdmin: false, username: null, password: null };
    }
  });

  ipcMain.handle('user:getAdminSecurity', async () => {
    try {
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      const row = await knex('user').where({ type: tableUser.TYPE_SUPER_ADMIN }).first();
      if (!row) return { twofaEnabled: false };
      const twofa = await knex('user_2fa').where({ user_id: row.id }).select('is_enabled').first();
      return { twofaEnabled: !!(twofa && twofa.is_enabled === 1) };
    } catch {
      return { twofaEnabled: false };
    }
  });

  // 修改超级管理员密码（复杂度与 createSuperAdmin 对齐）
  ipcMain.handle('user:changeAdminPassword', async (evt, newPassword) => {
    try {
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      const row = await knex('user').where({ type: tableUser.TYPE_SUPER_ADMIN }).first();
      if (!row) return { success: false, error: 'ADMIN_NOT_FOUND' };

      const passwordPlain = jwtUtil.decodeClientPassword(newPassword);
      const result = validatePassword(passwordPlain);
      if (!result.valid) return { success: false, error: result.error };

      const encryptedPassword = jwtUtil.encryptPassword(passwordPlain);
      await knex('user').where({ id: row.id }).update({ password: encryptedPassword });
      await tableConfig.deleteConfigByKey(tableConfig.KEY_IS_INITIAL_ADMIN, 0);
      return { success: true };
    } catch (e) {
      return { success: false, error: 'FAILED' };
    }
  });

  ipcMain.handle('user:updateAdmin', async (evt, payload) => {
    try {
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      const row = await knex('user').where({ type: tableUser.TYPE_SUPER_ADMIN }).first();
      if (!row) return { success: false, error: 'ADMIN_NOT_FOUND' };

      const data = {};
      let changed = false;
      let newUsername = '';

      if (payload && typeof payload.username === 'string') {
        const username = payload.username.trim();
        if (username) {
          const uResult = validateUsername(username);
          if (!uResult.valid) return { success: false, error: uResult.error };
          const exists = await knex('user').where({ username }).andWhereNot({ id: row.id }).first();
          if (exists) return { success: false, error: 'USERNAME_EXISTS' };
          data.username = username;
          newUsername = username;
          changed = true;
        }
      }

      if (payload && typeof payload.password === 'string') {
        const pwdRaw = payload.password.trim();
        if (pwdRaw) {
          const passwordPlain = jwtUtil.decodeClientPassword(pwdRaw);
          const pResult = validatePassword(passwordPlain, { username: newUsername || row.username });
          if (!pResult.valid) return { success: false, error: pResult.error };
          data.password = jwtUtil.encryptPassword(passwordPlain);
          changed = true;
        }
      }

      if (!changed) return { success: false, error: 'NO_CHANGES' };
      await knex('user').where({ id: row.id }).update(data);
      await tableConfig.deleteConfigByKey(tableConfig.KEY_IS_INITIAL_ADMIN, 0);
      return { success: true };
    } catch (e) {
      const msg = e && e.message ? String(e.message) : '';
      const isUsernameConstraint = e && (e.code === 'SQLITE_CONSTRAINT' || e.code === 'SQLITE_CONSTRAINT_UNIQUE') && msg.includes('user.username');
      if (isUsernameConstraint) return { success: false, error: 'USERNAME_EXISTS' };
      return { success: false, error: 'FAILED' };
    }
  });

  ipcMain.handle('user:resetAdmin2fa', async () => {
    try {
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      const row = await knex('user').where({ type: tableUser.TYPE_SUPER_ADMIN }).first();
      if (!row) return { success: false, error: 'ADMIN_NOT_FOUND' };
      const { TwoFAService } = require('../api/modules/auth/2fa/twofaService');
      const service = new TwoFAService(knex);
      await service.adminReset(row.id);
      return { success: true };
    } catch {
      return { success: false, error: 'FAILED' };
    }
  });

  // --- Cache statistics & cleanup ---
  const cacheScanJobs = new Map();

  function walkDirSync(dirPath) {
    const path = require('path');
    const fs = require('fs');
    let fileCount = 0;
    let totalSize = 0;
    try {
      const entries = fs.readdirSync(dirPath, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(dirPath, entry.name);
        try {
          if (entry.isDirectory()) {
            const sub = walkDirSync(fullPath);
            fileCount += sub.fileCount;
            totalSize += sub.totalSize;
          } else if (entry.isFile()) {
            const stat = fs.statSync(fullPath);
            fileCount += 1;
            totalSize += stat.size;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return { fileCount, totalSize };
  }

  function removeDirContentsSync(dirPath) {
    const path = require('path');
    const fs = require('fs');
    try {
      const entries = fs.readdirSync(dirPath, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(dirPath, entry.name);
        try {
          if (entry.isDirectory()) {
            fs.rmSync(fullPath, { recursive: true, force: true });
          } else {
            fs.unlinkSync(fullPath);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  ipcMain.handle('cache:scanFolders', async (event, { cacheDir, folders, jobId }) => {
    const path = require('path');
    const win = require('electron').BrowserWindow.fromWebContents(event.sender);
    if (!win) return { success: false, error: 'NO_WINDOW' };

    // Abort any previous scan for this window
    if (cacheScanJobs.has(jobId)) {
      cacheScanJobs.get(jobId).aborted = true;
    }
    const ctrl = { aborted: false };
    cacheScanJobs.set(jobId, ctrl);

    try {
      for (let i = 0; i < folders.length; i++) {
        if (ctrl.aborted) break;
        const folderName = folders[i];
        const folderPath = path.join(cacheDir, folderName);

        // Send progress: scanning this folder
        win.webContents.send('cache:scanProgress', { jobId, folder: folderName, index: i, total: folders.length, phase: 'scanning' });

        let fileCount = 0;
        let totalSize = 0;
        // Yield to event loop to keep UI responsive
        await new Promise(resolve => {
          setImmediate(() => {
            if (!ctrl.aborted && fs.existsSync(folderPath)) {
              const result = walkDirSync(folderPath);
              fileCount = result.fileCount;
              totalSize = result.totalSize;
            }
            resolve();
          });
        });

        if (ctrl.aborted) break;

        // Send result for this folder
        win.webContents.send('cache:scanProgress', {
          jobId,
          folder: folderName,
          index: i,
          total: folders.length,
          phase: 'done',
          fileCount,
          totalSize,
        });
      }
    } catch (err) {
      win.webContents.send('cache:scanProgress', { jobId, phase: 'error', error: err && err.message ? String(err.message) : String(err) });
    } finally {
      cacheScanJobs.delete(jobId);
      win.webContents.send('cache:scanComplete', { jobId, aborted: ctrl.aborted });
    }

    return { success: true };
  });

  ipcMain.handle('cache:cancelScan', async (_event, jobId) => {
    const ctrl = cacheScanJobs.get(jobId);
    if (ctrl) {
      ctrl.aborted = true;
      return true;
    }
    return false;
  });

  ipcMain.handle('cache:cleanFolders', async (event, { cacheDir, folders, jobId }) => {
    const path = require('path');
    const win = require('electron').BrowserWindow.fromWebContents(event.sender);
    if (!win) return { success: false, error: 'NO_WINDOW' };

    try {
      for (let i = 0; i < folders.length; i++) {
        const folderName = folders[i];
        const folderPath = path.join(cacheDir, folderName);

        win.webContents.send('cache:cleanProgress', { jobId, folder: folderName, index: i, total: folders.length, phase: 'deleting' });

        await new Promise(resolve => {
          setImmediate(() => {
            try {
              if (fs.existsSync(folderPath)) {
                removeDirContentsSync(folderPath);
              }
            } catch (_) {}
            resolve();
          });
        });

        win.webContents.send('cache:cleanProgress', { jobId, folder: folderName, index: i, total: folders.length, phase: 'done' });
      }
    } catch (err) {
      win.webContents.send('cache:cleanProgress', { jobId, phase: 'error', error: err && err.message ? String(err.message) : String(err) });
    } finally {
      win.webContents.send('cache:cleanComplete', { jobId });
    }

    return { success: true };
  });
}

module.exports = { register };
