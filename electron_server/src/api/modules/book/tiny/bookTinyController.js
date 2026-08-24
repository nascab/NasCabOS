const fs = require('fs');
const path = require('path');
const ResponseUtil = require('../../../apiUtils/responseUtil');
const bookTinyUtil = require('../../../../workers/bookIndex/bookTinyUtil');
const BookListService = require('../list/bookListService');

class BookTinyController {
  async getTiny(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const q = req.query || {};
      const fileHash = String(q.file_hash ?? q.fileHash ?? '').trim();
      const size = Math.max(50, Math.min(2000, Number(q.size || 500) || 500));
      if (!fileHash) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);

      const service = new BookListService(req.dbBook);
      const indexRow = await service.getIndexByFileHash({ fileHash });
      if (!indexRow || !indexRow.id) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);

      const canAccess = await service.canUserAccessIndex({ user, indexRow });
      if (!canAccess) return ResponseUtil.forbidden(req, res);

      const coverState = Number(indexRow.cover_state || 0) || 0;
      if (coverState === 2) {
        return ResponseUtil.error(req, res, 'book.BOOK_TINY_NOT_AVAILABLE', 404);
      }

      const targetPath = bookTinyUtil.getTinyPathByHash(fileHash);
      if (!targetPath) {
        return ResponseUtil.error(req, res, 'book.BOOK_TINY_FAILED', 500);
      }

      try {
        const st = await fs.promises.stat(targetPath);
        if (st && st.isFile() && st.size > 0) {
          if (coverState !== 1) {
            await req
              .dbBook('book_index')
              .where({ id: indexRow.id })
              .update({ cover_state: 1 })
              .catch(() => {});
          }
          return res.sendFile(targetPath);
        }
      } catch (_) {}

      const fullPath = path.join(String(indexRow.path), String(indexRow.filename));
      const ok = await bookTinyUtil
        .ensureBookTiny({
          filePath: fullPath,
          fileHash,
          coverBuffer: null,
          size,
          timeoutMs: 30000,
        })
        .catch(() => false);

      await req
        .dbBook('book_index')
        .where({ id: indexRow.id })
        .update({ cover_state: ok ? 1 : 2 })
        .catch(() => {});

      if (!ok) {
        return ResponseUtil.error(req, res, 'book.BOOK_TINY_FAILED', 404);
      }

      return res.sendFile(targetPath);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'book.BOOK_TINY_FAILED';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'book.BOOK_TINY_FAILED' : msgKey, statusCode);
    }
  }
}

module.exports = new BookTinyController();
