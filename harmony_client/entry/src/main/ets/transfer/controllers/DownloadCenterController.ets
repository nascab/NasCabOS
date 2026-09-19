import { ComponentContent, promptAction } from '@kit.ArkUI';
import fs from '@ohos.file.fs';
import { AppTheme } from '../../core/theme/AppTheme';
import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { WindowStore } from '../../common/WindowStore';
import { DownloadedFileEntry } from '../models/DownloadModels';
import { DownloadHistoryStorage } from '../storage/DownloadHistoryStorage';
import { DownloadService } from '../services/DownloadService';

/** 已完成列表分页大小（对齐 Flutter _pageSize） */
const PAGE_SIZE: number = 30;

/** 带勾选框确认弹窗结果 */
interface CheckConfirmResult {
  /** 是否点击确定 */
  confirmed: boolean;
  /** 勾选框最终状态 */
  checked: boolean;
}

/**
 * 下载中心页面临时控制器（对齐 Flutter AppDownloadCenterController）：
 * - 已完成记录分页加载、下拉刷新
 * - 监听 DownloadService 文件完成事件（600ms 防抖自动刷新）
 * - 单条删除 / 全部清理（均带「同时删除已下载的文件」勾选框）
 *
 * 非单例：随页面创建、随页面销毁并注销监听。
 */
@ObservedV2
export class DownloadCenterController {
  @Trace downloadedFiles: DownloadedFileEntry[] = [];
  @Trace isRefreshingFiles: boolean = false;
  @Trace isLoadingMore: boolean = false;
  @Trace hasMore: boolean = true;

  private nextOffset: number = 0;
  private history: DownloadHistoryStorage = new DownloadHistoryStorage();
  private service: DownloadService = DownloadService.getInstance();
  private debounceTimer: number = -1;
  private closed: boolean = false;

  constructor() {
    // 服务完成文件下载后，防抖刷新已完成列表（对齐 Flutter 600ms Worker）
    this.service.setCompletionListener((): void => {
      this.scheduleRefresh();
    });
    void this.loadFirstPage();
  }

  /** 页面销毁：注销监听并清理定时器 */
  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    this.service.setCompletionListener(undefined);
    if (this.debounceTimer >= 0) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
  }

  private scheduleRefresh(): void {
    if (this.debounceTimer >= 0) {
      clearTimeout(this.debounceTimer);
    }
    this.debounceTimer = setTimeout((): void => {
      this.debounceTimer = -1;
      void this.loadFirstPage();
    }, 600);
  }

  // ==================== 分页加载 ====================

  /** 下拉刷新 / 首次进入 */
  async loadFirstPage(): Promise<void> {
    if (this.isRefreshingFiles) {
      return;
    }
    this.isRefreshingFiles = true;
    try {
      const rows: DownloadedFileEntry[] = await this.history.page(0, PAGE_SIZE);
      const entries: DownloadedFileEntry[] = [];
      for (const r of rows) {
        entries.push(await this.toEntry(r));
      }
      this.downloadedFiles = entries;
      this.nextOffset = entries.length;
      this.hasMore = rows.length >= PAGE_SIZE;
    } catch (e) {
      console.error('[DownloadCenter] 首页加载失败: ' + `${e}`);
    } finally {
      this.isRefreshingFiles = false;
    }
  }

  /** 滚动接近底部时加载更多 */
  async loadMore(): Promise<void> {
    if (!this.hasMore || this.isLoadingMore || this.isRefreshingFiles) {
      return;
    }
    this.isLoadingMore = true;
    try {
      const rows: DownloadedFileEntry[] = await this.history.page(this.nextOffset, PAGE_SIZE);
      if (rows.length === 0) {
        this.hasMore = false;
        return;
      }
      const more: DownloadedFileEntry[] = [];
      for (const r of rows) {
        more.push(await this.toEntry(r));
      }
      this.downloadedFiles = this.downloadedFiles.concat(more);
      this.nextOffset += more.length;
      this.hasMore = rows.length >= PAGE_SIZE;
    } catch (e) {
      console.error('[DownloadCenter] 加载更多失败: ' + `${e}`);
    } finally {
      this.isLoadingMore = false;
    }
  }

  /** 数据库行 → UI 条目（检查本地文件是否仍存在） */
  private async toEntry(row: DownloadedFileEntry): Promise<DownloadedFileEntry> {
    const e: DownloadedFileEntry = new DownloadedFileEntry();
    e.id = row.id;
    e.path = row.path;
    e.name = row.name;
    e.remotePath = row.remotePath;
    e.size = row.size;
    e.completedTimeMs = row.completedTimeMs;
    e.fileMissing = !DownloadCenterController.pathExists(e.path);
    return e;
  }

  private static pathExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_e) {
      return false;
    }
  }

  // ==================== 删除 / 清理 ====================

  /** 删除单条记录（勾选时同时删除本地文件，对齐 Flutter promptDeleteEntry） */
  async promptDeleteEntry(entry: DownloadedFileEntry): Promise<void> {
    const r: CheckConfirmResult | undefined = await showCheckConfirmDialog(
      L10n.t('confirm_delete', '确定删除吗？'),
      entry.name,
      L10n.t('delete_downloaded_local_file', '同时删除已下载的文件'),
      true);
    if (!r || !r.confirmed) {
      return;
    }
    if (r.checked) {
      DownloadCenterController.deleteLocalFile(entry.path);
    }
    await this.history.deleteById(entry.id);
    const remain: DownloadedFileEntry[] =
      this.downloadedFiles.filter((e: DownloadedFileEntry): boolean => e.id !== entry.id);
    this.downloadedFiles = remain;
  }

  /** 顶部「清理」：有活跃任务时拦截，否则弹窗确认清空（对齐 Flutter promptClearAllHistory） */
  async promptClearAllHistory(): Promise<void> {
    if (this.service.hasActiveTasks()) {
      ToastUtil.show(L10n.t('download_center_stop_tasks_first',
        '有文件正在下载，请先停止下载任务'));
      return;
    }
    const r: CheckConfirmResult | undefined = await showCheckConfirmDialog(
      L10n.t('download_history_clear_title', '清理下载记录'),
      L10n.t('download_history_clear_message',
        '将清空全部下载记录；下载文件均保存在应用私有下载目录中，勾选后可一并删除。'),
      L10n.t('delete_downloaded_local_file', '同时删除已下载的文件'),
      true);
    if (!r || !r.confirmed) {
      return;
    }
    if (r.checked) {
      const paths: string[] = await this.history.allLocalPaths();
      for (const p of paths) {
        DownloadCenterController.deleteLocalFile(p);
      }
    }
    await this.history.clearAllRecords();
    this.downloadedFiles = [];
    this.hasMore = false;
    this.nextOffset = 0;
  }

  /** 删除本地文件（仅文件；不存在/失败均忽略） */
  private static deleteLocalFile(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (_e) {
      // 忽略删除失败
    }
  }
}

// ============================================================
// 带勾选框的确认弹窗（自包含：ComponentContent + promptAction）
// ============================================================

/** 弹窗参数（@Trace 勾选状态，切换即时刷新） */
@ObservedV2
class CheckConfirmParams {
  @Trace checked: boolean = true;
  title: string = '';
  message: string = '';
  checkLabel: string = '';
  onResult: (confirmed: boolean, checked: boolean) => void =
    (_c: boolean, _v: boolean): void => {
    };
}

@Builder
function CheckConfirmContent(p: CheckConfirmParams) {
  Column({ space: 14 }) {
    // 标题
    Text(p.title)
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.current().onSurface)
      .width('100%')
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })

    // 正文（过长可滚动）
    Scroll() {
      Text(p.message)
        .fontSize(14)
        .fontColor(AppTheme.current().subText)
        .width('100%')
    }
    .width('100%')
    .constraintSize({ maxHeight: 280 })
    .align(Alignment.TopStart)

    // 勾选行
    Row({ space: 8 }) {
      Checkbox({ name: 'dl_check', group: 'dl_check_group' })
        .select(p.checked)
        .selectedColor(AppTheme.current().primary)
        .width(20)
        .height(20)
        .onChange((value: boolean): void => {
          p.checked = value;
        })
      Text(p.checkLabel)
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .layoutWeight(1)
    }
    .width('100%')

    Divider().color(AppTheme.current().divider)

    // 操作按钮
    Row() {
      Text(L10n.cancel)
        .fontSize(15)
        .fontColor(AppTheme.current().subText)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .padding({ top: 8, bottom: 8 })
        .onClick((): void => {
          p.onResult(false, p.checked);
        })
      Divider()
        .vertical(true)
        .strokeWidth(1)
        .color(AppTheme.current().divider)
      Text(L10n.ok)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().primary)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .padding({ top: 8, bottom: 8 })
        .onClick((): void => {
          p.onResult(true, p.checked);
        })
    }
    .width('100%')
    .height(40)
  }
  .width('82%')
  .constraintSize({ maxWidth: 340 })
  .padding(20)
  .backgroundColor(AppTheme.current().surfaceBg)
  .borderRadius(16)
}

/**
 * 显示带勾选框的确认弹窗。
 *
 * @param title      标题
 * @param message    正文
 * @param checkLabel 勾选框文案
 * @param initialChecked 勾选框初始状态
 * @returns 确定返回 {confirmed:true, checked}；取消/点遮罩返回 undefined
 */
function showCheckConfirmDialog(title: string, message: string, checkLabel: string,
  initialChecked: boolean): Promise<CheckConfirmResult | undefined> {
  return new Promise<CheckConfirmResult | undefined>(
    (resolve: (v: CheckConfirmResult | undefined) => void): void => {
      const ui = WindowStore.getMainWindow()?.getUIContext();
      if (!ui) {
        resolve(undefined);
        return;
      }

      const p: CheckConfirmParams = new CheckConfirmParams();
      p.title = title;
      p.message = message;
      p.checkLabel = checkLabel;
      p.checked = initialChecked;

      let done: boolean = false;
      const finish = (v: CheckConfirmResult | undefined): void => {
        if (!done) {
          done = true;
          resolve(v);
        }
      };

      const content: ComponentContent<CheckConfirmParams> =
        new ComponentContent<CheckConfirmParams>(ui, wrapBuilder(CheckConfirmContent), p);
      p.onResult = (confirmed: boolean, checked: boolean): void => {
        finish({ confirmed, checked });
        try {
          ui.getPromptAction().closeCustomDialog(content);
        } catch (_e) {
          // 弹窗可能已关闭
        }
      };

      const options: promptAction.BaseDialogOptions = {
        isModal: true,
        autoCancel: true,
        alignment: DialogAlignment.Center,
        onWillDismiss: (action: DismissDialogAction): void => {
          action.dismiss();
          finish(undefined);
        }
      };
      ui.getPromptAction().openCustomDialog(content, options).catch((): void => {
        finish(undefined);
      });
    });
}
