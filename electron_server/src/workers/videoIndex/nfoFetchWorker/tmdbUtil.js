class TmdbUtil {
  //清洗文件名用于搜索
  getSearchTokens(text) {
    const cleaned = this.cleanSearchText(text).toLowerCase();
    if (!cleaned) return [];

    const parts = cleaned
      .split(' ')
      .map(s => s.trim())
      .filter(Boolean);
    let year = 0;
    const tokens = [];
    for (const raw of parts) {
      const tok = raw.trim();
      if (!tok) continue;
      if (TmdbUtil.EXCLUDE_TOKENS.has(tok)) continue;
      let pass = true;
      for (const like of TmdbUtil.EXCLUDE_LIKE_TOKENS) {
        if (tok.includes(like) && like.length / tok.length > 0.5) {
          pass = false;
          continue;
        }
      }
      if (!pass) continue;
      if (/^\d{3,4}p$/.test(tok)) continue;
      if (/^\d{3,4}x\d{3,4}$/.test(tok)) continue;
      if (/^\d{4}$/.test(tok)) {
        const y = Number(tok) || 0;
        if (y >= 1895 && y <= 2100) {
          if (!year) year = y;
          continue;
        }
      }
      if (/^\d{6,}$/.test(tok)) continue;
      tokens.push(tok);
    }
    return { tokens, year };
  }
  cleanSearchText(s) {
    let t = String(s || '').trim();
    if (!t) return '';
    t = t.replace(/www\.[a-zA-Z\d-]+\.(?:com\.cn|cn|com|net|cc|de|uk|org|info|nl|eu|ru|org|live|tv)\b/gi, ' ');
    t = t.replace(/\b(?:https?:\/\/)\S+\b/gi, ' ');
    t = t.replace(/\b(?:5\.1|7\.1)\b/gi, ' ');
    t = t.replace(/\bS\d{1,2}E\d{1,2}\b/gi, ' ');
    t = t.replace(/[\[\]{}()]/g, ' ');
    t = t.replace(/[`\-~!@#$%^&*()_+=|{}[\]:;"',.<>/?\\，。！？【】（）《》、：；“”‘’]/g, ' ');
    t = t.replace(/\s+/g, ' ').trim();
    return t;
  }
  //包含也不行的
  static EXCLUDE_LIKE_TOKENS = new Set([
    'hd国语中英双字',
    'hd国语中字',
    'hd中英双字',
    '中字',
    '双语',
    '英语中字',
    '英文中字',
    '中文字幕',
    '官方中文字幕',
    '电影天堂',
    '阳光电影',
    '英语中英双字',
    'dygod',
  ]);
  //判断相等的
  static EXCLUDE_TOKENS = new Set([
    'rarbg',
    'nodlabs',
    'hdsweb',
    'pianyuan',
    'dl',
    'hhweb',
    'eng',
    'chs',
    'btsj6',
    'btsj5',
    'btsj4',
    'btsj3',
    'btsj2',
    'btsj1',
    'btdx8',
    'mp4ba',
    'ddp5',
    'dreamhd',
    'hd1080p',
    '2160p',
    '1080p',
    '720p',
    '480p',
    '4k',
    'uhd',
    'hdr',
    'hdr10',
    'sdr',
    'dv',
    'atmos',
    'truehd',
    'dts',
    'dts-hd',
    'aac',
    'ac3',
    'ddp',
    '10bit',
    '8bit',
    'x264',
    'x265',
    'h264',
    'h265',
    'hevc',
    'avc',
    'web',
    'webrip',
    'web-dl',
    'webdl',
    'bdrip',
    'brrip',
    'bluray',
    'blu-ray',
    'remux',
    'hdtv',
    'internal',
    'remastered',
    'mkv',
    'mp4',
    'avi',
    'rmvb',
    'rm',
    'mov',
    '3gp',
    'hd',
    'org',
    '2audio',
    'uump4',
    'bd',
    '阳光电影dygod',
  ]);
}
let tmdbUtil = new TmdbUtil();
module.exports = tmdbUtil;
