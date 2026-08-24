const tableConfig = require('../../../../db/table/tableConfig');
const config = require('../../../../config/config');
const knexUtil = require('../../../../db/knexUtil');
const dbUtil = require('../../../../db/dbUtil');
const tableUser = require('../../../../db/table/tableUser');
class AppsService {
  constructor() {}

  static KEY_USER_APPS_HIDE = 'userAppsHide';
  static KEY_USER_APPS_ORDER = 'userAppsOrder';

  async _getUserType(userId) {
    const uid = Number(userId);
    if (!Number.isFinite(uid) || uid <= 0) return null;
    try {
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      const row = await knex('user').where({ id: uid }).first('type');
      return row && row.type ? String(row.type) : null;
    } catch (_) {
      return null;
    }
  }

  async _getAllowedApps(userId) {
    const defaults = config.defaultApps;
    const noShow = Array.isArray(config.normalUserNoShowApps) ? config.normalUserNoShowApps : [];
    if (noShow.length === 0) return defaults;

    const userType = await this._getUserType(userId);
    const isNormalUser = Number(userId) <= 0 || userType === tableUser.TYPE_USER;
    if (!isNormalUser) return defaults;

    return defaults.filter(app => !noShow.includes(app));
  }

  /**
   * 获取APP列表
   * @returns {Promise<Object>} APP列表
   */
  async getApps(userId = 0) {
    const defaults = await this._getAllowedApps(userId);
    let orderValue = await tableConfig.getConfigByKey(AppsService.KEY_USER_APPS_ORDER, userId);
    let order = [];
    try {
      order = orderValue ? JSON.parse(orderValue) : [];
    } catch (e) {
      order = [];
    }
    order = (Array.isArray(order) ? order : []).filter(a => defaults.includes(a));
    order = Array.from(new Set(order));
    const all = [...order, ...defaults.filter(a => !order.includes(a))];

    let hideValue = await tableConfig.getConfigByKey(AppsService.KEY_USER_APPS_HIDE, userId);
    let hide = [];
    try {
      hide = hideValue ? JSON.parse(hideValue) : [];
    } catch (e) {
      hide = [];
    }
    hide = (Array.isArray(hide) ? hide : []).filter(a => all.includes(a));
    return {
      hide_app: hide,
      all_app: all,
    };
  }

  async setHideApps(userId, hideApps) {
    const all = await this._getAllowedApps(userId);
    const sanitized = (Array.isArray(hideApps) ? hideApps : []).filter(a => all.includes(a));
    await tableConfig.setConfigByKey(AppsService.KEY_USER_APPS_HIDE, JSON.stringify(sanitized), userId);
    return await this.getApps(userId);
  }

  async unhideApp(userId, app) {
    const current = await this.getApps(userId);
    const hide = current.hide_app.filter(a => a !== app);
    await tableConfig.setConfigByKey(AppsService.KEY_USER_APPS_HIDE, JSON.stringify(hide), userId);
    return await this.getApps(userId);
  }

  async hideApp(userId, app) {
    const all = await this._getAllowedApps(userId);
    if (!all.includes(app)) return await this.getApps(userId);
    const current = await this.getApps(userId);
    const hide = current.hide_app;
    if (!hide.includes(app)) {
      hide.push(app);
      await tableConfig.setConfigByKey(AppsService.KEY_USER_APPS_HIDE, JSON.stringify(hide), userId);
    }
    return await this.getApps(userId);
  }

  async setAppsOrder(userId, orderApps) {
    const defaults = await this._getAllowedApps(userId);
    let sanitized = (Array.isArray(orderApps) ? orderApps : []).filter(a => defaults.includes(a));
    sanitized = Array.from(new Set(sanitized));
    await tableConfig.setConfigByKey(AppsService.KEY_USER_APPS_ORDER, JSON.stringify(sanitized), userId);
    return await this.getApps(userId);
  }
}

module.exports = AppsService;
