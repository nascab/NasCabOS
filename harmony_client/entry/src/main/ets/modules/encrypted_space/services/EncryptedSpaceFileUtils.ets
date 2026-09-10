import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { APIClient } from '../../../core/network/APIClient';
import { L10n } from '../../../core/localization/L10n';
import { ToastUtil } from '../../../common/ToastUtil';
import { PlayerPlaylistItem } from '../../../video_player/models/PlayerModels';
import { openVideoPlayer } from '../../../video_player/views/PlayerNavigator';
import { MediaPickerUtil } from '../../../transfer/utils/MediaPickerUtil';
import { EncryptedSpaceActiveSpace, EncryptedFileItem } from '../models/EncryptedSpaceModels';
import { EncryptedSpaceApiService } from './EncryptedSpaceApiService';

const TAG = 'EncryptedSpaceFile';

/**
 * 加密空间文件工具：本地文件选择、URI 文件名提取、解码文件下载另存
 * （对齐 Flutter MobileMediaFilePicker / DownloadController.handleDownload）。
 */
export class EncryptedSpaceFileUtils {
  /** 相册选择（图片+视频多选，对齐 MobileMediaFilePicker.pickMediaUploadEntries） */
  static async pickMediaUris(): Promise<string[]> {
    return MediaPickerUtil.pickMedia();
  }

  /** 文件选择（任意类型多选，对齐 MobileMediaFilePicker.pickFiles） */
  static async pickFileUris(): Promise<string[]> {
    return MediaPickerUtil.pickFiles();
  }

  /** 从 URI 提取上传文件名（最后一段路径，剥除查询参数） */
  static fileNameFromUri(uri: string): string {
    return MediaPickerUtil.uriDisplayName(uri);
  }

  /**
   * 下载解码文件并弹出系统"保存"选择器写入（对齐 Flutter DownloadController.handleDownload）。
   * 用户取消静默；失败 Toast（对齐导出失败提示）。
   */
  static async downloadAndSave(url: string, fileName: string): Promise<void> {
    if (url.trim().length === 0) {
      return;
    }
    const name = fileName.trim().length > 0 ? fileName.trim() : 'file';
    try {
      await EncryptedSpaceFileUtils.saveUrlAs(url, name);
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      hilog.error(0x0000, TAG, 'downloadAndSave failed: %{public}s', msg);
      ToastUtil.show(msg.length > 0 ? msg : L10n.operationFailed);
    }
  }

  /** 下载 url 内容并写入用户选择位置；用户取消返回 false；失败抛错 */
  private static async saveUrlAs(url: string, fileName: string): Promise<boolean> {
    const docPicker = new picker.DocumentViewPicker();
    const opts = new picker.DocumentSaveOptions();
    opts.newFileNames = [fileName];
    const uris = await docPicker.save(opts);
    if (!uris || uris.length === 0) {
      return false;
    }
    const token = (APIClient.getInstance().accessToken ?? '').trim();
    const header: Record<string, string> = {};
    if (token.length > 0) {
      header['Authorization'] = `Bearer ${token}`;
    }
    const client = http.createHttp();
    let file: fs.File | null = null;
    try {
      const resp = await client.request(url, {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 120000,
        maxLimit: 200 * 1024 * 1024
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`HTTP ${resp.responseCode}`);
      }
      file = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, resp.result as ArrayBuffer);
      return true;
    } catch (e) {
      const msg = e instanceof Error ? e.message : `${JSON.stringify(e)}`;
      hilog.error(0x0000, TAG, 'saveUrlAs failed: %{public}s', msg);
      throw new Error(msg);
    } finally {
      if (file !== null) {
        fs.closeSync(file);
      }
      client.destroy();
    }
  }

  /** 打开视频播放器（对齐 _openVideo：视频解码 URL 列表 + 命中下标） */
  static openVideoPlayer(active: EncryptedSpaceActiveSpace,
    videos: EncryptedFileItem[], index: number): void {
    const playlist: PlayerPlaylistItem[] = [];
    for (const v of videos) {
      const it = new PlayerPlaylistItem();
      it.path = EncryptedSpaceApiService.buildDecodeUrl(
        active.spaceId, active.token, v.indexId, '', false, '');
      it.name = v.displayTitle();
      playlist.push(it);
    }
    if (playlist.length === 0 || index < 0 || index >= playlist.length) {
      return;
    }
    openVideoPlayer(playlist, index, 1);
  }
}
