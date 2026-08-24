const express = require('express');
const router = express.Router();
const { authenticateJWT, requireSuperAdmin } = require('../../middleware/authMiddleware');
const UserValidation = require('./userValidation');
const userController = require('./userController');

// 获取用户列表（仅超级管理员）
router.post('/list', authenticateJWT, requireSuperAdmin, UserValidation.validateListBody(), UserValidation.handleValidationErrors, userController.listUsers);

// 创建子用户（仅超级管理员）：body 含 username、password；可选 user_remark、phone（密保由服务端占位，客户端勿传 question/answer）
router.post('/create', authenticateJWT, requireSuperAdmin, UserValidation.validateCreateUser(), UserValidation.handleValidationErrors, userController.createUser);

// 更新用户（仅超级管理员）：可选 username、password、is_active、user_remark、phone
router.post('/update/:id', authenticateJWT, requireSuperAdmin, UserValidation.validateUpdateUser(), UserValidation.handleValidationErrors, userController.updateUser);

// 批量删除用户（仅超级管理员）
router.post('/delete', authenticateJWT, requireSuperAdmin, UserValidation.validateBatchDelete(), UserValidation.handleValidationErrors, userController.deleteUsers);

// 获取用户权限（仅超级管理员）
router.post('/permissions/get', authenticateJWT, requireSuperAdmin, UserValidation.validateGetPermissions(), UserValidation.handleValidationErrors, userController.getUserPermissions);

// 设置用户权限（覆盖式，支持批量）（仅超级管理员）
router.post('/permissions/:uid', authenticateJWT, requireSuperAdmin, UserValidation.validateSetPermissions(), UserValidation.handleValidationErrors, userController.setUserPermissions);

// 获取用户登录记录（仅超级管理员）
router.post('/login-records', authenticateJWT, requireSuperAdmin, UserValidation.validateGetPermissions(), UserValidation.handleValidationErrors, userController.getLoginRecords);

// 获取用户文件操作日志（仅超级管理员）
router.post('/file-log/list', authenticateJWT, requireSuperAdmin, UserValidation.validateGetUserFileLogs(), UserValidation.handleValidationErrors, userController.getUserFileLogs);

// 用户2FA管理（仅超级管理员）
router.post('/2fa/status', authenticateJWT, requireSuperAdmin, UserValidation.validateTwofaUid(), UserValidation.handleValidationErrors, userController.getUser2faStatus);
router.post('/2fa/setup', authenticateJWT, requireSuperAdmin, UserValidation.validateTwofaUid(), UserValidation.handleValidationErrors, userController.setupUser2fa);
router.post('/2fa/enable', authenticateJWT, requireSuperAdmin, UserValidation.validateTwofaUidCode(), UserValidation.handleValidationErrors, userController.enableUser2fa);
router.post('/2fa/reset', authenticateJWT, requireSuperAdmin, UserValidation.validateTwofaUid(), UserValidation.handleValidationErrors, userController.resetUser2fa);

router.post('/token/scoped', authenticateJWT, UserValidation.validateCreateScopedToken(), UserValidation.handleValidationErrors, userController.createScopedToken);

module.exports = router;
