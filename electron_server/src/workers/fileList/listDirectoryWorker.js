'use strict';

const { parentPort } = require('worker_threads');
const fs = require('fs');
const path = require('path');
const config = require('../../config/config');
const FileUtil = require('../../utils/fileUtil');

function buildSegments(resolved) {
  const sep = path.sep;
  const isWin = process.platform === 'win32';
  const segs = [];
  if (isWin) {
    const m = resolved.match(/^([A-Za-z]:)(\\|\/)/);
    let acc = '';
    if (m) {
      acc = `${m[1]}${sep}`;
      segs.push({ name: m[1], path: acc });
    }
    const rest = resolved.replace(m ? m[0] : '', '');
    const parts = rest.split(/\\|\//).filter(Boolean);
    for (const part of parts) {
      acc = path.join(acc || '', part);
      segs.push({ name: part, path: acc });
    }
    return segs;
  }

  let acc = sep;
  segs.push({ name: sep, path: sep });
  const parts = resolved.split(sep).filter(Boolean);
  for (const part of parts) {
    acc = path.join(acc, part);
    segs.push({ name: part, path: acc });
  }
  return segs;
}

function buildListPayload(base, items) {
  const sep = path.sep;
  const segments = base ? buildSegments(base) : [];
  return { base, items, segments, sep };
}

async function pathToItem(fullPath, opts = {}) {
  const resolved = path.resolve(fullPath);
  const includeExists = !!opts.includeExists;
  const isDirHint = typeof opts.isDirHint === 'boolean' ? opts.isDirHint : null;
  const nameHint = typeof opts.name === 'string' ? opts.name : null;

  let exists = false;
  let size = null;
  let mtimeMs = null;
  let isDir = isDirHint !== null ? isDirHint : true;

  try {
    const st = await fs.promises.stat(resolved);
    exists = true;
    isDir = st.isDirectory();
    mtimeMs = st.mtimeMs;
    size = isDir ? null : st.size;
  } catch (_) {}

  let name = nameHint || path.basename(resolved) || resolved;
  if (process.platform === 'win32') {
    const m = resolved.match(/^([A-Za-z]:)[\\/]*$/);
    if (m) name = m[1];
  }

  const ext = isDir ? '' : path.extname(resolved).toLowerCase();
  const type = isDir ? 'dir' : config.getFileType(ext);

  const item = { name, path: resolved, type, size, mtimeMs, ext };
  if (includeExists) item.exists = exists;
  return item;
}

async function getRoots() {
  const isWin = process.platform === 'win32';
  if (isWin) {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
    const roots = [];
    for (const l of letters) {
      const p = `${l}:\\`;
      try {
        if (fs.existsSync(p)) {
          let mtimeMs = null;
          try {
            const st = await fs.promises.stat(p);
            mtimeMs = st.mtimeMs;
          } catch (_) {}
          roots.push({ path: p, name: `${l}:`, type: 'dir', size: null, mtimeMs, ext: '' });
        }
      } catch (_) {}
    }
    return roots;
  }

  const candidates = ['/', '/Users', '/Volumes'];
  const exist = candidates.filter(p => {
    try {
      return fs.existsSync(p);
    } catch {
      return false;
    }
  });

  const result = [];
  for (const p of exist) {
    let mtimeMs = null;
    try {
      const st = await fs.promises.stat(p);
      mtimeMs = st.mtimeMs;
    } catch (_) {}
    result.push({
      path: p,
      name: path.basename(p) || p,
      type: 'dir',
      size: null,
      mtimeMs,
      ext: '',
    });
  }
  return result;
}

async function listDirectory(dirPath, onlyDir = true, includeHidden = false) {
  if (!dirPath) throw new Error('file.INVALID_PATH');
  let resolved = path.resolve(dirPath);
  const st = await fs.promises.stat(resolved);
  // 请求路径本身是文件时仍列出其父目录（兼容文件浏览等），但须显式标记，避免客户端把「文件」误判为「文件夹」
  let targetIsFile = false;
  if (st.isFile()) {
    targetIsFile = true;
    resolved = path.dirname(resolved);
  }
  const entries = await fs.promises.readdir(resolved, { withFileTypes: true });
  const items = (
    await Promise.all(
      entries.map(ent =>
        pathToItem(path.join(resolved, ent.name), {
          name: ent.name,
          isDirHint: !ent.isFile(),
        })
      )
    )
  )
    .filter(i => (onlyDir ? i.type === 'dir' : true))
    .filter(i => {
      if (includeHidden) return true;
      const n = i.name || '';
      return !n.startsWith('.');
    })
    .filter(i => !FileUtil.isSystemFile(i.name || ''));
  const payload = buildListPayload(resolved, items);
  if (targetIsFile) payload.targetIsFile = true;
  return payload;
}

async function listPathList(pathList, onlyDir = true, includeHidden = false, base = '') {
  const input = Array.isArray(pathList) ? pathList : [];
  const unique = new Map();
  for (const p of input) {
    if (typeof p !== 'string') continue;
    const trimmed = p.trim();
    if (!trimmed) continue;
    const resolved = path.resolve(trimmed);
    unique.set(resolved, true);
  }

  const items = await Promise.all(Array.from(unique.keys()).map(p => pathToItem(p, { includeExists: true })));

  const filtered = items
    .filter(i => (onlyDir ? i.type === 'dir' : true))
    .filter(i => {
      if (includeHidden) return true;
      const n = i.name || '';
      return !n.startsWith('.');
    })
    .filter(i => !FileUtil.isSystemFile(i.name || ''))
    .sort((a, b) => String(a.name || '').localeCompare(String(b.name || '')));

  const baseResolved = typeof base === 'string' && base.trim() ? path.resolve(base) : '';
  return buildListPayload(baseResolved, filtered);
}

async function listSourceDirs(sourcePaths) {
  const input = Array.isArray(sourcePaths) ? sourcePaths : [];
  const items = await Promise.all(
    input.map(async p => {
      let mtimeMs = null;
      let exists = false;
      try {
        const st = await fs.promises.stat(p);
        mtimeMs = st.mtimeMs;
        exists = !!st.isDirectory();
      } catch (_) {}
      return {
        path: p,
        name: path.basename(p) || p,
        type: 'dir',
        size: null,
        mtimeMs,
        ext: '',
        exists,
      };
    })
  );
  return { base: '', items, segments: [], sep: path.sep };
}

async function runTask(action, payload) {
  if (action === 'getRoots') return getRoots();
  if (action === 'listDirectory') return listDirectory(payload && payload.dirPath, !!(payload && payload.onlyDir), !!(payload && payload.includeHidden));
  if (action === 'listPathList') return listPathList(payload && payload.pathList, !!(payload && payload.onlyDir), !!(payload && payload.includeHidden), payload && payload.base);
  if (action === 'listSourceDirs') return listSourceDirs(payload && payload.sourcePaths);
  throw new Error('file.UNKNOWN_WORKER_TASK');
}

if (parentPort) {
  parentPort.on('message', async message => {
    const action = message && message.action ? String(message.action) : '';
    const payload = message && message.payload ? message.payload : null;

    try {
      const result = await runTask(action, payload);
      parentPort.postMessage({ ok: true, result });
    } catch (err) {
      parentPort.postMessage({ ok: false, error: err && err.message ? String(err.message) : String(err) });
    } finally {
      try {
        parentPort.close();
      } catch (_) {}
      process.exit(0);
    }
  });
}
