import { util } from '@kit.ArkTS';
import { HeaderMap } from '../common/HeaderMap';
import { P2pControlPayload } from '../common/JsonTypes';

export enum P2pRtcChannel {
  API = 'api',
  FILE = 'file',
  UPLOAD = 'upload',
  DOWNLOAD = 'download',
  VIDEO = 'video',
}

export enum P2pIcePreference {
  AUTO = 'auto',
  DIRECT_ONLY = 'directOnly',
  RELAY_ONLY = 'relayOnly',
}

export enum P2pTransportKind {
  UNKNOWN = 'unknown',
  DIRECT = 'direct',
  RELAY = 'relay',
}

export class P2pApiResponse {
  status: number;
  headers: HeaderMap;
  bodyBytes: Uint8Array;

  constructor(status: number, headers: HeaderMap, bodyBytes: Uint8Array) {
    this.status = status;
    this.headers = headers;
    this.bodyBytes = bodyBytes;
  }
}

export class P2PError extends Error {
  code: string;

  constructor(code: string, message?: string) {
    super(message ?? code);
    this.code = code;
  }

  static emptyPairCode(): P2PError {
    return new P2PError('empty_pair_code', '配对码为空');
  }

  static invalidSession(): P2PError {
    return new P2PError('invalid_session', '无效 P2P 会话');
  }

  static notConnected(): P2PError {
    return new P2PError('p2p_not_connected', 'P2P 未连接');
  }

  static wsError(code: string): P2PError {
    return new P2PError(code, code);
  }
}

export class P2pRequestId {
  private static counter: number = 0;

  static generate(): string {
    P2pRequestId.counter += 1;
    const ts = Date.now() * 1000;
    const rand = Math.floor(Math.random() * (1 << 30));
    return `${ts}_${rand}_${P2pRequestId.counter}`;
  }
}

export enum P2pControlType {
  READY = 0x01,
  PING = 0x02,
  PONG = 0x03,
  REQ = 0x10,
  REQ_BEGIN = 0x11,
  REQ_END = 0x12,
  REQ_CANCEL = 0x13,
  CANCEL = 0x14,
  RES_BEGIN = 0x20,
  RES_END = 0x21,
  FLOW = 0x22,
  ACK = 0x30,
  WS_OPEN = 0x40,
  WS_SEND = 0x41,
  WS_CLOSE = 0x42,
  WS_OPEN_OK = 0x43,
  WS_OPEN_ERROR = 0x44,
  WS_MESSAGE = 0x45,
  WS_ERROR = 0x46,
}

const CONTROL_MAGIC: number[] = [0x4e, 0x50, 0x43, 0x01];

export class P2pControlBinary {
  static encodeVarint(n: number): Uint8Array {
    // 64 位安全：位运算会截断到 32 位，Date.now() 级别的时间戳会被破坏
    let v = n < 0 ? 0 : n;
    const out: number[] = [];
    while (v >= 0x80) {
      out.push((v % 128) | 0x80);
      v = Math.floor(v / 128);
    }
    out.push(v % 128);
    return new Uint8Array(out);
  }

  static encodeString(s: string): Uint8Array {
    const encoder = new util.TextEncoder();
    const b = encoder.encodeInto(s);
    if (b.length === 0) {
      return new Uint8Array([0]);
    }
    const len = P2pControlBinary.encodeVarint(b.length);
    const out = new Uint8Array(len.length + b.length);
    out.set(len, 0);
    out.set(b, len.length);
    return out;
  }

  static encodeHeaderMap(map: HeaderMap): Uint8Array {
    const parts: number[] = [];
    let count = 0;
    const entries: string[][] = [];
    map.forEach((value: string, key: string) => {
      if (key.length > 0) {
        entries.push([key, value]);
        count++;
      }
    });
    const countBytes = P2pControlBinary.encodeVarint(count);
    for (let i = 0; i < countBytes.length; i++) {
      parts.push(countBytes[i]);
    }
    for (let i = 0; i < entries.length; i++) {
      const kb = P2pControlBinary.encodeString(entries[i][0]);
      const vb = P2pControlBinary.encodeString(entries[i][1]);
      for (let j = 0; j < kb.length; j++) parts.push(kb[j]);
      for (let j = 0; j < vb.length; j++) parts.push(vb[j]);
    }
    return new Uint8Array(parts);
  }

  private static appendMagicAndType(parts: number[], type: P2pControlType): void {
    for (let i = 0; i < CONTROL_MAGIC.length; i++) {
      parts.push(CONTROL_MAGIC[i]);
    }
    parts.push(type);
  }

  private static appendBytes(parts: number[], arr: Uint8Array): void {
    for (let i = 0; i < arr.length; i++) {
      parts.push(arr[i]);
    }
  }

  static encodeControl(prefix: string, type: P2pControlType, payload: P2pControlPayload): Uint8Array | undefined {
    const parts: number[] = [];
    P2pControlBinary.appendMagicAndType(parts, type);

    if (type === P2pControlType.PING || type === P2pControlType.PONG) {
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeVarint(payload.ts));
      return new Uint8Array(parts);
    }
    if (type === P2pControlType.REQ_END || type === P2pControlType.REQ_CANCEL || type === P2pControlType.CANCEL) {
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeString(payload.id));
      return new Uint8Array(parts);
    }
    if (type === P2pControlType.ACK) {
      // 对齐 Flutter：ack = id + delta(varint)，用于响应体流控
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeString(payload.id));
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeVarint(payload.delta));
      return new Uint8Array(parts);
    }
    if (type === P2pControlType.REQ) {
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeString(payload.id));
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeString(payload.method));
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeString(payload.path));
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeHeaderMap(payload.headers));
      return new Uint8Array(parts);
    }
    if (type === P2pControlType.REQ_BEGIN) {
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeString(payload.id));
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeString(payload.method));
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeString(payload.path));
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeHeaderMap(payload.headers));
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeVarint(payload.length));
      return new Uint8Array(parts);
    }
    if (type === P2pControlType.WS_OPEN) {
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeString(payload.id));
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeString(payload.path));
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeHeaderMap(payload.headers));
      return new Uint8Array(parts);
    }
    if (type === P2pControlType.WS_SEND) {
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeString(payload.id));
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeString(payload.data));
      return new Uint8Array(parts);
    }
    if (type === P2pControlType.WS_CLOSE) {
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeString(payload.id));
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeVarint(payload.code));
      P2pControlBinary.appendBytes(parts, P2pControlBinary.encodeString(payload.reason));
      return new Uint8Array(parts);
    }
    return undefined;
  }

  static isControl(data: Uint8Array): boolean {
    if (data.length < 5) return false;
    return data[0] === CONTROL_MAGIC[0] && data[1] === CONTROL_MAGIC[1] &&
      data[2] === CONTROL_MAGIC[2] && data[3] === CONTROL_MAGIC[3];
  }
}

export class P2pBinaryFrame {
  static readonly VERSION_V1: number = 0x01;
  static readonly CHUNK_SIZE: number = 64 * 1024;

  static buildHeader(version: number, requestId: string): Uint8Array {
    const encoder = new util.TextEncoder();
    const idBytes = encoder.encodeInto(requestId);
    const idLen = Math.min(idBytes.length, 255);
    const header = new Uint8Array(2 + idLen);
    header[0] = version;
    header[1] = idLen;
    header.set(idBytes.subarray(0, idLen), 2);
    return header;
  }
}

/**
 * 控制帧二进制读取器，解码规则对齐 Flutter _tryDecodeControlBinary：
 * varint / 长度前缀字符串 / 长度前缀 header map。
 */
export class P2pBinaryReader {
  private data: Uint8Array;
  private pos: number;
  private decoder: util.TextDecoder = new util.TextDecoder();

  constructor(data: Uint8Array, pos: number) {
    this.data = data;
    this.pos = pos;
  }

  readVarint(): number | undefined {
    let out = 0;
    let mult = 1;
    while (true) {
      if (this.pos >= this.data.length) {
        return undefined;
      }
      const b = this.data[this.pos];
      this.pos += 1;
      // 用乘法避免位运算 32 位截断
      out += (b & 0x7f) * mult;
      if ((b & 0x80) === 0) {
        return out;
      }
      mult *= 128;
      if (mult > 9223372036854775807) {
        return undefined;
      }
    }
  }

  readString(): string | undefined {
    const len = this.readVarint();
    if (len === undefined || len < 0) {
      return undefined;
    }
    const end = this.pos + len;
    if (end > this.data.length) {
      return undefined;
    }
    if (len === 0) {
      return '';
    }
    const s = this.decoder.decodeToString(this.data.subarray(this.pos, end));
    this.pos = end;
    return s;
  }

  readHeaderMap(): HeaderMap | undefined {
    const n = this.readVarint();
    if (n === undefined || n < 0) {
      return undefined;
    }
    const out = new HeaderMap();
    for (let i = 0; i < n; i++) {
      const k = this.readString();
      const v = this.readString();
      if (k === undefined || v === undefined) {
        return undefined;
      }
      if (k.length > 0) {
        out.set(k, v);
      }
    }
    return out;
  }
}

/** P2P 请求路由：目标通道 + 去掉代理标记后的上游路径 */
export class P2pChannelRoute {
  channel: P2pRtcChannel;
  path: string;

  constructor(channel: P2pRtcChannel, path: string) {
    this.channel = channel;
    this.path = path;
  }
}

export class P2pChannelUtil {
  static fallbackForPath(path: string): P2pRtcChannel {
    const p = path.trim();
    if (p.startsWith('/api/file/upload')) return P2pRtcChannel.UPLOAD;
    if (p.startsWith('/api/file/download')) return P2pRtcChannel.DOWNLOAD;
    if (p.startsWith('/api/videoPlayer/')) return P2pRtcChannel.VIDEO;
    if (p.startsWith('/api/file/rawFile')) return P2pRtcChannel.FILE;
    if (p.startsWith('/api/file') || p.startsWith('/api/static')) return P2pRtcChannel.FILE;
    return P2pRtcChannel.API;
  }

  static resolvePath(path: string): P2pRtcChannel {
    const idx = path.indexOf('?');
    const basePath = idx >= 0 ? path.substring(0, idx) : path;
    return P2pChannelUtil.fallbackForPath(basePath);
  }

  /** 解析 URL 里的 p2pChannel 标记（对齐 Flutter P2pChannelUtil.parseMark） */
  static parseMark(raw: string): P2pRtcChannel | undefined {
    const s = raw.trim().toLowerCase();
    if (s.length === 0) {
      return undefined;
    }
    if (s === P2pRtcChannel.API) {
      return P2pRtcChannel.API;
    }
    if (s === P2pRtcChannel.FILE) {
      return P2pRtcChannel.FILE;
    }
    if (s === P2pRtcChannel.UPLOAD) {
      return P2pRtcChannel.UPLOAD;
    }
    if (s === P2pRtcChannel.DOWNLOAD) {
      return P2pRtcChannel.DOWNLOAD;
    }
    if (s === P2pRtcChannel.VIDEO) {
      return P2pRtcChannel.VIDEO;
    }
    return undefined;
  }

  private static queryParam(path: string, key: string): string | undefined {
    const qi = path.indexOf('?');
    if (qi < 0) {
      return undefined;
    }
    const query = path.substring(qi + 1);
    for (const pair of query.split('&')) {
      const eq = pair.indexOf('=');
      const k = eq >= 0 ? pair.substring(0, eq) : pair;
      if (k !== key) {
        continue;
      }
      const raw = eq >= 0 ? pair.substring(eq + 1) : '';
      try {
        return decodeURIComponent(raw);
      } catch (_e) {
        return raw;
      }
    }
    return undefined;
  }

  /** 去掉 p2pChannel 参数（转发上游前调用，对齐 Flutter stripP2pChannelFromPath） */
  static stripP2pChannel(path: string): string {
    const qi = path.indexOf('?');
    if (qi < 0) {
      return path;
    }
    const base = path.substring(0, qi);
    const kept: string[] = [];
    for (const part of path.substring(qi + 1).split('&')) {
      const p = part.trim();
      if (p.length === 0) {
        continue;
      }
      const eq = p.indexOf('=');
      const k = eq >= 0 ? p.substring(0, eq) : p;
      if (k === 'p2pChannel') {
        continue;
      }
      kept.push(p);
    }
    return kept.length === 0 ? base : `${base}?${kept.join('&')}`;
  }

  /** 同时解析通道与转发路径（优先 p2pChannel 标记，其次按路径回退） */
  static resolveTarget(path: string): P2pChannelRoute {
    let channel = P2pChannelUtil.resolvePath(path);
    const mark = P2pChannelUtil.queryParam(path, 'p2pChannel');
    if (mark !== undefined) {
      const parsed = P2pChannelUtil.parseMark(mark);
      if (parsed !== undefined) {
        channel = parsed;
      }
    }
    return new P2pChannelRoute(channel, P2pChannelUtil.stripP2pChannel(path));
  }
}

/** P2P 通道内 WebSocket 隧道事件回调（对齐 Flutter _P2pRtcWebSocketChannel） */
export interface P2pWsListener {
  onOpen?: () => void;
  onMessage?: (data: string) => void;
  onError?: (error: string) => void;
  onClose?: (code: number, reason: string) => void;
}

/** 发送一条控制帧到所属 DataChannel，返回是否发送成功 */
export type P2pWsControlSender = (type: P2pControlType, payload: P2pControlPayload) => boolean;

/**
 * 运行在 P2P DataChannel 之上的 WebSocket 隧道（对齐 Flutter _P2pRtcWebSocketChannel）：
 * - open() 发送 ws:open，服务端回应 ws:open:ok 后进入可写状态，未就绪期间的发送先缓存
 * - send()/close() 分别对应 ws:send / ws:close 控制帧
 * - 服务端的 ws:message / ws:error / ws:close 由 WebRTCClient 转发到 handleXxx
 */
export class P2pWebSocket {
  private static nextSeq: number = 0;

  readonly id: string;
  listener: P2pWsListener = {};
  private path: string;
  private headers: HeaderMap;
  private sender: P2pWsControlSender;
  private disposeHandler: (id: string) => void;
  private ready: boolean = false;
  private closed: boolean = false;
  private pending: string[] = [];

  constructor(path: string, headers: HeaderMap, sender: P2pWsControlSender,
    disposeHandler: (id: string) => void) {
    P2pWebSocket.nextSeq += 1;
    this.id = `${Date.now()}_${Math.floor(Math.random() * 1073741824)}_${P2pWebSocket.nextSeq}`;
    this.path = path;
    this.headers = headers;
    this.sender = sender;
    this.disposeHandler = disposeHandler;
  }

  /** 发起隧道握手（ws:open） */
  open(): void {
    if (this.closed || this.ready) {
      return;
    }
    const payload = new P2pControlPayload();
    payload.id = this.id;
    payload.path = this.path;
    payload.headers = this.headers;
    if (!this.sender(P2pControlType.WS_OPEN, payload)) {
      this.fail('p2p_ws_open_send_failed');
    }
  }

  /** 发送文本数据；握手未完成时先缓存，open:ok 后按序补发 */
  send(data: string): void {
    if (this.closed) {
      return;
    }
    if (!this.ready) {
      this.pending.push(data);
      return;
    }
    this.write(data);
  }

  /** 本地关闭：向服务端通知 ws:close 并结束隧道 */
  close(): void {
    if (this.closed) {
      return;
    }
    if (this.ready) {
      const payload = new P2pControlPayload();
      payload.id = this.id;
      this.sender(P2pControlType.WS_CLOSE, payload);
    }
    this.finalize(1000, '');
  }

  // ===== 由 WebRTCClient 驱动的服务端事件 =====

  handleOpenOk(): void {
    if (this.closed) {
      return;
    }
    if (!this.ready) {
      this.ready = true;
      this.listener.onOpen?.();
    }
    const queued = this.pending;
    this.pending = [];
    for (let i = 0; i < queued.length; i++) {
      this.write(queued[i]);
    }
  }

  handleOpenError(error: string): void {
    this.fail(error);
  }

  handleMessage(data: string): void {
    if (this.closed) {
      return;
    }
    this.listener.onMessage?.(data);
  }

  handleRemoteError(error: string): void {
    this.fail(error);
  }

  handleRemoteClose(code: number, reason: string): void {
    this.finalize(code, reason);
  }

  private write(data: string): void {
    if (this.closed || !this.ready) {
      return;
    }
    const payload = new P2pControlPayload();
    payload.id = this.id;
    payload.data = data;
    if (!this.sender(P2pControlType.WS_SEND, payload)) {
      this.fail('p2p_ws_send_failed');
    }
  }

  private fail(error: string): void {
    if (this.closed) {
      return;
    }
    this.listener.onError?.(error);
    this.finalize(1011, error);
  }

  private finalize(code: number, reason: string): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    this.ready = false;
    this.pending = [];
    this.disposeHandler(this.id);
    this.listener.onClose?.(code, reason);
  }
}
