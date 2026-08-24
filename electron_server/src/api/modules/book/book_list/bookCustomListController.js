const ResponseUtil = require('../../../apiUtils/responseUtil');
const BookCustomListService = require('./bookCustomListService');

class BookCustomListController {
  async list(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const service = new BookCustomListService(req.dbBook);
      const result = await service.listLists(req.body || {}, user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      console.log(e);
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  async get(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const listId = req.body && (req.body.list_id ?? req.body.listId ?? req.body.id);
      if (!listId) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);

      const service = new BookCustomListService(req.dbBook);
      const result = await service.getList({ listId, user });
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  async create(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const name = req.body && req.body.name;
      if (!name) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);

      const service = new BookCustomListService(req.dbBook);
      const result = await service.createList({ name, user });
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 201);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 400;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  async update(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const listId = req.body && (req.body.list_id ?? req.body.listId ?? req.body.id);
      const name = req.body && req.body.name;
      if (!listId || !name) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);

      const service = new BookCustomListService(req.dbBook);
      const result = await service.updateList({ listId, name, user });
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 400;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  async delete(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const listId = req.body && (req.body.list_id ?? req.body.listId ?? req.body.id);
      if (!listId) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);

      const service = new BookCustomListService(req.dbBook);
      const ok = await service.deleteList({ listId, user });
      return ResponseUtil.success(req, res, ok, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 400;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  async addIndexes(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const listId = body.list_id ?? body.listId ?? body.id;
      const indexIds = body.index_ids ?? body.indexIds ?? body.index_id ?? body.indexId;
      if (!listId || !indexIds) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);

      const service = new BookCustomListService(req.dbBook);
      const ok = await service.addListIndexes({ listId, indexIds, user });
      return ResponseUtil.success(req, res, ok, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 400;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  async removeIndexes(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const listId = body.list_id ?? body.listId ?? body.id;
      const indexIds = body.index_ids ?? body.indexIds ?? body.index_id ?? body.indexId;
      if (!listId || !indexIds) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);

      const service = new BookCustomListService(req.dbBook);
      const ok = await service.removeListIndexes({ listId, indexIds, user });
      return ResponseUtil.success(req, res, ok, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 400;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }
}

module.exports = new BookCustomListController();
