import { picker } from '@kit.CoreFileKit';
import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { UriReader } from './UriReader';

/**
 * 本地选择器工具（对齐 Flutter mobile_media_file_picker.dart）：
 * - 相册选择：PhotoViewPicker（图片+视频一次可选，最多 500）
 * - 文件选择：DocumentViewPicker（任意类型多选）
 */
export class MediaPickerUtil {
  /** 打开相册选择器，返回选中的 URI 列表 */
  static async pickMedia(): Promise<string[]> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const opts = new picker.PhotoSelectOptions();
      opts.MIMEType = picker.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
      opts.maxSelectNumber = 500;
      const result: picker.PhotoSelectResult = await photoPicker.select(opts);
      return result.photoUris ?? [];
    } catch (_e) {
      // 用户取消选择
      return [];
    }
  }

  /** 打开文件选择器，返回选中的 URI 列表 */
  static async pickFiles(): Promise<string[]> {
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 500;
      const uris: string[] = await docPicker.select(opts);
      return uris ?? [];
    } catch (_e) {
      // 用户取消选择
      return [];
    }
  }

  /** 从 URI 提取显示名（最后一段路径，剥除查询参数） */
  static uriDisplayName(uri: string): string {
    const clean = uri.split('?')[0];
    const idx = clean.lastIndexOf('/');
    if (idx < 0 || idx >= clean.length - 1) {
      return '';
    }
    return decodeURIComponent(clean.substring(idx + 1));
  }

  /** 校验 URI 可访问；不可访问时提示 */
  static async ensureUriReadable(uri: string): Promise<boolean> {
    const ok = UriReader.exists(uri);
    if (!ok) {
      ToastUtil.show(L10n.t('file_not_found', '文件不存在'));
    }
    return ok;
  }
}
