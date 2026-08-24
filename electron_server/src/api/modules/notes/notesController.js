const fs = require('fs');
const path = require('path');
const multer = require('multer');
const ResponseUtil = require('../../apiUtils/responseUtil');
const config = require('../../../config/config');
const notesService = require('./notesService');

function normalizeError(error) {
  if (error && error.statusCode) {
    return error;
  }
  const err = new Error(
    error && error.message ? String(error.message) : 'common.ERROR',
  );
  err.statusCode = 500;
  return err;
}

function getReqValue(req, key) {
  if (req.body && req.body[key] !== undefined) return req.body[key];
  if (req.query && req.query[key] !== undefined) return req.query[key];
  return undefined;
}

function runMulter(uploader, req, res) {
  return new Promise((resolve, reject) => {
    uploader(req, res, err => {
      if (err) return reject(err);
      resolve();
    });
  });
}

function _normalizeComparePath(p) {
  const resolved = path.resolve(String(p || ''));
  return process.platform === 'win32' ? resolved.toLowerCase() : resolved;
}

function _isPathInside(root, candidate) {
  const base = _normalizeComparePath(root);
  const full = _normalizeComparePath(candidate);
  const rel = path.relative(base, full);
  if (!rel) return true;
  return rel && !rel.startsWith('..') && !path.isAbsolute(rel);
}

function _scoreFilenameText(value) {
  const text = typeof value === 'string' ? value.trim() : '';
  if (!text) return Number.NEGATIVE_INFINITY;
  let score = 0;
  const cjk = (text.match(/[\u3400-\u9FFF\uF900-\uFAFF]/g) || []).length;
  const asciiWord = (text.match(/[A-Za-z0-9._()\-[\] ]/g) || []).length;
  const latin1ish = (text.match(/[\u00A0-\u00FF]/g) || []).length;
  const replacement = (text.match(/\uFFFD/g) || []).length;
  score += cjk * 6;
  score += asciiWord;
  score -= latin1ish * 2;
  score -= replacement * 8;
  return score;
}

function normalizeUploadedOriginalName(raw) {
  const name = typeof raw === 'string' ? raw.trim() : '';
  if (!name) return '';
  if (/^[\x00-\x7F]*$/.test(name)) return name;
  if (name.includes('\uFFFD')) return name;
  if (/[\u3400-\u9FFF\uF900-\uFAFF]/.test(name)) return name;

  const latin1ish = (name.match(/[\u00A0-\u00FF]/g) || []).length;
  const nonAscii = (name.match(/[^\x00-\x7F]/g) || []).length;
  const shouldTryDecode =
    nonAscii >= 2 && latin1ish / Math.max(1, nonAscii) > 0.8;
  if (!shouldTryDecode) return name;

  const decoded = Buffer.from(name, 'latin1').toString('utf8').trim();
  if (!decoded || decoded.includes('\uFFFD')) return name;

  return _scoreFilenameText(decoded) > _scoreFilenameText(name)
    ? decoded
    : name;
}

class NotesController {
  async _handle(req, res, action, successMessage = 'common.SUCCESS') {
    try {
      const data = await action();
      return ResponseUtil.success(req, res, data, successMessage);
    } catch (error) {
      const err = normalizeError(error);
      return ResponseUtil.error(
        req,
        res,
        err.message || 'common.ERROR',
        Number(err.statusCode) || 500,
      );
    }
  }

  getNotebookStatus = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.getNotebookStatus({
          knex: req.dbMain,
          user: req.user,
        }),
    );

  selectNotebook = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.selectNotebook({
          knex: req.dbMain,
          user: req.user,
          folderPath: getReqValue(req, 'folderPath'),
        }),
    );

  getState = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.getState({
          knex: req.dbMain,
          user: req.user,
          groupId: getReqValue(req, 'groupId'),
          keyword: getReqValue(req, 'keyword'),
          includeDeleted:
            getReqValue(req, 'includeDeleted') === true ||
            String(getReqValue(req, 'includeDeleted') || '') === 'true',
        }),
    );

  createGroup = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.createGroup({
          knex: req.dbMain,
          user: req.user,
          name: getReqValue(req, 'name'),
        }),
    );

  updateGroup = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.updateGroup({
          knex: req.dbMain,
          user: req.user,
          groupId: getReqValue(req, 'groupId'),
          name: getReqValue(req, 'name'),
        }),
    );

  deleteGroup = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.deleteGroup({
          knex: req.dbMain,
          user: req.user,
          groupId: getReqValue(req, 'groupId'),
        }),
    );

  reorderGroups = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.reorderGroups({
          knex: req.dbMain,
          user: req.user,
          orderedGroupIds: getReqValue(req, 'orderedGroupIds'),
        }),
    );

  createNote = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.createNote({
          knex: req.dbMain,
          user: req.user,
          groupId: getReqValue(req, 'groupId'),
          title: getReqValue(req, 'title'),
        }),
    );

  getNoteDetail = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.getNoteDetail({
          knex: req.dbMain,
          user: req.user,
          noteId: getReqValue(req, 'noteId'),
        }),
    );

  saveNote = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.saveNote({
          knex: req.dbMain,
          user: req.user,
          noteId: getReqValue(req, 'noteId'),
          title: getReqValue(req, 'title'),
          baseRevision: getReqValue(req, 'baseRevision'),
          deltaPatch: getReqValue(req, 'deltaPatch'),
        }),
    );

  updateNoteMeta = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.updateNoteMeta({
          knex: req.dbMain,
          user: req.user,
          noteIds: getReqValue(req, 'noteIds'),
          noteId: getReqValue(req, 'noteId'),
          title: getReqValue(req, 'title'),
          tagColor: getReqValue(req, 'tagColor'),
          isPinned:
            getReqValue(req, 'isPinned') === undefined
              ? undefined
              : getReqValue(req, 'isPinned') === true ||
                String(getReqValue(req, 'isPinned') || '') === 'true',
        }),
    );

  moveNote = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.moveNote({
          knex: req.dbMain,
          user: req.user,
          noteId: getReqValue(req, 'noteId'),
          targetGroupId: getReqValue(req, 'targetGroupId'),
        }),
    );

  batchMoveNotes = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.batchMoveNotes({
          knex: req.dbMain,
          user: req.user,
          noteIds: getReqValue(req, 'noteIds'),
          targetGroupId: getReqValue(req, 'targetGroupId'),
        }),
    );

  deleteNote = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.deleteNote({
          knex: req.dbMain,
          user: req.user,
          noteId: getReqValue(req, 'noteId'),
        }),
    );

  batchDeleteNotes = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.batchDeleteNotes({
          knex: req.dbMain,
          user: req.user,
          noteIds: getReqValue(req, 'noteIds'),
        }),
    );

  restoreNote = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.restoreNote({
          knex: req.dbMain,
          user: req.user,
          noteId: getReqValue(req, 'noteId'),
        }),
    );

  batchRestoreNotes = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.batchRestoreNotes({
          knex: req.dbMain,
          user: req.user,
          noteIds: getReqValue(req, 'noteIds'),
        }),
    );

  permanentlyDeleteNote = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.permanentlyDeleteNote({
          knex: req.dbMain,
          user: req.user,
          noteId: getReqValue(req, 'noteId'),
        }),
    );

  batchPermanentlyDeleteNotes = async (req, res) =>
    this._handle(
      req,
      res,
      () =>
        notesService.batchPermanentlyDeleteNotes({
          knex: req.dbMain,
          user: req.user,
          noteIds: getReqValue(req, 'noteIds'),
        }),
    );

  uploadAsset = async (req, res) => {
    let stageDir = '';
    let stagePath = '';
    try {
      stageDir = path.join(config.getUploadTempDir(), 'notes_upload_stage');
      await fs.promises.mkdir(stageDir, { recursive: true });
      const uploader = multer({
        storage: multer.diskStorage({
          destination: function (_req, _file, cb) {
            cb(null, stageDir);
          },
          filename: function (_req, file, cb) {
            const ext = path.extname(file.originalname || '').toLowerCase();
            cb(
              null,
              `${Date.now()}_${Math.round(Math.random() * 1e9)}${ext || '.bin'}`,
            );
          },
        }),
        limits: { fileSize: 100 * 1024 * 1024 },
      }).single('file');
      await runMulter(uploader, req, res);
      stagePath = req.file && req.file.path ? String(req.file.path) : '';
      if (!stagePath) {
        throw normalizeError({ message: 'file.INVALID_PARAMS', statusCode: 400 });
      }
      if (!_isPathInside(stageDir, stagePath)) {
        throw normalizeError({ message: 'file.INVALID_PATH', statusCode: 400 });
      }
      const data = await notesService.saveUploadedAsset({
        knex: req.dbMain,
        user: req.user,
        noteId: getReqValue(req, 'noteId'),
        sourcePath: stagePath,
        originalName:
          normalizeUploadedOriginalName(req.file && req.file.originalname) ||
          path.basename(stagePath || '') ||
          'asset.bin',
      });
      stagePath = '';
      return ResponseUtil.success(req, res, data, 'common.SUCCESS');
    } catch (error) {
      if (stagePath) {
        if (stageDir && _isPathInside(stageDir, stagePath)) {
          await fs.promises.unlink(stagePath).catch(() => {});
        }
      }
      const err = normalizeError(error);
      return ResponseUtil.error(
        req,
        res,
        err.message || 'common.ERROR',
        Number(err.statusCode) || 500,
      );
    }
  };

  getAsset = async (req, res) => {
    try {
      const data = await notesService.resolveAsset({
        knex: req.dbMain,
        user: req.user,
        noteId: getReqValue(req, 'noteId'),
        assetName: getReqValue(req, 'name'),
      });
      return res.sendFile(data.filePath);
    } catch (error) {
      const err = normalizeError(error);
      return ResponseUtil.error(
        req,
        res,
        err.message || 'common.ERROR',
        Number(err.statusCode) || 500,
      );
    }
  };

  exportNote = async (req, res) => {
    try {
      const data = await notesService.exportNote({
        knex: req.dbMain,
        user: req.user,
        noteId: getReqValue(req, 'noteId'),
        format: getReqValue(req, 'format'),
      });
      const encodedFilename = encodeURIComponent(data.fileName).replace(
        /%([0-9A-F]{2})/g,
        (match, p1) => `%${p1.toUpperCase()}`,
      );
      res.setHeader('Content-Type', data.contentType);
      res.setHeader(
        'Content-Disposition',
        `attachment; filename*=UTF-8''${encodedFilename}`,
      );
      return res.status(200).send(data.buffer);
    } catch (error) {
      const err = normalizeError(error);
      return ResponseUtil.error(
        req,
        res,
        err.message || 'common.ERROR',
        Number(err.statusCode) || 500,
      );
    }
  };
}

module.exports = new NotesController();
