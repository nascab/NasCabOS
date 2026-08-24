const path = require('path');

function parsePathListText(text) {
  if (!text) return [];
  try {
    const arr = JSON.parse(String(text));
    return Array.isArray(arr) ? arr.map(v => String(v || '').trim()).filter(Boolean) : [];
  } catch (_) {
    return [];
  }
}

function intersectPaths(validPaths, limitPaths) {
  const base = Array.isArray(validPaths) ? validPaths : [];
  const limit = Array.isArray(limitPaths) ? limitPaths : [];
  const intersected = [];
  for (const vp of base) {
    for (const sp of limit) {
      if (sp.startsWith(vp)) {
        intersected.push(sp);
      } else if (vp.startsWith(sp)) {
        intersected.push(vp);
      }
    }
  }
  return [...new Set(intersected)];
}

function applyPathPrefixFilter(query, pathColumn, paths) {
  const list = Array.isArray(paths) ? paths.map(p => String(p || '').trim()).filter(Boolean) : [];
  if (list.length === 0) {
    query.whereRaw('1 = 0');
    return;
  }
  query.where(builder => {
    for (const p of list) {
      builder.orWhere(function () {
        this.where(pathColumn, p).orWhere(pathColumn, 'like', `${p}${path.sep}%`);
      });
    }
  });
}

module.exports = {
  parsePathListText,
  intersectPaths,
  applyPathPrefixFilter,
};
