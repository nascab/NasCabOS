const { getLocalizedMessage } = require('../../utils/i18nUtil');

class ResponseUtil {
  static CODE_PWD_REQUIRED = 998;
  static CODE_PWD_ERROR = 999; //错误码 密码错误
  /**
   * 成功响应
   * @param {Object} req - 请求对象
   * @param {Object} res - 响应对象
   * @param {*} data - 响应数据
   * @param {string} messageKey - 国际化消息键
   * @param {number} statusCode - HTTP状态码
   */
  static success(req, res, data = null, messageKey = 'common.SUCCESS', statusCode = 200) {
    const response = {
      success: true,
      message: getLocalizedMessage(req, messageKey),
      data: data,
    };

    // 如果data为null，移除data字段
    if (data === null) {
      delete response.data;
    }

    return res.status(statusCode).json(response);
  }

  /**
   * 错误响应
   * @param {Object} req - 请求对象
   * @param {Object} res - 响应对象
   * @param {string} messageKey - 国际化消息键
   * @param {number} statusCode - HTTP状态码
   * @param {*} errorData - 错误详情
   */
  static error(req, res, messageKey, statusCode = 500, errorData = null, args = []) {
    const response = {
      success: false,
      message: getLocalizedMessage(req, messageKey, args),
      code: messageKey,
    };

    // 开发环境包含错误详情
    if (process.env.NODE_ENV === 'development' && errorData) {
      response.error = errorData;
    }
    return res.status(statusCode).json(response);
  }

  static errorWithArgs(req, res, messageKey, args = [], statusCode = 500) {
    return this.error(req, res, messageKey, statusCode, null, args);
  }

  /**
   * 验证错误响应
   * @param {Object} req - 请求对象
   * @param {Object} res - 响应对象
   * @param {Array} errors - 验证错误数组
   */
  static validationError(req, res, errors) {
    return res.status(400).json({
      success: false,
      message: getLocalizedMessage(req, 'validation.VALIDATION_ERROR'),
      code: 'VALIDATION_ERROR',
      errors: errors,
    });
  }

  /**
   * 未授权错误响应
   * @param {Object} req - 请求对象
   * @param {Object} res - 响应对象
   */
  static unauthorized(req, res) {
    return this.error(req, res, 'common.UNAUTHORIZED', 401);
  }

  /**
   * 禁止访问错误响应
   * @param {Object} req - 请求对象
   * @param {Object} res - 响应对象
   */
  static forbidden(req, res) {
    return this.error(req, res, 'common.FORBIDDEN', 403);
  }

  /**
   * 未找到错误响应
   * @param {Object} req - 请求对象
   * @param {Object} res - 响应对象
   * @param {string} resource - 资源名称
   */
  static notFound(req, res, resource = 'RESOURCE') {
    return this.error(req, res, `${resource}_NOT_FOUND`, 404);
  }

  /**
   * 服务器错误响应
   * @param {Object} req - 请求对象
   * @param {Object} res - 响应对象
   * @param {Error} error - 错误对象
   */
  static serverError(req, res, error) {
    console.error('Server Error:', error);
    return this.error(req, res, 'INTERNAL_SERVER_ERROR', 500);
  }

  /**
   * 分页响应
   * @param {Object} req - 请求对象
   * @param {Object} res - 响应对象
   * @param {Array} data - 数据数组
   * @param {number} total - 总记录数
   * @param {number} page - 当前页码
   * @param {number} limit - 每页数量
   */
  static paginated(req, res, data, total, page, limit) {
    const totalPages = Math.ceil(total / limit);

    return this.success(
      req,
      res,
      {
        items: data,
        pagination: {
          total,
          page: parseInt(page),
          limit: parseInt(limit),
          totalPages,
          hasNextPage: page < totalPages,
          hasPrevPage: page > 1,
        },
      },
      'SUCCESS'
    );
  }
}

module.exports = ResponseUtil;
