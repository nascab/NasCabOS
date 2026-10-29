import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { APIClient } from '../core/network/APIClient';
import { NetworkConfig } from '../core/network/NetworkConfig';
import { P2PService } from './P2PService';
import { P2pChannelUtil } from './P2pProtocol';
import { P2pStreamHandler } from './WebRTCClient';
import { HeaderMap } from '../common/HeaderMap';

/** 单次 socket send 的最大字节数（P2P 分块最大 128KB，这里再切一次保证稳定） */
const SOCKET_SEND_CHUNK = 64 * 1024;
/** 流式请求空闲超时：转码产片/原画大文件可能出现较长时间无数据，给足余量 */
const STREAM_IDLE_TIMEOUT_MS = 300000;

/** Range 缓存块大小（对齐 Flutter VideoRangeMemoryCache.blockSize） */
const RANGE_BLOCK_SIZE = 256 * 1024;
/** 单会话缓存上限（对齐 Flutter 默认 1GB 的保守值，控制设备内存占用） */
const RANGE_CACHE_MAX_BYTES = 256 * 1024 * 1024;
/** 尾部 moov 探测的单次上游范围（对齐 Flutter _maxTailUpstreamChunkBytes） */
const TAIL_PROBE_CHUNK = 1024 * 1024;
/** 正常播放的单次上游范围（对齐 Flutter _maxPlaybackUpstreamChunkBytes，禁止一次拖到 EOF） */
const PLAYBACK_CHUNK = 4 * 1024 * 1024;
/** 播放段上游 Range 按 1MB 对齐，重叠请求可复用同一段缓存 */
const PLAYBACK_ALIGN = 1024 * 1024;
/** 对外开放的缓存前缀上限（对齐 Flutter _maxPrefixServeBytes） */
const MAX_PREFIX_SERVE = 4 * 1024 * 1024;
/** 尾部探测允许回写的最小连续前缀 */
const MIN_PREFIX_TAIL = 4096;
/** 正常播放允许回写的最小连续前缀 */
const MIN_PREFIX_PLAYBACK = 32 * 1024;
/** 尾部探测判定阈值（相对文件大小） */
const TAIL_PROBE_RATIO = 0.6;

/** 解析后的 HTTP Range（end 为闭区间，openEnded 表示 bytes=start-） */
class ParsedRange {
  start: number = 0;
  end: number | undefined = undefined;
  openEnded: boolean = false;

  constructor(start: number, end: number | undefined, openEnded: boolean) {
    this.start = start;
    this.end = end;
    this.openEnded = openEnded;
  }
}

/** 对齐后的上游拉取计划（客户端 Range 与 NAS Range 可能不同） */
class RangeFetchPlan {
  clientStart: number = 0;
  clientEnd: number = 0;
  fetchStart: number = 0;
  fetchEnd: number = 0;
  skipToClient: number = 0;
  clientLength: number = 0;
}

function parseRangeHeader(header: string, fileSize: number | undefined): ParsedRange | undefined {
  const v = header.trim();
  if (!v.toLowerCase().startsWith('bytes=')) {
    return undefined;
  }
  const spec = v.substring(6).trim();
  const dash = spec.indexOf('-');
  if (dash < 0) {
    return undefined;
  }
  const left = spec.substring(0, dash).trim();
  const right = spec.substring(dash + 1).trim();

  if (left.length === 0) {
    // bytes=-N：取文件尾部 N 字节
    const suffix = Number.parseInt(right);
    if (!Number.isFinite(suffix) || suffix <= 0) {
      return undefined;
    }
    if (fileSize === undefined || fileSize <= 0) {
      return undefined;
    }
    const start = fileSize - suffix;
    return new ParsedRange(start < 0 ? 0 : start, fileSize - 1, false);
  }

  const start = Number.parseInt(left);
  if (!Number.isFinite(start) || start < 0) {
    return undefined;
  }
  if (right.length === 0) {
    return new ParsedRange(start, undefined, true);
  }
  const end = Number.parseInt(right);
  if (!Number.isFinite(end) || end < start) {
    return undefined;
  }
  return new ParsedRange(start, end, false);
}

function isTailProbe(start: number, fileSize: number | undefined): boolean {
  if (fileSize !== undefined && fileSize > 0) {
    return start > Math.round(fileSize * TAIL_PROBE_RATIO);
  }
  return start > 1500000000;
}

function minPrefixFor(start: number, fileSize: number | undefined): number {
  return isTailProbe(start, fileSize) ? MIN_PREFIX_TAIL : MIN_PREFIX_PLAYBACK;
}

/**
 * 构造上游拉取计划（对齐 Flutter VideoRangeMemoryCache._resolveUpstreamPlan）：
 * 开放 Range 不得扩到 EOF，单次响应/单次上游拉取都限制在 chunk 字节内，
 * 否则 NAS/P2P 会持续推送数 GB 数据，播放器 seek 时整条链路被拖死。
 */
function buildRangePlan(parsed: ParsedRange, fileSize: number | undefined): RangeFetchPlan | undefined {
  const tail = isTailProbe(parsed.start, fileSize);
  const chunk = tail ? TAIL_PROBE_CHUNK : PLAYBACK_CHUNK;
  const fileEnd = (fileSize !== undefined && fileSize > 0) ? fileSize - 1 : undefined;

  let responseEnd = 0;
  if (parsed.openEnded) {
    responseEnd = parsed.start + chunk - 1;
  } else if (parsed.end !== undefined) {
    responseEnd = parsed.end;
    if (responseEnd - parsed.start + 1 > chunk) {
      responseEnd = parsed.start + chunk - 1;
    }
  } else {
    return undefined;
  }
  if (fileEnd !== undefined && responseEnd > fileEnd) {
    responseEnd = fileEnd;
  }
  if (responseEnd < parsed.start) {
    return undefined;
  }

  const fetchStart = tail ? parsed.start : Math.floor(parsed.start / PLAYBACK_ALIGN) * PLAYBACK_ALIGN;
  let fetchEnd = fetchStart + chunk - 1;
  if (fetchEnd < responseEnd) {
    fetchEnd = responseEnd;
  }
  if (fileEnd !== undefined && fetchEnd > fileEnd) {
    fetchEnd = fileEnd;
  }

  const plan = new RangeFetchPlan();
  plan.clientStart = parsed.start;
  plan.clientEnd = responseEnd;
  plan.fetchStart = fetchStart;
  plan.fetchEnd = fetchEnd;
  plan.skipToClient = parsed.start - fetchStart;
  plan.clientLength = responseEnd - parsed.start + 1;
  return plan;
}

/** 大小写不敏感取请求头（播放器/ffmpeg 的头名大小写不固定） */
function headerValue(headers: HeaderMap, name: string): string | undefined {
  const target = name.toLowerCase();
  let found: string | undefined = undefined;
  headers.forEach((v: string, k: string): void => {
    if (found === undefined && k.toLowerCase() === target) {
      found = v;
    }
  });
  return found;
}

/** 大小写不敏感覆盖请求头（转发前替换 Range） */
function setHeaderIgnoreCase(headers: HeaderMap, name: string, value: string): void {
  const target = name.toLowerCase();
  const toRemove: string[] = [];
  headers.forEach((_v: string, k: string): void => {
    if (k.toLowerCase() === target) {
      toRemove.push(k);
    }
  });
  for (const k of toRemove) {
    headers.remove(k);
  }
  headers.set(name, value);
}

/** 原画播放的 raw 文件接口（对齐 Flutter isVideoRawFilePath） */
function isRawPlaybackPath(pathOnly: string): boolean {
  return pathOnly === '/api/videoPlayer/rawFile' || pathOnly === '/api/file/rawFile';
}

/** 仅 mp4/mov 走 Range 缓存（对齐 Flutter allowRangeCache，其它格式保持原透传行为） */
function supportsRangeCache(mediaPath: string): boolean {
  const dot = mediaPath.lastIndexOf('.');
  if (dot < 0) {
    return false;
  }
  const ext = mediaPath.substring(dot).toLowerCase();
  return ext === '.mp4' || ext === '.mov' || ext === '.m4v';
}

/** 从请求 URL 的 path 参数取出媒体文件路径 */
function mediaPathFromTarget(target: string): string {
  const qi = target.indexOf('?');
  if (qi < 0) {
    return '';
  }
  const query = target.substring(qi + 1);
  for (const pair of query.split('&')) {
    const eq = pair.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    if (pair.substring(0, eq) === 'path') {
      const raw = pair.substring(eq + 1);
      try {
        return decodeURIComponent(raw);
      } catch (_e) {
        return raw;
      }
    }
  }
  return '';
}

/** 按媒体扩展名推断 Content-Type（避免一律 video/mp4 误导解封装器） */
function contentTypeForPath(mediaPath: string): string {
  const dot = mediaPath.lastIndexOf('.');
  if (dot < 0 || dot === mediaPath.length - 1) {
    return 'application/octet-stream';
  }
  switch (mediaPath.substring(dot).toLowerCase()) {
    case '.mp4':
    case '.m4v':
      return 'video/mp4';
    case '.mov':
      return 'video/quicktime';
    case '.mkv':
      return 'video/x-matroska';
    case '.webm':
      return 'video/webm';
    case '.avi':
      return 'video/x-msvideo';
    case '.wmv':
      return 'video/x-ms-wmv';
    case '.flv':
      return 'video/x-flv';
    case '.ts':
    case '.m2ts':
      return 'video/mp2t';
    case '.mpeg':
    case '.mpg':
      return 'video/mpeg';
    case '.3gp':
      return 'video/3gpp';
    default:
      return 'application/octet-stream';
  }
}

/**
 * 稀疏块 Range 内存缓存（对齐 Flutter VideoRangeMemoryCache）：
 * mp4 的 moov 常在文件末尾，seek 时会反复请求尾部区间；把已拉取的字节按块留下，
 * 后续请求直接命中，避免重复走 P2P。
 */
export class PlaybackRangeCache {
  private sessionKey: string = '';
  fileSize: number | undefined = undefined;
  private blocks: Map<number, Uint8Array> = new Map();
  private totalBytes: number = 0;

  /** 切换媒体文件时重建会话；同一文件只更新文件大小 */
  reset(sessionKey: string, fileSizeBytes: number): void {
    if (this.sessionKey === sessionKey) {
      if (fileSizeBytes > 0) {
        this.fileSize = fileSizeBytes;
      }
      return;
    }
    this.clear();
    this.sessionKey = sessionKey;
    if (fileSizeBytes > 0) {
      this.fileSize = fileSizeBytes;
    }
  }

  clear(): void {
    this.sessionKey = '';
    this.fileSize = undefined;
    this.blocks.clear();
    this.totalBytes = 0;
  }

  /** 用上游响应头里的 Content-Range/Content-Length 补全文件总大小 */
  updateFileSizeFromHeaders(headers: HeaderMap): void {
    const cr = headerValue(headers, 'content-range');
    if (cr !== undefined && cr.length > 0) {
      const m = cr.trim().match(/bytes\s+\d+-\d+\/(\d+|\*)/i);
      if (m !== null && m.length > 1 && m[1] !== '*') {
        const total = Number.parseInt(m[1]);
        if (Number.isFinite(total) && total > 0) {
          this.fileSize = total;
        }
      }
      return;
    }
    const cl = headerValue(headers, 'content-length');
    if (cl !== undefined && cl.length > 0) {
      const n = Number.parseInt(cl.trim());
      if (Number.isFinite(n) && n > 0) {
        this.fileSize = n;
      }
    }
  }

  private touchBlock(index: number): void {
    const data = this.blocks.get(index);
    if (data === undefined) {
      return;
    }
    this.blocks.delete(index);
    this.blocks.set(index, data);
  }

  private putBlock(index: number, data: Uint8Array): void {
    const existing = this.blocks.get(index);
    if (existing !== undefined) {
      this.totalBytes -= existing.length;
      this.blocks.delete(index);
    }
    this.blocks.set(index, data);
    this.totalBytes += data.length;
    this.touchBlock(index);
    this.evictIfNeeded();
  }

  private evictIfNeeded(): void {
    while (this.totalBytes > RANGE_CACHE_MAX_BYTES) {
      let firstIndex = -1;
      let found = false;
      this.blocks.forEach((_v: Uint8Array, k: number): void => {
        if (!found) {
          firstIndex = k;
          found = true;
        }
      });
      if (!found) {
        return;
      }
      const removed = this.blocks.get(firstIndex);
      if (removed !== undefined) {
        this.totalBytes -= removed.length;
      }
      this.blocks.delete(firstIndex);
    }
  }

  /** 把上游分块按绝对偏移写入缓存 */
  ingestBytes(absoluteOffset: number, chunk: Uint8Array): void {
    if (chunk.length === 0) {
      return;
    }
    let off = absoluteOffset;
    let idx = 0;
    while (idx < chunk.length) {
      const blockIndex = Math.floor(off / RANGE_BLOCK_SIZE);
      const inBlock = off % RANGE_BLOCK_SIZE;
      const take = Math.min(RANGE_BLOCK_SIZE - inBlock, chunk.length - idx);
      const piece = chunk.subarray(idx, idx + take);

      const existing = this.blocks.get(blockIndex);
      const block = new Uint8Array(RANGE_BLOCK_SIZE);
      if (existing !== undefined) {
        block.set(existing.subarray(0, Math.min(existing.length, RANGE_BLOCK_SIZE)), 0);
      }
      block.set(piece, inBlock);

      if (inBlock + take >= RANGE_BLOCK_SIZE) {
        this.putBlock(blockIndex, block);
      } else {
        // 未写满的块只保留已写部分长度，读取时按有效长度判定
        const partial = block.slice(0, inBlock + take);
        const prev = this.blocks.get(blockIndex);
        if (prev !== undefined) {
          this.totalBytes -= prev.length;
          this.blocks.delete(blockIndex);
        }
        this.blocks.set(blockIndex, partial);
        this.totalBytes += partial.length;
        this.touchBlock(blockIndex);
        this.evictIfNeeded();
      }

      off += take;
      idx += take;
    }
  }

  /** 从 start 起连续可读的缓存字节数（不超过 maxEnd） */
  cachedPrefixLength(start: number, maxEnd: number): number {
    if (maxEnd < start) {
      return 0;
    }
    let pos = start;
    while (pos <= maxEnd) {
      const blockIndex = Math.floor(pos / RANGE_BLOCK_SIZE);
      const inBlock = pos % RANGE_BLOCK_SIZE;
      const block = this.blocks.get(blockIndex);
      if (block === undefined || inBlock >= block.length) {
        break;
      }
      const available = block.length - inBlock;
      const need = maxEnd - pos + 1;
      const take = Math.min(available, need);
      pos += take;
      if (block.length < RANGE_BLOCK_SIZE) {
        break;
      }
    }
    return pos - start;
  }

  isFullyCached(start: number, end: number): boolean {
    if (end < start) {
      return false;
    }
    return this.cachedPrefixLength(start, end) >= (end - start + 1);
  }

  blockAt(index: number): Uint8Array | undefined {
    return this.blocks.get(index);
  }
}

/** 请求期间状态（一次 TCP 连接只处理一个 GET/HEAD） */
class PlaybackClientSession {
  private proxy: LocalPlaybackProxy;
  private client: socket.TCPSocketConnection;
  private buffer: string = '';
  private requestStarted: boolean = false;
  private finished: boolean = false;
  private closed: boolean = false;
  private cancelFn: (() => void) | undefined = undefined;
  private headersSent: boolean = false;
  private useChunked: boolean = false;
  private writeChain: Promise<void> = Promise.resolve();

  /** Range 直出状态 */
  private passthroughBody: boolean = false;
  private rangeFetchStart: number = 0;
  private rangeReceived: number = 0;
  private rangeClientStart: number = 0;
  private rangeClientEnd: number = 0;
  private rangeSkip: number = 0;
  private rangeRemaining: number = 0;

  constructor(proxy: LocalPlaybackProxy, client: socket.TCPSocketConnection) {
    this.proxy = proxy;
    this.client = client;

    this.client.on('close', (): void => {
      if (this.finished) {
        return;
      }
      this.finished = true;
      const fn = this.cancelFn;
      this.cancelFn = undefined;
      if (fn !== undefined) {
        fn();
      }
    });

    this.client.on('message', (value: socket.SocketMessageInfo) => {
      this.onMessage(value);
    });
  }

  // ================================ 写回 ================================

  private closeClient(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    this.writeChain.then((): void => {
      this.client.close();
    }).catch((): void => {
      this.client.close();
    });
  }

  /** 串行发送，保证响应数据按序写回；写入失败视为播放器已断开 */
  private enqueuePiece(bytes: Uint8Array): void {
    this.writeChain = this.writeChain
      .then((): Promise<void> => this.client.send({ data: bytes.buffer as ArrayBuffer }))
      .catch((): void => {
        if (!this.finished) {
          this.finished = true;
          const fn = this.cancelFn;
          this.cancelFn = undefined;
          if (fn !== undefined) {
            fn();
          }
        }
      });
  }

  private enqueue(bytes: Uint8Array): void {
    for (let offset = 0; offset < bytes.length; offset += SOCKET_SEND_CHUNK) {
      const end = Math.min(offset + SOCKET_SEND_CHUNK, bytes.length);
      this.enqueuePiece(bytes.subarray(offset, end).slice());
    }
  }

  private enqueueText(text: string): void {
    const encoder = new util.TextEncoder();
    this.enqueue(encoder.encodeInto(text));
  }

  /** 按响应头决定原样写回还是 chunked 包装后写回 */
  private writeStreamData(data: Uint8Array): void {
    if (!this.useChunked) {
      this.enqueue(data);
      return;
    }
    const encoder = new util.TextEncoder();
    const sizeBytes = encoder.encodeInto(`${data.length.toString(16)}\r\n`);
    const tail = encoder.encodeInto('\r\n');
    const out = new Uint8Array(sizeBytes.length + data.length + tail.length);
    out.set(sizeBytes, 0);
    out.set(data, sizeBytes.length);
    out.set(tail, sizeBytes.length + data.length);
    this.enqueue(out);
  }

  private writeSimpleError(status: number, reason: string, detail: string): void {
    this.finished = true;
    this.headersSent = true;
    const encoder = new util.TextEncoder();
    const bodyBytes = encoder.encodeInto(detail);
    const head = `HTTP/1.1 ${status} ${reason}\r\n` +
      `Content-Type: text/plain; charset=utf-8\r\n` +
      `Content-Length: ${bodyBytes.length}\r\n` +
      `Connection: close\r\n\r\n`;
    this.enqueueText(head);
    this.enqueue(bodyBytes);
    this.closeClient();
  }

  /** 直出上游响应头（过滤 connection/transfer-encoding，无长度时用 chunked） */
  private writeUpstreamHead(status: number, respHeaders: HeaderMap, isHead: boolean): void {
    this.headersSent = true;
    const headLines: string[] = [];
    headLines.push(`HTTP/1.1 ${status} ${reasonPhrase(status)}`);
    let hasLength = false;
    respHeaders.forEach((v: string, k: string): void => {
      const lk = k.toLowerCase();
      if (lk === 'connection' || lk === 'transfer-encoding') {
        return;
      }
      if (lk === 'content-length') {
        hasLength = true;
      }
      headLines.push(`${k}: ${v}`);
    });
    if (!isHead && !hasLength) {
      this.useChunked = true;
      headLines.push('Transfer-Encoding: chunked');
    }
    headLines.push('Connection: close');
    this.enqueueText(headLines.join('\r\n') + '\r\n\r\n');
  }

  /** Range 响应头：206 + 明确 Content-Length/Content-Range，让解封装器拿到确定长度 */
  private writeRangeHead(start: number, end: number, contentType: string | undefined,
    fileSize: number | undefined): void {
    this.headersSent = true;
    const length = end - start + 1;
    const total = (fileSize !== undefined && fileSize > 0) ? `${fileSize}` : '*';
    const ct = contentType !== undefined && contentType.length > 0
      ? contentType : 'application/octet-stream';
    const head = `HTTP/1.1 206 Partial Content\r\n` +
      `Content-Type: ${ct}\r\n` +
      `Accept-Ranges: bytes\r\n` +
      `Content-Length: ${length}\r\n` +
      `Content-Range: bytes ${start}-${end}/${total}\r\n` +
      `Cache-Control: no-store\r\n` +
      `Connection: close\r\n\r\n`;
    this.enqueueText(head);
  }

  private endResponse(): void {
    if (this.useChunked) {
      this.enqueueText('0\r\n\r\n');
    }
    this.closeClient();
  }

  /** 已满足客户端区间：立刻停止上游推送并结束响应 */
  private finishRangeResponse(): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    const fn = this.cancelFn;
    this.cancelFn = undefined;
    if (fn !== undefined) {
      fn();
    }
    this.endResponse();
  }

  // ================================ 请求 ================================

  private onMessage(value: socket.SocketMessageInfo): void {
    if (this.requestStarted) {
      // 播放请求均为 GET/HEAD，请求体直接忽略
      return;
    }
    const decoder = new util.TextDecoder();
    this.buffer += decoder.decodeToString(new Uint8Array(value.message));
    const headerEnd = this.buffer.indexOf('\r\n\r\n');
    if (headerEnd < 0) {
      return;
    }
    this.requestStarted = true;

    const headerPart = this.buffer.substring(0, headerEnd);
    const lines = headerPart.split('\r\n');
    const requestLine = lines.length > 0 ? lines[0] : '';
    const parts = requestLine.split(' ');
    const method = parts.length > 0 ? parts[0].trim().toUpperCase() : 'GET';
    let target = parts.length > 1 ? parts[1].trim() : '';

    // 兼容代理式绝对地址：GET http://127.0.0.1:port/path HTTP/1.1
    if (target.startsWith('http://') || target.startsWith('https://')) {
      const schemeEnd = target.indexOf('://');
      const pathIdx = target.indexOf('/', schemeEnd + 3);
      target = pathIdx >= 0 ? target.substring(pathIdx) : '/';
    }
    if (target.length === 0 || !target.startsWith('/')) {
      this.writeSimpleError(400, 'Bad Request', 'bad request target');
      return;
    }

    const headers = new HeaderMap();
    for (let i = 1; i < lines.length; i++) {
      const idx = lines[i].indexOf(':');
      if (idx > 0) {
        const k = lines[i].substring(0, idx).trim();
        const v = lines[i].substring(idx + 1).trim();
        headers.set(k, v);
      }
    }
    // 播放器不会带鉴权头：URL 未带 accessToken 时补 Authorization（对齐 Flutter/Android 代理）
    if (headerValue(headers, 'authorization') === undefined && target.indexOf('accessToken=') < 0) {
      const token = (APIClient.getInstance().accessToken ?? '').trim();
      if (token.length > 0) {
        headers.set('Authorization', `Bearer ${token}`);
      }
    }

    const isHead = method === 'HEAD';
    const rangeHeader = headerValue(headers, 'range');
    const mediaPath = mediaPathFromTarget(target);
    if (rangeHeader !== undefined && method === 'GET'
      && isRawPlaybackPath(target.split('?')[0]) && supportsRangeCache(mediaPath)) {
      if (this.tryServeRange(target, method, headers, rangeHeader, mediaPath)) {
        return;
      }
    }
    this.startPassthrough(target, method, headers, isHead);
  }

  // ================================ Range 分支 ================================

  /**
   * 对齐 Flutter：原画 rawFile 的 Range 请求走「分块上游 + 块缓存 + 归一化 206」。
   * mp4 的 moov 在文件末尾时，解封装器会 seek 到尾部再读；若不限制单次上游范围，
   * NAS 会一直推送到 EOF，播放器 seek 直接卡死（日志表现为 Seek failed / partial file）。
   * 返回 true 表示已接管响应。
   */
  private tryServeRange(target: string, method: string, headers: HeaderMap, rangeHeader: string,
    mediaPath: string): boolean {
    const cache = this.proxy.getRangeCache();
    const parsed = parseRangeHeader(rangeHeader, cache.fileSize);
    if (parsed === undefined) {
      return false;
    }
    const plan = buildRangePlan(parsed, cache.fileSize);
    if (plan === undefined) {
      return false;
    }
    const contentType = contentTypeForPath(mediaPath);

    // 1) 客户端区间已全部命中缓存：直接写回
    if (cache.isFullyCached(plan.clientStart, plan.clientEnd)) {
      this.writeRangeHead(plan.clientStart, plan.clientEnd, contentType, cache.fileSize);
      this.writeCachedRange(plan.clientStart, plan.clientEnd);
      this.endResponse();
      return true;
    }

    // 2) 已有连续前缀：先回前缀，播放器随后会续传剩余区间
    const prefixLen = cache.cachedPrefixLength(plan.clientStart, plan.clientEnd);
    const minPrefix = minPrefixFor(plan.clientStart, cache.fileSize);
    if (prefixLen >= minPrefix) {
      let end = plan.clientStart + Math.min(prefixLen, MAX_PREFIX_SERVE) - 1;
      if (end > plan.clientEnd) {
        end = plan.clientEnd;
      }
      this.writeRangeHead(plan.clientStart, end, contentType, cache.fileSize);
      this.writeCachedRange(plan.clientStart, end);
      this.endResponse();
      return true;
    }

    // 3) 对齐区间内已有前缀时只拉缺口
    let fetchStart = plan.fetchStart;
    const fetchPrefix = cache.cachedPrefixLength(plan.fetchStart, plan.fetchEnd);
    if (fetchPrefix > 0) {
      fetchStart = plan.fetchStart + fetchPrefix;
    }
    if (fetchStart > plan.fetchEnd) {
      this.writeRangeHead(plan.clientStart, plan.clientEnd, contentType, cache.fileSize);
      this.writeCachedRange(plan.clientStart, plan.clientEnd);
      this.endResponse();
      return true;
    }

    const upstreamHeaders = headers.removeProxyHeaders();
    setHeaderIgnoreCase(upstreamHeaders, 'Range', `bytes=${fetchStart}-${plan.fetchEnd}`);

    this.rangeFetchStart = fetchStart;
    this.rangeReceived = 0;
    this.rangeClientStart = plan.clientStart;
    this.rangeClientEnd = plan.clientEnd;
    this.rangeSkip = plan.skipToClient;
    this.rangeRemaining = plan.clientLength;

    const streamHandler: P2pStreamHandler = {
      onBegin: (status: number, respHeaders: HeaderMap): void => {
        if (this.finished) {
          return;
        }
        cache.updateFileSizeFromHeaders(respHeaders);
        if (status === 200) {
          // 服务端忽略了 Range：整文件按序直出（与旧行为一致，至少不阻塞首屏）
          this.passthroughBody = true;
          this.writeUpstreamHead(200, respHeaders, false);
          return;
        }
        if (status !== 206) {
          this.writeSimpleError(status, reasonPhrase(status), 'upstream range unavailable');
          return;
        }
        const size = cache.fileSize;
        if (size !== undefined && size > 0 && this.rangeClientEnd > size - 1) {
          this.rangeClientEnd = size - 1;
        }
        if (this.rangeClientEnd < this.rangeClientStart) {
          this.writeSimpleError(416, 'Range Not Satisfiable', 'range not satisfiable');
          return;
        }
        const upstreamCt = headerValue(respHeaders, 'content-type');
        this.writeRangeHead(this.rangeClientStart, this.rangeClientEnd,
          upstreamCt !== undefined ? upstreamCt : contentType, size);

        // 上游起点之前若已有缓存，先把这部分写给播放器
        const cachedUntil = Math.min(fetchStart - 1, this.rangeClientEnd);
        if (cachedUntil >= this.rangeClientStart) {
          this.writeCachedRange(this.rangeClientStart, cachedUntil);
          this.rangeSkip = 0;
          this.rangeRemaining = this.rangeClientEnd - cachedUntil;
        } else {
          this.rangeSkip = Math.max(0, this.rangeClientStart - fetchStart);
          this.rangeRemaining = this.rangeClientEnd - this.rangeClientStart + 1;
        }
      },
      onChunk: (data: Uint8Array): void => {
        if (this.finished) {
          return;
        }
        const absOffset = this.rangeFetchStart + this.rangeReceived;
        this.rangeReceived += data.length;
        if (this.passthroughBody) {
          // 上游忽略 Range（整文件 200），缓存偏移不可信，直接直出
          this.writeStreamData(data);
          return;
        }
        cache.ingestBytes(absOffset, data);
        let out = data;
        if (this.rangeSkip > 0) {
          if (out.length <= this.rangeSkip) {
            this.rangeSkip -= out.length;
            return;
          }
          out = out.subarray(this.rangeSkip);
          this.rangeSkip = 0;
        }
        if (this.rangeRemaining <= 0) {
          return;
        }
        if (out.length > this.rangeRemaining) {
          out = out.subarray(0, this.rangeRemaining);
        }
        this.rangeRemaining -= out.length;
        this.writeStreamData(out);
        if (this.rangeRemaining <= 0) {
          this.finishRangeResponse();
        }
      },
      onEnd: (): void => {
        if (this.finished) {
          return;
        }
        this.finished = true;
        this.cancelFn = undefined;
        this.endResponse();
      },
      onError: (e: Error): void => {
        console.error(`LocalPlaybackProxy stream error: ${e.message} url=${target}`);
        if (this.finished) {
          return;
        }
        this.finished = true;
        this.cancelFn = undefined;
        if (!this.headersSent) {
          this.writeSimpleError(502, 'Bad Gateway', `p2p stream error: ${e.message}`);
        } else {
          this.closeClient();
        }
      }
    };

    P2PService.getInstance()
      .sendOnChannelStream(P2pChannelUtil.resolvePath(target), method, target, upstreamHeaders,
        new Uint8Array(0), STREAM_IDLE_TIMEOUT_MS, streamHandler)
      .then((cancel: () => void): void => {
        this.cancelFn = cancel;
        if (this.finished) {
          cancel();
        }
      })
      .catch((e: Error): void => {
        console.error(`LocalPlaybackProxy request failed: ${e.message} url=${target}`);
        if (this.finished) {
          return;
        }
        this.finished = true;
        this.cancelFn = undefined;
        if (!this.headersSent) {
          this.writeSimpleError(502, 'Bad Gateway', `p2p not ready: ${e.message}`);
        } else {
          this.closeClient();
        }
      });
    return true;
  }

  /** 按块写出已连续缓存的 [start..end] */
  private writeCachedRange(start: number, end: number): void {
    const cache = this.proxy.getRangeCache();
    let pos = start;
    while (pos <= end) {
      const blockIndex = Math.floor(pos / RANGE_BLOCK_SIZE);
      const inBlock = pos % RANGE_BLOCK_SIZE;
      const block = cache.blockAt(blockIndex);
      if (block === undefined || inBlock >= block.length) {
        return;
      }
      const take = Math.min(block.length - inBlock, end - pos + 1);
      this.enqueue(block.subarray(inBlock, inBlock + take).slice());
      pos += take;
    }
  }

  // ================================ 透传分支 ================================

  private startPassthrough(target: string, method: string, headers: HeaderMap, isHead: boolean): void {
    const streamHandler: P2pStreamHandler = {
      onBegin: (status: number, respHeaders: HeaderMap): void => {
        this.writeUpstreamHead(status, respHeaders, isHead);
      },
      onChunk: (data: Uint8Array): void => {
        if (isHead) {
          return;
        }
        this.writeStreamData(data);
      },
      onEnd: (): void => {
        if (this.finished) {
          return;
        }
        this.finished = true;
        this.cancelFn = undefined;
        this.endResponse();
      },
      onError: (e: Error): void => {
        console.error(`LocalPlaybackProxy stream error: ${e.message} url=${target}`);
        if (this.finished) {
          return;
        }
        this.finished = true;
        this.cancelFn = undefined;
        if (!this.headersSent) {
          this.writeSimpleError(502, 'Bad Gateway', `p2p stream error: ${e.message}`);
        } else {
          this.closeClient();
        }
      }
    };

    P2PService.getInstance()
      .sendOnChannelStream(P2pChannelUtil.resolvePath(target), method, target,
        headers.removeProxyHeaders(), new Uint8Array(0), STREAM_IDLE_TIMEOUT_MS, streamHandler)
      .then((cancel: () => void): void => {
        this.cancelFn = cancel;
        if (this.finished) {
          cancel();
        }
      })
      .catch((e: Error): void => {
        console.error(`LocalPlaybackProxy request failed: ${e.message} url=${target}`);
        if (this.finished) {
          return;
        }
        this.finished = true;
        this.cancelFn = undefined;
        if (!this.headersSent) {
          this.writeSimpleError(502, 'Bad Gateway', `p2p not ready: ${e.message}`);
        } else {
          this.closeClient();
        }
      });
  }
}

/**
 * P2P 本地 HTTP 代理：
 * `p2p.local` 是虚拟域名，底层播放器（mpv/ffmpeg）无法解析，
 * 因此把播放地址改写到本机 `127.0.0.1:<port>`，由这里转成 P2P 通道请求。
 * 视频/大文件走流式转发（边收边写），不整体缓存。
 */
export class LocalPlaybackProxy {
  private static instance: LocalPlaybackProxy | undefined = undefined;
  isRunning: boolean = false;
  port: number | undefined = undefined;
  private tcpServer: socket.TCPSocketServer | undefined = undefined;
  private startPromise: Promise<void> | undefined = undefined;
  private readonly rangeCache: PlaybackRangeCache = new PlaybackRangeCache();
  /** 播放期间的引用计数：对齐 Flutter LocalWebAssetServer.acquireForVideo */
  private videoRefCount: number = 0;
  /** P2P 断开时若有播放引用，延后关闭，避免端口变化让播放器地址失效 */
  private stopPending: boolean = false;

  static getInstance(): LocalPlaybackProxy {
    if (!LocalPlaybackProxy.instance) {
      LocalPlaybackProxy.instance = new LocalPlaybackProxy();
    }
    return LocalPlaybackProxy.instance;
  }

  getRangeCache(): PlaybackRangeCache {
    return this.rangeCache;
  }

  /** 起播前绑定当前媒体会话（不同文件会清空 Range 缓存） */
  prepareVideoSession(path: string, fileSizeBytes: number): void {
    this.rangeCache.reset(path, fileSizeBytes);
  }

  /** 播放引用 +1（对齐 Flutter acquireForVideo） */
  acquireForVideo(): void {
    this.videoRefCount += 1;
    this.stopPending = false;
  }

  /** 播放引用 -1；归零且此前有待关闭请求时才真正关闭（对齐 Flutter releaseForVideo） */
  releaseForVideo(): void {
    if (this.videoRefCount > 0) {
      this.videoRefCount -= 1;
    }
    if (this.videoRefCount === 0 && this.stopPending) {
      this.stopPending = false;
      this.stopNow();
    }
  }

  async start(): Promise<void> {
    if (this.isRunning) {
      return;
    }
    if (!APIClient.getInstance().isP2pMode) {
      return;
    }
    // 并发调用（建连流程 + 播放器起播）合并为同一次启动
    if (this.startPromise !== undefined) {
      await this.startPromise;
      return;
    }
    this.startPromise = this.openServer();
    try {
      await this.startPromise;
    } finally {
      this.startPromise = undefined;
    }
  }

  private async openServer(): Promise<void> {
    try {
      this.tcpServer = socket.constructTCPSocketServerInstance();
      this.tcpServer.on('connect', (client: socket.TCPSocketConnection) => {
        this.handleConnection(client);
      });
      await this.tcpServer.listen({ address: '127.0.0.1', port: 0, family: 1 });
      const local = await this.tcpServer.getLocalAddress();
      this.port = local.port;
      this.isRunning = true;
    } catch (e) {
      console.error(`LocalPlaybackProxy start failed: ${e}`);
      this.stopNow();
    }
  }

  stop(): void {
    // 播放中先挂起：关闭后端口会变，播放器仍持有旧地址，seek 时会 Connection refused
    if (this.videoRefCount > 0) {
      this.stopPending = true;
      return;
    }
    this.stopNow();
  }

  private stopNow(): void {
    if (this.tcpServer) {
      this.tcpServer.off('connect');
      this.tcpServer.close();
      this.tcpServer = undefined;
    }
    this.isRunning = false;
    this.port = undefined;
    this.rangeCache.clear();
  }

  getBaseUrl(): string | undefined {
    if (!APIClient.getInstance().isP2pMode || !this.isRunning || !this.port) {
      return undefined;
    }
    return `http://127.0.0.1:${this.port}`;
  }

  /** 把 p2p.local 播放地址改写到本地代理；非 P2P 地址原样返回 */
  resolveP2pProxyUrl(url: string): string {
    if (!url.startsWith(NetworkConfig.P2P_BASE_URL)) {
      return url;
    }
    const base = this.getBaseUrl();
    if (!base) {
      return url;
    }
    return url.replace(NetworkConfig.P2P_BASE_URL, base);
  }

  private handleConnection(client: socket.TCPSocketConnection): void {
    new PlaybackClientSession(this, client);
  }
}

function reasonPhrase(status: number): string {
  switch (status) {
    case 200:
      return 'OK';
    case 206:
      return 'Partial Content';
    case 301:
      return 'Moved Permanently';
    case 302:
      return 'Found';
    case 304:
      return 'Not Modified';
    case 400:
      return 'Bad Request';
    case 401:
      return 'Unauthorized';
    case 403:
      return 'Forbidden';
    case 404:
      return 'Not Found';
    case 416:
      return 'Range Not Satisfiable';
    case 500:
      return 'Internal Server Error';
    case 503:
      return 'Service Unavailable';
    default:
      return 'OK';
  }
}
