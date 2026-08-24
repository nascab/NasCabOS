const ResponseUtil = require('../../apiUtils/responseUtil');
const { MessageService } = require('./messageService');
const tableUser = require('../../../db/table/tableUser');

class MessageController {
  async list(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const query = req.query || {};
      const page = query.page || 1;
      const pageSize = query.pageSize || 20;
      const level = query.level;
      const keyword = query.keyword;

      const userType = req.user.type || '';
      const isAdmin = userType === tableUser.TYPE_SUPER_ADMIN || userType === tableUser.TYPE_ADMIN;

      const service = new MessageService(req.dbMain);
      const result = await service.getMessages({
        uid,
        page,
        pageSize,
        level,
        keyword,
        isAdmin,
      });

      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async add(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const title = body.title ?? '';
      const message = body.message;
      const action = body.action ?? null;
      const level = body.level ?? 0;
      const isPublic = body.isPublic ?? 1;

      if (!message || !message.trim()) {
        return ResponseUtil.error(req, res, 'message.MESSAGE_REQUIRED', 400);
      }

      const userType = req.user.type || '';
      const isAdmin = userType === tableUser.TYPE_SUPER_ADMIN || userType === tableUser.TYPE_ADMIN;

      if (!isAdmin && (isPublic === 0 || level > 0 || action !== null)) {
        return ResponseUtil.forbidden(req, res);
      }

      const service = new MessageService(req.dbMain);
      const result = await service.addMessage({
        uid,
        title,
        message,
        action,
        level,
        isPublic,
      });

      return ResponseUtil.success(req, res, result, 'message.ADD_SUCCESS', 201);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async markAsRead(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const messageId = body.messageId;

      const userType = req.user.type || '';
      const isAdmin = userType === tableUser.TYPE_SUPER_ADMIN || userType === tableUser.TYPE_ADMIN;

      const service = new MessageService(req.dbMain);
      const result = await service.markAsRead({
        uid,
        messageId,
        isAdmin,
      });

      return ResponseUtil.success(req, res, result, 'message.MARK_READ_SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async delete(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const messageId = body.messageId;

      if (!messageId) {
        return ResponseUtil.error(req, res, 'message.MESSAGE_ID_REQUIRED', 400);
      }

      const userType = req.user.type || '';
      const isAdmin = userType === tableUser.TYPE_SUPER_ADMIN || userType === tableUser.TYPE_ADMIN;

      const service = new MessageService(req.dbMain);
      const result = await service.deleteMessage({
        uid,
        messageId,
        isAdmin,
      });

      if (!result.deleted) {
        return ResponseUtil.error(req, res, 'message.MESSAGE_NOT_FOUND', 404);
      }

      return ResponseUtil.success(req, res, result, 'message.DELETE_SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async clear(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const level = body.level;

      const userType = req.user.type || '';
      const isAdmin = userType === tableUser.TYPE_SUPER_ADMIN || userType === tableUser.TYPE_ADMIN;

      const service = new MessageService(req.dbMain);
      const result = await service.clearMessages({
        uid,
        level,
        isAdmin,
      });

      return ResponseUtil.success(req, res, result, 'message.CLEAR_SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async getUnreadCount(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const userType = req.user.type || '';
      const isAdmin = userType === tableUser.TYPE_SUPER_ADMIN || userType === tableUser.TYPE_ADMIN;

      const service = new MessageService(req.dbMain);
      const count = await service.getUnreadCount({
        uid,
        isAdmin,
      });

      return ResponseUtil.success(req, res, { count }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }
}

module.exports = new MessageController();
