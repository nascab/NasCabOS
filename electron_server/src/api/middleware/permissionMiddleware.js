const { getLocalizedMessage } = require('../../utils/i18nUtil');
const { hasPermission } = require('../../utils/permissionUtil');

/**
 * 权限校验中间件工厂
 * 根据指定动作与资源路径字段，校验用户是否有权限
 * @param {string} action - 动作（view/download/update/delete/upload
 * @param {{from:string,type?:string}} options - 路径来源与资源类型
 *  - from: 资源路径来源字段（'query.path' | 'body.path' | 'params.path'）
 *  - type: 资源类型，默认 'file'
 */
function requirePermission(action, options = { from: 'query.path', type: 'file' }) {
  return async (req, res, next) => {
    try {
      if (!req.user) {
        return res.status(401).json({
          success: false,
          message: getLocalizedMessage(req, 'auth.AUTHENTICATION_REQUIRED'),
        });
      }

      const [scope, field] = options.from.split('.');
      const resPath = req[scope] && req[scope][field] ? req[scope][field] : '';
      const ok = await hasPermission(req.dbMain, req.user, action, resPath, options.type);
      if (!ok) {
        return res.status(403).json({
          success: false,
          message: getLocalizedMessage(req, 'auth.PERMISSION_DENIED'),
        });
      }
      return next();
    } catch (err) {
      return res.status(500).json({
        success: false,
        message: getLocalizedMessage(req, 'common.ERROR'),
      });
    }
  };
}

module.exports = {
  requirePermission,
};
