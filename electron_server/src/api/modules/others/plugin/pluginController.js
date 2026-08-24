const ResponseUtil = require('../../../apiUtils/responseUtil');
const Logger = require('../../../../utils/logger');
const remoteAssets = require('../../../../utils/remoteAssetsManager');

class PluginController {
  async getMountLibsStatus(req, res) {
    try {
      const data = remoteAssets.getMountLibsStatus();
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      Logger.error('plugin mountLibsStatus failed', e);
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }
}

module.exports = new PluginController();
