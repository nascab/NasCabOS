const ResponseUtil = require('../../../apiUtils/responseUtil');
const BookSourceService = require('./bookSourceService');
const FileUtil = require('../../../../utils/fileUtil');
const fs = require('fs');

async function stopBookIndexWorkerBeforeDelete(timeoutMs = 8000) {
  const waitStopped = new Promise(resolve => {
    if (typeof process.send !== 'function') return resolve(false);

    const requestId = `${Date.now()}_${Math.random().toString(16).slice(2)}`;
    let done = false;
    const timer = setTimeout(
      () => {
        if (done) return;
        done = true;
        process.removeListener('message', onMessage);
        resolve(false);
      },
      Math.max(1000, Number(timeoutMs || 0) || 0)
    );

    const onMessage = message => {
      if (!message || message.type !== 'stopBookIndexWorkerResponse') return;
      if (!message.data || message.data.requestId !== requestId) return;
      if (done) return;
      done = true;
      clearTimeout(timer);
      process.removeListener('message', onMessage);
      resolve(!!message.data.stopped);
    };
    process.on('message', onMessage);

    try {
      process.send({ type: 'stopBookIndexWorker', data: { requestId } });
    } catch (_) {
      clearTimeout(timer);
      process.removeListener('message', onMessage);
      resolve(false);
    }
  });

  return await waitStopped;
}

class BookSourceController {
  async listSources(req, res) {
    try {
      const service = new BookSourceService(req.dbBook);
      const list = await service.listSources();
      const enriched = await Promise.all(
        (list || []).map(async row => {
          const p = row && row.path ? String(row.path) : '';
          let exists = false;
          if (p) {
            try {
              const stat = await fs.promises.stat(p);
              exists = !!(stat && stat.isDirectory());
            } catch (_) {}
          }
          return { ...row, exists };
        })
      );
      return ResponseUtil.success(req, res, enriched, 'book.BOOK_SOURCE_LIST_SUCCESS', 200);
    } catch (err) {
      return ResponseUtil.error(req, res, 'book.BOOK_SOURCE_LIST_FAILED', 500);
    }
  }

  async addSource(req, res) {
    try {
      const service = new BookSourceService(req.dbBook);
      const { path } = req.body || {};
      if (FileUtil.isProtectedPath(path)) {
        return ResponseUtil.error(req, res, 'file.SYSTEM_PROTECTED_PATH');
      }
      if (!fs.existsSync(path)) {
        return ResponseUtil.error(req, res, 'file.FOLDER_NOT_EXIST');
      }

      const result = await service.addSource(path);
      const statusCode = result.action === 'insert' ? 201 : 200;
      const messageKey = result.action === 'insert' ? 'book.BOOK_SOURCE_ADD_SUCCESS' : 'book.BOOK_SOURCE_UPDATE_SUCCESS';

      const scanPath = result && result.row && result.row.path ? String(result.row.path) : '';
      if (scanPath) {
        try {
          const exists = await req.dbBook('book_scan_task').where({ scan_path: scanPath }).first();
          if (!exists) {
            await req.dbBook('book_scan_task').insert({
              scan_path: scanPath,
              remark: 'source_add',
              create_time: new Date(),
            });
          }
          if (process.send) {
            process.send({ type: 'startBookIndexWorker', data: { scanPath } });
          }
        } catch (_) {}
      }
      if (process.send) {
        try {
          process.send({ type: 'resetBookWatchWorker' });
        } catch (_) {}
      }

      return ResponseUtil.success(req, res, result.row, messageKey, statusCode);
    } catch (err) {
      const msgKey = err && err.message ? err.message : 'common.ERROR';
      const statusCode = msgKey === 'book.BOOK_SOURCE_EXISTS' || msgKey === 'book.BOOK_SOURCE_PARENT_EXISTS' ? 409 : 400;
      if (err && err.args) {
        return ResponseUtil.errorWithArgs(req, res, msgKey, err.args, statusCode);
      }
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async scanSource(req, res) {
    try {
      const rawPath = req.body && req.body.path !== undefined ? req.body.path : req.body && req.body.scan_path !== undefined ? req.body.scan_path : '';
      const input = rawPath === undefined || rawPath === null ? '' : String(rawPath).trim();
      if (!input) {
        return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
      }

      let scanPaths = [];
      if (input === 'all') {
        const rows = await req
          .dbBook('book_source')
          .select('path')
          .catch(() => []);
        scanPaths = (rows || []).map(r => (r && r.path ? String(r.path) : '')).filter(Boolean);
      } else {
        const scanPath = input;
        const row = await req.dbBook('book_source').where({ path: scanPath }).first('id');
        if (!row || !row.id) {
          return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
        }
        scanPaths = [scanPath];
      }

      const unique = Array.from(new Set((scanPaths || []).map(p => (p ? String(p) : '')).filter(Boolean)));
      if (unique.length === 0) {
        return ResponseUtil.success(req, res, { inserted: 0 }, 'common.SUCCESS', 200);
      }

      const remark = input === 'all' ? 'source_scan_all' : 'source_scan';
      const inserted = await req.dbBook.transaction(async trx => {
        const existingRows = await trx('book_scan_task')
          .select('scan_path')
          .whereIn('scan_path', unique)
          .catch(() => []);
        const existing = new Set();
        for (const r of existingRows || []) {
          const s = r && r.scan_path ? String(r.scan_path) : '';
          if (s) existing.add(s);
        }

        const toInsert = [];
        for (const p of unique) {
          if (!existing.has(p)) {
            toInsert.push({
              scan_path: p,
              remark,
              create_time: new Date(),
            });
          }
        }

        if (toInsert.length === 0) return 0;
        await trx('book_scan_task').insert(toInsert);
        return toInsert.length;
      });

      if (process.send) {
        try {
          process.send({ type: 'startBookIndexWorker', data: { scanPath: input } });
        } catch (_) {}
      }

      return ResponseUtil.success(req, res, { inserted }, 'common.SUCCESS', 200);
    } catch (err) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async deleteSource(req, res) {
    try {
      await stopBookIndexWorkerBeforeDelete();
      const service = new BookSourceService(req.dbBook);
      const { id, path } = req.body || {};
      const affected = await service.deleteSource({ id, path });
      if (process.send) {
        try {
          process.send({ type: 'resetBookWatchWorker' });
        } catch (_) {}
      }
      if (process.send) {
        try {
          process.send({ type: 'startBookIndexWorker', data: {} });
        } catch (_) {}
      }
      return ResponseUtil.success(req, res, { affected }, 'book.BOOK_SOURCE_DELETE_SUCCESS', 200);
    } catch (err) {
      const msgKey = err && err.message ? err.message : 'common.ERROR';
      return ResponseUtil.error(req, res, msgKey, 400);
    }
  }

  async updateSource(req, res) {
    try {
      const service = new BookSourceService(req.dbBook);
      await stopBookIndexWorkerBeforeDelete();
      const id = req.params && req.params.id;
      const row = await service.updateSource(id, req.body || {});
      const scanPath = row && row.rescan_scan_path ? String(row.rescan_scan_path) : '';
      if (scanPath) {
        if (process.send) {
          try {
            process.send({ type: 'startBookIndexWorker', data: { scanPath } });
          } catch (_) {}
        }
      }
      if (process.send) {
        try {
          process.send({ type: 'resetBookWatchWorker' });
        } catch (_) {}
      }
      return ResponseUtil.success(req, res, row, 'book.BOOK_SOURCE_UPDATE_SUCCESS', 200);
    } catch (err) {
      const msgKey = err && err.message ? err.message : 'common.ERROR';
      const statusCode = msgKey === 'common.NOT_FOUND' ? 404 : 400;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async relocateSource(req, res) {
    try {
      await stopBookIndexWorkerBeforeDelete();
      const service = new BookSourceService(req.dbBook);
      const id = req.params && req.params.id;
      const { new_path: newPath } = req.body || {};
      if (FileUtil.isProtectedPath(newPath)) {
        return ResponseUtil.error(req, res, 'file.SYSTEM_PROTECTED_PATH');
      }
      if (!newPath) {
        return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
      }

      let stat;
      try {
        stat = await fs.promises.stat(String(newPath));
      } catch (_) {
        stat = null;
      }
      if (!stat || !stat.isDirectory()) {
        return ResponseUtil.error(req, res, 'file.FOLDER_NOT_EXIST', 400);
      }

      const result = await service.relocateSource(id, newPath);

      if (process.send) {
        try {
          process.send({ type: 'resetBookWatchWorker' });
        } catch (_) {}
      }

      return ResponseUtil.success(req, res, result, 'book.BOOK_SOURCE_RELOCATE_SUCCESS', 200);
    } catch (err) {
      const msgKey = err && err.message ? err.message : 'common.ERROR';
      const statusCode =
        msgKey === 'common.NOT_FOUND' ? 404 : msgKey === 'book.BOOK_SOURCE_EXISTS' || msgKey === 'book.BOOK_SOURCE_PARENT_EXISTS' ? 409 : 400;
      if (err && err.args) {
        return ResponseUtil.errorWithArgs(req, res, msgKey, err.args, statusCode);
      }
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }
}

module.exports = new BookSourceController();
