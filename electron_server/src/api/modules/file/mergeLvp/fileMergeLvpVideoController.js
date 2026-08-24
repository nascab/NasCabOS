'use strict';

const fs = require('fs');
const path = require('path');
const exifr = require('exifr');

/**
 * 从 merge LVP (OPPO 实况照片) JPEG 中提取嵌入的 MP4 视频并流式返回
 * GET /api/file/mergeLvpVideo?path=xxx
 */
async function getMergeLvpVideo(req, res) {
  try {
    const { path: pathUrl } = req.query;
    if (!pathUrl) return res.status(400).send('Missing path');

    const fullPath = path.resolve(pathUrl);

    try {
      await fs.promises.access(fullPath, fs.constants.R_OK);
    } catch (e) {
      return res.status(404).send('File not found');
    }

    // 解析 EXIF 获取嵌入视频的长度
    const metadata = await exifr.parse(fullPath, true);
    let videoLength = 0;

    if (metadata && metadata['Directory'] && metadata['Directory'].length > 0) {
      const dirs = metadata['Directory'];
      const videoItem = dirs[dirs.length - 1]['Item'];
      if (videoItem && videoItem['Mime'] && videoItem['Mime'].indexOf('video/') !== -1 && videoItem['Length']) {
        videoLength = Number(videoItem['Length']);
      }
    }

    if (!videoLength || videoLength <= 0) {
      return res.status(400).send('Not a valid merge LVP photo');
    }

    // 读取文件并提取视频数据（视频位于文件末尾）
    const fileBuffer = await fs.promises.readFile(fullPath);
    const fileTotalSize = fileBuffer.length;

    if (videoLength > fileTotalSize) {
      return res.status(400).send('Invalid video length in EXIF');
    }

    const videoBuffer = fileBuffer.slice(fileTotalSize - videoLength);

    // 设置响应头，支持 Range 请求以便播放器 seek
    const videoSize = videoBuffer.length;
    res.setHeader('Content-Type', 'video/mp4');
    res.setHeader('Accept-Ranges', 'bytes');

    const range = req.headers.range;
    if (range) {
      const parts = range.replace(/bytes=/, '').split('-');
      const start = parseInt(parts[0], 10);
      const end = parts[1] ? parseInt(parts[1], 10) : videoSize - 1;
      const chunkSize = (end - start) + 1;

      res.status(206);
      res.setHeader('Content-Range', `bytes ${start}-${end}/${videoSize}`);
      res.setHeader('Content-Length', chunkSize);
      res.end(videoBuffer.slice(start, end + 1));
    } else {
      res.setHeader('Content-Length', videoSize);
      res.end(videoBuffer);
    }
  } catch (err) {
    console.error('getMergeLvpVideo error:', err);
    if (!res.headersSent) res.status(500).send(err.message || 'Internal server error');
  }
}

module.exports = { getMergeLvpVideo };
