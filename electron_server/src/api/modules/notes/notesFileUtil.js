const fs = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');

const NOTEBOOK_MARK_DIR = '.nascab_notes';
const MANIFEST_FILE = 'manifest.json';
const INDEX_FILE = 'index.json';
const TRASH_DIR = 'trash';
const APP_MARK = 'nascabos_notes';
const INDEX_VERSION = 1;
const DEFAULT_GROUP_ID = 'all';
const DEFAULT_GROUP_NAME = 'all';
const LEGACY_DEFAULT_GROUP_NAMES = new Set(['all', '全部']);
const RESERVED_NAMES = new Set([NOTEBOOK_MARK_DIR]);
const IGNORE_ROOT_NAMES = new Set(['.DS_Store', 'Thumbs.db']);

function ensureString(v) {
  if (v === undefined || v === null) return '';
  return String(v);
}

function nowIso() {
  return new Date().toISOString();
}

function sanitizeName(input, fallback = 'untitled') {
  const raw = ensureString(input)
    .trim()
    .replace(/[\\/:*?"<>|]/g, ' ')
    .replace(/\s+/g, ' ')
    .replace(/^\.+|\.+$/g, '');
  const safe = raw || fallback;
  return safe.slice(0, 80);
}

async function ensureDir(dirPath) {
  await fs.promises.mkdir(dirPath, { recursive: true });
}

async function pathExists(targetPath) {
  try {
    await fs.promises.access(targetPath, fs.constants.F_OK);
    return true;
  } catch (_) {
    return false;
  }
}

async function isDirEmpty(dirPath) {
  const entries = await fs.promises.readdir(dirPath).catch(() => []);
  return entries.filter(name => !IGNORE_ROOT_NAMES.has(name)).length === 0;
}

async function readJson(filePath, fallback = null) {
  try {
    const raw = await fs.promises.readFile(filePath, 'utf8');
    return JSON.parse(raw);
  } catch (_) {
    return fallback;
  }
}

async function writeJson(filePath, value) {
  await ensureDir(path.dirname(filePath));
  const payload = JSON.stringify(value, null, 2);
  const tempPath = `${filePath}.${process.pid}.${Date.now()}.${Math.round(
    Math.random() * 1e9,
  )}.tmp`;
  let handle = null;
  try {
    handle = await fs.promises.open(tempPath, 'w');
    await handle.writeFile(payload, 'utf8');
    await handle.sync();
    await handle.close();
    handle = null;
    await fs.promises.rename(tempPath, filePath);
  } catch (error) {
    if (handle) {
      await handle.close().catch(() => {});
    }
    await fs.promises.unlink(tempPath).catch(() => {});
    throw error;
  }
}

function createDefaultIndex() {
  const now = nowIso();
  return {
    version: INDEX_VERSION,
    updatedAt: now,
    groups: [
      {
        id: DEFAULT_GROUP_ID,
        name: DEFAULT_GROUP_NAME,
        folderName: DEFAULT_GROUP_NAME,
        sort: 0,
        isSystem: true,
        createTime: now,
        updateTime: now,
      },
    ],
    notes: [],
  };
}

function createManifest() {
  const now = nowIso();
  return {
    app: APP_MARK,
    version: INDEX_VERSION,
    createTime: now,
    updateTime: now,
  };
}

function getNotebookMetaDir(notebookPath) {
  return path.join(notebookPath, NOTEBOOK_MARK_DIR);
}

function getManifestPath(notebookPath) {
  return path.join(getNotebookMetaDir(notebookPath), MANIFEST_FILE);
}

function getIndexPath(notebookPath) {
  return path.join(getNotebookMetaDir(notebookPath), INDEX_FILE);
}

function getTrashRoot(notebookPath) {
  return path.join(getNotebookMetaDir(notebookPath), TRASH_DIR);
}

function normalizeIndex(index) {
  const normalized = index && typeof index === 'object' ? index : {};
  const groups = Array.isArray(normalized.groups) ? normalized.groups : [];
  const notes = Array.isArray(normalized.notes) ? normalized.notes : [];
  return {
    version: INDEX_VERSION,
    updatedAt: ensureString(normalized.updatedAt) || nowIso(),
    groups,
    notes,
  };
}

function ensureDefaultGroup(index) {
  const next = normalizeIndex(index);
  const defaultGroupIndex = next.groups.findIndex(
    group => ensureString(group.id) === DEFAULT_GROUP_ID,
  );
  if (defaultGroupIndex >= 0) {
    const current = next.groups[defaultGroupIndex];
    next.groups[defaultGroupIndex] = {
      ...current,
      name: DEFAULT_GROUP_NAME,
      folderName: ensureString(current.folderName) || DEFAULT_GROUP_NAME,
      isSystem: true,
    };
    return next;
  }
  const exists = false;
  if (!exists) {
    const now = nowIso();
    next.groups.unshift({
      id: DEFAULT_GROUP_ID,
      name: DEFAULT_GROUP_NAME,
      folderName: DEFAULT_GROUP_NAME,
      sort: 0,
      isSystem: true,
      createTime: now,
      updateTime: now,
    });
  }
  return next;
}

function pickUniqueFolderName(baseName, existingNames = new Set()) {
  const safeBase = sanitizeName(baseName, 'untitled');
  let candidate = safeBase;
  let suffix = 2;
  while (existingNames.has(candidate) || RESERVED_NAMES.has(candidate)) {
    candidate = `${safeBase} ${suffix}`;
    suffix += 1;
  }
  existingNames.add(candidate);
  return candidate;
}

function getGroupById(index, groupId) {
  return ensureDefaultGroup(index).groups.find(group => ensureString(group.id) === ensureString(groupId)) || null;
}

function getNoteById(index, noteId) {
  return normalizeIndex(index).notes.find(note => ensureString(note.id) === ensureString(noteId)) || null;
}

function getGroupPath(notebookPath, group) {
  return path.join(notebookPath, ensureString(group.folderName));
}

function getNotePath(notebookPath, group, note) {
  return path.join(getGroupPath(notebookPath, group), ensureString(note.folderName || note.id));
}

function getNoteMetaPath(notebookPath, group, note) {
  return path.join(getNotePath(notebookPath, group, note), 'meta.json');
}

function getNoteContentPath(notebookPath, group, note) {
  return path.join(getNotePath(notebookPath, group, note), 'content.delta.json');
}

function getNoteAssetsPath(notebookPath, group, note) {
  return path.join(getNotePath(notebookPath, group, note), 'assets');
}

function getDeletedNotePath(notebookPath, note) {
  return path.join(getTrashRoot(notebookPath), ensureString(note.id));
}

function extractPlainTextFromDelta(deltaOps) {
  const ops = Array.isArray(deltaOps) ? deltaOps : [];
  return ops
    .map(op => {
      if (!op || typeof op !== 'object') return '';
      const insert = op.insert;
      if (typeof insert === 'string') return insert;
      if (insert && typeof insert === 'object') return ' ';
      return '';
    })
    .join('')
    .replace(/\s+/g, ' ')
    .trim();
}

function makePreviewText(deltaOps, maxLength = 120) {
  const plain = extractPlainTextFromDelta(deltaOps);
  if (plain.length <= maxLength) return plain;
  return `${plain.slice(0, maxLength)}...`;
}

function buildEmptyDelta() {
  return [{ insert: '\n' }];
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function isDefaultGroupFolderName(folderName) {
  return LEGACY_DEFAULT_GROUP_NAMES.has(ensureString(folderName).trim());
}

function createNoteRecord({ title = '', groupId = DEFAULT_GROUP_ID } = {}) {
  const now = nowIso();
  return {
    id: uuidv4(),
    title: sanitizeName(title, ''),
    groupId: ensureString(groupId) || DEFAULT_GROUP_ID,
    folderName: '',
    tagColor: '',
    isPinned: false,
    isDeleted: false,
    deletedAt: '',
    createTime: now,
    updateTime: now,
    preview: '',
    assetCount: 0,
    contentRev: 0,
  };
}

module.exports = {
  NOTEBOOK_MARK_DIR,
  MANIFEST_FILE,
  INDEX_FILE,
  TRASH_DIR,
  APP_MARK,
  INDEX_VERSION,
  DEFAULT_GROUP_ID,
  DEFAULT_GROUP_NAME,
  LEGACY_DEFAULT_GROUP_NAMES,
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
  getNotebookMetaDir,
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
};
