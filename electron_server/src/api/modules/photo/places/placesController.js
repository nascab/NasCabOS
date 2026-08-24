const ResponseUtil = require('../../../apiUtils/responseUtil');
const Logger = require('../../../../utils/logger');
const PlacesService = require('./placesService');
const { getUserLanguage } = require('../../../../utils/i18nUtil');
const tableConfig = require('../../../../db/table/tableConfig');
const photoTimeLineService = require('../timeline/photoTimeLineService');
const userUtil = require('../../../../utils/userUtil');

async function getEnableByKey(key) {
  try {
    const raw = await tableConfig.getConfigByKey(key);
    return raw === '1' ? 1 : 0;
  } catch (_) {
    return 0;
  }
}

class PlacesController {
  async listPlaces(req, res) {
    try {
      const placeEnable = await getEnableByKey('ai_place_enable');
      if (placeEnable !== 1) {
        return ResponseUtil.success(
          req,
          res,
          {
            placeEnable,
            items: [],
            pagination: { total: 0, page: 1, pageSize: 0 },
          },
          'common.SUCCESS',
          200
        );
      }
      const locale = getUserLanguage(req);
      let validPaths;
      if (req.user && !userUtil.isAdmin(req.user)) {
        const validPathsRaw = await photoTimeLineService.getValidPaths(req.user);
        validPaths = (validPathsRaw || []).map(p => (p ? String(p) : '')).filter(Boolean);
      }
      const service = new PlacesService(req.dbPhoto);
      const result = await service.listPlaces({ ...(req.body || {}), locale, ...(validPaths !== undefined ? { validPaths } : {}) });
      return ResponseUtil.success(req, res, { placeEnable, ...result }, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('listPlaces error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async setPlaceStatus(req, res) {
    try {
      const service = new PlacesService(req.dbPhoto);
      const result = await service.updatePlaceStatus(req.body || {});
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      Logger.error('setPlaceStatus error:', e);
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : msgKey === 'common.NOT_FOUND' ? 404 : msgKey === 'common.PARAM_ERROR' ? 400 : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async resetPlaces(req, res) {
    try {
      const service = new PlacesService(req.dbPhoto);
      const result = await service.resetPlacesRecognition();
      const placeEnable = await getEnableByKey('ai_place_enable');
      if (placeEnable === 1 && process.send) {
        try {
          process.send({ type: 'toggleAiPlace', data: { enable: 1 } });
        } catch (_) {}
      }
      return ResponseUtil.success(
        req,
        res,
        { ok: true, ...result },
        'common.SUCCESS',
        200
      );
    } catch (e) {
      Logger.error('resetPlaces error:', e);
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }
}

module.exports = new PlacesController();
