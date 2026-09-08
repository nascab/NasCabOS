/**
 * WebVTT 解析（对齐 Flutter webvtt_parser.dart）：
 * 解析服务端 subtitle-vtt 接口返回的字幕文本，供客户端叠层渲染。
 */

import { SubtitleCue } from '../models/PlayerModels';

function parseVttTimestamp(raw: string): number | undefined {
  const s = raw.trim();
  if (s.length === 0) {
    return undefined;
  }
  const parts = s.split(':');
  if (parts.length < 2 || parts.length > 3) {
    return undefined;
  }
  let hours = 0;
  let minutes = 0;
  let seconds = 0;
  if (parts.length === 3) {
    hours = parseIntOr(parts[0], 0);
    minutes = parseIntOr(parts[1], 0);
    seconds = parseFloatOr(parts[2].replace(',', '.'));
  } else {
    minutes = parseIntOr(parts[0], 0);
    seconds = parseFloatOr(parts[1].replace(',', '.'));
  }
  if (hours < 0 || minutes < 0 || seconds < 0) {
    return undefined;
  }
  return Math.round(hours * 3600 * 1000 + minutes * 60 * 1000 + seconds * 1000);
}

function parseIntOr(v: string, fallback: number): number {
  const n = parseInt(v, 10);
  return Number.isNaN(n) ? fallback : n;
}

function parseFloatOr(v: string): number {
  const n = parseFloat(v);
  return Number.isNaN(n) ? 0 : n;
}

/** 解析 WebVTT 文本为按开始时间排序的 cue 列表 */
export function parseWebVtt(vttText: string): SubtitleCue[] {
  const normalized = vttText.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const lines = normalized.split('\n');
  const cues: SubtitleCue[] = [];

  let i = 0;
  // 跳过 BOM 与头部
  while (i < lines.length && lines[i].trim().length === 0) {
    i++;
  }
  if (i < lines.length) {
    const first = lines[i].trimStart();
    if (first.startsWith('\uFEFF')) {
      lines[i] = first.substring(1);
    }
  }
  if (i < lines.length && lines[i].trim().toUpperCase().startsWith('WEBVTT')) {
    i++;
  }

  while (i < lines.length) {
    while (i < lines.length && lines[i].trim().length === 0) {
      i++;
    }
    if (i >= lines.length) {
      break;
    }

    // 跳过 NOTE/STYLE/REGION 块
    const head = lines[i].trim();
    if (head.startsWith('NOTE') || head.startsWith('STYLE') || head.startsWith('REGION')) {
      i++;
      while (i < lines.length && lines[i].trim().length > 0) {
        i++;
      }
      continue;
    }

    // 可选 cue 标识行
    let timeLine = lines[i];
    if (!timeLine.includes('-->')) {
      i++;
      if (i >= lines.length) {
        break;
      }
      timeLine = lines[i];
    }

    const arrow = timeLine.indexOf('-->');
    if (arrow === -1) {
      i++;
      continue;
    }
    const left = timeLine.substring(0, arrow).trim();
    const rightPart = timeLine.substring(arrow + 3).trim();
    const right = rightPart.split(/\s+/)[0].trim();

    const startMs = parseVttTimestamp(left);
    const endMs = parseVttTimestamp(right);
    i++;
    if (startMs === undefined || endMs === undefined) {
      // 跳过该 cue 的文本行直到空行
      while (i < lines.length && lines[i].trim().length > 0) {
        i++;
      }
      continue;
    }

    const buf: string[] = [];
    while (i < lines.length && lines[i].trim().length > 0) {
      buf.push(lines[i]);
      i++;
    }
    const text = formatCueText(buf.join('\n').trim());
    if (text.length > 0 && endMs > startMs) {
      cues.push(new SubtitleCue(startMs, endMs, text));
    }
  }

  cues.sort((a: SubtitleCue, b: SubtitleCue): number => a.startMs - b.startMs);
  return cues;
}

/** 二分查找当前时间活跃的 cue（cues 必须已按 start 排序） */
export function findActiveCue(cues: SubtitleCue[], positionMs: number): SubtitleCue | undefined {
  if (cues.length === 0) {
    return undefined;
  }
  let lo = 0;
  let hi = cues.length - 1;
  let best = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    const c = cues[mid];
    if (c.startMs <= positionMs) {
      best = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  if (best < 0) {
    return undefined;
  }
  const c = cues[best];
  if (positionMs >= c.startMs && positionMs <= c.endMs) {
    return c;
  }
  return undefined;
}

/** ffmpeg WebVTT 常带 <br>/<font> 等标签；客户端叠层需转成纯文本 */
function formatCueText(raw: string): string {
  let s = raw.trim();
  if (s.length === 0) {
    return s;
  }
  s = s.replace(/<br\s*\/?>/gi, '\n');
  s = s.replace(/<[^>]*>/g, '');
  s = s.replace(/\{[^}]*\}/g, '');
  s = s.replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
  return s.trim();
}
