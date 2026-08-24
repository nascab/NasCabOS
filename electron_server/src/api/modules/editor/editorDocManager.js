const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const Y = require('yjs');

const MAX_EDITOR_FILE_BYTES = 20 * 1024 * 1024;

function buildDocId(filePath) {
  return crypto.createHash('sha1').update(String(filePath)).digest('hex');
}

function isValidOp(op) {
  if (!op || typeof op !== 'object') return false;
  if (Object.prototype.hasOwnProperty.call(op, 'retain')) {
    const n = Number(op.retain);
    return Number.isFinite(n) && n >= 0;
  }
  if (Object.prototype.hasOwnProperty.call(op, 'delete')) {
    const n = Number(op.delete);
    return Number.isFinite(n) && n >= 0;
  }
  if (Object.prototype.hasOwnProperty.call(op, 'insert')) {
    return typeof op.insert === 'string';
  }
  return false;
}

function normalizeOps(rawOps) {
  if (!Array.isArray(rawOps)) return null;
  const ops = [];
  for (const op of rawOps) {
    if (!isValidOp(op)) return null;
    if (op.retain !== undefined) {
      const n = Math.trunc(Number(op.retain));
      if (n > 0) ops.push({ retain: n });
    } else if (op.delete !== undefined) {
      const n = Math.trunc(Number(op.delete));
      if (n > 0) ops.push({ delete: n });
    } else if (op.insert !== undefined) {
      const s = String(op.insert);
      if (s.length > 0) ops.push({ insert: s });
    }
  }
  return ops;
}

function applyOpsToYText(ytext, ops) {
  let index = 0;
  const len = ytext.length;
  for (const op of ops) {
    if (op.retain !== undefined) {
      index += op.retain;
      continue;
    }
    if (op.delete !== undefined) {
      const del = op.delete;
      if (del > 0) {
        const safeIndex = Math.max(0, Math.min(index, ytext.length));
        const safeDel = Math.max(0, Math.min(del, ytext.length - safeIndex));
        if (safeDel > 0) {
          ytext.delete(safeIndex, safeDel);
        }
      }
      continue;
    }
    if (op.insert !== undefined) {
      const ins = op.insert;
      if (ins) {
        const safeIndex = Math.max(0, Math.min(index, ytext.length));
        ytext.insert(safeIndex, ins);
        index += ins.length;
      }
    }
  }
  if (index < 0 || index > len + 1) {
    return;
  }
}

class EditorDocManager {
  constructor() {
    this._docs = new Map();
  }

  _flushSaveNow(docInfo) {
    if (!docInfo || !docInfo.filePath) return;
    const text = docInfo.ytext ? docInfo.ytext.toString() : '';
    fs.promises.writeFile(docInfo.filePath, text, 'utf8').catch(() => null);
  }

  async open({ filePath }) {
    const resolved = path.resolve(String(filePath));
    const st = await fs.promises.stat(resolved).catch(() => null);
    if (!st || !st.isFile()) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }
    if (st.size > MAX_EDITOR_FILE_BYTES) {
      const err = new Error('editor.FILE_TOO_LARGE');
      err.statusCode = 413;
      throw err;
    }
    const docId = buildDocId(resolved);
    const existing = this._docs.get(docId);
    if (existing) {
      existing.lastAccessAt = Date.now();
      if (existing.clients.size === 0) {
        const content = await fs.promises.readFile(resolved, 'utf8').catch(() => null);
        if (content !== null) {
          const currentText = existing.ytext.toString();
          if (currentText !== content) {
            existing.ydoc.transact(() => {
              existing.ytext.delete(0, existing.ytext.length);
              if (content) {
                existing.ytext.insert(0, content);
              }
            });
            existing.rev = 0;
          }
        }
      }
      return existing;
    }

    const content = await fs.promises.readFile(resolved, 'utf8');

    const ydoc = new Y.Doc();
    const ytext = ydoc.getText('content');
    if (content) {
      ytext.insert(0, content);
    }

    const docInfo = {
      docId,
      filePath: resolved,
      ydoc,
      ytext,
      rev: 0,
      clients: new Set(),
      saveTimer: null,
      lastAccessAt: Date.now(),
      fsWritable: true,
    };
    this._docs.set(docId, docInfo);
    return docInfo;
  }

  getById(docId) {
    return this._docs.get(String(docId));
  }

  attachClient(docInfo, ws) {
    docInfo.clients.add(ws);
    docInfo.lastAccessAt = Date.now();
  }

  detachClient(docInfo, ws) {
    docInfo.clients.delete(ws);
    docInfo.lastAccessAt = Date.now();
    if (docInfo.clients.size === 0) {
      if (docInfo.saveTimer) {
        clearTimeout(docInfo.saveTimer);
        docInfo.saveTimer = null;
        this._flushSaveNow(docInfo);
      }
      setTimeout(() => {
        const current = this._docs.get(docInfo.docId);
        if (!current) return;
        if (current.clients.size > 0) return;
        const staleMs = 5 * 60 * 1000;
        if (Date.now() - current.lastAccessAt >= staleMs) {
          this._docs.delete(docInfo.docId);
          try {
            current.ydoc.destroy();
          } catch (_) {}
        }
      }, 10 * 1000);
    }
  }

  scheduleSave(docInfo, { delayMs = 800, onError } = {}) {
    if (docInfo.saveTimer) clearTimeout(docInfo.saveTimer);
    docInfo.saveTimer = setTimeout(
      async () => {
        docInfo.saveTimer = null;
        const text = docInfo.ytext.toString();
        try {
          await fs.promises.writeFile(docInfo.filePath, text, 'utf8');
        } catch (e) {
          if (typeof onError === 'function') onError(e);
        }
      },
      Math.max(50, Number(delayMs) || 800)
    );
  }

  applyOps(docInfo, ops) {
    const normalized = normalizeOps(ops);
    if (!normalized) return { ok: false, reason: 'invalid_ops' };

    docInfo.ydoc.transact(() => {
      applyOpsToYText(docInfo.ytext, normalized);
    });
    docInfo.rev += 1;
    docInfo.lastAccessAt = Date.now();
    return { ok: true, rev: docInfo.rev, ops: normalized };
  }
}

module.exports = {
  EditorDocManager,
  buildDocId,
  normalizeOps,
};
