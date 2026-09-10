import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import pasteboard from '@ohos.pasteboard';
import { APIClient } from '../../../core/network/APIClient';
import { L10n } from '../../../core/localization/L10n';
import { ToastUtil } from '../../../common/ToastUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'NotesFile';

/**
 * 笔记文件工具：服务器文件下载并另存（对齐 Flutter FilePicker.saveFile / DownloadController 语义）。
 */
export class NotesFileUtils {
  /**
   * 笔记导出下载（对齐 Flutter DownloadController.handleDownload）：下载并另存，
   * 失败 Toast（对齐导出失败提示），取消/成功静默。
   */
  static async exportNote(url: string, fileName: string): Promise<void> {
    if (url.trim().length === 0) {
      return;
    }
    try {
      await NotesFileUtils.saveUrlAs(url, fileName);
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      hilog.error(0x0000, TAG, 'exportNote failed: %{public}s', msg);
      ToastUtil.show(msg.length > 0 ? msg : L10n.t('notes_export_failed'));
    }
  }

  /** 笔记导出扩展名（对齐 buildExportUrl：markdown → md） */
  static exportExt(format: string): string {
    const lower = format.trim().toLowerCase();
    return lower === 'markdown' ? 'md' : lower;
  }

  /**
   * 下载 url 内容并弹出系统"保存"文档选择器写入用户选择位置。
   * 返回 true 表示已保存；用户取消返回 false；失败抛错。
   */
  static async saveUrlAs(url: string, fileName: string): Promise<boolean> {
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
        maxLimit: 100 * 1024 * 1024
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

  /**
   * 复制网络图片到剪贴板（对齐 Flutter 图片菜单 Copy：像素位图入剪贴板）。
   * 非图片内容/下载失败静默失败（Toast 提示）。
   */
  static async copyImageToClipboard(url: string): Promise<void> {
    const target = url.trim();
    if (target.length === 0) {
      return;
    }
    let client: http.HttpRequest | null = null;
    try {
      const token = (APIClient.getInstance().accessToken ?? '').trim();
      const header: Record<string, string> = {};
      if (token.length > 0 && target.startsWith('http')) {
        header['Authorization'] = `Bearer ${token}`;
      }
      client = http.createHttp();
      const resp = await client.request(target, {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 60000,
        maxLimit: 50 * 1024 * 1024
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`HTTP ${resp.responseCode}`);
      }
      const source = image.createImageSource(resp.result as ArrayBuffer);
      const pixelMap = await source.createPixelMap();
      const data = pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, pixelMap);
      pasteboard.getSystemPasteboard().setPasteData(data);
      await source.release();
    } catch (e) {
      hilog.error(0x0000, TAG, 'copyImageToClipboard failed: %{public}s',
        e instanceof Error ? e.message : `${JSON.stringify(e)}`);
      ToastUtil.show(L10n.operationFailed);
    } finally {
      if (client !== null) {
        client.destroy();
      }
    }
  }

  /**
   * 图片保存下载 URL（对齐 Flutter _buildDownloadUrl）：
   * http(s) URL；仅有 name 参数时补 fileName=name；其余原样。
   */
  static buildImageDownloadUrl(imageUrl: string): string {
    const trimmed = imageUrl.trim();
    const q = trimmed.indexOf('?');
    if (q < 0) {
      return trimmed;
    }
    const query = trimmed.substring(q + 1);
    const parts = query.split('&');
    let hasFileName = false;
    let assetName = '';
    const kept: string[] = [];
    parts.forEach((p: string): void => {
      const eq = p.indexOf('=');
      if (eq < 0) {
        return;
      }
      const key = p.substring(0, eq).trim();
      const val = p.substring(eq + 1).trim();
      if (key === 'fileName') {
        hasFileName = true;
      } else if (key === 'name') {
        assetName = val;
      }
      kept.push(p);
    });
    if (assetName.length > 0 && !hasFileName) {
      kept.push(`fileName=${assetName}`);
    }
    return `${trimmed.substring(0, q)}?${kept.join('&')}`;
  }

  /** 图片保存文件名（优先 fileName/name 查询参数，否则取路径末段） */
  static imageFileNameFromUrl(imageUrl: string): string {
    const trimmed = imageUrl.trim();
    const q = trimmed.indexOf('?');
    const query = q >= 0 ? trimmed.substring(q + 1) : '';
    if (query.length > 0) {
      const parts = query.split('&');
      for (const key of ['fileName', 'name']) {
        for (const p of parts) {
          const eq = p.indexOf('=');
          if (eq > 0 && p.substring(0, eq).trim() === key) {
            const val = decodeURIComponent(p.substring(eq + 1).trim());
            if (val.length > 0) {
              return val;
            }
          }
        }
      }
    }
    const path = q >= 0 ? trimmed.substring(0, q) : trimmed;
    const slash = path.lastIndexOf('/');
    const name = slash >= 0 ? path.substring(slash + 1) : path;
    return name.length > 0 ? name : 'image';
  }
}

