const ResponseUtil = require('../../../apiUtils/responseUtil');
const Logger = require('../../../../utils/logger');
const userUtil = require('../../../../utils/userUtil');
class HwController {
  async getMetrics(req, res) {
    try {
      if (!req.user || !userUtil.isAdmin(req.user)) {
        return ResponseUtil.success(req, res, {}, 'common.SUCCESS');
      }

      const metrics = await new Promise((resolve, reject) => {
        const requestId = `${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
        let settled = false;
        const cleanup = () => {
          clearTimeout(timeout);
          process.off('message', handleResponse);
        };
        const resolveOnce = payload => {
          if (settled) return;
          settled = true;
          cleanup();
          resolve(payload);
        };
        const rejectOnce = error => {
          if (settled) return;
          settled = true;
          cleanup();
          reject(error);
        };
        const handleResponse = message => {
          if (!message || message.type !== 'getHwMetricsResponse') return;
          const incomingRequestId = message?.data?.requestId == null ? '' : String(message.data.requestId);
          if (incomingRequestId && incomingRequestId !== requestId) return;
          const payload = message?.data && typeof message.data === 'object' ? message.data.payload || {} : {};
          resolveOnce(payload);
        };
        const timeout = setTimeout(() => rejectOnce(new Error('获取硬件监控数据超时')), 3000);

        process.on('message', handleResponse);
        if (!process.send) {
          resolveOnce({});
          return;
        }
        try {
          process.send({
            type: 'getHwMetrics',
            data: { requestId },
            timestamp: Date.now(),
          });
        } catch (e) {
          rejectOnce(e);
        }
      });

      return ResponseUtil.success(req, res, metrics || {}, 'common.SUCCESS');
    } catch (err) {
      Logger.error('Hardware metrics failed', err, { method: 'getMetrics' });
      return ResponseUtil.success(req, res, {}, 'common.SUCCESS');
    }
  }
}

module.exports = new HwController();
