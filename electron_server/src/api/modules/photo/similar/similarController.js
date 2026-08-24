const ResponseUtil = require('../../../apiUtils/responseUtil');
const SimilarService = require('./similarService');
const tableConfig = require('../../../../db/table/tableConfig');

async function getEnableByKey(key) {
  try {
    const raw = await tableConfig.getConfigByKey(key);
    return raw === '1' ? 1 : 0;
  } catch (_) {
    return 0;
  }
}

class SimilarController {
  async listSimilarGroups(req, res) {
    try {
      const similarEnable = await getEnableByKey('ai_similar_enable');
      const body = req.body || {};
      const page = Math.max(1, Number(body.page) || 1);
      const pageSize = Math.max(1, Math.min(200, Number(body.pageSize ?? body.page_size) || 20));

      if (similarEnable !== 1) {
        return ResponseUtil.success(
          req,
          res,
          {
            similarEnable,
            items: [],
            pagination: { total: 0, page, pageSize },
          },
          'common.SUCCESS',
          200
        );
      }

      const service = new SimilarService(req.dbPhoto);
      const result = await service.listSimilarGroups({ ...body, page, pageSize });
      return ResponseUtil.success(req, res, { similarEnable, ...result }, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async batchDelete(req, res) {
    try {
      const body = req.body || {};
      const ids = body.ids ?? body.id_list ?? body.idList;
      if (!Array.isArray(ids)) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      const service = new SimilarService(req.dbPhoto);
      const deleted = await service.batchDeleteSimilarRecords(ids);
      return ResponseUtil.success(req, res, { deleted }, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async reset(req, res) {
    try {
      const service = new SimilarService(req.dbPhoto);
      const ok = await service.resetSimilarScan();
      if (ok && process.send) {
        try {
          process.send({ type: 'startSimilarScan' });
        } catch (_) {}
      }
      return ResponseUtil.success(req, res, { ok: !!ok }, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }
}

module.exports = new SimilarController();
