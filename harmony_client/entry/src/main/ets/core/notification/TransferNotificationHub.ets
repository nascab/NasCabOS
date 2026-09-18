import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { L10n } from '../localization/L10n';
import { WindowStore } from '../../common/WindowStore';

const ID_DOWNLOAD = 9201;
const ID_UPLOAD = 9202;
const ID_BACKUP = 9203;
/** 进度刷新节流（对齐 Flutter TransferWorkNotificationHub._throttle） */
const THROTTLE_MS = 700;

/**
 * 传输类后台任务共用本地通知（对齐 Flutter TransferWorkNotificationHub）：
 * 下载 / 上传 / 相册备份各最多一条通知，refcount 归零时移除；
 * 进度刷新带 700ms 节流。通知内容使用系统 downloadTemplate 进度条（支持时）。
 */

class ThrottleClock {
  last: number = 0;

  shouldSkip(): boolean {
    const now = Date.now();
    if (now - this.last < THROTTLE_MS) {
      return true;
    }
    this.last = now;
    return false;
  }
}

export class TransferNotificationHub {
  private static downloadRef: number = 0;
  private static uploadRef: number = 0;
  private static backupRef: number = 0;
  private static downloadClock: ThrottleClock = new ThrottleClock();
  private static uploadClock: ThrottleClock = new ThrottleClock();
  private static backupClock: ThrottleClock = new ThrottleClock();
  private static inited: boolean = false;
  /** 用户已拒绝通知授权时置 false，后续直接跳过 publish */
  private static allowed: boolean = true;
  private static templateSupported: boolean | undefined = undefined;

  private static context(): common.UIAbilityContext | undefined {
    return WindowStore.appContext;
  }

  /** 初始化：请求通知授权（系统弹窗仅首次出现）；失败静默跳过（对齐 Flutter _notificationsAllowed） */
  private static async ensureInitialized(): Promise<void> {
    if (TransferNotificationHub.inited) {
      return;
    }
    TransferNotificationHub.inited = true;
    const ctx = TransferNotificationHub.context();
    if (!ctx) {
      TransferNotificationHub.allowed = false;
      return;
    }
    try {
      await notificationManager.requestEnableNotification(ctx);
    } catch (_e) {
      // 用户拒绝或重复请求时抛错：保持 allowed=true 由 publish 失败兜底
    }
    try {
      const support = await notificationManager.isSupportTemplate('downloadTemplate');
      TransferNotificationHub.templateSupported = support;
    } catch (_e) {
      TransferNotificationHub.templateSupported = false;
    }
  }

  private static bodyText(title: string, text: string): notificationManager.NotificationContent {
    return {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal: { title: title, text: text, additionalText: '' }
    };
  }

  /** 发布/更新带进度条的通知；模板不可用时回退纯文本 */
  private static async showWithProgress(id: number, title: string, text: string,
    progress: number | undefined): Promise<void> {
    await TransferNotificationHub.ensureInitialized();
    if (!TransferNotificationHub.allowed) {
      return;
    }
    try {
      const request: notificationManager.NotificationRequest = {
        id: id,
        content: TransferNotificationHub.bodyText(title, text)
      };
      if (TransferNotificationHub.templateSupported) {
        const tplData: Record<string, Object> = {
          'progressValue': progress !== undefined && progress > 0 ? progress : 0,
          'progressMax': 100,
          'isPercent': true,
          'title': title,
          'fileName': text
        };
        const tpl: notificationManager.NotificationTemplate = {
          name: 'downloadTemplate',
          data: tplData
        };
        request.template = tpl;
      }
      await notificationManager.publish(request);
    } catch (_e) {
      // 通知发送失败不阻断传输（权限被拒等）
    }
  }

  private static async cancel(id: number): Promise<void> {
    try {
      await notificationManager.cancel(id);
    } catch (_e) {
      // 通知可能已移除
    }
  }

  // ==================== 下载 ====================

  static async downloadWorkBegan(): Promise<void> {
    TransferNotificationHub.downloadRef += 1;
    if (TransferNotificationHub.downloadRef !== 1) {
      return;
    }
    await TransferNotificationHub.showWithProgress(
      ID_DOWNLOAD,
      L10n.t('transfer_notification_downloading_title', '正在下载...'),
      L10n.t('transfer_notification_downloading_body', '@displayName\n@progress @networkSpeed',
        TransferNotificationHub.params3('…', '', '')),
      undefined);
  }

  static async downloadWorkEnded(): Promise<void> {
    if (TransferNotificationHub.downloadRef > 0) {
      TransferNotificationHub.downloadRef -= 1;
    }
    if (TransferNotificationHub.downloadRef === 0) {
      await TransferNotificationHub.cancel(ID_DOWNLOAD);
    }
  }

  static async downloadProgressThrottled(displayName: string, percent: number | undefined): Promise<void> {
    if (TransferNotificationHub.downloadRef <= 0) {
      return;
    }
    if (TransferNotificationHub.downloadClock.shouldSkip()) {
      return;
    }
    const progressText = percent !== undefined ? `${percent}%` : '…';
    await TransferNotificationHub.showWithProgress(
      ID_DOWNLOAD,
      L10n.t('transfer_notification_downloading_title', '正在下载...'),
      L10n.t('transfer_notification_downloading_body', '@displayName\n@progress @networkSpeed',
        TransferNotificationHub.params3(displayName, progressText, '')),
      percent);
  }

  // ==================== 上传 ====================

  static async uploadWorkBegan(): Promise<void> {
    TransferNotificationHub.uploadRef += 1;
    if (TransferNotificationHub.uploadRef !== 1) {
      return;
    }
    await TransferNotificationHub.showWithProgress(
      ID_UPLOAD,
      L10n.t('transfer_notification_uploading_title', '正在上传...'),
      L10n.t('transfer_notification_uploading_body', '@displayName\n@progress @networkSpeed',
        TransferNotificationHub.params3('…', '', '')),
      undefined);
  }

  static async uploadWorkEnded(): Promise<void> {
    if (TransferNotificationHub.uploadRef > 0) {
      TransferNotificationHub.uploadRef -= 1;
    }
    if (TransferNotificationHub.uploadRef === 0) {
      await TransferNotificationHub.cancel(ID_UPLOAD);
    }
  }

  static async uploadWorkForceCancel(): Promise<void> {
    TransferNotificationHub.uploadRef = 0;
    await TransferNotificationHub.cancel(ID_UPLOAD);
  }

  static async uploadProgressThrottled(displayName: string, processed: number, total: number): Promise<void> {
    if (TransferNotificationHub.uploadRef <= 0) {
      return;
    }
    if (TransferNotificationHub.uploadClock.shouldSkip()) {
      return;
    }
    let pct: number | undefined = undefined;
    if (total > 0) {
      pct = Math.min(100, Math.max(0, Math.floor((processed / total) * 100)));
    }
    const progressText = pct !== undefined ? `${pct}%` : '…';
    await TransferNotificationHub.showWithProgress(
      ID_UPLOAD,
      L10n.t('transfer_notification_uploading_title', '正在上传...'),
      L10n.t('transfer_notification_uploading_body', '@displayName\n@progress @networkSpeed',
        TransferNotificationHub.params3(displayName, progressText, '')),
      pct);
  }

  // ==================== 相册备份 ====================

  static async backupWorkBegan(): Promise<void> {
    TransferNotificationHub.backupRef += 1;
    if (TransferNotificationHub.backupRef !== 1) {
      return;
    }
    await TransferNotificationHub.showWithProgress(
      ID_BACKUP,
      L10n.t('transfer_notification_photo_backup_title', '正在备份相册…'),
      L10n.t('transfer_notification_photo_backup_body', '@currentFile\n@progress',
        TransferNotificationHub.params2('…', '')),
      undefined);
  }

  static async backupWorkEnded(): Promise<void> {
    if (TransferNotificationHub.backupRef > 0) {
      TransferNotificationHub.backupRef -= 1;
    }
    if (TransferNotificationHub.backupRef === 0) {
      await TransferNotificationHub.cancel(ID_BACKUP);
    }
  }

  /**
   * 刷新相册备份通知文案（内部节流）；progress 为 0~1（与 PhotoBackupRuntime.progress 一致），
   * 无总字节/文件数信息时进度文本为空。
   */
  static async photoBackupProgressThrottled(currentFile: string, progress: number | undefined,
    doneFiles: number, totalFiles: number): Promise<void> {
    if (TransferNotificationHub.backupRef <= 0) {
      return;
    }
    if (TransferNotificationHub.backupClock.shouldSkip()) {
      return;
    }
    let progressText: string;
    if (progress !== undefined) {
      progressText = `${Math.floor(progress * 100)}%`;
    } else if (totalFiles > 0) {
      progressText = `${doneFiles}/${totalFiles}`;
    } else {
      progressText = '';
    }
    const file = currentFile.trim().length > 0 ? currentFile : '…';
    let pct: number | undefined = undefined;
    if (progress !== undefined) {
      pct = Math.min(100, Math.max(0, Math.floor(progress * 100)));
    }
    await TransferNotificationHub.showWithProgress(
      ID_BACKUP,
      L10n.t('transfer_notification_photo_backup_title', '正在备份相册…'),
      L10n.t('transfer_notification_photo_backup_body', '@currentFile\n@progress',
        TransferNotificationHub.params2(file, progressText)),
      pct);
  }

  // ==================== 参数构造 ====================

  private static params3(displayName: string, progress: string, networkSpeed: string): Map<string, string> {
    const p = new Map<string, string>();
    p.set('displayName', displayName);
    p.set('progress', progress);
    p.set('networkSpeed', networkSpeed);
    return p;
  }

  private static params2(currentFile: string, progress: string): Map<string, string> {
    const p = new Map<string, string>();
    p.set('currentFile', currentFile);
    p.set('progress', progress);
    return p;
  }
}
