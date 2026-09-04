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
}
