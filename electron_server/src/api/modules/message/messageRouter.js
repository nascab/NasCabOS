const express = require('express');
const router = express.Router();
const { authenticateJWT } = require('../../middleware/authMiddleware');
const messageController = require('./messageController');

router.get('/list', authenticateJWT, (req, res) => messageController.list(req, res));
router.post('/add', authenticateJWT, (req, res) => messageController.add(req, res));
router.post('/markAsRead', authenticateJWT, (req, res) => messageController.markAsRead(req, res));
router.post('/delete', authenticateJWT, (req, res) => messageController.delete(req, res));
router.post('/clear', authenticateJWT, (req, res) => messageController.clear(req, res));
router.get('/unreadCount', authenticateJWT, (req, res) => messageController.getUnreadCount(req, res));

module.exports = router;
