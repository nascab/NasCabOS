const express = require('express');
const router = express.Router();
const { authenticateJWT, requireAdmin } = require('../../middleware/authMiddleware');
const { requirePermission } = require('../../middleware/permissionMiddleware');
const { requireDownloadViewOrSubtitleUploadFile } = require('../../middleware/subtitleUploadRawAccess');
const listController = require('./list/fileListController');
const mkdirController = require('./mkdir/fileMkdirController');
const createController = require('./create/fileCreateController');
const deleteController = require('./delete/fileDeleteController');
const favoriteController = require('./favorite/fileFavoriteController');
const recentController = require('./recent/fileRecentController');
const rawController = require('./raw/fileRawController');
const tinyController = require('./tiny/fileTinyController');
const operationController = require('./operation/fileOperationController');
const logController = require('./log/fileLogController');
const renameController = require('./rename/fileRenameController');
const uploadController = require('./upload/uploadController');
const { uploadChunkStage } = require('./upload/uploadMiddleware');
const indexConfigController = require('./config/fileIndexConfigController');
const fileSystemController = require('./system/fileSystemController');
const userShareFolderController = require('./userShareFolder/userShareFolderController');
const userCustomPathController = require('./customPath/userCustomPathController');
const mergeLvpController = require('./mergeLvp/fileMergeLvpVideoController');

// 获取系统根目录候选
// roots接口一般用于浏览，可以视为对根路径的view权限，或者需要特殊处理（暂定view）
// router.post(
//   '/roots',
//   authenticateJWT,
//   requirePermission(['download', 'view'], { from: 'body.path' }),
//   fileController.getRoots
// );

// 列出指定目录内容
router.post('/list', authenticateJWT, listController.list);
router.post('/search', authenticateJWT, listController.globalSearch);

router.get('/userShareFolder/list', authenticateJWT, (req, res) => userShareFolderController.list(req, res));
router.post('/userShareFolder/add', authenticateJWT, requireAdmin, (req, res) => userShareFolderController.add(req, res));
router.post('/userShareFolder/remove', authenticateJWT, requireAdmin, (req, res) => userShareFolderController.remove(req, res));
router.post('/userShareFolder/allowDownload', authenticateJWT, requireAdmin, (req, res) => userShareFolderController.setAllowDownload(req, res));

router.post('/customPath/add', authenticateJWT, (req, res) => userCustomPathController.add(req, res));
router.post('/customPath/remove', authenticateJWT, (req, res) => userCustomPathController.remove(req, res));

// 读取索引开关：任意登录用户需要知道是否可全盘/子树检索；写配置仍仅管理员
router.get('/config/index', authenticateJWT, (req, res) =>
  indexConfigController.getIndexSettings(req, res)
);
router.post('/config/index', authenticateJWT, requireAdmin,(req, res) => indexConfigController.setIndexSettings(req, res));
router.post('/config/index/reset', authenticateJWT, requireAdmin,(req, res) => indexConfigController.resetIndex(req, res));

router.post('/mkdir/check', authenticateJWT, mkdirController.canMkdir);

// 新建文件夹
// 需要父目录的 upload/create 权限，这里用 upload 代表在目录下创建内容
router.post('/mkdir', authenticateJWT, requirePermission('upload', { from: 'body.base' }), mkdirController.mkdir);

// 新建文件 (txt/md)
// 需要父目录的 upload/create 权限，这里用 upload 代表在目录下创建内容
router.post('/create', authenticateJWT, requirePermission('upload', { from: 'body.base' }), createController.create);

// 添加收藏 (view 权限？)
router.post('/quick/favorites/add', authenticateJWT, favoriteController.add);

// 移除收藏
router.post('/quick/favorites/remove', authenticateJWT, favoriteController.remove);

// 清除最近访问记录
router.post('/quick/recent/clear', authenticateJWT, recentController.clear);

// 获取原始文件 (传raw=1) 或处理后的图片
router.get('/rawFile', authenticateJWT, requireDownloadViewOrSubtitleUploadFile, rawController.getRawFile);

// 从 merge LVP (OPPO 实况照片) JPEG 中提取并返回嵌入的 MP4 视频
router.get('/mergeLvpVideo', authenticateJWT, requirePermission(['download', 'view'], { from: 'query.path' }), (req, res) => mergeLvpController.getMergeLvpVideo(req, res));

// 获取文件缩略图
router.get('/tiny', authenticateJWT, requirePermission(['download', 'view'], { from: 'query.path' }), tinyController.getTiny);

// 获取文件属性
router.get('/attributes', authenticateJWT, requirePermission(['view'], { from: 'query.path' }), listController.getAttributes);
router.get('/attributes/resolve', authenticateJWT, listController.getResolvedAttributes);
router.get('/exists', authenticateJWT, listController.getExists);
router.get('/fs-access', authenticateJWT, requirePermission(['view'], { from: 'query.path' }), listController.getFsAccess);
router.get('/md5', authenticateJWT, requirePermission(['view'], { from: 'query.path' }), listController.getMd5);

// 文件下载
router.get(
  '/download',
  authenticateJWT,
  operationController.download
);

// 文件复制
router.post('/copy', authenticateJWT, (req, res) => operationController.copy(req, res));
// 文件移动
router.post('/move', authenticateJWT, (req, res) => operationController.move(req, res));
// 删除文件或文件夹
router.post('/delete', authenticateJWT, deleteController.remove);
// 文件操作日志列表
router.post('/log/list', authenticateJWT, requireAdmin,logController.list);
// 清除文件操作日期  需要 uid type state
router.post('/log/clear', authenticateJWT, requireAdmin,logController.clear);
// 取消文件操作任务
router.post('/cancel_file_operation', authenticateJWT, operationController.cancelFileOperation);

// 重命名文件或文件夹
router.post('/rename', authenticateJWT, requirePermission('update', { from: 'body.path' }), renameController.rename);

// --- 上传相关 ---

// Check uploaded chunks
router.post('/upload/check', authenticateJWT, requirePermission('upload', { from: 'body.targetDir' }), uploadController.checkChunk);

// Upload a chunk requirePermission必须在uploadChunkStage之后，否则拿不到参数
router.post('/upload/chunk', authenticateJWT, uploadChunkStage, requirePermission('upload', { from: 'body.targetDir' }), uploadController.uploadChunk);

// --- 本机文件系统操作（仅在客户端与服务端同机时有效）---

// 在系统中用默认程序打开文件/文件夹
router.post('/system/open', authenticateJWT, requirePermission('view', { from: 'body.path' }), (req, res) => fileSystemController.openInSystem(req, res));

// 在系统文件管理器中选中并显示文件/文件夹
router.post('/system/show', authenticateJWT, requirePermission('view', { from: 'body.path' }), (req, res) => fileSystemController.showInSystem(req, res));

module.exports = router;
