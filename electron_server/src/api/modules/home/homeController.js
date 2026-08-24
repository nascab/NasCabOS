const ResponseUtil = require('../../apiUtils/responseUtil');
const { MessageService } = require('../message/messageService');
const tableUser = require('../../../db/table/tableUser');

class HomeController {
  async config(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const userType = req.user.type || '';
      const isAdmin = userType === tableUser.TYPE_SUPER_ADMIN || userType === tableUser.TYPE_ADMIN;

      const service = new MessageService(req.dbMain);
      const cutoff = new Date(Date.now() - 72 * 60 * 60 * 1000);

      let query = service.knex(service.table).where('create_time', '>=', cutoff);
      if (isAdmin) {
        query = query.where(function () {
          this.where('is_public', 1).orWhere('is_public', 0);
        });
      } else {
        query = query.where(function () {
          this.where('is_public', 1).orWhere('uid', uid);
        });
      }

      const row = await query.orderBy('create_time', 'desc').first();
      const newMessage = row && typeof row.message === 'string' ? row.message : '';
      return ResponseUtil.success(req, res, { newMessage }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }
}

module.exports = new HomeController();
