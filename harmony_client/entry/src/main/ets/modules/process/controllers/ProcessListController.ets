import { L10n } from '../../../core/localization/L10n';
import { WorkerProcessItem, PROCESS_UNKNOWN_NAME_KEY } from '../models/ProcessModels';
import { ProcessApiService } from '../services/ProcessApiService';

/** 未知进程显示名（对齐 Flutter _formatProcessDisplayName） */
export function formatProcessDisplayName(item: WorkerProcessItem): string {
  const base = L10n.t(item.nameKey);
  if (item.nameKey === PROCESS_UNKNOWN_NAME_KEY) {
    const path = item.workerPath.trim();
    const role = item.role.trim();
    const raw = path.length > 0 ? path : role;
    if (raw.length > 0) {
      return `${base}（${raw}）`;
    }
  }
  return base;
}

/**
 * 进程列表控制器（对齐 Flutter ProcessListController；@ObservedV2 + @Trace 驱动 V2 刷新）。
 * 生命周期由页面负责：aboutToAppear 调 onInit()，aboutToDisappear 调 onClose()（对应 Flutter
 * State.initState Get.put / dispose Get.delete，页面销毁后无残留轮询）。
 */
@ObservedV2
export class ProcessListController {
  @Trace workers: WorkerProcessItem[] = [];
  @Trace isInitialLoading: boolean = true;
  @Trace loadError: string = '';

  private closed: boolean = false;
  /** 轮询间隔定时器（onClose 时清除，立即结束等待） */
  private pollTimer: number = -1;

  onInit(): void {
    void this.pollLoop();
  }

  onClose(): void {
    this.closed = true;
    if (this.pollTimer >= 0) {
      clearTimeout(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  /** 每 3s 轮询一次（对齐 _pollLoop） */
  private async pollLoop(): Promise<void> {
    while (!this.closed) {
      await this.fetchOnce();
      if (this.closed) {
        break;
      }
      await this.sleepInterval();
    }
  }

  private sleepInterval(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      this.pollTimer = setTimeout((): void => {
        this.pollTimer = -1;
        resolve();
      }, 3000);
    });
  }

  private async fetchOnce(): Promise<void> {
    const res = await ProcessApiService.fetchWorkerProcessList();
    if (this.closed) {
      return;
    }
    if (!res.success) {
      this.loadError = res.message ?? '';
      this.isInitialLoading = false;
      return;
    }
    this.loadError = '';
    this.workers = res.data ?? [];
    this.isInitialLoading = false;
  }
}
