const fs = require('fs');
const path = require('path');
const archiver = require('archiver');
const Logger = require('../../../utils/logger');
const ResponseUtil = require('../../apiUtils/responseUtil');
const config = require('../../../config/config');
const sharpUtils = require('../../../utils/sharpUtils');
const fileService = require('../file/core/fileService');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { verifyQuickSharePwd, getQuickShareBruteKey, isQuickShareBruteLocked, recordQuickShareBruteFailure, clearQuickShareBruteOnSuccess } = require('../../middleware/quickShareAuthMiddleware');
const QuickShareBinary = require('./quickShareBinary');

function _toRelJoin(baseRel, name) {
  const a = typeof baseRel === 'string' ? baseRel.trim() : '';
  const b = typeof name === 'string' ? name.trim() : '';
  if (!a) return b;
  if (!b) return a;
  return `${a.replace(/\/+$/, '')}/${b.replace(/^\/+/, '')}`;
}

async function _statToItem(absPath, relPath, nameHint = null) {
  const resolved = path.resolve(String(absPath || ''));
  const st = await fs.promises.stat(resolved);
  const isDir = st.isDirectory();
  const name = nameHint || path.basename(resolved) || resolved;
  const ext = isDir ? '' : path.extname(resolved).toLowerCase();
  const type = isDir ? 'dir' : config.getFileType(ext);
  return {
    name,
    relPath,
    type,
    size: isDir ? null : st.size,
    mtimeMs: st.mtimeMs,
    ctimeMs: st.birthtimeMs || st.ctimeMs || null,
    ext,
  };
}

function _buildSegments(relBase) {
  const raw = typeof relBase === 'string' ? relBase.trim() : '';
  const parts = raw ? raw.split('/').filter(Boolean) : [];
  const segs = [{ name: '/', relPath: '' }];
  let acc = '';
  for (const p of parts) {
    acc = _toRelJoin(acc, p);
    segs.push({ name: p, relPath: acc });
  }
  return segs;
}

function _readToken(req) {
  const q = req.query || {};
  const b = req.body || {};
  const v = q.qt ?? q.token ?? b.qt ?? b.token;
  return typeof v === 'string' ? v.trim() : String(v || '').trim();
}

function _readPwd(req) {
  const b = req.body || {};
  const v = b.pwd ?? b.password;
  return typeof v === 'string' ? v : v == null ? '' : String(v);
}

function _readPwdHash(req) {
  const b = req.body || {};
  const v = b.pwdHash ?? b.passwordHash ?? b.pwh;
  return typeof v === 'string' ? v : v == null ? '' : String(v);
}

function _sha256Hex(text) {
  return crypto
    .createHash('sha256')
    .update(String(text ?? ''), 'utf8')
    .digest('hex');
}

class QuickSharePublicController {
  async auth(req, res) {
    try {
      const parsed = QuickShareBinary.decodeAuthRequest(req.body);
      if (!parsed) {
        Logger.warn('[quickShare] public/auth: bad body (decodeAuthRequest failed)', {
          bodyLen: req.body ? req.body.length : 0,
        });
        return res
          .status(400)
          .set('content-type', 'application/octet-stream')
          .send(QuickShareBinary.encodeError({ msgType: QuickShareBinary.MSG_AUTH_RES, code: 400 }));
      }
      const token = String(parsed.qt || '').trim();
      if (!token) {
        Logger.warn('[quickShare] public/auth: empty qt after decode');
        return res
          .status(400)
          .set('content-type', 'application/octet-stream')
          .send(QuickShareBinary.encodeError({ msgType: QuickShareBinary.MSG_AUTH_RES, code: 400 }));
      }

      const knex = req.dbMain;
      if (!knex) {
        Logger.warn('[quickShare] public/auth: no req.dbMain', { qt: token });
        return res
          .status(500)
          .set('content-type', 'application/octet-stream')
          .send(QuickShareBinary.encodeError({ msgType: QuickShareBinary.MSG_AUTH_RES, code: 500 }));
      }

      const share = await knex('quick_share').where({ token }).first();
      if (!share) {
        Logger.warn('[quickShare] public/auth: share not in DB', { qt: token });
        return res
          .status(404)
          .set('content-type', 'application/octet-stream')
          .send(QuickShareBinary.encodeError({ msgType: QuickShareBinary.MSG_AUTH_RES, code: 404 }));
      }

      const now = Date.now();
      const endTime = share.end_time ? new Date(share.end_time).getTime() : null;
      if (endTime && Number.isFinite(endTime) && endTime > 0 && endTime < now) {
        Logger.warn('[quickShare] public/auth: share expired', { qt: token, endTime });
        return res
          .status(410)
          .set('content-type', 'application/octet-stream')
          .send(QuickShareBinary.encodeError({ msgType: QuickShareBinary.MSG_AUTH_RES, code: 410 }));
      }

      const bruteKey = getQuickShareBruteKey(req, token);
      if (isQuickShareBruteLocked(bruteKey)) {
        return res
          .status(429)
          .set('content-type', 'application/octet-stream')
          .send(QuickShareBinary.encodeError({ msgType: QuickShareBinary.MSG_AUTH_RES, code: 429 }));
      }

      const needsPwd = true;
      if (needsPwd) {
        const providedPwdHash = String(parsed.pwdHash || '');
        const providedPwd = String(parsed.pwd || '');
        const parsedPwd = String(share.pwd || '').trim();
        const okByHash = !!(providedPwdHash && parsedPwd && !parsedPwd.startsWith('pbkdf2$') && providedPwdHash === _sha256Hex(parsedPwd));
        if (!okByHash && !providedPwd) {
          return res
            .status(ResponseUtil.CODE_PWD_REQUIRED)
            .set('content-type', 'application/octet-stream')
            .send(
              QuickShareBinary.encodeError({
                msgType: QuickShareBinary.MSG_AUTH_RES,
                code: ResponseUtil.CODE_PWD_REQUIRED,
              })
            );
        }
        if (!okByHash && !verifyQuickSharePwd(share.pwd, providedPwd)) {
          recordQuickShareBruteFailure(bruteKey);
          return res
            .status(ResponseUtil.CODE_PWD_ERROR)
            .set('content-type', 'application/octet-stream')
            .send(
              QuickShareBinary.encodeError({
                msgType: QuickShareBinary.MSG_AUTH_RES,
                code: ResponseUtil.CODE_PWD_ERROR,
              })
            );
        }
        clearQuickShareBruteOnSuccess(bruteKey);
      }

      const secret = process.env.JWT_SECRET;
      if (!secret) {
        Logger.error('[quickShare] public/auth: JWT_SECRET not set, cannot sign qsat', { qt: token });
        return res
          .status(500)
          .set('content-type', 'application/octet-stream')
          .send(QuickShareBinary.encodeError({ msgType: QuickShareBinary.MSG_AUTH_RES, code: 500 }));
      }

      const qsat = jwt.sign(
        {
          type: 'quickShare',
          qt: token,
          pwdHash: _sha256Hex(share && share.pwd ? String(share.pwd) : ''),
          createTime: Date.now(),
        },
        secret,
        { expiresIn: '24h' }
      );

      Logger.info('[quickShare] public/auth: success', { qt: token, shareId: share.id });
      return res.status(200).set('content-type', 'application/octet-stream').send(QuickShareBinary.encodeAuthResponse({ qsat }));
    } catch (e) {
      Logger.error('[quickShare] public/auth: exception', e);
      return res
        .status(500)
        .set('content-type', 'application/octet-stream')
        .send(QuickShareBinary.encodeError({ msgType: QuickShareBinary.MSG_AUTH_RES, code: 500 }));
    }
  }

  async list(req, res) {
    try {
      const qs = req.quickShare;
      if (!qs) {
        Logger.error('[quickShare] public/list: req.quickShare missing (middleware bug?)');
        return res
          .status(500)
          .set('content-type', 'application/octet-stream')
          .send(QuickShareBinary.encodeError({ msgType: QuickShareBinary.MSG_LIST_RES, code: 500 }));
      }
      const share = qs.share || {};

      let st;
      try {
        st = await fs.promises.stat(qs.targetPath);
      } catch (e) {
        // 470：库里有分享记录，但磁盘路径不存在/不可访问（与中间件「无记录」404 区分，便于前端提示）
        Logger.warn('[quickShare] public/list: stat failed (path missing)', {
          qt: qs.token,
          targetPath: qs.targetPath,
          err: e && e.message ? e.message : String(e),
        });
        return res
          .status(470)
          .set('content-type', 'application/octet-stream')
          .send(QuickShareBinary.encodeError({ msgType: QuickShareBinary.MSG_LIST_RES, code: 470 }));
      }

      const relBase = qs.relPath || '';
      if (st.isFile()) {
        const item = await _statToItem(qs.targetPath, relBase);
        Logger.info('[quickShare] public/list: success (single file)', { qt: qs.token, relBase: relBase || '(root)' });
        return res
          .status(200)
          .set('content-type', 'application/octet-stream')
          .send(
            QuickShareBinary.encodeListResponse({
              share: {
                remark: share.remark || null,
                end_time: share.end_time || null,
                hasPwd: !!(share.pwd && String(share.pwd).trim()),
              },
              base: relBase,
              segments: _buildSegments(relBase),
              items: [item],
            })
          );
      }

      const entries = await fs.promises.readdir(qs.targetPath, { withFileTypes: true });
      const items = [];
      for (const ent of entries) {
        const name = ent && ent.name ? String(ent.name) : '';
        if (!name) continue;
        if (name.startsWith('.')) continue;
        const abs = path.join(qs.targetPath, name);
        const rel = _toRelJoin(relBase, name);
        try {
          items.push(await _statToItem(abs, rel, name));
        } catch (_) {}
      }

      items.sort((a, b) => {
        const ad = a.type === 'dir';
        const bd = b.type === 'dir';
        if (ad !== bd) return ad ? -1 : 1;
        return String(a.name || '').localeCompare(String(b.name || ''));
      });

      Logger.info('[quickShare] public/list: success', {
        qt: qs.token,
        isFile: st.isFile(),
        itemCount: items.length,
        relBase: relBase || '(root)',
      });
      return res
        .status(200)
        .set('content-type', 'application/octet-stream')
        .send(
          QuickShareBinary.encodeListResponse({
            share: {
              remark: share.remark || null,
              end_time: share.end_time || null,
              hasPwd: !!(share.pwd && String(share.pwd).trim()),
            },
            base: relBase,
            segments: _buildSegments(relBase),
            items,
          })
        );
    } catch (e) {
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('[quickShare] public/list: exception', e, { statusCode });
      return res
        .status(statusCode)
        .set('content-type', 'application/octet-stream')
        .send(QuickShareBinary.encodeError({ msgType: QuickShareBinary.MSG_LIST_RES, code: statusCode }));
    }
  }

  async tiny(req, res) {
    try {
      const qs = req.quickShare;
      if (!qs) return ResponseUtil.error(req, res, 'common.ERROR', 500);
      const size = req.query && req.query.size;
      const targetPath = qs.targetPath;
      const targetTinyPath = await fileService.getTinyImgByPath(targetPath, size);
      if (fs.existsSync(targetTinyPath)) {
        return await res.sendFile(targetTinyPath);
      }
      return res.sendStatus(404);
    } catch (e) {
      if (e && e.message === 'file.NOT_FOUND') return res.sendStatus(404);
      if (e && e.message === 'file.TINY_PENDING') return res.status(404).end();
      if (e && String(e.message || '').startsWith('file.UNSUPPORTED_TYPE')) return res.sendStatus(415);
      return ResponseUtil.error(req, res, 'file.TINY_FAILED', 500, { error: e && e.message ? String(e.message) : String(e) });
    }
  }

  async raw(req, res) {
    try {
      const qs = req.quickShare;
      if (!qs) return ResponseUtil.error(req, res, 'common.ERROR', 500);
      const { download, size, quality, raw, code } = req.query || {};
      const fullPath = path.resolve(qs.targetPath);

      try {
        await fs.promises.access(fullPath, fs.constants.R_OK);
      } catch (_) {
        return res.status(404).send('File not found');
      }

      const filename = path.basename(fullPath);
      const ext = path.extname(fullPath).toLowerCase();
      const isDownloadReq = download == '1';

      if (config.isImg(ext) && raw != '1') {
        await sharpUtils.processToResponse(res, fullPath, size, quality);
        return;
      }

      if (code == 'utf8' && path.extname(fullPath).toLowerCase() == '.txt') {
        const content = await fs.promises.readFile(fullPath, 'utf8');
        res.type('text/plain; charset=utf-8');
        return res.send(content);
      }

      if (isDownloadReq) {
        res.download(fullPath, filename);
        return;
      }
      return res.sendFile(fullPath, { dotfiles: 'allow' }, err => {
        if (!err) return;
        if (err.code === 'ECONNABORTED' || err.code === 'EPIPE' || err.code === 'ECONNRESET') return;
        if (!res.headersSent) res.status(500).send(err.message);
      });
    } catch (e) {
      if (!res.headersSent) res.status(500).send(e && e.message ? String(e.message) : String(e));
    }
  }

  async download(req, res) {
    try {
      const qs = req.quickShare;
      if (!qs) return ResponseUtil.error(req, res, 'common.ERROR', 500);
      const targetPath = path.resolve(qs.targetPath);

      let st;
      try {
        st = await fs.promises.stat(targetPath);
      } catch (_) {
        return ResponseUtil.error(req, res, 'quickShare.PATH_NOT_FOUND', 404);
      }

      if (st.isFile()) {
        return res.download(targetPath, path.basename(targetPath));
      }

      const zipName = `${path.basename(targetPath) || 'folder'}.zip`;
      const archive = archiver('zip', { zlib: { level: 1 } });
      res.attachment(zipName);

      let stopped = false;
      const stop = err => {
        if (stopped) return;
        stopped = true;
        try {
          archive.abort();
        } catch (_) {}
        if (!res.headersSent) {
          res.status(500).end();
          return;
        }
        res.destroy(err instanceof Error ? err : new Error('zip error'));
      };

      archive.on('error', stop);
      res.on('error', stop);
      res.on('close', () => stop(new Error('closed')));

      archive.pipe(res);
      const name = path.basename(targetPath) || 'folder';
      archive.directory(targetPath, name);
      await archive.finalize();
    } catch (e) {
      if (!res.headersSent) return ResponseUtil.error(req, res, 'file.DOWNLOAD_ERROR', 500);
      res.destroy(e instanceof Error ? e : new Error('download error'));
    }
  }
}

module.exports = new QuickSharePublicController();
