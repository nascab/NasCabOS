const express = require('express');
const { authenticateJWT } = require('../../middleware/authMiddleware');
const notesController = require('./notesController');

const router = express.Router();

router.post('/notebook/status', authenticateJWT, notesController.getNotebookStatus);
router.post('/notebook/select', authenticateJWT, notesController.selectNotebook);

router.post('/state', authenticateJWT, notesController.getState);

router.post('/group/create', authenticateJWT, notesController.createGroup);
router.post('/group/update', authenticateJWT, notesController.updateGroup);
router.post('/group/delete', authenticateJWT, notesController.deleteGroup);
router.post('/group/reorder', authenticateJWT, notesController.reorderGroups);

router.post('/note/create', authenticateJWT, notesController.createNote);
router.post('/note/detail', authenticateJWT, notesController.getNoteDetail);
router.post('/note/save', authenticateJWT, notesController.saveNote);
router.post('/note/meta', authenticateJWT, notesController.updateNoteMeta);
router.post('/note/move', authenticateJWT, notesController.moveNote);
router.post('/note/batchMove', authenticateJWT, notesController.batchMoveNotes);
router.post('/note/delete', authenticateJWT, notesController.deleteNote);
router.post('/note/batchDelete', authenticateJWT, notesController.batchDeleteNotes);
router.post('/note/restore', authenticateJWT, notesController.restoreNote);
router.post('/note/batchRestore', authenticateJWT, notesController.batchRestoreNotes);
router.post('/note/permanentDelete', authenticateJWT, notesController.permanentlyDeleteNote);
router.post(
  '/note/batchPermanentDelete',
  authenticateJWT,
  notesController.batchPermanentlyDeleteNotes,
);
router.post('/note/uploadAsset', authenticateJWT, notesController.uploadAsset);
router.get('/note/asset', authenticateJWT, notesController.getAsset);
router.get('/note/export', authenticateJWT, notesController.exportNote);

module.exports = router;
