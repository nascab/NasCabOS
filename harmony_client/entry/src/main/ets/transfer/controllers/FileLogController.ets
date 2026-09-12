import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { FileOperationLog } from '../../modules/user/models/UserModels';
import { FileLogService } from '../services/FileLogService';

/**
 * 文件操作日志控制器（对齐 Flutter FileLogController）：
 * 状态/类型筛选 + 关键字搜索（500ms 防抖）+ 分页加载 + 3s 自动刷新（仅"进行中"）+ 清除/取消。
 */
@ObservedV2
export class FileLogController {
  @Trace logs: FileOperationLog[] = [];
  @Trace isLoading: boolean = false;
  @Trace isLoadMore: boolean = false;
  @Trace total: number = 0;
  /** 筛选：processing/waiting/completed/failed（对齐 statusOptions） */
  @Trace selectedStatus: string = 'processing';
  /** 筛选：all/copy/move/delete/rename（对齐 typeOptions） */
  @Trace selectedType: string = 'all';
  @Trace searchKeyword: string = '';

  private currentPage: number = 1;
  private readonly pageSize: number = 20;
  private searchTimer: number = -1;
  private refreshTimer: number = -1;
  private static readonly SEARCH_DEBOUNCE_MS: number = 500;
  private static readonly REFRESH_INTERVAL_MS: number = 3000;

  /** 状态筛选选项（key 亦为 L10n key） */
  static readonly STATUS_OPTIONS: string[] = ['processing', 'waiting', 'completed', 'failed'];
  /** 类型筛选选项（key 亦为 L10n key） */
  static readonly TYPE_OPTIONS: string[] = ['all', 'copy', 'move', 'delete', 'rename'];

  onInit(): void {
    void this.loadData(true);
    this.startAutoRefresh();
  }

  close(): void {
    this.stopAutoRefresh();
    this.clearSearchTimer();
  }

  /** 状态筛选 → 服务端 stateList（对齐 _getCurrentStateList） */
  private stateListFor(status: string): string[] {
    switch (status) {
      case 'processing':
        return ['PROCESSING'];
      case 'waiting':
        return ['WAIT'];
      case 'completed':
        return ['SUCCESS'];
      case 'failed':
        return ['ERROR', 'CANCELLED', 'INTERRUPTED'];
      default:
        return [];
    }
  }

  /** 类型筛选 → 服务端 types（all → 不传，对齐 _getCurrentTypes） */
  private typesFor(type: string): string[] | undefined {
    if (type === 'all') {
      return undefined;
    }
    return [type];
  }

  private async loadData(refresh: boolean): Promise<void> {
    if (refresh) {
      this.currentPage = 1;
      this.isLoading = true;
    } else {
      this.currentPage++;
      this.isLoadMore = true;
    }
    try {
      const kw = this.searchKeyword.trim();
      const data = await FileLogService.getFileLogs(
        this.typesFor(this.selectedType), this.currentPage, this.pageSize,
        this.stateListFor(this.selectedStatus), kw.length > 0 ? kw : undefined);
      if (data !== undefined) {
        this.total = data.total;
        this.logs = refresh ? data.list : this.logs.concat(data.list);
      }
    } catch (_e) {
      // 网络异常静默（对齐 Flutter catch 空处理）
    } finally {
      if (refresh) {
        this.isLoading = false;
      } else {
        this.isLoadMore = false;
      }
    }
  }

  /** 下拉刷新 */
  onRefresh(): void {
    void this.loadData(true);
  }

  /** 触底加载更多（对齐 _onScroll 触发条件：未在加载且还有更多） */
  onLoadMore(): void {
    if (this.isLoadMore || this.isLoading || this.logs.length >= this.total) {
      return;
    }
    void this.loadData(false);
  }

  /** 搜索（立即记录关键字，500ms 防抖后刷新） */
  onSearch(value: string): void {
    this.searchKeyword = value;
    this.clearSearchTimer();
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      void this.loadData(true);
    }, FileLogController.SEARCH_DEBOUNCE_MS);
  }

  onStatusChanged(status: string): void {
    if (status === this.selectedStatus) {
      return;
    }
    this.selectedStatus = status;
    void this.loadData(true);
    // 仅"进行中"开启 3s 自动刷新（对齐 onStatusChanged）
    if (status === 'processing') {
      this.startAutoRefresh();
    } else {
      this.stopAutoRefresh();
    }
  }

  onTypeChanged(type: string): void {
    if (type === this.selectedType) {
      return;
    }
    this.selectedType = type;
    void this.loadData(true);
  }

  /** 清除日志（对齐 clearLogs：completed/error/waiting 按状态清除，all 清除全部） */
  async clearLogs(type: string): Promise<void> {
    let stateList: string[] | undefined;
    if (type === 'completed') {
      stateList = ['SUCCESS'];
    } else if (type === 'error') {
      stateList = ['ERROR', 'CANCELLED', 'INTERRUPTED'];
    } else if (type === 'waiting') {
      stateList = ['WAIT'];
    }
    const ok = await FileLogService.clearLogs(stateList);
    if (ok) {
      ToastUtil.show(L10n.t('file_logs_cleared', '操作记录已清除'));
      this.onRefresh();
    } else {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    }
  }

  /** 取消进行中的操作（对齐 cancelTask） */
  async cancelTask(log: FileOperationLog): Promise<void> {
    const ok = await FileLogService.cancelFileOperation(log.id);
    if (ok) {
      this.onRefresh();
    } else {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    }
  }

  /** 仅"进行中"状态下 3s 轮询刷新（对齐 _startAutoRefresh） */
  private startAutoRefresh(): void {
    this.stopAutoRefresh();
    if (this.selectedStatus !== 'processing') {
      return;
    }
    this.refreshTimer = setInterval((): void => {
      void this.loadData(true);
    }, FileLogController.REFRESH_INTERVAL_MS);
  }

  private stopAutoRefresh(): void {
    if (this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  private clearSearchTimer(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
  }
}
