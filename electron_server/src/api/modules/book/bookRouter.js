const express = require('express');
const router = express.Router();
const { authenticateJWT, requireAdmin } = require('../../middleware/authMiddleware');
const bookSourceController = require('./source/bookSourceController');
const bookListController = require('./list/bookListController');
const bookTinyController = require('./tiny/bookTinyController');
const bookArchiveController = require('./archive/bookArchiveController');
const bookHistoryController = require('./history/bookHistoryController');
const bookPreferenceController = require('./preference/bookPreferenceController');
const bookFavoriteController = require('./favorite/bookFavoriteController');
const bookCustomListController = require('./book_list/bookCustomListController');
const bookCollectionController = require('./collection/bookCollectionController');
const fileListController = require('../file/list/fileListController');

function createFileViewHandler(sourceType, action) {
  return (req, res) => {
    req.body = { ...(req.body || {}), sourceType };
    return fileListController[action](req, res);
  };
}

router.post('/source/list', authenticateJWT, requireAdmin, bookSourceController.listSources);
router.post('/source/add', authenticateJWT, requireAdmin, bookSourceController.addSource);
router.post('/source/delete', authenticateJWT, requireAdmin, bookSourceController.deleteSource);
router.post('/source/update/:id', authenticateJWT, requireAdmin, bookSourceController.updateSource);
router.post('/source/relocate/:id', authenticateJWT, requireAdmin, bookSourceController.relocateSource);
router.post('/source/scan', authenticateJWT, requireAdmin, bookSourceController.scanSource);

router.post('/list', authenticateJWT, bookListController.list);
router.post('/list/count', authenticateJWT, bookListController.count);
router.post('/delete', authenticateJWT, bookListController.deleteEntries);

router.post('/favorite/add', authenticateJWT, bookFavoriteController.add);
router.post('/favorite/remove', authenticateJWT, bookFavoriteController.remove);
router.post('/favorite/batch', authenticateJWT, bookFavoriteController.batch);

router.post('/collection/list', authenticateJWT, bookCollectionController.listCollections);
router.post('/collection/get', authenticateJWT, bookCollectionController.getCollection);
router.post('/collection/create', authenticateJWT, bookCollectionController.createCollection);
router.post('/collection/delete', authenticateJWT, bookCollectionController.deleteCollection);
router.post('/collection/update', authenticateJWT, bookCollectionController.updateCollection);

router.post('/book_list/list', authenticateJWT, bookCustomListController.list);
router.post('/book_list/get', authenticateJWT, bookCustomListController.get);
router.post('/book_list/create', authenticateJWT, bookCustomListController.create);
router.post('/book_list/update', authenticateJWT, bookCustomListController.update);
router.post('/book_list/delete', authenticateJWT, bookCustomListController.delete);
router.post('/book_list/index/add', authenticateJWT, bookCustomListController.addIndexes);
router.post('/book_list/index/remove', authenticateJWT, bookCustomListController.removeIndexes);

router.get('/tiny', authenticateJWT, bookTinyController.getTiny);
router.post('/archive/list', authenticateJWT, bookArchiveController.listArchiveImages);
router.get('/archive/file', authenticateJWT, bookArchiveController.getArchiveFile);
router.get('/history', authenticateJWT, bookHistoryController.get);
router.post('/history', authenticateJWT, bookHistoryController.upsert);
router.post('/history/list', authenticateJWT, bookHistoryController.list);
router.post('/history/clear', authenticateJWT, bookHistoryController.clear);
router.get('/preference', authenticateJWT, bookPreferenceController.get);
router.post('/preference', authenticateJWT, bookPreferenceController.upsert);
router.post('/file_view/list', authenticateJWT, createFileViewHandler('book', 'list'));
router.post('/file_view/search', authenticateJWT, createFileViewHandler('book', 'globalSearch'));

module.exports = router;
