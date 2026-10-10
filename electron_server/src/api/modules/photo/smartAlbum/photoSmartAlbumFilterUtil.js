const photoSmartAlbumHolidayUtil = require('./photoSmartAlbumHolidayUtil');

function _isDateString(s) {
  if (!s || typeof s !== 'string') return false;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return Number.isFinite(d.getTime());
}

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
    filename: { column: `${tableAlias}.filename`, type: 'text' },
    path: { column: `${tableAlias}.path`, type: 'text' },
    camera: { column: `${tableAlias}.camera`, type: 'text' },
    size_mb: { column: `${tableAlias}.size`, type: 'number', scale: 1024 * 1024 },
    duration_min: { column: `${tableAlias}.duration`, type: 'number', scale: 60 },
    width: { column: `${tableAlias}.width`, type: 'number', scale: 1 },
    height: { column: `${tableAlias}.height`, type: 'number', scale: 1 },
  };
  const meta = fieldMap[field];
  if (!meta) return null;

  if (meta.type === 'text') {
    if (operator !== 'contains') return null;
    const s = String(value || '').trim();
    if (!s) return null;
    return { column: meta.column, operator: 'contains', value: s };
  }

  if (operator !== 'gt' && operator !== 'eq' && operator !== 'lt') return null;
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return { column: meta.column, operator, value: n * meta.scale };
}

function _applySingleCondition(qb, condition) {
  if (condition.operator === 'contains') {
    qb.where(condition.column, 'like', `%${condition.value}%`);
    return;
  }
  if (condition.operator === 'gt') {
    qb.where(condition.column, '>', condition.value);
    return;
  }
  if (condition.operator === 'eq') {
    qb.where(condition.column, '=', condition.value);
    return;
  }
  if (condition.operator === 'lt') {
    qb.where(condition.column, '<', condition.value);
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

function applySmartDateFilter(query, filterContent, tableAlias) {
  const mode = String(filterContent.mode || '').trim();
  if (mode === 'anniversary') {
    const repeat = String(filterContent.repeat || '').trim();
    const month = Number(filterContent.month);
    const day = Number(filterContent.day);
    if (repeat === 'year' && Number.isFinite(month) && Number.isFinite(day)) {
      const mm = String(Math.max(1, Math.min(12, month))).padStart(2, '0');
      const dd = String(Math.max(1, Math.min(31, day))).padStart(2, '0');
      query.whereRaw(`strftime('%m-%d', ${tableAlias}.original_date) = ?`, [`${mm}-${dd}`]);
    } else if (repeat === 'month' && Number.isFinite(day)) {
      const dd = String(Math.max(1, Math.min(31, day))).padStart(2, '0');
      query.whereRaw(`strftime('%d', ${tableAlias}.original_date) = ?`, [dd]);
    }
    return;
  }

  if (mode === 'fixed') {
    const date = String(filterContent.date || '').trim();
    const operator = String(filterContent.operator || 'on').trim();
    if (!_isDateString(date)) return;
    if (operator === 'before') {
      query.where(`${tableAlias}.original_date`, '<=', date);
    } else if (operator === 'after') {
      query.where(`${tableAlias}.original_date`, '>=', date);
    } else {
      query.where(`${tableAlias}.original_date`, date);
    }
    return;
  }

  if (mode === 'range') {
    const start = String(filterContent.start || '').trim();
    const end = String(filterContent.end || '').trim();
    if (!_isDateString(start) || !_isDateString(end)) return;
    const [s, e] = start <= end ? [start, end] : [end, start];
    query.whereBetween(`${tableAlias}.original_date`, [s, e]);
    return;
  }

  if (mode === 'holiday') {
    applyHolidayFilter(query, filterContent, tableAlias);
  }
}

function applyHolidayFilter(query, filterContent, tableAlias) {
  const holidayKey = String(filterContent.holiday || '').trim();
  if (!photoSmartAlbumHolidayUtil.isValidHolidayKey(holidayKey)) return;

  const column = `${tableAlias}.original_date`;

  // 公历固定月日的节日（元旦/劳动节/国庆/妇女节等）直接按月-日匹配
  const fixed = photoSmartAlbumHolidayUtil.getFixedMonthDayRange(holidayKey);
  if (fixed) {
    if (fixed.start === fixed.end) {
      query.whereRaw(`strftime('%m-%d', ${column}) = ?`, [fixed.start]);
    } else {
      query.whereRaw(`strftime('%m-%d', ${column}) BETWEEN ? AND ?`, [
        fixed.start,
        fixed.end,
      ]);
    }
    return;
  }

  // 农历节日/清明/复活节：展开支持年份范围内的公历日期，按区间 OR 匹配
  const windows = photoSmartAlbumHolidayUtil.getHolidayWindows(holidayKey);
  if (windows.length === 0) return;
  query.where(builder => {
    windows.forEach((w, idx) => {
      if (idx === 0) {
        builder.whereBetween(column, [w.start, w.end]);
      } else {
        builder.orWhereBetween(column, [w.start, w.end]);
      }
    });
  });
}

/**
 * 校验筛选内容是否合法（仅对节假日模式做严格校验，其他模式保持兼容）
 */
function isValidSmartAlbumFilter(type, filterContent) {
  const t = String(type || 'condition').trim();
  if (t !== 'smart_date') return true;
  const content =
    filterContent && typeof filterContent === 'object' ? filterContent : {};
  if (String(content.mode || '').trim() === 'holiday') {
    return photoSmartAlbumHolidayUtil.isValidHolidayKey(content.holiday);
  }
  return true;
}

function applySmartAlbumFilter(query, type, filterContent, tableAlias) {
  const t = String(type || 'condition').trim();
  if (t === 'smart_date') {
    applySmartDateFilter(query, filterContent, tableAlias);
    return;
  }
  applyConditionFilter(query, filterContent, tableAlias);
}

module.exports = {
  parseFilterContentText,
  applySmartAlbumFilter,
  applySmartDateFilter,
  applyConditionFilter,
  applyHolidayFilter,
  isValidSmartAlbumFilter,
};
