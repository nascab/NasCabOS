'use strict';

const fs = require('fs');
const path = require('path');
const config = require('../../config/config');
const sharpUtils = require('../../utils/sharpUtils');
const MusicTagReader = require('./musicTagReader');

/**
 * 将封面 buffer 写入缓存目录并生成 webp 缩略图
 * @param {{ fileHash: string, coverBuffer: Buffer|Uint8Array, size?: number }} opts
 * @returns {Promise<boolean>}
 */
async function ensureInnerCoverTiny({ fileHash, coverBuffer, size = 500 }) {
  const hash = String(fileHash || '').trim();
  if (!hash) return false;
  if (!coverBuffer || !(Buffer.isBuffer(coverBuffer) || coverBuffer instanceof Uint8Array)) return false;

  const folder = typeof config.getMusicCoverCachePath === 'function' ? config.getMusicCoverCachePath() : '';
  if (!folder) return false;
  const targetPath = path.join(folder, `${hash}.webp`);

  try {
    const st = await fs.promises.stat(targetPath);
    if (st && st.isFile() && st.size > 0) return true;
  } catch (_) {}

  try {
    await fs.promises.mkdir(folder, { recursive: true }).catch(() => {});
    await sharpUtils.genTinyFile(Buffer.from(coverBuffer), folder, hash, 'image', size);
    return true;
  } catch (_) {
    return false;
  }
}

/**
 * 从音频文件重新读取内嵌封面并写入缓存（用于 getCover 缓存丢失时按需重建）
 * @param {{ fullPath: string, fileHash: string, size?: number }} opts
 * @returns {Promise<boolean>}
 */
async function regenerateCoverFromFile({ fullPath, fileHash, size = 200 }) {
  const p = fullPath ? path.resolve(String(fullPath)) : '';
  const hash = fileHash ? String(fileHash).trim() : '';
  if (!p || !hash) return false;

  let st = null;
  try {
    st = await fs.promises.stat(p);
  } catch (_) {}
  if (!st || !st.isFile()) return false;

  const tagReader = new MusicTagReader();
  let tags = null;
  try {
    tags = await tagReader.readAudioTags(p);
  } catch (_) {}
  if (!tags) return false;

  const coverBuffer = tagReader.extractInnerCoverBuffer(tags);
  if (!coverBuffer) return false;

  return await ensureInnerCoverTiny({ fileHash: hash, coverBuffer, size });
}

module.exports = {
  ensureInnerCoverTiny,
  regenerateCoverFromFile,
};
