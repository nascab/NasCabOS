const ResponseUtil = require('../../../apiUtils/responseUtil');
const GpsSupplementService = require('./gpsSupplementService');

class GpsSupplementController {
  async status(req, res) {
    try {
      const service = new GpsSupplementService(req.dbPhoto);
      const result = await service.getStatus();
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (_) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async startScan(req, res) {
    try {
      if (process.send) {
        try {
          process.send({ type: 'startGpsSupplementScan' });
        } catch (_) {}
      }
      const service = new GpsSupplementService(req.dbPhoto);
      const result = await service.getStatus();
      return ResponseUtil.success(req, res, { ok: true, ...result }, 'common.SUCCESS', 200);
    } catch (_) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async apply(req, res) {
    try {
      const body = req.body || {};
      const batchId = Number(body.batchId ?? body.batch_id);
      const latitude = Number(body.latitude);
      const longitude = Number(body.longitude);
      const selectedIdsRaw = Array.isArray(body.photoIds)
        ? body.photoIds
        : (Array.isArray(body.photo_ids) ? body.photo_ids : []);
      if (!batchId || !Number.isFinite(latitude) || !Number.isFinite(longitude)) {
        return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      }

      const service = new GpsSupplementService(req.dbPhoto);
      const affected = await service.applyBatchGps(
        batchId,
        latitude,
        longitude,
        selectedIdsRaw,
      );
      return ResponseUtil.success(req, res, { ok: true, affected }, 'common.SUCCESS', 200);
    } catch (e) {
      const statusCode = Number(e && e.statusCode) || 500;
      const errorKey = e && e.message ? String(e.message) : 'common.ERROR';
      return ResponseUtil.error(req, res, errorKey, statusCode);
    }
  }

  async skip(req, res) {
    try {
      const body = req.body || {};
      const batchId = Number(body.batchId ?? body.batch_id);
      if (!batchId) {
        return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      }

      const service = new GpsSupplementService(req.dbPhoto);
      const ok = await service.skipBatch(batchId);
      if (!ok) {
        return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
      }
      return ResponseUtil.success(req, res, { ok: true }, 'common.SUCCESS', 200);
    } catch (_) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async reset(req, res) {
    try {
      const service = new GpsSupplementService(req.dbPhoto);
      const result = await service.resetAll();
      const status = await service.getStatus();
      return ResponseUtil.success(
        req,
        res,
        { ok: true, ...result, ...status },
        'common.SUCCESS',
        200
      );
    } catch (_) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }
}

module.exports = new GpsSupplementController();
