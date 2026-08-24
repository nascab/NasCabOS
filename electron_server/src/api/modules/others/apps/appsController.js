const AppsService = require('./appsService');
const ResponseUtil = require('../../../apiUtils/responseUtil');

class AppsController {
  constructor() {
    this.appsService = new AppsService();
  }

  getApps = async (req, res) => {
    try {
      const uid = req.user.id;
      const data = await this.appsService.getApps(uid);
      return ResponseUtil.success(req, res, data, 'GET_APPS_SUCCESS');
    } catch (error) {
      return ResponseUtil.serverError(req, res, error);
    }
  };

  setHideApps = async (req, res) => {
    try {
      const uid = req.user.id;
      const hideApps = req.body.hide_app || [];
      const data = await this.appsService.setHideApps(uid, hideApps);
      return ResponseUtil.success(req, res, data, 'SET_HIDE_APPS_SUCCESS');
    } catch (error) {
      return ResponseUtil.serverError(req, res, error);
    }
  };

  hideApp = async (req, res) => {
    try {
      const uid = req.user.id;
      const app = req.body.app;
      const data = await this.appsService.hideApp(uid, app);
      return ResponseUtil.success(req, res, data, 'HIDE_APP_SUCCESS');
    } catch (error) {
      return ResponseUtil.serverError(req, res, error);
    }
  };

  unhideApp = async (req, res) => {
    try {
      const uid = req.user.id;
      const app = req.body.app;
      const data = await this.appsService.unhideApp(uid, app);
      return ResponseUtil.success(req, res, data, 'UNHIDE_APP_SUCCESS');
    } catch (error) {
      return ResponseUtil.serverError(req, res, error);
    }
  };

  setAppsOrder = async (req, res) => {
    try {
      const uid = req.user.id;
      const orderApps = req.body.order_app || [];
      const data = await this.appsService.setAppsOrder(uid, orderApps);
      return ResponseUtil.success(req, res, data, 'SET_APPS_ORDER_SUCCESS');
    } catch (error) {
      return ResponseUtil.serverError(req, res, error);
    }
  };
}

module.exports = AppsController;
