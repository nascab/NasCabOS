import { L10n } from '../../../core/localization/L10n';

/** 时间解析结果：ms 为绝对时间；treatAsLocal 表示服务器返回的是无时区的本地时间字符串 */
class ParsedTime {
  ms: number = 0;
  treatAsLocal: boolean = false;
}

function pad2(n: number): string {
  return `${n < 10 ? '0' : ''}${n}`;
}

function isNumeric(s: string): boolean {
  return /^\d+$/.test(s);
}

/** 字符串是否带时区标记（Z 结尾或 +hh:mm / +hhmm 偏移结尾） */
function hasTimezoneMark(iso: string): boolean {
  return /Z$/i.test(iso) || /[+-]\d{2}:?\d{2}$/.test(iso);
}

function fromEpoch(n: number): ParsedTime {
  const p = new ParsedTime();
  const isMs = n > 10000000000;
  p.ms = isMs ? n : n * 1000;
  return p;
}

/**
 * 解析「上次登录」时间（对齐 Flutter _LoggedInCard._formatLocalTime）：
 * 无时区字符串按 UTC 解释后转本地显示（避免服务端下发 naive UTC 串重复加时区）。
 */
function parseLastLogin(v: Object | undefined | null): ParsedTime | undefined {
  if (v === undefined || v === null) {
    return undefined;
  }
  if (typeof v === 'number') {
    return fromEpoch(v);
  }
  if (typeof v !== 'string') {
    return undefined;
  }
  const s = v.trim();
  if (s.length === 0) {
    return undefined;
  }
  if (isNumeric(s)) {
    return fromEpoch(Number(s));
  }
  const iso = s.replace(' ', 'T');
  const t = Date.parse(hasTimezoneMark(iso) ? iso : `${iso}Z`);
  if (!Number.isFinite(t)) {
    return undefined;
  }
  const p = new ParsedTime();
  p.ms = t;
  p.treatAsLocal = false;
  return p;
}

/**
 * 解析会员相关时间（对齐 Flutter _parseMembershipDateTime）：
 * 无时区字符串按服务器当地时间直接展示，不再 toLocal。
 */
function parseMembershipTime(v: Object | undefined | null): ParsedTime | undefined {
  if (v === undefined || v === null) {
    return undefined;
  }
  if (typeof v === 'number') {
    return fromEpoch(v);
  }
  if (typeof v !== 'string') {
    return undefined;
  }
  const s = v.trim();
  if (s.length === 0) {
    return undefined;
  }
  if (isNumeric(s)) {
    return fromEpoch(Number(s));
  }
  const iso = s.replace(' ', 'T');
  const naive = !hasTimezoneMark(iso);
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) {
    return undefined;
  }
  const p = new ParsedTime();
  p.ms = t;
  p.treatAsLocal = naive;
  return p;
}

function formatMs(ms: number, withSeconds: boolean): string {
  const dt = new Date(ms);
  const base = `${dt.getFullYear()}-${pad2(dt.getMonth() + 1)}-${pad2(dt.getDate())} `
    + `${pad2(dt.getHours())}:${pad2(dt.getMinutes())}`;
  return withSeconds ? `${base}:${pad2(dt.getSeconds())}` : base;
}

/** 上次登录时间显示（yyyy-MM-dd HH:mm；解析失败回退原值） */
export function formatLastLoginText(v: Object | undefined | null): string {
  const p = parseLastLogin(v);
  if (p === undefined) {
    return v === undefined || v === null ? '' : `${v}`;
  }
  return formatMs(p.ms, false);
}

/** 会员时间显示（yyyy-MM-dd HH:mm；解析失败回退原值/'-'） */
export function formatMembershipTime(v: Object | undefined | null): string {
  const p = parseMembershipTime(v);
  if (p === undefined) {
    return v === undefined || v === null ? '-' : `${v}`;
  }
  return formatMs(p.ms, false);
}

/** 会员时间是否已过期（早于当前时间） */
export function isMembershipExpired(v: Object | undefined | null): boolean {
  const p = parseMembershipTime(v);
  if (p === undefined) {
    return false;
  }
  return p.ms <= Date.now();
}

/**
 * DDNS 上次解析时间显示（对齐 Flutter _formatLocalDateTime；支持 epoch 秒/毫秒与 ISO 串）。
 * 本地时区显示 yyyy-MM-dd HH:mm:ss（Flutter 为 DateFormat.yMd(loc).add_Hms()）。
 */
export function formatDdnsTime(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  if (typeof v === 'number') {
    return formatMs(v > 1000000000000 ? v : v * 1000, true);
  }
  if (typeof v !== 'string') {
    return `${v}`;
  }
  const s = v.trim();
  if (s.length === 0) {
    return '';
  }
  if (isNumeric(s)) {
    const n = Number(s);
    return formatMs(n > 1000000000000 ? n : n * 1000, true);
  }
  const t = Date.parse(s.replace(' ', 'T'));
  if (!Number.isFinite(t)) {
    return s;
  }
  return formatMs(t, true);
}

/** 错误码翻译显示（对齐 Flutter _formatError：能翻译用译文，否则原文） */
export function formatErrorCode(raw: string): string {
  const code = raw.trim();
  if (code.length === 0) {
    return '';
  }
  const translated = L10n.t(code, '');
  if (translated.length > 0 && translated !== code) {
    return translated;
  }
  return code;
}
