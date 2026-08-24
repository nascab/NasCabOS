function parseFilterContentText(text) {
  try {
    const parsed = JSON.parse(String(text || '{}'));
    if (!parsed || typeof parsed !== 'object') return {};
    return parsed;
  } catch (_) {
    return {};
  }
}

function _normalizeCondition(cond, tableAlias) {
  if (!cond || typeof cond !== 'object') return null;
  const field = String(cond.field || '').trim();
  const operator = String(cond.operator || '').trim();
  const value = cond.value;

  const fieldMap = {
    name: { type: 'name', columns: [`${tableAlias}.nfo_name`, `${tableAlias}.filename`] },
    nfo_name: { type: 'text', column: `${tableAlias}.nfo_name` },
    nfo_actor: { type: 'text', column: `${tableAlias}.nfo_actor` },
    nfo_director: { type: 'text', column: `${tableAlias}.nfo_director` },
    nfo_genres: { type: 'text', column: `${tableAlias}.nfo_genres` },
    nfo_regions: { type: 'text', column: `${tableAlias}.nfo_regions` },
    filename: { type: 'text', column: `${tableAlias}.filename` },
    path: { type: 'text', column: `${tableAlias}.path` },
    year: { type: 'number', column: `${tableAlias}.nfo_year`, scale: 1 },
    score: { type: 'number', column: `${tableAlias}.nfo_score`, scale: 1 },
    duration_min: { type: 'number', column: `${tableAlias}.duration`, scale: 60 },
  };
  const meta = fieldMap[field];
  if (!meta) return null;

  if (meta.type === 'text') {
    if (operator !== 'contains') return null;
    const s = String(value || '').trim();
    if (!s) return null;
    return { type: 'contains', column: meta.column, value: s };
  }

  if (meta.type === 'name') {
    if (operator !== 'contains') return null;
    const s = String(value || '').trim();
    if (!s) return null;
    return { type: 'contains_any', columns: meta.columns, value: s };
  }

  if (operator !== 'gt' && operator !== 'eq' && operator !== 'lt') return null;
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return { type: 'compare', column: meta.column, operator, value: n * meta.scale };
}

function _applySingleCondition(qb, condition) {
  if (condition.type === 'contains') {
    qb.where(condition.column, 'like', `%${condition.value}%`);
    return;
  }
  if (condition.type === 'contains_any') {
    qb.where(builder => {
      for (const col of condition.columns) {
        builder.orWhere(col, 'like', `%${condition.value}%`);
      }
    });
    return;
  }
  if (condition.type === 'compare') {
    if (condition.operator === 'gt') qb.where(condition.column, '>', condition.value);
    else if (condition.operator === 'lt') qb.where(condition.column, '<', condition.value);
    else qb.where(condition.column, '=', condition.value);
  }
}

function applyConditionFilter(query, filterContent, tableAlias) {
  const logic = String(filterContent.logic || 'and').toLowerCase() === 'or' ? 'or' : 'and';
  const conditions = Array.isArray(filterContent.conditions) ? filterContent.conditions : [];
  const mapped = conditions.map(c => _normalizeCondition(c, tableAlias)).filter(Boolean);
  if (mapped.length === 0) return;

  if (logic === 'or') {
    query.where(builder => {
      for (const c of mapped) {
        builder.orWhere(b => _applySingleCondition(b, c));
      }
    });
    return;
  }
  for (const c of mapped) {
    _applySingleCondition(query, c);
  }
}

function applySmartAlbumFilter(query, type, filterContent, tableAlias) {
  applyConditionFilter(query, filterContent, tableAlias);
}

module.exports = {
  parseFilterContentText,
  applySmartAlbumFilter,
  applyConditionFilter,
};
