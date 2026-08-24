const axios = require('axios');
const apiConfig = require('../../../../config/apiConfig');

/** 与远端 music 模块约定的品牌标识头，可通过环境变量覆盖 */
const MUSIC_LYRIC_BRAND_KEY = String(process.env.MUSIC_LYRIC_BRAND_KEY || 'nascab').trim();

let lyricUtils = {};

/**
 * （/api/music/lyric/search）搜索音乐歌词
 */
lyricUtils.searchLyric = async function (params) {
  const searchMusicName = params.searchMusicName || '';
  if (!searchMusicName) return null;
  const startedAt = Date.now();
  try {
    const r = await axios.post(
      apiConfig.apiMusicLyricSearchPath,
      { keyword: searchMusicName },
      {
        timeout: 30000,
        validateStatus: () => true,
        headers: {
          'Content-Type': 'application/json',
          'X-Client-Brand': MUSIC_LYRIC_BRAND_KEY,
        },
      }
    );
    if (r.status !== 200 || !r.data || Number(r.data.code) !== 0) {
      console.log(`[lyric] 远端歌词搜索失败 status=${r.status} code=${r.data?.code} keyword="${searchMusicName}"`);
      return null;
    }
    const list = r.data.data;
    console.log(
      `[lyric] 远端歌词搜索成功 url=${apiConfig.apiMusicLyricSearchPath} keyword="${searchMusicName}" 结果数=${Array.isArray(list) ? list.length : 0} 耗时=${Date.now() - startedAt}ms`
    );
    return Array.isArray(list) ? list : null;
  } catch (e) {
    console.log(`[lyric] 远端歌词搜索异常 keyword="${searchMusicName}" err=${e?.message}`);
    return null;
  }
};

module.exports = lyricUtils;
