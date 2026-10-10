/**
 * 智能相册「节假日」模式工具
 *
 * 节假日分两类：
 * 1. 公历固定日期（元旦/劳动节/国庆等）：直接用月-日即可，无需按年份展开；
 * 2. 日期每年变化的节假日：
 *    - 春节/端午/中秋：农历节日，使用 1900-2100 农历数据表换算为公历日期；
 *    - 清明节：二十四节气之一，公历 4 月 4 日或 5 日，用寿星公式计算；
 *    - 复活节：春分月圆后的第一个星期日，用公历 computus 算法计算。
 *
 * 农历及节气仅展开支持 1976-2076（2026 年前后 50 年），查询时按年份做 IN/区间匹配。
 */

const HOLIDAY_MIN_YEAR = 1976;
const HOLIDAY_MAX_YEAR = 2076;

/**
 * 农历年信息表 1900-2100（经典通用数据表）
 * 每个数据位描述一个农历月的大小，低 4 位为闰月月份，0x10000 位描述闰月大小
 */
const LUNAR_INFO = [
  0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2,
  0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977,
  0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970,
  0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950,
  0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557,
  0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0,
  0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0,
  0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6,
  0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570,
  0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x055c0, 0x0ab60, 0x096d5, 0x092e0,
  0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5,
  0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930,
  0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530,
  0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45,
  0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0,
  0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20, 0x1a6c4, 0x0aae0,
  0x0a2e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4,
  0x052d0, 0x0a9b8, 0x0a950, 0x0b490, 0x04b73, 0x06ad0, 0x0a4d0, 0x0d8b8, 0x0d950, 0x0f6a3,
  0x05b50, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45, 0x0b5a0,
  0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0, 0x14b63,
  0x09370,
];

function _lunarLeapMonth(year) {
  return LUNAR_INFO[year - 1900] & 0xf;
}

function _lunarLeapDays(year) {
  if (_lunarLeapMonth(year)) {
    return LUNAR_INFO[year - 1900] & 0x10000 ? 30 : 29;
  }
  return 0;
}

function _lunarMonthDays(year, month) {
  return LUNAR_INFO[year - 1900] & (0x10000 >> month) ? 30 : 29;
}

function _lunarYearDays(year) {
  let sum = 348;
  for (let i = 0x8000; i > 0x8; i >>= 1) {
    if (LUNAR_INFO[year - 1900] & i) sum += 1;
  }
  return sum + _lunarLeapDays(year);
}

/**
 * 农历日期转公历日期（仅支持非闰月，节日均取正常月份）
 * @returns {{year:number, month:number, day:number}|null}
 */
function lunarToSolar(year, month, day) {
  if (year < 1900 || year > 2100) return null;
  if (month < 1 || month > 12) return null;

  let offset = 0;
  for (let i = 1900; i < year; i++) {
    offset += _lunarYearDays(i);
  }
  const leap = _lunarLeapMonth(year);
  for (let i = 1; i < month; i++) {
    offset += _lunarMonthDays(year, i);
    // 闰月插在对应的正常月份之后
    if (i === leap) offset += _lunarLeapDays(year);
  }
  if (day < 1 || day > _lunarMonthDays(year, month)) return null;
  offset += day - 1;

  // 农历 1900 年正月初一 = 公历 1900-01-31
  const ms = Date.UTC(1900, 0, 31) + offset * 86400000;
  const d = new Date(ms);
  return { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() };
}

/**
 * 公历复活节（西方教会，Gregorian computus）
 * @returns {{month:number, day:number}}
 */
function easterSunday(year) {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31);
  const day = ((h + l - 7 * m + 114) % 31) + 1;
  return { month, day };
}

/**
 * 清明节日期（寿星公式，适用 1900-2099）
 * 注意按年份所在世纪取不同常数，1976-2076 范围内与实际节气日期一致
 */
function qingmingDay(year) {
  const y = year % 100;
  const c = year >= 2000 ? 4.81 : 5.59;
  const day = Math.floor(y * 0.2422 + c) - Math.floor(y / 4);
  return { month: 4, day };
}

function _formatYmd(year, month, day) {
  const mm = String(month).padStart(2, '0');
  const dd = String(day).padStart(2, '0');
  return `${year}-${mm}-${dd}`;
}

function _addDays(year, month, day, delta) {
  const d = new Date(Date.UTC(year, month - 1, day) + delta * 86400000);
  return { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() };
}

/**
 * 节假日定义
 * kind:
 *  - fixed_day       公历固定单日 { mm, dd }
 *  - fixed_range     公历固定区间 { start:{mm,dd}, end:{mm,dd} }
 *  - lunar_day       农历单日 { month, day }
 *  - spring_festival 春节区间（除夕夜 ~ 正月初七）
 *  - qingming        清明（按年计算的单日）
 *  - easter          复活节（按年计算的单日）
 */
const HOLIDAY_DEFS = {
  new_year: { kind: 'fixed_range', start: { mm: 1, dd: 1 }, end: { mm: 1, dd: 3 } },
  spring_festival: { kind: 'spring_festival' },
  qingming: { kind: 'qingming' },
  labor_day: { kind: 'fixed_range', start: { mm: 5, dd: 1 }, end: { mm: 5, dd: 3 } },
  dragon_boat: { kind: 'lunar_day', month: 5, day: 5 },
  mid_autumn: { kind: 'lunar_day', month: 8, day: 15 },
  national_day: { kind: 'fixed_range', start: { mm: 10, dd: 1 }, end: { mm: 10, dd: 7 } },
  women_day: { kind: 'fixed_day', mm: 3, dd: 8 },
  youth_day: { kind: 'fixed_day', mm: 5, dd: 4 },
  children_day: { kind: 'fixed_day', mm: 6, dd: 1 },
  army_day: { kind: 'fixed_day', mm: 8, dd: 1 },
  christmas: { kind: 'fixed_day', mm: 12, dd: 25 },
  easter: { kind: 'easter' },
};

const HOLIDAY_KEYS = Object.keys(HOLIDAY_DEFS);

function isValidHolidayKey(key) {
  return Object.prototype.hasOwnProperty.call(HOLIDAY_DEFS, String(key || ''));
}

/**
 * 取公历固定月日（每年相同），null 表示该节日不是公历固定日期
 * @returns {{start:string,end:string}|null} 月日格式 MM-DD
 */
function getFixedMonthDayRange(key) {
  const def = HOLIDAY_DEFS[String(key || '')];
  if (!def) return null;
  if (def.kind === 'fixed_day') {
    const md = _formatYmd(2000, def.mm, def.dd).slice(5);
    return { start: md, end: md };
  }
  if (def.kind === 'fixed_range') {
    return {
      start: _formatYmd(2000, def.start.mm, def.start.dd).slice(5),
      end: _formatYmd(2000, def.end.mm, def.end.dd).slice(5),
    };
  }
  return null;
}

/**
 * 按年份展开某节日的公历日期区间
 * @returns {Array<{start:string,end:string}>}
 */
function getHolidayYearWindows(key, year) {
  const def = HOLIDAY_DEFS[String(key || '')];
  if (!def) return [];

  if (def.kind === 'lunar_day') {
    const d = lunarToSolar(year, def.month, def.day);
    if (!d) return [];
    const date = _formatYmd(d.year, d.month, d.day);
    return [{ start: date, end: date }];
  }

  if (def.kind === 'spring_festival') {
    // 正月初一
    const first = lunarToSolar(year, 1, 1);
    if (!first) return [];
    // 除夕 = 正月初一前一天；初七 = 正月初一后 6 天
    const chuxi = _addDays(first.year, first.month, first.day, -1);
    const day7 = _addDays(first.year, first.month, first.day, 6);
    return [
      {
        start: _formatYmd(chuxi.year, chuxi.month, chuxi.day),
        end: _formatYmd(day7.year, day7.month, day7.day),
      },
    ];
  }

  if (def.kind === 'qingming') {
    const d = qingmingDay(year);
    const date = _formatYmd(year, d.month, d.day);
    return [{ start: date, end: date }];
  }

  if (def.kind === 'easter') {
    const d = easterSunday(year);
    const date = _formatYmd(year, d.month, d.day);
    return [{ start: date, end: date }];
  }

  return [];
}

/**
 * 展开支持年份范围内的所有区间（农历/清明/复活节用）
 */
function getHolidayWindows(key) {
  if (!isValidHolidayKey(key)) return [];
  const windows = [];
  for (let year = HOLIDAY_MIN_YEAR; year <= HOLIDAY_MAX_YEAR; year++) {
    windows.push(...getHolidayYearWindows(key, year));
  }
  return windows;
}

module.exports = {
  HOLIDAY_MIN_YEAR,
  HOLIDAY_MAX_YEAR,
  HOLIDAY_KEYS,
  isValidHolidayKey,
  getFixedMonthDayRange,
  getHolidayYearWindows,
  getHolidayWindows,
  lunarToSolar,
  easterSunday,
  qingmingDay,
};
