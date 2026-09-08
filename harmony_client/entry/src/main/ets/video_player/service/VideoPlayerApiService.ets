/**
 * 播放器 API 服务（对齐 Flutter controllers/parts 中使用的 /api/videoPlayer/* 端点）：
 * info / stop / preference / subtitle-vtt / searchSubtitle / downloadSearchedSubtitle /
 * deleteExternalSubtitle / uploadSubtitle。
 */

import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { APIClient } from '../../core/network/APIClient';
import { APIResponse } from '../../core/network/APIResponse';
import { ApiEnvelope } from '../../common/JsonTypes';
import { hilog } from '@kit.PerformanceAnalysisKit';
import fs from '@ohos.file.fs';

const TAG = 'PlayerApi';

function jsonRecordParser(): (data: Object, code: number) => Record<string, Object> {
  return (d: Object, _c: number) => JSON.parse(JSON.stringify(d)) as Record<string, Object>;
}

/** 空请求体（显式类型，避免无类型对象字面量报错） */
const EMPTY_BODY: Record<string, Object> = {};

/** 带 Authorization 的请求头（显式 Record 类型） */
function authHeader(token: string): Record<string, string> {
  const h: Record<string, string> = {};
  if (token.length > 0) {
    h['Authorization'] = `Bearer ${token}`;
  }
  return h;
}

export class VideoPlayerApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  /** GET /api/videoPlayer/info：流信息（duration/size/openSkip/streams/externalSubtitles/preference） */
  async getStreamInfo(filePath: string, internalPath: string,
    ignoreFindSub: number): Promise<APIResponse<Record<string, Object>>> {
    const query = new Map<string, string>();
    query.set('filePath', filePath);
    query.set('ignoreFindSub', `${ignoreFindSub === 0 ? 0 : 1}`);
    if (internalPath.trim().length > 0) {
      query.set('internalPath', internalPath);
    }
    return this.api().apiGet<Record<string, Object>>('/api/videoPlayer/info', query,
      undefined, undefined, jsonRecordParser());
  }

  /** GET /api/file/attributes：文件基础信息（name/path/size，对齐 Flutter VideoInfoDrawer） */
  async getFileAttributes(filePath: string): Promise<APIResponse<Record<string, Object>>> {
    const query = new Map<string, string>();
    query.set('path', filePath);
    return this.api().apiGet<Record<string, Object>>('/api/file/attributes', query,
      undefined, undefined, jsonRecordParser());
  }

  /** POST /api/videoPlayer/stop：停止转码会话 */
  async stopTranscode(playId: string): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'playId': playId };
    return this.api().apiPost<Record<string, Object>>('/api/videoPlayer/stop', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  /** POST /api/videoPlayer/preference：保存进度与音轨/字幕偏好 */
  async savePreference(filePath: string, internalPath: string, positionSec: number,
    subtitleLabel: string, audioLabel: string): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'filePath': filePath,
      'playback_position': `${positionSec}`,
      'subtitle_label': subtitleLabel,
      'audio_label': audioLabel
    };
    if (internalPath.trim().length > 0) {
      body['internalPath'] = internalPath.trim();
    }
    return this.api().apiPost<Record<string, Object>>('/api/videoPlayer/preference', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  /** POST /api/videoPlayer/searchSubtitle：字幕搜索（searchType: feature/keyword） */
  async searchSubtitles(videoPath: string, searchType: string,
    keyword: string): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'filePath': videoPath,
      'searchType': searchType
    };
    if (keyword.trim().length > 0) {
      body['keyword'] = keyword.trim();
    }
    return this.api().apiPost<Record<string, Object>>('/api/videoPlayer/searchSubtitle', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  /** POST /api/videoPlayer/downloadSearchedSubtitle：下载搜索到的字幕 */
  async downloadSearchedSubtitle(videoPath: string, surl: string, sname: string,
    language: string): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'filePath': videoPath,
      'surl': surl,
      'sname': sname,
      'language': language
    };
    return this.api().apiPost<Record<string, Object>>('/api/videoPlayer/downloadSearchedSubtitle',
      body, undefined, undefined, undefined, jsonRecordParser());
  }

  /** POST /api/videoPlayer/deleteExternalSubtitle：删除外挂字幕 */
  async deleteExternalSubtitle(videoPath: string,
    subtitlePath: string): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'filePath': videoPath,
      'subtitlePath': subtitlePath
    };
    return this.api().apiPost<Record<string, Object>>('/api/videoPlayer/deleteExternalSubtitle',
      body, undefined, undefined, undefined, jsonRecordParser());
  }

  /** GET /api/videoPlayer/subtitle-vtt：字幕 VTT 文本（外挂传 subtitlePath，内嵌传 filePath + subtitleIndex） */
  async getSubtitleVtt(videoPath: string, subtitleIndex: number,
    subtitlePath: string): Promise<string | undefined> {
    const api = this.api();
    const token = api.accessToken ?? '';
    let url = `${api.baseUrl}/api/videoPlayer/subtitle-vtt?subtitleIndex=${subtitleIndex}`;
    if (subtitlePath.trim().length > 0) {
      url += `&subtitlePath=${encodeURIComponent(subtitlePath)}`;
    } else {
      url += `&filePath=${encodeURIComponent(videoPath)}`;
    }
    if (token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    const client = http.createHttp();
    try {
      const resp = await client.request(url, {
        method: http.RequestMethod.GET,
        header: authHeader(token),
        connectTimeout: 15000,
        readTimeout: 30000
      });
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        const text = resp.result as string;
        return text.length > 0 ? text : undefined;
      }
      hilog.error(0x0000, TAG, 'subtitle-vtt http %{public}d', resp.responseCode);
      return undefined;
    } catch (e) {
      hilog.error(0x0000, TAG, 'subtitle-vtt failed: %{public}s', JSON.stringify(e));
      return undefined;
    } finally {
      client.destroy();
    }
  }

  /** POST /api/videoPlayer/uploadSubtitle：上传本地字幕文件（multipart/form-data） */
  async uploadSubtitle(videoPath: string, localFilePath: string,
    filename: string): Promise<APIResponse<Record<string, Object>>> {
    const api = this.api();
    const token = api.accessToken ?? '';
    const boundary = `nascab-${Date.now()}`;
    let file: fs.File | null = null;
    try {
      file = fs.openSync(localFilePath, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      const fileBytes = new Uint8Array(buf);

      const filePart = `--${boundary}\r\n` +
        `Content-Disposition: form-data; name="file"; filename="${filename}"\r\n` +
        `Content-Type: application/octet-stream\r\n\r\n`;
      const tail = `\r\n`;
      const pathPart = `--${boundary}\r\n` +
        `Content-Disposition: form-data; name="filePath"\r\n\r\n${videoPath}\r\n`;
      const end = `\r\n--${boundary}--\r\n`;

      const encoder = new util.TextEncoder();
      const headBytes: Uint8Array = encoder.encode(pathPart + filePart);
      const tailBytes: Uint8Array = encoder.encode(tail + end);

      const total: number = headBytes.length + fileBytes.length + tailBytes.length;
      const bodyBuf = new ArrayBuffer(total);
      const bodyView = new Uint8Array(bodyBuf);
      bodyView.set(headBytes, 0);
      bodyView.set(fileBytes, headBytes.length);
      bodyView.set(tailBytes, headBytes.length + fileBytes.length);

      const header: Record<string, string> = {
        'Content-Type': `multipart/form-data; boundary=${boundary}`
      };
      if (token.length > 0) {
        header['Authorization'] = `Bearer ${token}`;
      }
      const client = http.createHttp();
      try {
        const resp = await client.request(`${api.baseUrl}/api/videoPlayer/uploadSubtitle`, {
          method: http.RequestMethod.POST,
          header: header,
          extraData: bodyBuf,
          connectTimeout: 15000,
          readTimeout: 60000
        });
        const ok = resp.responseCode >= 200 && resp.responseCode < 300;
        const text = resp.result as string;
        if (!ok) {
          return APIResponse.failure('upload failed', resp.responseCode);
        }
        const json = JSON.parse(text) as ApiEnvelope;
        return APIResponse.fromJSON<Record<string, Object>>(resp.responseCode, json, jsonRecordParser());
      } finally {
        client.destroy();
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'uploadSubtitle failed: %{public}s', JSON.stringify(e));
      return APIResponse.failure(`${JSON.stringify(e)}`);
    } finally {
      if (file !== null) {
        fs.closeSync(file);
      }
    }
  }
}
