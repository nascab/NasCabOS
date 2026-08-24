const express = require('express');
const router = express.Router();
const { authenticateJWT, requireSuperAdmin } = require('../../middleware/authMiddleware');
const AuthValidation = require('./authValidation');
const authController = require('./authController');

/**
 * 用户相关API路由
 * 路由层只负责HTTP请求的路由和中间件管理
 * 业务逻辑已分离到控制器层
 */

// 检测超级管理员是否存在
router.get('/hasSuperAdmin', authController.hasSuperAdmin);

// 获取服务器状态 用于判断是否是nascabos服务器
router.get('/isNasCabServer', (req, res) => {
  authController.isNasCabServer(req, res);
});

// 创建超级管理员
// router.post('/createSuperAdmin', AuthValidation.validateCreateSuperAdmin(), AuthValidation.handleValidationErrors, authController.createSuperAdmin);

// 用户登录
router.post('/login', AuthValidation.validateLogin(), AuthValidation.handleValidationErrors, authController.login);

// 登录2FA验证（无需JWT）
router.post('/2fa/login/verify', AuthValidation.validateTwofaLoginVerify(), AuthValidation.handleValidationErrors, authController.verify2faLogin);

// 刷新JWT token
router.post('/refreshJwt', AuthValidation.validateRefreshToken(), AuthValidation.handleValidationErrors, authController.refreshJwt);

// 获取找回管理员密码所需信息（无需登录，仅局域网，仅管理员账号）
router.get('/recoverInfo', authController.getRecoverInfo);

// 找回管理员密码（仅局域网）
router.post('/recoverPassword', AuthValidation.validateRecoverPassword(), AuthValidation.handleValidationErrors, authController.recoverPassword);

// 用户退出登录（需要认证）
router.post('/logout', authenticateJWT, authController.logout);

// 获取当前用户信息（需要认证）
router.get('/profile', authenticateJWT, authController.getProfile);

// 获取在线用户列表（需要认证，权限校验在Controller中）
// router.get('/online-users', authenticateJWT, authController.getOnlineUsers);

// 设备管理（需要认证）
router.get('/devices', authenticateJWT, authController.listDevices);
router.post('/devices/kick', authenticateJWT, authController.kickDevice);

// 2FA：当前用户（需要认证）
router.get('/2fa/status', authenticateJWT, authController.twofaStatus);
router.post('/2fa/setup', authenticateJWT, requireSuperAdmin, authController.twofaSetup);
router.post('/2fa/enable', authenticateJWT, requireSuperAdmin, AuthValidation.validateTwofaCode(), AuthValidation.handleValidationErrors, authController.twofaEnable);
router.post('/2fa/disable', authenticateJWT, requireSuperAdmin, AuthValidation.validateTwofaCode(), AuthValidation.handleValidationErrors, authController.twofaDisable);
router.post('/2fa/backup/rotate', authenticateJWT, requireSuperAdmin, AuthValidation.validateTwofaCode(), AuthValidation.handleValidationErrors, authController.twofaRotateBackupCodes);

module.exports = router;
