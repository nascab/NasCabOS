import { QUICK_SHARE_AES_KEY } from './constants.js';

export function base64ToBytes(b64) {
  const raw = String(b64 || '').trim();
  if (!raw) return new Uint8Array(0);
  try {
    const bin = atob(raw);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch (_) {
    return new Uint8Array(0);
  }
}

export async function sha256Hex(text) {
  try {
    if (!window.crypto || !window.crypto.subtle) return '';
    const buf = await window.crypto.subtle.digest('SHA-256', new TextEncoder().encode(String(text ?? '')));
    const bytes = new Uint8Array(buf);
    let hex = '';
    for (const b of bytes) hex += b.toString(16).padStart(2, '0');
    return hex;
  } catch (_) {
    return '';
  }
}

export async function sha256Bytes(text) {
  try {
    if (!window.crypto || !window.crypto.subtle) return new Uint8Array(0);
    const buf = await window.crypto.subtle.digest('SHA-256', new TextEncoder().encode(String(text ?? '')));
    return new Uint8Array(buf);
  } catch (_) {
    return new Uint8Array(0);
  }
}

export async function decryptPairCode(enc) {
  const bytes = base64ToBytes(enc);
  if (!bytes || bytes.length <= 16) return '';
  const iv = bytes.slice(0, 16);
  const data = bytes.slice(16);
  try {
    if (!window.crypto || !window.crypto.subtle) return '';
    const keyRaw = await sha256Bytes(QUICK_SHARE_AES_KEY);
    if (!keyRaw.length) return '';
    const key = await window.crypto.subtle.importKey('raw', keyRaw, { name: 'AES-CBC' }, false, ['decrypt']);
    const plainBuf = await window.crypto.subtle.decrypt({ name: 'AES-CBC', iv }, key, data);
    return new TextDecoder().decode(new Uint8Array(plainBuf)).trim();
  } catch (_) {
    return '';
  }
}
