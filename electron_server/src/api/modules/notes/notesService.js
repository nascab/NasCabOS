const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');
const config = require('../../../config/config');
const tableConfig = require('../../../db/table/tableConfig');
const { hasPermission } = require('../../../utils/permissionUtil');
const {
  APP_MARK,
  DEFAULT_GROUP_ID,
  DEFAULT_GROUP_NAME,
  ensureString,
  nowIso,
  sanitizeName,
  ensureDir,
  pathExists,
  isDirEmpty,
  readJson,
  writeJson,
  createDefaultIndex,
  createManifest,
  getManifestPath,
  getIndexPath,
  getTrashRoot,
  normalizeIndex,
  ensureDefaultGroup,
  pickUniqueFolderName,
  getGroupById,
  getNoteById,
  getGroupPath,
  getNotePath,
  getNoteMetaPath,
  getNoteContentPath,
  getNoteAssetsPath,
  getDeletedNotePath,
  extractPlainTextFromDelta,
  makePreviewText,
  buildEmptyDelta,
  cloneJson,
  isDefaultGroupFolderName,
  createNoteRecord,
} = require('./notesFileUtil');

function cloneAttrs(attrs) {
  if (!attrs || typeof attrs !== 'object' || Array.isArray(attrs)) return undefined;
  return cloneJson(attrs);
}

function mergeAttrs(base, patch) {
  const next = cloneAttrs(base) || {};
  const patchAttrs = cloneAttrs(patch);
  if (!patchAttrs) {
    return Object.keys(next).length > 0 ? next : undefined;
  }
  for (const [key, value] of Object.entries(patchAttrs)) {
    if (value === null) {
      delete next[key];
    } else {
      next[key] = value;
    }
  }
  return Object.keys(next).length > 0 ? next : undefined;
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

async function moveFile(
  sourcePath,
  targetPath,
  { allowedSourceRoot = '', allowedTargetRoot = '' } = {},
) {
  try {
    await fs.promises.rename(sourcePath, targetPath);
    return;
  } catch (error) {
    const code = error && error.code ? String(error.code) : '';
    const message = error && error.message ? String(error.message) : '';
    const isCrossDevice =
      code === 'EXDEV' || message.toLowerCase().includes('cross-device');
    if (!isCrossDevice) throw error;

    if (allowedTargetRoot && !_isPathInside(allowedTargetRoot, targetPath)) {
      const err = new Error('file.INVALID_PATH');
      err.statusCode = 400;
      throw err;
    }

    try {
      await fs.promises.copyFile(sourcePath, targetPath);
    } catch (copyError) {
      if (allowedTargetRoot && _isPathInside(allowedTargetRoot, targetPath)) {
        await fs.promises.unlink(targetPath).catch(() => {});
      }
      throw copyError;
    }

    try {
      if (allowedSourceRoot && !_isPathInside(allowedSourceRoot, sourcePath)) {
        if (allowedTargetRoot && _isPathInside(allowedTargetRoot, targetPath)) {
          await fs.promises.unlink(targetPath).catch(() => {});
        }
        const err = new Error('file.INVALID_PATH');
        err.statusCode = 400;
        throw err;
      }
      await fs.promises.unlink(sourcePath);
    } catch (unlinkError) {
      if (allowedTargetRoot && _isPathInside(allowedTargetRoot, targetPath)) {
        await fs.promises.unlink(targetPath).catch(() => {});
      }
      throw unlinkError;
    }
  }
}

function attrsEqual(a, b) {
  return JSON.stringify(a || null) === JSON.stringify(b || null);
}

function getOpLength(op) {
  if (!op || typeof op !== 'object') return 0;
  if (typeof op.insert === 'string') return op.insert.length;
  if (op.insert && typeof op.insert === 'object') return 1;
  if (op.retain !== undefined) return Math.max(0, Math.trunc(Number(op.retain) || 0));
  if (op.delete !== undefined) return Math.max(0, Math.trunc(Number(op.delete) || 0));
  return 0;
}

function normalizeStoredDelta(rawDelta) {
  const rawOps = Array.isArray(rawDelta) ? rawDelta : buildEmptyDelta();
  const ops = [];
  for (const rawOp of rawOps) {
    if (!rawOp || typeof rawOp !== 'object') continue;
    if (!Object.prototype.hasOwnProperty.call(rawOp, 'insert')) continue;
    const attrs = cloneAttrs(rawOp.attributes);
    if (typeof rawOp.insert === 'string') {
      if (rawOp.insert.length === 0) continue;
      const op = { insert: rawOp.insert };
      if (attrs) op.attributes = attrs;
      ops.push(op);
      continue;
    }
    if (rawOp.insert && typeof rawOp.insert === 'object' && !Array.isArray(rawOp.insert)) {
      const op = { insert: cloneJson(rawOp.insert) };
      if (attrs) op.attributes = attrs;
      ops.push(op);
    }
  }
  return ops.length > 0 ? ops : buildEmptyDelta();
}

function normalizePatchDelta(rawOps) {
  if (!Array.isArray(rawOps)) return null;
  const ops = [];
  for (const rawOp of rawOps) {
    if (!rawOp || typeof rawOp !== 'object') return null;
    const attrs = cloneAttrs(rawOp.attributes);
    if (Object.prototype.hasOwnProperty.call(rawOp, 'retain')) {
      const retain = Math.trunc(Number(rawOp.retain));
      if (!Number.isFinite(retain) || retain < 0) return null;
      if (retain > 0) {
        const op = { retain };
        if (attrs) op.attributes = attrs;
        ops.push(op);
      }
      continue;
    }
    if (Object.prototype.hasOwnProperty.call(rawOp, 'delete')) {
      const del = Math.trunc(Number(rawOp.delete));
      if (!Number.isFinite(del) || del < 0) return null;
      if (del > 0) ops.push({ delete: del });
      continue;
    }
    if (Object.prototype.hasOwnProperty.call(rawOp, 'insert')) {
      if (typeof rawOp.insert === 'string') {
        if (rawOp.insert.length === 0) continue;
        const op = { insert: rawOp.insert };
        if (attrs) op.attributes = attrs;
        ops.push(op);
        continue;
      }
      if (rawOp.insert && typeof rawOp.insert === 'object' && !Array.isArray(rawOp.insert)) {
        const op = { insert: cloneJson(rawOp.insert) };
        if (attrs) op.attributes = attrs;
        ops.push(op);
        continue;
      }
    }
    return null;
  }
  return ops;
}

function pushDeltaOp(ops, rawOp) {
  if (!rawOp || !Object.prototype.hasOwnProperty.call(rawOp, 'insert')) return;
  const attrs = cloneAttrs(rawOp.attributes);
  if (typeof rawOp.insert === 'string') {
    if (rawOp.insert.length === 0) return;
    const last = ops.length > 0 ? ops[ops.length - 1] : null;
    if (
      last &&
      typeof last.insert === 'string' &&
      attrsEqual(last.attributes, attrs)
    ) {
      last.insert += rawOp.insert;
      return;
    }
    const op = { insert: rawOp.insert };
    if (attrs) op.attributes = attrs;
    ops.push(op);
    return;
  }
  if (!rawOp.insert || typeof rawOp.insert !== 'object' || Array.isArray(rawOp.insert)) {
    return;
  }
  const op = { insert: cloneJson(rawOp.insert) };
  if (attrs) op.attributes = attrs;
  ops.push(op);
}

function createInsertIterator(delta) {
  const ops = normalizeStoredDelta(delta);
  let opIndex = 0;
  let opOffset = 0;

  const moveToNextNonEmpty = () => {
    while (opIndex < ops.length) {
      const current = ops[opIndex];
      const currentLength = getOpLength(current);
      if (currentLength > opOffset) break;
      opIndex += 1;
      opOffset = 0;
    }
  };

  const take = (count, attrsMapper) => {
    const result = [];
    let remaining = Math.max(0, Math.trunc(Number(count) || 0));
    while (remaining > 0) {
      moveToNextNonEmpty();
      if (opIndex >= ops.length) break;
      const current = ops[opIndex];
      const currentLength = getOpLength(current);
      const available = Math.max(0, currentLength - opOffset);
      if (available <= 0) {
        opIndex += 1;
        opOffset = 0;
        continue;
      }
      const chunkLength = Math.min(remaining, available);
      const insert =
        typeof current.insert === 'string'
          ? current.insert.slice(opOffset, opOffset + chunkLength)
          : cloneJson(current.insert);
      const nextAttrs = attrsMapper
        ? attrsMapper(cloneAttrs(current.attributes))
        : cloneAttrs(current.attributes);
      const nextOp = { insert };
      if (nextAttrs) nextOp.attributes = nextAttrs;
      pushDeltaOp(result, nextOp);
      remaining -= chunkLength;
      opOffset += chunkLength;
    }
    return result;
  };

  const skip = count => {
    let remaining = Math.max(0, Math.trunc(Number(count) || 0));
    while (remaining > 0) {
      moveToNextNonEmpty();
      if (opIndex >= ops.length) break;
      const currentLength = getOpLength(ops[opIndex]);
      const available = Math.max(0, currentLength - opOffset);
      if (available <= 0) {
        opIndex += 1;
        opOffset = 0;
        continue;
      }
      const chunkLength = Math.min(remaining, available);
      remaining -= chunkLength;
      opOffset += chunkLength;
    }
  };

  const takeRemaining = () => take(Number.MAX_SAFE_INTEGER);

  return {
    take,
    skip,
    takeRemaining,
  };
}

function appendDeltaOps(target, ops) {
  for (const op of ops) {
    pushDeltaOp(target, op);
  }
}

function applyDeltaPatch(currentDelta, patchDelta) {
  const patchOps = normalizePatchDelta(patchDelta);
  if (!patchOps) return null;
  const source = createInsertIterator(currentDelta);
  const resultOps = [];

  for (const op of patchOps) {
    if (op.retain !== undefined) {
      appendDeltaOps(
        resultOps,
        source.take(op.retain, attrs => mergeAttrs(attrs, op.attributes)),
      );
      continue;
    }
    if (op.delete !== undefined) {
      source.skip(op.delete);
      continue;
    }
    if (Object.prototype.hasOwnProperty.call(op, 'insert')) {
      pushDeltaOp(resultOps, op);
    }
  }

  appendDeltaOps(resultOps, source.takeRemaining());
  return resultOps.length > 0 ? resultOps : buildEmptyDelta();
}

const LINE_ATTRIBUTE_KEYS = new Set([
  'header',
  'list',
  'blockquote',
  'code-block',
  'align',
  'indent',
  'direction',
]);

function escapeHtml(value) {
  return ensureString(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function escapeMarkdown(value) {
  return ensureString(value)
    .replace(/\\/g, '\\\\')
    .replace(/([`*_{}\[\]()#+\-!>])/g, '\\$1');
}

function splitDeltaAttrs(rawAttrs) {
  const attrs = cloneAttrs(rawAttrs);
  if (!attrs) return { inlineAttrs: undefined, lineAttrs: undefined };
  const inlineAttrs = {};
  const lineAttrs = {};
  for (const [key, value] of Object.entries(attrs)) {
    if (LINE_ATTRIBUTE_KEYS.has(key)) {
      lineAttrs[key] = value;
    } else {
      inlineAttrs[key] = value;
    }
  }
  return {
    inlineAttrs: Object.keys(inlineAttrs).length > 0 ? inlineAttrs : undefined,
    lineAttrs: Object.keys(lineAttrs).length > 0 ? lineAttrs : undefined,
  };
}

function parseDeltaLines(delta) {
  const ops = normalizeStoredDelta(delta);
  const lines = [];
  let currentSegments = [];

  const flushLine = lineAttrs => {
    lines.push({
      segments: currentSegments,
      attrs: cloneAttrs(lineAttrs) || {},
    });
    currentSegments = [];
  };

  for (const op of ops) {
    if (typeof op.insert === 'string') {
      let text = op.insert;
      while (text.length > 0) {
        const newlineIndex = text.indexOf('\n');
        const { inlineAttrs, lineAttrs } = splitDeltaAttrs(op.attributes);
        if (newlineIndex === -1) {
          currentSegments.push({
            kind: 'text',
            value: text,
            attrs: inlineAttrs,
          });
          text = '';
          continue;
        }
        const textPart = text.slice(0, newlineIndex);
        if (textPart) {
          currentSegments.push({
            kind: 'text',
            value: textPart,
            attrs: inlineAttrs,
          });
        }
        flushLine(lineAttrs);
        text = text.slice(newlineIndex + 1);
      }
      continue;
    }
    if (op.insert && typeof op.insert === 'object' && !Array.isArray(op.insert)) {
      currentSegments.push({
        kind: 'embed',
        value: cloneJson(op.insert),
        attrs: cloneAttrs(op.attributes),
      });
    }
  }

  if (lines.length === 0 || currentSegments.length > 0) {
    flushLine();
  }
  return lines;
}

function getEmbedSpec(noteFolderPath, insert, { forHtml = false } = {}) {
  if (!insert || typeof insert !== 'object' || Array.isArray(insert)) return null;
  const imageValue = typeof insert.image === 'string' ? insert.image.trim() : '';
  if (imageValue) {
    const source =
      forHtml && imageValue.startsWith('assets/')
        ? pathToFileURL(
            path.join(noteFolderPath, imageValue.replace(/^assets[\\/]/, 'assets/')),
          ).href
        : imageValue;
    return {
      type: 'image',
      source,
      label: path.basename(imageValue.split('?')[0].split('#')[0]) || 'image',
    };
  }
  const videoValue = typeof insert.video === 'string' ? insert.video.trim() : '';
  if (videoValue) {
    const source =
      forHtml && videoValue.startsWith('assets/')
        ? pathToFileURL(
            path.join(noteFolderPath, videoValue.replace(/^assets[\\/]/, 'assets/')),
          ).href
        : videoValue;
    return {
      type: 'video',
      source,
      label: path.basename(videoValue.split('?')[0].split('#')[0]) || 'video',
    };
  }
  return null;
}

function wrapHtmlInline(text, attrs) {
  let output = text;
  if (!attrs) return output;
  if (attrs.code) output = `<code>${output}</code>`;
  if (attrs.bold) output = `<strong>${output}</strong>`;
  if (attrs.italic) output = `<em>${output}</em>`;
  if (attrs.underline) output = `<u>${output}</u>`;
  if (attrs.strike) output = `<s>${output}</s>`;
  if (typeof attrs.link === 'string' && attrs.link.trim()) {
    output = `<a href="${escapeHtml(attrs.link.trim())}">${output}</a>`;
  }
  return output;
}

function renderLineText(segments) {
  return segments
    .map(segment => {
      if (segment.kind === 'text') {
        return ensureString(segment.value);
      }
      const embed = getEmbedSpec('', segment.value);
      if (!embed) return '';
      return embed.type === 'image'
        ? `[image: ${embed.label}]`
        : `[video: ${embed.label}]`;
    })
    .join('');
}

function renderLineMarkdown(segments) {
  return segments
    .map(segment => {
      if (segment.kind === 'text') {
        let output = escapeMarkdown(segment.value);
        const attrs = segment.attrs || {};
        if (attrs.code) output = `\`${output}\``;
        if (attrs.bold) output = `**${output}**`;
        if (attrs.italic) output = `_${output}_`;
        if (attrs.strike) output = `~~${output}~~`;
        if (typeof attrs.link === 'string' && attrs.link.trim()) {
          const href = attrs.link.trim();
          const label = output || escapeMarkdown(href);
          output = `[${label}](${href})`;
        }
        return output;
      }
      const embed = getEmbedSpec('', segment.value);
      if (!embed) return '';
      if (embed.type === 'image') {
        return `![${escapeMarkdown(embed.label)}](${embed.source})`;
      }
      return `[video: ${escapeMarkdown(embed.label)}](${embed.source})`;
    })
    .join('');
}

function renderLineHtml(segments, noteFolderPath) {
  return segments
    .map(segment => {
      if (segment.kind === 'text') {
        return wrapHtmlInline(escapeHtml(segment.value), segment.attrs);
      }
      const embed = getEmbedSpec(noteFolderPath, segment.value, { forHtml: true });
      if (!embed) return '';
      if (embed.type === 'image') {
        return `<img src="${escapeHtml(embed.source)}" alt="${escapeHtml(embed.label)}" />`;
      }
      return `<a href="${escapeHtml(embed.source)}">[Video] ${escapeHtml(embed.label)}</a>`;
    })
    .join('');
}

function getLineIndent(attrs) {
  return Math.max(0, Math.trunc(Number(attrs && attrs.indent) || 0));
}

function buildExportFileName(note, format) {
  const ext = format === 'markdown' ? 'md' : format;
  const fallbackName = `note_${ensureString(note && note.id).slice(0, 8) || 'export'}`;
  const baseName = sanitizeName(ensureString(note && note.title).trim(), fallbackName);
  return `${baseName || fallbackName}.${ext}`;
}

function buildTextDocument(note, delta) {
  const title = ensureString(note && note.title).trim() || buildExportFileName(note, 'txt');
  const body = parseDeltaLines(delta)
    .map(line => {
      const attrs = line.attrs || {};
      const content = renderLineText(line.segments);
      const indent = '  '.repeat(getLineIndent(attrs));
      if (attrs.list === 'ordered') return `${indent}1. ${content}`;
      if (attrs.list === 'bullet') return `${indent}- ${content}`;
      if (attrs.list === 'checked') return `${indent}- [x] ${content}`;
      if (attrs.list === 'unchecked') return `${indent}- [ ] ${content}`;
      if (attrs.blockquote) return `${indent}> ${content}`;
      return `${indent}${content}`;
    })
    .join('\n')
    .trimEnd();
  return `${title}\n\n${body}\n`;
}

function buildMarkdownDocument(note, delta) {
  const title = ensureString(note && note.title).trim() || buildExportFileName(note, 'md');
  const lines = parseDeltaLines(delta);
  const output = [`# ${escapeMarkdown(title)}`, ''];
  let previousOrderedKey = '';
  let orderedIndex = 0;
  for (const line of lines) {
    const attrs = line.attrs || {};
    const indentLevel = getLineIndent(attrs);
    const indent = '  '.repeat(indentLevel);
    const content = renderLineMarkdown(line.segments);
    if (attrs['code-block']) {
      output.push(`${indent}    ${renderLineText(line.segments)}`);
      previousOrderedKey = '';
      continue;
    }
    if (attrs.list === 'ordered') {
      const currentKey = `${indentLevel}:${attrs.list}`;
      orderedIndex = currentKey === previousOrderedKey ? orderedIndex + 1 : 1;
      previousOrderedKey = currentKey;
      output.push(`${indent}${orderedIndex}. ${content}`);
      continue;
    }
    previousOrderedKey = '';
    if (attrs.list === 'bullet') {
      output.push(`${indent}- ${content}`);
      continue;
    }
    if (attrs.list === 'checked') {
      output.push(`${indent}- [x] ${content}`);
      continue;
    }
    if (attrs.list === 'unchecked') {
      output.push(`${indent}- [ ] ${content}`);
      continue;
    }
    if (attrs.blockquote) {
      output.push(`${indent}> ${content}`);
      continue;
    }
    if (attrs.header) {
      const level = Math.min(6, Math.max(1, Math.trunc(Number(attrs.header) || 1)));
      output.push(`${'#'.repeat(level)} ${content}`);
      continue;
    }
    output.push(`${indent}${content}`);
  }
  return `${output.join('\n').trimEnd()}\n`;
}

function buildHtmlDocument(note, delta, noteFolderPath) {
  const title = ensureString(note && note.title).trim() || buildExportFileName(note, 'pdf');
  const lines = parseDeltaLines(delta);
  const blocks = [`<h1>${escapeHtml(title)}</h1>`];
  let previousOrderedKey = '';
  let orderedIndex = 0;
  for (const line of lines) {
    const attrs = line.attrs || {};
    const indent = getLineIndent(attrs) * 24;
    const align = ensureString(attrs.align).trim();
    const alignStyle = align ? `text-align:${escapeHtml(align)};` : '';
    const marginStyle = indent > 0 ? `margin-left:${indent}px;` : '';
    const content = renderLineHtml(line.segments, noteFolderPath) || '<br />';
    if (attrs['code-block']) {
      blocks.push(
        `<pre style="${marginStyle}${alignStyle}"><code>${escapeHtml(
          renderLineText(line.segments),
        )}</code></pre>`,
      );
      previousOrderedKey = '';
      continue;
    }
    if (attrs.list) {
      const currentKey = `${attrs.list}:${indent}`;
      orderedIndex =
        attrs.list === 'ordered' && currentKey === previousOrderedKey
          ? orderedIndex + 1
          : 1;
      previousOrderedKey = currentKey;
      const marker =
        attrs.list === 'ordered'
          ? `${orderedIndex}.`
          : attrs.list === 'checked'
            ? '&#9745;'
            : attrs.list === 'unchecked'
              ? '&#9744;'
              : '&#8226;';
      blocks.push(
        `<div class="list-item" style="${marginStyle}${alignStyle}"><span class="marker">${marker}</span><span class="content">${content}</span></div>`,
      );
      continue;
    }
    previousOrderedKey = '';
    if (attrs.blockquote) {
      blocks.push(
        `<blockquote style="${marginStyle}${alignStyle}">${content}</blockquote>`,
      );
      continue;
    }
    if (attrs.header) {
      const level = Math.min(6, Math.max(1, Math.trunc(Number(attrs.header) || 1)));
      blocks.push(
        `<h${level} style="${marginStyle}${alignStyle}">${content}</h${level}>`,
      );
      continue;
    }
    blocks.push(`<p style="${marginStyle}${alignStyle}">${content}</p>`);
  }
  return `<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>${escapeHtml(title)}</title>
    <style>
      @page { size: A4; margin: 18mm 14mm; }
      body {
        font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", sans-serif;
        color: #111827;
        line-height: 1.6;
        font-size: 14px;
        word-break: break-word;
      }
      h1, h2, h3, h4, h5, h6 { margin: 0 0 12px; }
      p, blockquote, pre, .list-item { margin: 0 0 10px; white-space: pre-wrap; }
      blockquote {
        border-left: 3px solid #d1d5db;
        padding-left: 12px;
        color: #4b5563;
      }
      pre {
        background: #f3f4f6;
        padding: 10px 12px;
        border-radius: 8px;
        overflow: hidden;
      }
      code {
        font-family: "SFMono-Regular", "Consolas", monospace;
        background: #f3f4f6;
        padding: 1px 4px;
        border-radius: 4px;
      }
      pre code {
        background: transparent;
        padding: 0;
      }
      .list-item {
        display: flex;
        gap: 8px;
        align-items: flex-start;
      }
      .marker {
        flex: none;
        min-width: 24px;
      }
      .content {
        flex: 1;
        min-width: 0;
      }
      img {
        display: block;
        max-width: 100%;
        max-height: 520px;
        margin: 8px 0;
        border-radius: 6px;
      }
      a {
        color: #2563eb;
        text-decoration: none;
      }
    </style>
  </head>
  <body>
    ${blocks.join('\n    ')}
  </body>
</html>`;
}

class NotesService {
  static CONFIG_KEY_NOTEBOOK_PATH = 'notesNotebookPath';

  _toError(message, statusCode = 400) {
    const err = new Error(message);
    err.statusCode = statusCode;
    return err;
  }

  _resolveUid(user) {
    const uid = Number(user && user.id);
    if (!Number.isFinite(uid) || uid <= 0) {
      throw this._toError('auth.AUTHENTICATION_REQUIRED', 401);
    }
    return uid;
  }

  async _getNotebookPath(user) {
    const uid = this._resolveUid(user);
    const notebookPath = await tableConfig.getConfigByKey(
      NotesService.CONFIG_KEY_NOTEBOOK_PATH,
      uid,
    );
    return ensureString(notebookPath).trim();
  }

  async _saveNotebookPath(user, notebookPath) {
    const uid = this._resolveUid(user);
    const ok = await tableConfig.setConfigByKey(
      NotesService.CONFIG_KEY_NOTEBOOK_PATH,
      ensureString(notebookPath).trim(),
      uid,
    );
    if (!ok) {
      throw this._toError('common.ERROR', 500);
    }
  }

  async _assertPathPermission(knex, user, targetPath, action) {
    const ok = await hasPermission(knex, user, action, targetPath).catch(
      () => false,
    );
    if (!ok) {
      throw this._toError('auth.PERMISSION_DENIED', 403);
    }
  }

  _normalizeRequiredActions(actions, fallback = ['view']) {
    const list = Array.isArray(actions) ? actions : [actions];
    const normalized = list
      .map(action => ensureString(action).trim())
      .filter(Boolean);
    return normalized.length > 0 ? normalized : [...fallback];
  }

  async _assertPathPermissionsAll(knex, user, targetPath, actions) {
    const normalized = this._normalizeRequiredActions(actions);
    for (const action of normalized) {
      await this._assertPathPermission(knex, user, targetPath, action);
    }
  }

  _buildNotebookInfo(notebookPath, manifest, index) {
    const normalized = ensureDefaultGroup(index);
    const activeNotes = normalized.notes.filter(note => note.isDeleted !== true);
    const deletedNotes = normalized.notes.filter(note => note.isDeleted === true);
    return {
      selected: true,
      folderPath: notebookPath,
      name: path.basename(notebookPath) || notebookPath,
      version: manifest && manifest.version ? manifest.version : 1,
      groupCount: normalized.groups.length,
      noteCount: activeNotes.length,
      deletedCount: deletedNotes.length,
    };
  }

  async _saveManifest(notebookPath, manifest) {
    const next = manifest && typeof manifest === 'object' ? manifest : createManifest();
    next.updateTime = nowIso();
    await writeJson(getManifestPath(notebookPath), next);
    return next;
  }

  async _saveIndex(notebookPath, index) {
    const next = ensureDefaultGroup(normalizeIndex(index));
    next.updatedAt = nowIso();
    await writeJson(getIndexPath(notebookPath), next);
    return next;
  }

  _normalizeNoteIds(noteIds) {
    if (!Array.isArray(noteIds)) {
      throw this._toError('file.INVALID_PARAMS', 400);
    }
    const next = [];
    const seen = new Set();
    for (const rawId of noteIds) {
      const id = ensureString(rawId).trim();
      if (!id || seen.has(id)) continue;
      seen.add(id);
      next.push(id);
    }
    if (next.length === 0) {
      throw this._toError('file.INVALID_PARAMS', 400);
    }
    return next;
  }

  async _repairIndexFromDisk(notebookPath) {
    const base = createDefaultIndex();
    const rootEntries = await fs.promises
      .readdir(notebookPath, { withFileTypes: true })
      .catch(() => []);
    const groupFolderSet = new Set(base.groups.map(group => group.folderName));
    const notes = [];

    for (const entry of rootEntries) {
      if (!entry.isDirectory()) continue;
      if (entry.name.startsWith('.')) continue;
      const folderName = entry.name;
      let group =
        isDefaultGroupFolderName(folderName)
          ? base.groups.find(item => item.id === DEFAULT_GROUP_ID)
          : null;
      if (group) {
        group = {
          ...group,
          name: DEFAULT_GROUP_NAME,
          folderName,
        };
        base.groups[0] = group;
      }
      if (!group) {
        group = {
          id: `group_${folderName}`,
          name: folderName,
          folderName,
          sort: base.groups.length,
          isSystem: false,
          createTime: nowIso(),
          updateTime: nowIso(),
        };
        if (!groupFolderSet.has(folderName)) {
          base.groups.push(group);
          groupFolderSet.add(folderName);
        }
      }

      const noteEntries = await fs.promises
        .readdir(path.join(notebookPath, folderName), { withFileTypes: true })
        .catch(() => []);
      for (const noteEntry of noteEntries) {
        if (!noteEntry.isDirectory()) continue;
        const noteFolderPath = path.join(notebookPath, folderName, noteEntry.name);
        const rawMeta = await readJson(path.join(noteFolderPath, 'meta.json'), {});
        const rawDelta = await readJson(
          path.join(noteFolderPath, 'content.delta.json'),
          buildEmptyDelta(),
        );
        notes.push({
          id: ensureString(rawMeta.id) || noteEntry.name,
          title: ensureString(rawMeta.title) || noteEntry.name,
          groupId: ensureString(rawMeta.groupId) || group.id,
          folderName: ensureString(rawMeta.folderName) || noteEntry.name,
          tagColor: ensureString(rawMeta.tagColor),
          isPinned: rawMeta.isPinned === true,
          isDeleted: false,
          deletedAt: '',
          createTime: ensureString(rawMeta.createTime) || nowIso(),
          updateTime: ensureString(rawMeta.updateTime) || nowIso(),
          preview: ensureString(rawMeta.preview) || makePreviewText(rawDelta),
          assetCount: Number(rawMeta.assetCount) || 0,
          contentRev: Math.max(0, Math.trunc(Number(rawMeta.contentRev) || 0)),
        });
      }
    }

    const trashEntries = await fs.promises
      .readdir(getTrashRoot(notebookPath), { withFileTypes: true })
      .catch(() => []);
    for (const entry of trashEntries) {
      if (!entry.isDirectory()) continue;
      const noteFolderPath = path.join(getTrashRoot(notebookPath), entry.name);
      const rawMeta = await readJson(path.join(noteFolderPath, 'meta.json'), {});
      const rawDelta = await readJson(
        path.join(noteFolderPath, 'content.delta.json'),
        buildEmptyDelta(),
      );
      const preferredGroupId = ensureString(rawMeta.groupId);
      const groupId =
        preferredGroupId && base.groups.some(group => group.id === preferredGroupId)
          ? preferredGroupId
          : DEFAULT_GROUP_ID;
      notes.push({
        id: ensureString(rawMeta.id) || entry.name,
        title: ensureString(rawMeta.title) || entry.name,
        groupId,
        folderName: ensureString(rawMeta.folderName) || entry.name,
        tagColor: ensureString(rawMeta.tagColor),
        isPinned: rawMeta.isPinned === true,
        isDeleted: true,
        deletedAt:
          ensureString(rawMeta.deletedAt) ||
          ensureString(rawMeta.updateTime) ||
          nowIso(),
        createTime: ensureString(rawMeta.createTime) || nowIso(),
        updateTime: ensureString(rawMeta.updateTime) || nowIso(),
        preview: ensureString(rawMeta.preview) || makePreviewText(rawDelta),
        assetCount: Number(rawMeta.assetCount) || 0,
        contentRev: Math.max(0, Math.trunc(Number(rawMeta.contentRev) || 0)),
      });
    }

    base.notes = notes;
    return base;
  }

  async _loadNotebookContext({ knex, user, requiredActions = ['view'] }) {
    const notebookPath = await this._getNotebookPath(user);
    if (!notebookPath) {
      throw this._toError('notes.NOTEBOOK_NOT_SELECTED', 404);
    }
    const normalizedActions = this._normalizeRequiredActions(requiredActions);
    await this._assertPathPermissionsAll(
      knex,
      user,
      notebookPath,
      normalizedActions,
    );

    const st = await fs.promises.stat(notebookPath).catch(() => null);
    if (!st || !st.isDirectory()) {
      throw this._toError('notes.NOTEBOOK_NOT_FOUND', 404);
    }

    const manifestPath = getManifestPath(notebookPath);
    const manifest = await readJson(manifestPath, null);
    if (!manifest || manifest.app !== APP_MARK) {
      throw this._toError('notes.NOTEBOOK_INVALID', 400);
    }

    let index = await readJson(getIndexPath(notebookPath), null);
    if (!index) {
      index = await this._repairIndexFromDisk(notebookPath);
      const canPersistIndex = normalizedActions.some(action =>
        ['upload', 'update', 'delete'].includes(action),
      );
      if (canPersistIndex) {
        index = await this._saveIndex(notebookPath, index);
      } else {
        index = ensureDefaultGroup(index);
      }
    } else {
      index = ensureDefaultGroup(index);
    }

    return { notebookPath, manifest, index };
  }

  _sortedGroups(index) {
    const normalized = ensureDefaultGroup(index);
    const groups = [...normalized.groups];
    return groups.sort((a, b) => {
      if (a.isSystem === true && b.isSystem !== true) return -1;
      if (a.isSystem !== true && b.isSystem === true) return 1;
      return Number(a.sort || 0) - Number(b.sort || 0);
    });
  }

  _serializeGroupCounts(index) {
    const normalized = ensureDefaultGroup(index);
    const counts = new Map();
    for (const note of normalized.notes) {
      const key = ensureString(note.groupId) || DEFAULT_GROUP_ID;
      const current = counts.get(key) || { activeCount: 0, deletedCount: 0 };
      if (note.isDeleted === true) {
        current.deletedCount += 1;
      } else {
        current.activeCount += 1;
      }
      counts.set(key, current);
    }
    return this._sortedGroups(normalized).map(group => {
      const current = counts.get(group.id) || { activeCount: 0, deletedCount: 0 };
      return {
        ...group,
        noteCount: current.activeCount,
        deletedCount: current.deletedCount,
      };
    });
  }

  _serializeNote(index, note) {
    const group = getGroupById(index, note.groupId);
    return {
      ...note,
      groupName: group ? group.name : DEFAULT_GROUP_NAME,
    };
  }

  async _noteMatchesKeyword(ctx, note, keyword) {
    const lowered = ensureString(keyword).trim().toLowerCase();
    if (!lowered) return true;
    const summaryHaystack =
      `${ensureString(note.title)} ${ensureString(note.preview)}`.toLowerCase();
    if (summaryHaystack.includes(lowered)) {
      return true;
    }
    const delta = await this._loadNoteDelta(ctx, note);
    return extractPlainTextFromDelta(delta).toLowerCase().includes(lowered);
  }

  async getNotebookStatus({ knex, user }) {
    const notebookPath = await this._getNotebookPath(user);
    if (!notebookPath) {
      return { selected: false };
    }
    try {
      const ctx = await this._loadNotebookContext({
        knex,
        user,
        requiredActions: ['view'],
      });
      return this._buildNotebookInfo(ctx.notebookPath, ctx.manifest, ctx.index);
    } catch (_) {
      return {
        selected: false,
        folderPath: notebookPath,
      };
    }
  }

  async selectNotebook({ knex, user, folderPath }) {
    const targetPath = path.resolve(ensureString(folderPath).trim());
    if (!targetPath) {
      throw this._toError('file.INVALID_PARAMS', 400);
    }
    const st = await fs.promises.stat(targetPath).catch(() => null);
    if (!st || !st.isDirectory()) {
      throw this._toError('common.NOT_FOUND', 404);
    }

    await fs.promises.access(targetPath, fs.constants.R_OK | fs.constants.W_OK);

    let manifest = await readJson(getManifestPath(targetPath), null);
    let index = await readJson(getIndexPath(targetPath), null);

    if (manifest && manifest.app === APP_MARK) {
      await this._assertPathPermission(knex, user, targetPath, 'view');
      if (!index) {
        await this._assertPathPermission(knex, user, targetPath, 'update');
        index = await this._repairIndexFromDisk(targetPath);
        index = await this._saveIndex(targetPath, index);
      } else {
        index = ensureDefaultGroup(index);
      }
    } else {
      await this._assertPathPermission(knex, user, targetPath, 'upload');
      const empty = await isDirEmpty(targetPath);
      if (!empty) {
        throw this._toError('notes.NOTEBOOK_FOLDER_NOT_EMPTY', 400);
      }
      manifest = createManifest();
      index = createDefaultIndex();
      await ensureDir(getTrashRoot(targetPath));
      await this._saveManifest(targetPath, manifest);
      await this._saveIndex(targetPath, index);
    }

    await this._saveNotebookPath(user, targetPath);
    return {
      notebook: this._buildNotebookInfo(targetPath, manifest, index),
      groups: this._serializeGroupCounts(index),
    };
  }

  async getState({ knex, user, groupId = '', keyword = '', includeDeleted = false }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['view'],
    });
    const normalizedGroupId = ensureString(groupId).trim();
    const q = ensureString(keyword).trim().toLowerCase();
    let filteredNotes = ctx.index.notes.filter(note => {
      if (includeDeleted) {
        if (note.isDeleted !== true) return false;
      } else if (note.isDeleted === true) {
        return false;
      }
      if (normalizedGroupId && normalizedGroupId !== 'all' && note.groupId !== normalizedGroupId) {
        return false;
      }
      return true;
    });
    if (q) {
      const matched = await Promise.all(
        filteredNotes.map(async note => ({
          note,
          matched: await this._noteMatchesKeyword(ctx, note, q),
        })),
      );
      filteredNotes = matched.filter(item => item.matched).map(item => item.note);
    }
    const notes = filteredNotes
      .sort((a, b) => {
        const pinDelta = Number(b.isPinned === true) - Number(a.isPinned === true);
        if (pinDelta !== 0) return pinDelta;
        return ensureString(b.updateTime).localeCompare(ensureString(a.updateTime));
      })
      .map(note => this._serializeNote(ctx.index, note));

    return {
      notebook: this._buildNotebookInfo(ctx.notebookPath, ctx.manifest, ctx.index),
      groups: this._serializeGroupCounts(ctx.index),
      notes,
    };
  }

  async createGroup({ knex, user, name }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['upload'],
    });
    const displayName = sanitizeName(name, '');
    if (!displayName) {
      throw this._toError('file.INVALID_PARAMS', 400);
    }
    if (ctx.index.groups.some(group => group.name === displayName)) {
      throw this._toError('file.PATH_ALREADY_EXISTS', 409);
    }

    const existingNames = new Set(ctx.index.groups.map(group => group.folderName));
    const folderName = pickUniqueFolderName(displayName, existingNames);
    const group = {
      id: `group_${Date.now()}_${Math.round(Math.random() * 1e6)}`,
      name: displayName,
      folderName,
      sort:
        Math.max(
          0,
          ...ctx.index.groups
            .filter(item => item.isSystem !== true)
            .map(item => Number(item.sort) || 0),
        ) + 1,
      isSystem: false,
      createTime: nowIso(),
      updateTime: nowIso(),
    };
    await ensureDir(getGroupPath(ctx.notebookPath, group));
    ctx.index.groups.push(group);
    ctx.index = await this._saveIndex(ctx.notebookPath, ctx.index);
    return {
      group,
      groups: this._serializeGroupCounts(ctx.index),
    };
  }

  async updateGroup({ knex, user, groupId, name }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['update'],
    });
    const group = getGroupById(ctx.index, groupId);
    if (!group || group.isSystem) {
      throw this._toError('common.NOT_FOUND', 404);
    }
    const displayName = sanitizeName(name, '');
    if (!displayName) {
      throw this._toError('file.INVALID_PARAMS', 400);
    }
    if (ctx.index.groups.some(item => item.id !== group.id && item.name === displayName)) {
      throw this._toError('file.PATH_ALREADY_EXISTS', 409);
    }

    const existingNames = new Set(
      ctx.index.groups
        .filter(item => item.id !== group.id)
        .map(item => item.folderName),
    );
    const nextFolderName = pickUniqueFolderName(displayName, existingNames);
    const oldGroupPath = getGroupPath(ctx.notebookPath, group);
    const nextGroup = {
      ...group,
      name: displayName,
      folderName: nextFolderName,
      updateTime: nowIso(),
    };
    const newGroupPath = getGroupPath(ctx.notebookPath, nextGroup);
    if (oldGroupPath !== newGroupPath && (await pathExists(oldGroupPath))) {
      await fs.promises.rename(oldGroupPath, newGroupPath);
    }

    ctx.index.groups = ctx.index.groups.map(item =>
      item.id === group.id ? nextGroup : item,
    );
    ctx.index = await this._saveIndex(ctx.notebookPath, ctx.index);
    return {
      group: nextGroup,
      groups: this._serializeGroupCounts(ctx.index),
    };
  }

  async deleteGroup({ knex, user, groupId }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['delete'],
    });
    const group = getGroupById(ctx.index, groupId);
    if (!group || group.isSystem) {
      throw this._toError('common.NOT_FOUND', 404);
    }
    const existsNotes = ctx.index.notes.some(note => note.groupId === group.id);
    if (existsNotes) {
      throw this._toError('notes.GROUP_NOT_EMPTY', 400);
    }

    const groupPath = getGroupPath(ctx.notebookPath, group);
    if (await pathExists(groupPath)) {
      await fs.promises.rm(groupPath, { recursive: true, force: true });
    }
    ctx.index.groups = ctx.index.groups.filter(item => item.id !== group.id);
    ctx.index = await this._saveIndex(ctx.notebookPath, ctx.index);
    return { groups: this._serializeGroupCounts(ctx.index) };
  }

  async reorderGroups({ knex, user, orderedGroupIds }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['update'],
    });
    const customGroups = this._sortedGroups(ctx.index).filter(item => item.isSystem !== true);
    const nextIds = Array.isArray(orderedGroupIds)
      ? orderedGroupIds.map(id => ensureString(id).trim()).filter(Boolean)
      : [];
    if (customGroups.length !== nextIds.length) {
      throw this._toError('file.INVALID_PARAMS', 400);
    }
    const currentIdSet = new Set(customGroups.map(item => item.id));
    for (const groupId of nextIds) {
      if (!currentIdSet.has(groupId)) {
        throw this._toError('file.INVALID_PARAMS', 400);
      }
    }
    const rankMap = new Map(nextIds.map((id, index) => [id, index + 1]));
    ctx.index.groups = ctx.index.groups.map(group => {
      if (group.isSystem === true) return group;
      return {
        ...group,
        sort: rankMap.get(group.id) || 0,
        updateTime: nowIso(),
      };
    });
    ctx.index = await this._saveIndex(ctx.notebookPath, ctx.index);
    return {
      groups: this._serializeGroupCounts(ctx.index),
    };
  }

  async createNote({ knex, user, groupId, title }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['upload'],
    });
    const group = getGroupById(ctx.index, groupId || DEFAULT_GROUP_ID);
    if (!group) {
      throw this._toError('common.NOT_FOUND', 404);
    }

    const note = createNoteRecord({
      title: title ?? '',
      groupId: group.id,
    });
    note.folderName = `${sanitizeName(note.title, 'untitled')}_${note.id.slice(0, 8)}`;

    const noteDir = getNotePath(ctx.notebookPath, group, note);
    await ensureDir(noteDir);
    await ensureDir(getNoteAssetsPath(ctx.notebookPath, group, note));
    await writeJson(getNoteMetaPath(ctx.notebookPath, group, note), note);
    await writeJson(getNoteContentPath(ctx.notebookPath, group, note), buildEmptyDelta());

    ctx.index.notes.push(note);
    ctx.index = await this._saveIndex(ctx.notebookPath, ctx.index);
    return {
      note: this._serializeNote(ctx.index, note),
      groups: this._serializeGroupCounts(ctx.index),
    };
  }

  async _loadNoteDelta(ctx, note) {
    const group = getGroupById(ctx.index, note.groupId) || {
      id: DEFAULT_GROUP_ID,
      name: DEFAULT_GROUP_NAME,
      folderName: DEFAULT_GROUP_NAME,
    };
    const filePath = note.isDeleted
      ? path.join(getDeletedNotePath(ctx.notebookPath, note), 'content.delta.json')
      : getNoteContentPath(ctx.notebookPath, group, note);
    return readJson(filePath, buildEmptyDelta());
  }

  _resolveNoteFolderPath(ctx, note) {
    if (note.isDeleted === true) {
      return getDeletedNotePath(ctx.notebookPath, note);
    }
    const group = getGroupById(ctx.index, note.groupId) || {
      id: DEFAULT_GROUP_ID,
      name: DEFAULT_GROUP_NAME,
      folderName: DEFAULT_GROUP_NAME,
    };
    return getNotePath(ctx.notebookPath, group, note);
  }

  _normalizeExportFormat(format) {
    const value = ensureString(format).trim().toLowerCase();
    if (value === 'md' || value === 'markdown') return 'markdown';
    if (value === 'txt') return 'txt';
    if (value === 'pdf') return 'pdf';
    throw this._toError('file.INVALID_PARAMS', 400);
  }

  async _renderPdfBufferFromHtml(html) {
    let app;
    let BrowserWindow;
    try {
      ({ app, BrowserWindow } = require('electron'));
    } catch (_) {
      throw this._toError('common.ERROR', 500);
    }
    if (!app || !BrowserWindow) {
      throw this._toError('common.ERROR', 500);
    }
    await app.whenReady();
    const win = new BrowserWindow({
      show: false,
      width: 1024,
      height: 1440,
      webPreferences: {
        sandbox: true,
        contextIsolation: true,
      },
    });
    try {
      await win.loadURL(
        `data:text/html;charset=utf-8,${encodeURIComponent(html)}`,
      );
      return await win.webContents.printToPDF({
        printBackground: true,
        preferCSSPageSize: true,
      });
    } finally {
      if (!win.isDestroyed()) {
        win.destroy();
      }
    }
  }

  async exportNote({ knex, user, noteId, format }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['download'],
    });
    const note = getNoteById(ctx.index, noteId);
    if (!note) {
      throw this._toError('common.NOT_FOUND', 404);
    }
    const normalizedFormat = this._normalizeExportFormat(format);
    const delta = await this._loadNoteDelta(ctx, note);
    const noteFolderPath = this._resolveNoteFolderPath(ctx, note);
    if (normalizedFormat === 'txt') {
      return {
        buffer: Buffer.from(buildTextDocument(note, delta), 'utf8'),
        contentType: 'text/plain; charset=utf-8',
        fileName: buildExportFileName(note, 'txt'),
      };
    }
    if (normalizedFormat === 'markdown') {
      return {
        buffer: Buffer.from(buildMarkdownDocument(note, delta), 'utf8'),
        contentType: 'text/markdown; charset=utf-8',
        fileName: buildExportFileName(note, 'markdown'),
      };
    }
    return {
      buffer: await this._renderPdfBufferFromHtml(
        buildHtmlDocument(note, delta, noteFolderPath),
      ),
      contentType: 'application/pdf',
      fileName: buildExportFileName(note, 'pdf'),
    };
  }

  async getNoteDetail({ knex, user, noteId }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['view'],
    });
    const note = getNoteById(ctx.index, noteId);
    if (!note) {
      throw this._toError('common.NOT_FOUND', 404);
    }
    const delta = await this._loadNoteDelta(ctx, note);
    return {
      note: this._serializeNote(ctx.index, note),
      delta,
      revision: Math.max(0, Math.trunc(Number(note.contentRev) || 0)),
    };
  }

  async saveNote({ knex, user, noteId, title, baseRevision, deltaPatch }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['update'],
    });
    const note = getNoteById(ctx.index, noteId);
    if (!note || note.isDeleted === true) {
      throw this._toError('common.NOT_FOUND', 404);
    }
    const group = getGroupById(ctx.index, note.groupId);
    if (!group) {
      throw this._toError('common.NOT_FOUND', 404);
    }

    const currentRevision = Math.max(0, Math.trunc(Number(note.contentRev) || 0));
    const requestRevision = Math.max(0, Math.trunc(Number(baseRevision) || 0));
    if (requestRevision !== currentRevision) {
      throw this._toError('common.ERROR', 409);
    }

    const nextTitle = sanitizeName(title ?? note.title ?? '', '');
    const currentDelta = await this._loadNoteDelta(ctx, note);
    const nextDelta = Array.isArray(deltaPatch)
      ? applyDeltaPatch(currentDelta, deltaPatch)
      : normalizeStoredDelta(currentDelta);
    if (!nextDelta) {
      throw this._toError('file.INVALID_PARAMS', 400);
    }
    const noteDir = getNotePath(ctx.notebookPath, group, note);
    await ensureDir(noteDir);
    const assetsDir = getNoteAssetsPath(ctx.notebookPath, group, note);
    await ensureDir(assetsDir);
    const assetEntries = await fs.promises.readdir(assetsDir).catch(() => []);

    const nextNote = {
      ...note,
      title: nextTitle,
      preview: makePreviewText(nextDelta),
      assetCount: assetEntries.length,
      updateTime: nowIso(),
      contentRev: currentRevision + (Array.isArray(deltaPatch) ? 1 : 0),
    };

    await writeJson(getNoteContentPath(ctx.notebookPath, group, note), nextDelta);
    await writeJson(getNoteMetaPath(ctx.notebookPath, group, note), nextNote);

    ctx.index.notes = ctx.index.notes.map(item =>
      item.id === note.id ? nextNote : item,
    );
    ctx.index = await this._saveIndex(ctx.notebookPath, ctx.index);
    return {
      note: this._serializeNote(ctx.index, nextNote),
      revision: nextNote.contentRev,
    };
  }

  _normalizeMetaTargetIds(noteIds, noteId) {
    if (noteIds !== undefined) {
      return this._normalizeNoteIds(noteIds);
    }
    const normalizedId = ensureString(noteId).trim();
    if (!normalizedId) {
      throw this._toError('file.INVALID_PARAMS', 400);
    }
    return [normalizedId];
  }

  async _updateNoteMetaInContext(ctx, noteId, { title, tagColor, isPinned }) {
    const note = getNoteById(ctx.index, noteId);
    if (!note) {
      throw this._toError('common.NOT_FOUND', 404);
    }
    const group = getGroupById(ctx.index, note.groupId) || {
      folderName: DEFAULT_GROUP_NAME,
    };
    const nextNote = {
      ...note,
      title: title === undefined ? note.title : sanitizeName(title ?? '', ''),
      tagColor: tagColor === undefined ? note.tagColor : ensureString(tagColor).trim(),
      isPinned: isPinned === undefined ? note.isPinned : isPinned === true,
      updateTime: nowIso(),
    };
    ctx.index.notes = ctx.index.notes.map(item =>
      item.id === note.id ? nextNote : item,
    );
    if (note.isDeleted !== true) {
      await writeJson(getNoteMetaPath(ctx.notebookPath, group, nextNote), nextNote);
    }
    return this._serializeNote(ctx.index, nextNote);
  }

  async updateNoteMeta({ knex, user, noteIds, noteId, title, tagColor, isPinned }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['update'],
    });
    const normalizedIds = this._normalizeMetaTargetIds(noteIds, noteId);
    const updatedNotes = [];
    for (const currentNoteId of normalizedIds) {
      updatedNotes.push(
        await this._updateNoteMetaInContext(ctx, currentNoteId, {
          title,
          tagColor,
          isPinned,
        }),
      );
    }
    ctx.index = await this._saveIndex(ctx.notebookPath, ctx.index);
    return {
      note: updatedNotes[0] || null,
      notes: updatedNotes,
      updatedCount: updatedNotes.length,
    };
  }

  _buildMovePlans(ctx, noteIds, targetGroupId) {
    const workingNotes = normalizeIndex(ctx.index).notes.map(note => ({ ...note }));
    const plans = [];
    for (const noteId of noteIds) {
      const noteIndex = workingNotes.findIndex(item => item.id === noteId);
      const note = noteIndex >= 0 ? workingNotes[noteIndex] : null;
      if (!note || note.isDeleted === true) {
        throw this._toError('common.NOT_FOUND', 404);
      }
      const sourceGroup = getGroupById(ctx.index, note.groupId);
      const targetGroup = getGroupById(ctx.index, targetGroupId);
      if (!sourceGroup || !targetGroup) {
        throw this._toError('common.NOT_FOUND', 404);
      }
      if (sourceGroup.id === targetGroup.id) {
        plans.push({
          noteId: note.id,
          originalNote: cloneJson(note),
          nextNote: cloneJson(note),
          moved: false,
        });
        continue;
      }

      const existingNames = new Set(
        workingNotes
          .filter(item => item.groupId === targetGroup.id && item.id !== note.id)
          .map(item => item.folderName),
      );
      const nextFolderName = pickUniqueFolderName(
        ensureString(note.folderName) || ensureString(note.title) || 'untitled',
        existingNames,
      );
      const nextNote = {
        ...note,
        groupId: targetGroup.id,
        folderName: nextFolderName,
        updateTime: nowIso(),
      };
      workingNotes[noteIndex] = nextNote;
      plans.push({
        noteId: note.id,
        originalNote: cloneJson(note),
        nextNote: cloneJson(nextNote),
        moved: true,
      });
    }
    return plans;
  }

  async _rollbackMovePlans(ctx, plans) {
    for (const plan of [...plans].reverse()) {
      if (!plan.moved) continue;
      const sourceGroup = getGroupById(ctx.index, plan.originalNote.groupId);
      const targetGroup = getGroupById(ctx.index, plan.nextNote.groupId);
      if (!sourceGroup || !targetGroup) continue;
      const sourcePath = getNotePath(ctx.notebookPath, sourceGroup, plan.originalNote);
      const targetPath = getNotePath(ctx.notebookPath, targetGroup, plan.nextNote);
      if (await pathExists(targetPath)) {
        await ensureDir(getGroupPath(ctx.notebookPath, sourceGroup));
        await fs.promises.rename(targetPath, sourcePath).catch(() => {});
      }
      if (await pathExists(sourcePath)) {
        await writeJson(
          getNoteMetaPath(ctx.notebookPath, sourceGroup, plan.originalNote),
          plan.originalNote,
        ).catch(() => {});
      }
    }
  }

  async _executeMovePlans(ctx, plans) {
    const executed = [];
    const nextNoteMap = new Map(plans.map(plan => [plan.noteId, plan.nextNote]));
    const originalNotes = ctx.index.notes.map(note => ({ ...note }));
    try {
      for (const plan of plans) {
        if (!plan.moved) continue;
        const sourceGroup = getGroupById(ctx.index, plan.originalNote.groupId);
        const targetGroup = getGroupById(ctx.index, plan.nextNote.groupId);
        if (!sourceGroup || !targetGroup) {
          throw this._toError('common.NOT_FOUND', 404);
        }
        const sourcePath = getNotePath(ctx.notebookPath, sourceGroup, plan.originalNote);
        const targetPath = getNotePath(ctx.notebookPath, targetGroup, plan.nextNote);
        await ensureDir(getGroupPath(ctx.notebookPath, targetGroup));
        if (await pathExists(sourcePath)) {
          await fs.promises.rename(sourcePath, targetPath);
        }
        await writeJson(
          getNoteMetaPath(ctx.notebookPath, targetGroup, plan.nextNote),
          plan.nextNote,
        );
        executed.push(plan);
      }
      ctx.index.notes = ctx.index.notes.map(note => nextNoteMap.get(note.id) || note);
      ctx.index = await this._saveIndex(ctx.notebookPath, ctx.index);
    } catch (error) {
      ctx.index.notes = originalNotes;
      await this._rollbackMovePlans(ctx, executed);
      throw error;
    }
    return plans.map(plan =>
      this._serializeNote(ctx.index, nextNoteMap.get(plan.noteId) || plan.originalNote),
    );
  }

  async moveNote({ knex, user, noteId, targetGroupId }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['update'],
    });
    const movedNote = (
      await this._executeMovePlans(
        ctx,
        this._buildMovePlans(ctx, [ensureString(noteId).trim()], targetGroupId),
      )
    )[0];
    return {
      note: movedNote,
      groups: this._serializeGroupCounts(ctx.index),
    };
  }

  async batchMoveNotes({ knex, user, noteIds, targetGroupId }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['update'],
    });
    const normalizedIds = this._normalizeNoteIds(noteIds);
    const movedNotes = await this._executeMovePlans(
      ctx,
      this._buildMovePlans(ctx, normalizedIds, targetGroupId),
    );
    return {
      notes: movedNotes,
      movedCount: movedNotes.length,
      groups: this._serializeGroupCounts(ctx.index),
    };
  }

  async _deleteNoteInContext(ctx, noteId) {
    const note = getNoteById(ctx.index, noteId);
    if (!note) {
      throw this._toError('common.NOT_FOUND', 404);
    }
    if (note.isDeleted === true) {
      return this._serializeNote(ctx.index, note);
    }
    const group = getGroupById(ctx.index, note.groupId);
    if (!group) {
      throw this._toError('common.NOT_FOUND', 404);
    }
    const sourcePath = getNotePath(ctx.notebookPath, group, note);
    const trashPath = getDeletedNotePath(ctx.notebookPath, note);
    await ensureDir(getTrashRoot(ctx.notebookPath));
    if (await pathExists(sourcePath)) {
      await fs.promises.rename(sourcePath, trashPath);
    }
    const nextNote = {
      ...note,
      isDeleted: true,
      deletedAt: nowIso(),
      updateTime: nowIso(),
    };
    ctx.index.notes = ctx.index.notes.map(item =>
      item.id === note.id ? nextNote : item,
    );
    return this._serializeNote(ctx.index, nextNote);
  }

  async deleteNote({ knex, user, noteId }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['delete'],
    });
    const deletedNote = await this._deleteNoteInContext(ctx, noteId);
    ctx.index = await this._saveIndex(ctx.notebookPath, ctx.index);
    return {
      note: deletedNote,
      groups: this._serializeGroupCounts(ctx.index),
    };
  }

  async batchDeleteNotes({ knex, user, noteIds }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['delete'],
    });
    const normalizedIds = this._normalizeNoteIds(noteIds);
    const deletedNotes = [];
    for (const noteId of normalizedIds) {
      deletedNotes.push(await this._deleteNoteInContext(ctx, noteId));
    }
    ctx.index = await this._saveIndex(ctx.notebookPath, ctx.index);
    return {
      notes: deletedNotes,
      deletedCount: deletedNotes.length,
      groups: this._serializeGroupCounts(ctx.index),
    };
  }

  async _restoreNoteInContext(ctx, noteId) {
    const note = getNoteById(ctx.index, noteId);
    if (!note || note.isDeleted !== true) {
      throw this._toError('common.NOT_FOUND', 404);
    }
    const group = getGroupById(ctx.index, note.groupId) || getGroupById(ctx.index, DEFAULT_GROUP_ID);
    if (!group) {
      throw this._toError('common.NOT_FOUND', 404);
    }

    const trashPath = getDeletedNotePath(ctx.notebookPath, note);
    const existingNames = new Set(
      ctx.index.notes
        .filter(item => item.groupId === group.id && item.id !== note.id)
        .map(item => item.folderName),
    );
    const nextFolderName = pickUniqueFolderName(
      ensureString(note.folderName) || ensureString(note.title) || 'untitled',
      existingNames,
    );
    const nextNote = {
      ...note,
      groupId: group.id,
      folderName: nextFolderName,
      isDeleted: false,
      deletedAt: '',
      updateTime: nowIso(),
    };
    await ensureDir(getGroupPath(ctx.notebookPath, group));
    const targetPath = getNotePath(ctx.notebookPath, group, nextNote);
    if (await pathExists(trashPath)) {
      await fs.promises.rename(trashPath, targetPath);
    }
    await writeJson(getNoteMetaPath(ctx.notebookPath, group, nextNote), nextNote);
    ctx.index.notes = ctx.index.notes.map(item =>
      item.id === note.id ? nextNote : item,
    );
    return this._serializeNote(ctx.index, nextNote);
  }

  async restoreNote({ knex, user, noteId }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['upload', 'delete'],
    });
    const restoredNote = await this._restoreNoteInContext(ctx, noteId);
    ctx.index = await this._saveIndex(ctx.notebookPath, ctx.index);
    return {
      note: restoredNote,
      groups: this._serializeGroupCounts(ctx.index),
    };
  }

  async batchRestoreNotes({ knex, user, noteIds }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['upload', 'delete'],
    });
    const normalizedIds = this._normalizeNoteIds(noteIds);
    const restoredNotes = [];
    for (const noteId of normalizedIds) {
      restoredNotes.push(await this._restoreNoteInContext(ctx, noteId));
    }
    ctx.index = await this._saveIndex(ctx.notebookPath, ctx.index);
    return {
      notes: restoredNotes,
      restoredCount: restoredNotes.length,
      groups: this._serializeGroupCounts(ctx.index),
    };
  }

  async _permanentlyDeleteNoteInContext(ctx, noteId) {
    const note = getNoteById(ctx.index, noteId);
    if (!note) {
      throw this._toError('common.NOT_FOUND', 404);
    }
    const folderPath = note.isDeleted
      ? getDeletedNotePath(ctx.notebookPath, note)
      : getNotePath(
          ctx.notebookPath,
          getGroupById(ctx.index, note.groupId) || {
            folderName: DEFAULT_GROUP_NAME,
          },
          note,
        );
    if (await pathExists(folderPath)) {
      await fs.promises.rm(folderPath, { recursive: true, force: true });
    }
    ctx.index.notes = ctx.index.notes.filter(item => item.id !== note.id);
  }

  async permanentlyDeleteNote({ knex, user, noteId }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['delete'],
    });
    await this._permanentlyDeleteNoteInContext(ctx, noteId);
    ctx.index = await this._saveIndex(ctx.notebookPath, ctx.index);
    return { groups: this._serializeGroupCounts(ctx.index) };
  }

  async batchPermanentlyDeleteNotes({ knex, user, noteIds }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['delete'],
    });
    const normalizedIds = this._normalizeNoteIds(noteIds);
    for (const noteId of normalizedIds) {
      await this._permanentlyDeleteNoteInContext(ctx, noteId);
    }
    ctx.index = await this._saveIndex(ctx.notebookPath, ctx.index);
    return {
      deletedCount: normalizedIds.length,
      groups: this._serializeGroupCounts(ctx.index),
    };
  }

  async saveUploadedAsset({ knex, user, noteId, sourcePath, originalName }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['upload'],
    });
    const note = getNoteById(ctx.index, noteId);
    if (!note || note.isDeleted === true) {
      throw this._toError('common.NOT_FOUND', 404);
    }
    const group = getGroupById(ctx.index, note.groupId);
    if (!group) {
      throw this._toError('common.NOT_FOUND', 404);
    }
    const ext = path.extname(ensureString(originalName)).toLowerCase();
    const baseName = sanitizeName(path.basename(originalName, ext), 'asset');
    const assetName = `${baseName}_${Date.now()}${ext || '.bin'}`;
    const assetsDir = getNoteAssetsPath(ctx.notebookPath, group, note);
    await ensureDir(assetsDir);
    const targetPath = path.join(assetsDir, assetName);
    await moveFile(sourcePath, targetPath, {
      allowedSourceRoot: config.getUploadTempDir(),
      allowedTargetRoot: assetsDir,
    });
    const assetEntries = await fs.promises.readdir(assetsDir).catch(() => []);
    const nextNote = {
      ...note,
      assetCount: assetEntries.length,
      updateTime: nowIso(),
    };
    await writeJson(getNoteMetaPath(ctx.notebookPath, group, nextNote), nextNote);
    ctx.index.notes = ctx.index.notes.map(item =>
      item.id === note.id ? nextNote : item,
    );
    ctx.index = await this._saveIndex(ctx.notebookPath, ctx.index);
    return {
      assetName,
      assetPath: `assets/${assetName}`,
      note: this._serializeNote(ctx.index, nextNote),
    };
  }

  async resolveAsset({ knex, user, noteId, assetName }) {
    const ctx = await this._loadNotebookContext({
      knex,
      user,
      requiredActions: ['view'],
    });
    const note = getNoteById(ctx.index, noteId);
    if (!note || note.isDeleted === true) {
      throw this._toError('common.NOT_FOUND', 404);
    }
    const group = getGroupById(ctx.index, note.groupId);
    if (!group) {
      throw this._toError('common.NOT_FOUND', 404);
    }
    const safeName = path.basename(ensureString(assetName).trim());
    if (!safeName) {
      throw this._toError('file.INVALID_PARAMS', 400);
    }
    const fullPath = path.join(
      getNoteAssetsPath(ctx.notebookPath, group, note),
      safeName,
    );
    const st = await fs.promises.stat(fullPath).catch(() => null);
    if (!st || !st.isFile()) {
      throw this._toError('common.NOT_FOUND', 404);
    }
    return { filePath: fullPath, note: this._serializeNote(ctx.index, note) };
  }
}

module.exports = new NotesService();
