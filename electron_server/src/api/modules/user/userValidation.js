const { body, query, param, validationResult } = require('express-validator');
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

function isAnyOrStringArray(value) {
  if (value === undefined || value === null) return true;
  if (value === 'ANY') return true;
  if (Array.isArray(value)) {
    return value.every(v => typeof v === 'string' && String(v).trim());
  }
  if (typeof value === 'string') {
    const text = value.trim();
    if (!text) return false;
    if (text === 'ANY') return true;
    try {
      const parsed = JSON.parse(text);
      return Array.isArray(parsed) && parsed.every(v => typeof v === 'string' && String(v).trim());
    } catch (_) {
      return true;
    }
  }
  return false;
}

const UserValidation = {
  validateListBody() {
    return [
      body('page').optional().isInt({ min: 1 }).withMessage('validation.PAGE_NUMBER_INVALID'),
      body('limit').optional().isInt({ min: 1, max: 100 }).withMessage('validation.LIMIT_INVALID'),
      body('keyword').optional().isLength({ min: 0, max: 100 }).withMessage('validation.KEYWORD_LENGTH_INVALID'),
    ];
  },

  validateCreateUser() {
    return [
      body('username').isString().isLength({ min: 3, max: 20 }).withMessage('validation.USERNAME_LENGTH_INVALID'),
      body('password')
        .isString()
        .isLength({ min: 6 })
        .withMessage('validation.PASSWORD_TOO_SHORT')
        .custom((value, { req }) => {
          const passwordPlain = jwtUtil.decodeClientPassword(value);
          if (passwordPlain.length < 6) throw new Error('validation.PASSWORD_TOO_SHORT');
          if (isAllSameChar(passwordPlain)) throw new Error('validation.PASSWORD_REPEATED_CHAR');
          if (isConsecutiveDigits(passwordPlain)) throw new Error('validation.PASSWORD_CONSECUTIVE_NUMBERS');
          const username = req.body && req.body.username !== undefined ? String(req.body.username) : '';
          if (username && passwordPlain === username) throw new Error('validation.PASSWORD_SAME_AS_USERNAME');
          return true;
        }),
      body('user_remark').optional({ nullable: true }).isString().isLength({ max: 500 }).withMessage('validation.VALIDATION_ERROR'),
      body('phone').optional({ nullable: true }).isString().isLength({ max: 32 }).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateUpdateUser() {
    return [
      param('id').isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      body('username').optional().isString().isLength({ min: 3, max: 20 }).withMessage('validation.USERNAME_LENGTH_INVALID'),
      body('password')
        .optional()
        .isString()
        .isLength({ min: 6 })
        .withMessage('validation.PASSWORD_TOO_SHORT')
        .custom(async (value, { req }) => {
          const passwordPlain = jwtUtil.decodeClientPassword(value);
          if (passwordPlain.length < 6) throw new Error('validation.PASSWORD_TOO_SHORT');
          if (isAllSameChar(passwordPlain)) throw new Error('validation.PASSWORD_REPEATED_CHAR');
          if (isConsecutiveDigits(passwordPlain)) throw new Error('validation.PASSWORD_CONSECUTIVE_NUMBERS');

          let username = req.body && req.body.username !== undefined ? String(req.body.username) : '';
          if (!username) {
            const id = Number(req.params && req.params.id);
            if (req.dbMain && Number.isFinite(id) && id > 0) {
              const user = await req.dbMain('user').where({ id }).select('username').first();
              username = user && user.username ? String(user.username) : '';
            }
          }
          if (username && passwordPlain === username) throw new Error('validation.PASSWORD_SAME_AS_USERNAME');
          return true;
        }),
      body('user_remark').optional({ nullable: true }).isString().isLength({ max: 500 }).withMessage('validation.VALIDATION_ERROR'),
      body('phone').optional({ nullable: true }).isString().isLength({ max: 32 }).withMessage('validation.VALIDATION_ERROR'),
      body('is_active').optional().isBoolean().withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateBatchDelete() {
    return [body('ids').isArray({ min: 1 }).withMessage('validation.VALIDATION_ERROR')];
  },

  validateSetPermissions() {
    return [
      param('uid').isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      body('permissions').isArray().withMessage('validation.VALIDATION_ERROR'),
      body('permissions.*.res_path').isString().withMessage('validation.VALIDATION_ERROR'),
      body('permissions.*.action').isIn(['view', 'download', 'update', 'delete', 'upload', 'share']).withMessage('validation.VALIDATION_ERROR'),
      body('permissions.*.res_type').optional().isIn(['file']).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateGetPermissions() {
    return [body('uid').isInt({ min: 1 }).withMessage('validation.ID_INVALID')];
  },

  validateGetUserFileLogs() {
    return [
      body('uid').isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      body('page').optional().isInt({ min: 1 }).withMessage('validation.PAGE_NUMBER_INVALID'),
      body('pageSize').optional().isInt({ min: 1, max: 200 }).withMessage('validation.LIMIT_INVALID'),
      body('types').optional({ nullable: true }).isArray().withMessage('validation.VALIDATION_ERROR'),
      body('types.*').optional().isString().withMessage('validation.VALIDATION_ERROR'),
      body('stateList').optional({ nullable: true }).isArray().withMessage('validation.VALIDATION_ERROR'),
      body('stateList.*').optional().isString().withMessage('validation.VALIDATION_ERROR'),
      body('keyword').optional().isLength({ min: 0, max: 100 }).withMessage('validation.KEYWORD_LENGTH_INVALID'),
    ];
  },

  validateTwofaUid() {
    return [body('uid').isInt({ min: 1 }).withMessage('validation.ID_INVALID')];
  },

  validateTwofaUidCode() {
    return [
      body('uid').isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      body('code').notEmpty().withMessage('validation.VALIDATION_ERROR').isString().withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateCreateScopedToken() {
    return [
      body('allow_api').optional().custom(isAnyOrStringArray).withMessage('validation.VALIDATION_ERROR'),
      body('allow_path').optional().custom(isAnyOrStringArray).withMessage('validation.VALIDATION_ERROR'),
      body('expiresIn')
        .optional()
        .isString()
        .matches(/^\d+[smhd]$/)
        .withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  handleValidationErrors(req, res, next) {
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
  },
};

module.exports = UserValidation;
