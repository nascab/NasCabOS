const { body, param, query, validationResult } = require('express-validator');
const { getLocalizedMessage } = require('../../../utils/i18nUtil');
const jwtUtil = require('../../../utils/jwtUtil');

function isAllSameChar(text) {
  return typeof text === 'string' && text.length > 1 && /^(.)\1+$/.test(text);
}

function isConsecutiveDigits(text) {
  if (typeof text !== 'string') return false;
  if (text.length < 3) return false;
  if (!/^\d+$/.test(text)) return false;
  let dir = 0;
  for (let i = 1; i < text.length; i += 1) {
    const diff = Number(text[i]) - Number(text[i - 1]);
    if (diff !== 1 && diff !== -1) return false;
    if (dir === 0) dir = diff;
    else if (diff !== dir) return false;
  }
  return true;
}

/**
 * 用户认证模块验证中间件整合文件
 * 包含所有认证相关的验证规则和错误处理
 */
class AuthValidation {
  /**
   * 创建超级管理员验证规则
   */
  static validateCreateSuperAdmin() {
    return [
      body('username')
        .notEmpty()
        .withMessage('USERNAME_REQUIRED')
        .isLength({ min: 3, max: 20 })
        .withMessage('USERNAME_LENGTH_INVALID')
        .matches(/^[a-zA-Z0-9_]+$/)
        .withMessage('USERNAME_FORMAT_INVALID'),

      body('password')
        .notEmpty()
        .withMessage('PASSWORD_REQUIRED')
        .isLength({ min: 6 })
        .withMessage('PASSWORD_TOO_SHORT')
        .custom((value, { req }) => {
          const passwordPlain = jwtUtil.decodeClientPassword(value);
          if (passwordPlain.length < 6) throw new Error('validation.PASSWORD_TOO_SHORT');
          if (isAllSameChar(passwordPlain)) throw new Error('validation.PASSWORD_REPEATED_CHAR');
          if (isConsecutiveDigits(passwordPlain)) throw new Error('validation.PASSWORD_CONSECUTIVE_NUMBERS');
          const username = req.body && req.body.username !== undefined ? String(req.body.username) : '';
          if (username && passwordPlain === username) throw new Error('validation.PASSWORD_SAME_AS_USERNAME');
          const answer = req.body && req.body.answer !== undefined ? String(req.body.answer) : '';
          if (answer && passwordPlain === answer) throw new Error('validation.PASSWORD_SAME_AS_SECURITY_ANSWER');
          return true;
        }),

      body('question').notEmpty().withMessage('SECURITY_QUESTION_REQUIRED').isLength({ min: 2, max: 100 }).withMessage('SECURITY_QUESTION_LENGTH_INVALID'),

      body('answer').notEmpty().withMessage('SECURITY_ANSWER_REQUIRED').isLength({ min: 2, max: 100 }).withMessage('SECURITY_ANSWER_LENGTH_INVALID'),
    ];
  }

  /**
   * 用户登录验证规则
   */
  static validateLogin() {
    return [body('username').notEmpty().withMessage('USERNAME_REQUIRED'), body('password').notEmpty().withMessage('PASSWORD_REQUIRED')];
  }

  static validateTwofaCode() {
    return [body('code').notEmpty().withMessage('validation.VALIDATION_ERROR').isString().withMessage('validation.VALIDATION_ERROR')];
  }

  static validateTwofaLoginVerify() {
    return [
      body('tempToken').notEmpty().withMessage('validation.VALIDATION_ERROR').isString().withMessage('validation.VALIDATION_ERROR'),
      body('code').notEmpty().withMessage('validation.VALIDATION_ERROR').isString().withMessage('validation.VALIDATION_ERROR'),
    ];
  }

  /**
   * 刷新令牌验证规则
   */
  static validateRefreshToken() {
    return [body('refreshToken').notEmpty().withMessage('REFRESH_TOKEN_REQUIRED')];
  }

  /**
   * 找回密码验证规则
   */
  static validateRecoverPassword() {
    return [
      body('username').notEmpty().withMessage('USERNAME_REQUIRED'),
      body('answer').notEmpty().withMessage('SECURITY_ANSWER_REQUIRED').isLength({ min: 2, max: 100 }).withMessage('SECURITY_ANSWER_LENGTH_INVALID'),
      body('newPassword')
        .notEmpty()
        .withMessage('PASSWORD_REQUIRED')
        .isLength({ min: 6 })
        .withMessage('PASSWORD_TOO_SHORT')
        .custom((value, { req }) => {
          const passwordPlain = jwtUtil.decodeClientPassword(value);
          if (passwordPlain.length < 6) throw new Error('validation.PASSWORD_TOO_SHORT');
          if (isAllSameChar(passwordPlain)) throw new Error('validation.PASSWORD_REPEATED_CHAR');
          if (isConsecutiveDigits(passwordPlain)) throw new Error('validation.PASSWORD_CONSECUTIVE_NUMBERS');
          const username = req.body && req.body.username !== undefined ? String(req.body.username) : '';
          if (username && passwordPlain === username) throw new Error('validation.PASSWORD_SAME_AS_USERNAME');
          const answer = req.body && req.body.answer !== undefined ? String(req.body.answer) : '';
          if (answer && passwordPlain === answer) throw new Error('validation.PASSWORD_SAME_AS_SECURITY_ANSWER');
          return true;
        }),
      body('code').optional().isString().withMessage('validation.VALIDATION_ERROR'),
      body('device_fingerprint').optional().isObject().withMessage('validation.VALIDATION_ERROR'),
    ];
  }

  /**
   * 更新用户信息验证规则
   */
  static validateUpdateProfile() {
    return [
      body('username')
        .optional()
        .isLength({ min: 3, max: 20 })
        .withMessage('USERNAME_LENGTH_INVALID')
        .matches(/^[a-zA-Z0-9_]+$/)
        .withMessage('USERNAME_FORMAT_INVALID'),

      body('password').optional().isLength({ min: 6 }).withMessage('PASSWORD_TOO_SHORT'),

      body('question').optional().isLength({ min: 2, max: 100 }).withMessage('SECURITY_QUESTION_LENGTH_INVALID'),

      body('answer').optional().isLength({ min: 2, max: 100 }).withMessage('SECURITY_ANSWER_LENGTH_INVALID'),
    ];
  }

  /**
   * ID参数验证规则
   */
  static validateIdParam() {
    return [param('id').isInt({ min: 1 }).withMessage('INVALID_ID_PARAM')];
  }

  /**
   * 分页查询参数验证规则
   */
  static validatePagination() {
    return [query('page').optional().isInt({ min: 1 }).withMessage('INVALID_PAGE_PARAM'), query('limit').optional().isInt({ min: 1, max: 100 }).withMessage('INVALID_LIMIT_PARAM')];
  }

  /**
   * 邮箱验证规则
   */
  static validateEmail() {
    return [body('email').isEmail().withMessage('INVALID_EMAIL_FORMAT').normalizeEmail()];
  }

  /**
   * 手机号验证规则
   */
  static validatePhone() {
    return [
      body('phone')
        .matches(/^1[3-9]\d{9}$/)
        .withMessage('INVALID_PHONE_FORMAT'),
    ];
  }

  /**
   * 文件上传验证规则
   */
  static validateFileUpload(fieldName = 'file', maxSizeMB = 10) {
    return [
      body(fieldName).custom((value, { req }) => {
        if (!req.file) {
          throw new Error('FILE_REQUIRED');
        }

        if (req.file.size > maxSizeMB * 1024 * 1024) {
          throw new Error('FILE_SIZE_EXCEEDED');
        }

        return true;
      }),
    ];
  }

  /**
   * 排序参数验证规则
   */
  static validateSortParams(allowedFields = []) {
    return [query('sortBy').optional().isIn(allowedFields).withMessage('INVALID_SORT_FIELD'), query('sortOrder').optional().isIn(['asc', 'desc']).withMessage('INVALID_SORT_ORDER')];
  }

  /**
   * 处理验证错误
   */
  static handleValidationErrors(req, res, next) {
    const errors = validationResult(req);

    if (!errors.isEmpty()) {
      const errorMessages = errors
        .array()
        .map(error => getLocalizedMessage(req, error.msg))
        .join(', ');

      return res.status(400).json({
        success: false,
        message: errorMessages,
      });
    }

    next();
  }

  /**
   * 异步验证错误处理（用于异步验证规则）
   */
  static async handleAsyncValidationErrors(req, res, next) {
    try {
      const errors = validationResult(req);

      if (!errors.isEmpty()) {
        const errorMessages = errors
          .array()
          .map(error => getLocalizedMessage(req, error.msg))
          .join(', ');

        return res.status(400).json({
          success: false,
          message: errorMessages,
        });
      }

      next();
    } catch (error) {
      next(error);
    }
  }

  /**
   * 自定义验证错误处理
   */
  static createCustomHandler(customErrorMapper = null) {
    return (req, res, next) => {
      const errors = validationResult(req);

      if (!errors.isEmpty()) {
        const errorMessages = errors
          .array()
          .map(error => {
            if (customErrorMapper && customErrorMapper[error.msg]) {
              return getLocalizedMessage(req, customErrorMapper[error.msg]);
            }

            return getLocalizedMessage(req, error.msg);
          })
          .join(', ');

        return res.status(400).json({
          success: false,
          message: errorMessages,
        });
      }

      next();
    };
  }
}

module.exports = AuthValidation;
