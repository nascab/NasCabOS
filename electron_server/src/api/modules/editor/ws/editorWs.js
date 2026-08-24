const path = require('path');
const fs = require('fs');
const { hasPermission, parseAnyOrArray, matchApi } = require('../../../../utils/permissionUtil');
const { decodeJWT } = require('../../../middleware/authMiddleware');
const { docManager } = require('../editorController');

function safeSend(ws, payload) {
  if (!ws) return;
  if (ws.readyState !== 1) return;
  try {
    ws.send(JSON.stringify(payload));
  } catch (_) {}
}

module.exports = app => {
  app.ws('/api/editor/ws', async (ws, req) => {
    const accessToken = req.query && req.query.accessToken;
    let targetPath = req.query && req.query.path;

    if (!accessToken || !targetPath) {
      ws.close(4000, 'accessToken or path is empty');
      return;
    }

    try {
      req.user = decodeJWT(req, accessToken);
      if (!req.user) {
        ws.close(4000, 'invalid accessToken');
        return;
      }
      req.user.id = req.user.userId || req.user.id || req.user.uid || req.user.user_id;

      if (req.user && req.user.tokenType === 'scoped') {
        const now = new Date();
        const tokenRecord = await req.dbMain('user_token').where({ token: accessToken, is_valid: true, type: 'scoped' }).andWhere('expire_time', '>', now).first();
        if (!tokenRecord) {
          ws.close(4000, 'invalid accessToken');
          return;
        }
        const allowApi = parseAnyOrArray(tokenRecord.allow_api);
        if (!matchApi(allowApi, '/api/editor/ws')) {
          ws.close(4000, 'no permission');
          return;
        }
        req.user.allow_api = allowApi;
        req.user.allow_path = parseAnyOrArray(tokenRecord.allow_path);
      }

      targetPath = decodeURIComponent(String(targetPath));
      const viewOk = await hasPermission(req.dbMain, req.user, 'view', targetPath);
      if (!viewOk) {
        ws.close(4000, 'no permission');
        return;
      }
    } catch (_) {
      ws.close(4000, 'auth check failed');
      return;
    }

    const resolved = path.resolve(String(targetPath));
    let docInfo = null;
    try {
      docInfo = await docManager.open({ filePath: resolved });
    } catch (e) {
      ws.close(4000, 'open failed');
      return;
    }

    const canWriteByPerm = await hasPermission(req.dbMain, req.user, 'update', resolved).catch(() => false);

    const canReadByFs = await fs.promises
      .access(resolved, fs.constants.R_OK)
      .then(() => true)
      .catch(() => false);
    if (!canReadByFs) {
      safeSend(ws, { type: 'error', message: 'common.FORBIDDEN' });
      ws.close(4000, 'no read permission');
      return;
    }

    let canWriteByFs = await fs.promises
      .access(resolved, fs.constants.W_OK)
      .then(() => true)
      .catch(() => false);
    if (!canWriteByFs) {
      const st = await fs.promises.stat(resolved).catch(() => null);
      if (st && st.isFile()) {
        await fs.promises.chmod(resolved, st.mode | 0o200).catch(() => null);
        canWriteByFs = await fs.promises
          .access(resolved, fs.constants.W_OK)
          .then(() => true)
          .catch(() => false);
      }
    }

    const canWrite = !!canWriteByPerm && !!canWriteByFs;
    docInfo.fsWritable = !!canWriteByFs;

    ws._editor = { docId: docInfo.docId, filePath: resolved, canWrite: !!canWrite };
    docManager.attachClient(docInfo, ws);

    safeSend(ws, {
      type: 'sync',
      docId: docInfo.docId,
      path: resolved,
      rev: docInfo.rev,
      text: docInfo.ytext.toString(),
      canWrite: !!canWrite,
    });

    ws.on('message', msg => {
      let data = null;
      try {
        data = JSON.parse(msg);
      } catch (_) {
        return;
      }
      if (!data || typeof data !== 'object') return;

      const info = ws._editor;
      if (!info) return;
      const current = docManager.getById(info.docId);
      if (!current) return;

      if (data.type === 'ping') {
        safeSend(ws, { type: 'pong', at: Date.now() });
        return;
      }

      if (data.type === 'op') {
        if (!info.canWrite || current.fsWritable === false) {
          safeSend(ws, { type: 'readonly' });
          return;
        }
        const baseRev = Number(data.rev);
        if (!Number.isFinite(baseRev) || baseRev !== current.rev) {
          safeSend(ws, {
            type: 'resync',
            docId: current.docId,
            rev: current.rev,
            text: current.ytext.toString(),
          });
          return;
        }

        const ops = Array.isArray(data.ops) ? data.ops : null;
        if (!ops) return;

        const applied = docManager.applyOps(current, ops);
        if (!applied.ok) {
          safeSend(ws, { type: 'error', message: 'invalid_ops' });
          return;
        }

        docManager.scheduleSave(current, {
          onError: e => {
            const code = e && e.code ? String(e.code) : '';
            if (code === 'EACCES' || code === 'EPERM' || code === 'EROFS') {
              current.fsWritable = false;
              for (const client of current.clients) {
                if (client && client._editor) client._editor.canWrite = false;
                safeSend(client, { type: 'readonly' });
              }
            }
          },
        });

        safeSend(ws, { type: 'ack', rev: applied.rev });
        for (const client of current.clients) {
          if (client === ws) continue;
          safeSend(client, { type: 'op', rev: applied.rev, ops: applied.ops });
        }
      }
    });

    let cleaned = false;
    const cleanup = () => {
      if (cleaned) return;
      cleaned = true;
      try {
        const info = ws._editor;
        delete ws._editor;
        if (!info) return;
        const current = docManager.getById(info.docId);
        if (!current) return;
        docManager.detachClient(current, ws);
      } catch (_) {}
    };

    ws.on('close', cleanup);
    ws.on('error', cleanup);
  });
};
