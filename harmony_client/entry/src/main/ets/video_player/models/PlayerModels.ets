/**
 * 视频播放器数据模型（对齐 Flutter video_player 模块的 playlist / stream info 结构）。
 */

import { asNum, asStr } from '../../video/models/VideoModels';

/** 播放列表条目（对齐 Flutter playlist Map：path/name/internalPath） */
export class PlayerPlaylistItem {
  path: string = '';
  internalPath: string = '';
  name: string = '';

  static fromRecord(obj: Record<string, Object>): PlayerPlaylistItem {
    const it = new PlayerPlaylistItem();
    it.path = asStr(obj['path']).trim();
    it.internalPath = asStr(obj['internalPath']).trim();
    const nfo = asStr(obj['nfo_name']).trim();
    it.name = nfo.length > 0 ? nfo : asStr(obj['name']).trim();
    return it;
  }
}

/** 轨道信息（音频/字幕；对齐 Flutter _rawAudioTracks/_rawSubtitleTracks Map 结构） */
export class PlayerTrackInfo {
  /** 容器内流索引（外挂字幕为 -1） */
  index: number = 0;
  /** 同类轨道中的序号（selectTrack/转码 audioIndex 用） */
  mapIndex: number = 0;
  /** 显示名 */
  label: string = '';
  isExternal: boolean = false;
  /** 外挂字幕文件路径 */
  path: string = '';
  filename: string = '';
  language: string = 'und';
  title: string = '';
  codecName: string = '';
  /** 外挂字幕来源（searched/uploaded），空表示不可删除 */
  source: string = '';
  /** 原始流完整描述（信息抽屉展示用） */
  raw: Record<string, Object> | undefined = undefined;
}

/** 片头/片尾自动跳过区间（秒） */
export class PlayerOpenSkipInfo {
  startSec: number = 0;
  endSec: number = 0;
}

/** /api/videoPlayer/info 解析结果 */
export class PlayerStreamInfo {
  durationSec: number = 0;
  sizeBytes: number = 0;
  openSkip: PlayerOpenSkipInfo = new PlayerOpenSkipInfo();
  audioTracks: PlayerTrackInfo[] = [];
  videoTracks: PlayerTrackInfo[] = [];
  /** 内嵌字幕轨道（不含外挂） */
  innerSubtitleTracks: PlayerTrackInfo[] = [];
  /** 外挂字幕轨道 */
  externalSubtitleTracks: PlayerTrackInfo[] = [];
  /** 服务端保存的偏好（audio_label/subtitle_label/playback_position） */
  preference: Record<string, Object> | undefined = undefined;

  static fromData(data: Record<string, Object>): PlayerStreamInfo {
    const info = new PlayerStreamInfo();
    const dur = data['duration'];
    if (typeof dur === 'number') {
      info.durationSec = Math.round(dur);
    } else if (typeof dur === 'string') {
      const parsed = parseFloat(dur);
      if (!Number.isNaN(parsed)) {
        info.durationSec = Math.round(parsed);
      }
    }
    info.sizeBytes = Math.round(asNum(data['size']));
    const skip = data['openSkip'];
    if (skip !== undefined && skip !== null && skip instanceof Object) {
      const sm = skip as Record<string, Object>;
      info.openSkip.startSec = clampSec(asNum(sm['startSec'] ?? sm['start_sec']));
      info.openSkip.endSec = clampSec(asNum(sm['endSec'] ?? sm['end_sec']));
    }
    const streams = asArrayValue(data['streams']);
    let audioOrder = 0;
    let subOrder = 0;
    for (const sObj of streams) {
      const s = sObj;
      const codecType = asStr(s['codec_type']).toLowerCase();
      if (codecType === 'video') {
        const t = new PlayerTrackInfo();
        t.index = Math.round(asNum(s['index']));
        t.codecName = asStr(s['codec_name']).toLowerCase();
        t.raw = s;
        info.videoTracks.push(t);
      } else if (codecType === 'audio') {
        const tags = asRecordValue(s['tags']);
        const lang = asStr(tags['language']).trim().length > 0 ? asStr(tags['language']) : 'und';
        const title = asStr(tags['title']).trim().length > 0 ? asStr(tags['title']) : asStr(s['codec_name']);
        const t = new PlayerTrackInfo();
        t.index = Math.round(asNum(s['index']));
        t.mapIndex = audioOrder;
        t.label = `Audio ${t.index} (${lang}) - ${title}`;
        t.language = lang;
        t.title = title;
        t.codecName = asStr(s['codec_name']).toLowerCase();
        t.raw = s;
        info.audioTracks.push(t);
        audioOrder++;
      } else if (codecType === 'subtitle') {
        const tags = asRecordValue(s['tags']);
        const lang = asStr(tags['language']).trim().length > 0 ? asStr(tags['language']) : 'und';
        const title = asStr(tags['title']).trim().length > 0 ? asStr(tags['title']) : asStr(s['codec_name']);
        const t = new PlayerTrackInfo();
        t.index = Math.round(asNum(s['index']));
        t.mapIndex = subOrder;
        t.label = `(${lang}) ${title}`;
        t.isExternal = false;
        t.language = lang;
        t.title = title;
        t.codecName = asStr(s['codec_name']).toLowerCase();
        t.raw = s;
        info.innerSubtitleTracks.push(t);
        subOrder++;
      }
    }
    const extSubs = asArrayValue(data['externalSubtitles']);
    for (const eObj of extSubs) {
      const e = eObj;
      const t = new PlayerTrackInfo();
      t.index = -1;
      t.mapIndex = 0;
      t.isExternal = true;
      t.path = asStr(e['path']).trim();
      t.filename = asStr(e['filename']).trim();
      t.label = t.filename;
      t.language = asStr(e['language']).trim();
      t.source = asStr(e['source']).trim();
      t.codecName = asStr(e['ext']).toLowerCase();
      t.raw = e;
      info.externalSubtitleTracks.push(t);
    }
    const pref = data['preference'];
    if (pref !== undefined && pref !== null && pref instanceof Object) {
      info.preference = pref as Record<string, Object>;
    }
    return info;
  }
}

/** VTT 字幕 cue（毫秒时间轴） */
export class SubtitleCue {
  startMs: number = 0;
  endMs: number = 0;
  text: string = '';

  constructor(startMs: number, endMs: number, text: string) {
    this.startMs = startMs;
    this.endMs = endMs;
    this.text = text;
  }
}

function clampSec(v: number): number {
  if (!Number.isFinite(v) || v < 0) {
    return 0;
  }
  return Math.floor(v);
}

function asArrayValue(v: Object | undefined): Record<string, Object>[] {
  if (v === undefined || v === null || !Array.isArray(v)) {
    return [];
  }
  return (v as Object[]).filter((e: Object): boolean => e instanceof Object)
    .map((e: Object): Record<string, Object> => e as Record<string, Object>);
}

function asRecordValue(v: Object | undefined): Record<string, Object> {
  if (v !== undefined && v !== null && v instanceof Object && !Array.isArray(v)) {
    return v as Record<string, Object>;
  }
  return {} as Record<string, Object>;
}

/** 位图字幕编码（无法客户端渲染，需转码烧录） */
export function isBitmapSubtitleCodec(codecName: string): boolean {
  const v = codecName.toLowerCase().trim();
  return v === 'pgssub' || v === 'hdmv_pgs_subtitle' || v === 'vobsub' ||
    v === 'dvd_subtitle' || v === 'dvdsub' || v === 'dvb_subtitle' || v === 'xsub';
}

/** 位图外挂字幕扩展名 */
export function isBitmapSubtitleExt(ext: string): boolean {
  const v = ext.toLowerCase().trim();
  return v === '.sup' || v === '.sub' || v === '.idx';
}

/** 播放画质常量（对齐 Flutter qualityOptions） */
export const PLAYER_QUALITY_OPTIONS: string[] = [
  'original', '4k_20m', '4k_15m', '4k_10m', '1080p_8m', '1080p_5m',
  '1080p_3m', '1080p_2m', '720p_3m', '720p_2m', '720p_1m', '480p_1m'
];

const QUALITY_LABEL_SHORT: Map<string, string> = new Map<string, string>([
  ['4k_20m', '4K 20M'], ['4k_15m', '4K 15M'], ['4k_10m', '4K 10M'],
  ['1080p_8m', '1080P 8M'], ['1080p_5m', '1080P 5M'], ['1080p_3m', '1080P 3M'],
  ['1080p_2m', '1080P 2M'], ['720p_3m', '720P 3M'], ['720p_2m', '720P 2M'],
  ['720p_1m', '720P 1M'], ['480p_1m', '480P 1M']
]);

/** 画质短标签（quality 值 → 显示名） */
export function qualityLabelShort(quality: string, originalLabel: string, fallbackLabel: string): string {
  if (quality === 'original') {
    return originalLabel;
  }
  const v = QUALITY_LABEL_SHORT.get(quality);
  return v !== undefined ? v : fallbackLabel;
}

/** 默认转码画质 */
export const DEFAULT_TRANSCODE_QUALITY: string = '1080p_3m';
