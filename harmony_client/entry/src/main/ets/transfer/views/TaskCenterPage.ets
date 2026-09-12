import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { EmptyState } from '../../common/components/EmptyState';
import { SearchInputBar } from '../../common/components/SearchInputBar';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../common/SheetUtil';
import { PageScaffold } from '../../common/PageScaffold';
import { FileLogController } from '../controllers/FileLogController';
import { FileLogItem } from '../../modules/user/components/FileLogItem';
import { FileOperationLog } from '../../modules/user/models/UserModels';

/** 任务中心页面参数（对齐 Flutter AppTaskCenterPage 无参构造） */
export class TaskCenterPageParam {
}

/**
 * 任务中心页（对齐 Flutter AppTaskCenterPage）：
 * 管理员显示文件操作日志（FileLogPage：状态/类型筛选 + 搜索 + 清除 + 分页列表，3s 自动刷新）；
 * 非管理员显示"暂无任务"占位。
 */
@ComponentV2
export struct TaskCenterPage {
  @Param param: TaskCenterPageParam = new TaskCenterPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: FileLogController = new FileLogController();
  /** 搜索框文本（清除按钮响应式依赖） */
  @Local searchText: string = '';
  @Local refreshing: boolean = false;

  private isAdmin(): boolean {
    return CurrentUserStore.getInstance().isAdmin;
  }

  aboutToAppear(): void {
    if (this.isAdmin()) {
      this.ctrl.onInit();
    }
  }

  aboutToDisappear(): void {
    this.ctrl.close();
  }

  private pageTitle(): string {
    return this.isAdmin() ? L10n.t('file_operation', '文件操作')
      : L10n.t('app_task_center', '任务中心');
  }

  build() {
    PageScaffold({
      title: this.pageTitle(),
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.PageContent()
      }
    })
  }

  @Builder
  PageContent() {
    if (!this.isAdmin()) {
      // 非管理员占位（对齐 Flutter CustomNoData('task_empty')）
      Column() {
        EmptyState({ message: L10n.t('task_empty', '暂无任务') })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        this.FilterBar()
        Divider()
          .color(AppTheme.current().divider)
        this.LogList()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppTheme.current().pageBg)
    }
  }

  /** 顶部操作栏：状态筛选 + 类型筛选 + 搜索 + 清除（对齐 FileLogPage 顶栏顺序） */
  @Builder
  FilterBar() {
    Row({ space: 8 }) {
      // 状态筛选 chip（直接读取 @Trace，切换后文本即时刷新）
      Row({ space: 4 }) {
        Text(L10n.t(this.ctrl.selectedStatus, this.ctrl.selectedStatus))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(16)
          .fontColor([AppTheme.current().subText])
      }
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .borderRadius(10)
      .onClick((): void => {
        this.showStatusSheet();
      })
      // 类型筛选 chip
      Row({ space: 4 }) {
        Text(L10n.t(this.ctrl.selectedType, this.ctrl.selectedType))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(16)
          .fontColor([AppTheme.current().subText])
      }
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .borderRadius(10)
      .onClick((): void => {
        this.showTypeSheet();
      })
      SearchInputBar({
        hintText: L10n.t('search', '搜索'),
        text: this.searchText,
        onChanged: (v: string): void => {
          this.searchText = v;
          this.ctrl.onSearch(v);
        },
        onClear: (): void => {
          this.searchText = '';
          this.ctrl.onSearch('');
        }
      })
        .layoutWeight(1)
      // 清除按钮（对齐 Flutter Icons.delete_sweep + 清除菜单）
      Column() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([AppTheme.current().onSurface])
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width(36)
      .height(36)
      .borderRadius(18)
      .border({ width: 1, color: AppTheme.current().divider })
      .onClick((): void => {
        this.showClearSheet();
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  /** 日志列表：下拉刷新 + 触底加载更多（对齐 FileLogPage ListView） */
  @Builder
  LogList() {
    Refresh({ refreshing: this.refreshing }) {
      if (this.ctrl.isLoading && this.ctrl.logs.length === 0) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(AppTheme.current().primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.ctrl.logs.length === 0) {
        Column() {
          EmptyState({ message: L10n.t('no_data', '暂无数据') })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.ctrl.logs, (log: FileOperationLog): void => {
            ListItem() {
              FileLogItem({
                log: log,
                onCancel: (l: FileOperationLog): void => {
                  void this.ctrl.cancelTask(l);
                }
              })
            }
          }, (log: FileOperationLog): string => `${log.id}`)
          ListItem() {
            // 加载更多脚标（对齐 Flutter 底部 loading）
            if (this.ctrl.isLoadMore) {
              Column() {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color(AppTheme.current().primary)
              }
              .width('100%')
              .padding(16)
              .justifyContent(FlexAlign.Center)
            } else {
              Column()
                .width('100%')
                .height(16)
            }
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .onReachEnd((): void => {
          this.ctrl.onLoadMore();
        })
        .cachedCount(6)
      }
    }
    .onRefreshing((): void => {
      this.refreshing = true;
      this.ctrl.onRefresh();
      // 简单复位下拉状态（数据刷新由 3s 轮询/防抖驱动）
      setTimeout((): void => {
        this.refreshing = false;
      }, 600);
    })
    .width('100%')
    .layoutWeight(1)
  }

  /** 状态筛选弹层 */
  private showStatusSheet(): void {
    const p = new FileLogSheetParams();
    p.ctrl = this.ctrl;
    p.kind = 'status';
    SheetUtil.present(p, wrapBuilder(FileLogStatusSheetContent));
  }

  /** 类型筛选弹层 */
  private showTypeSheet(): void {
    const p = new FileLogSheetParams();
    p.ctrl = this.ctrl;
    p.kind = 'type';
    SheetUtil.present(p, wrapBuilder(FileLogTypeSheetContent));
  }

  /** 清除日志弹层（对齐 Flutter PopupMenu 四项） */
  private showClearSheet(): void {
    const p = new FileLogSheetParams();
    p.ctrl = this.ctrl;
    p.kind = 'clear';
    SheetUtil.present(p, wrapBuilder(FileLogClearSheetContent));
  }
}

// ==================== 筛选/清除弹层 ====================

class FileLogSheetParams extends SheetParamsBase {
  ctrl: FileLogController = new FileLogController();
  kind: string = 'status';
}

@Builder
function FileLogStatusSheetContent(p: FileLogSheetParams) {
  Column() {
    SheetHandle()
    ForEach(FileLogController.STATUS_OPTIONS, (op: string): void => {
      SheetListItem({
        showIcon: false,
        title: L10n.t(op, op),
        showCheck: true,
        checked: p.ctrl.selectedStatus === op,
        onSelect: (): void => {
          p.ctrl.onStatusChanged(op);
          p.close();
        }
      })
    }, (op: string): string => op)
  }
  .padding({ bottom: 28 })
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

@Builder
function FileLogTypeSheetContent(p: FileLogSheetParams) {
  Column() {
    SheetHandle()
    ForEach(FileLogController.TYPE_OPTIONS, (op: string): void => {
      SheetListItem({
        showIcon: false,
        title: L10n.t(op, op),
        showCheck: true,
        checked: p.ctrl.selectedType === op,
        onSelect: (): void => {
          p.ctrl.onTypeChanged(op);
          p.close();
        }
      })
    }, (op: string): string => op)
  }
  .padding({ bottom: 28 })
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

@Builder
function FileLogClearSheetContent(p: FileLogSheetParams) {
  Column() {
    SheetHandle()
    SheetListItem({
      showIcon: false,
      title: L10n.t('task_clear_completed', '清除已完成'),
      onSelect: (): void => {
        p.close();
        void p.ctrl.clearLogs('completed');
      }
    })
    SheetListItem({
      showIcon: false,
      title: L10n.t('task_clear_error', '清除错误'),
      onSelect: (): void => {
        p.close();
        void p.ctrl.clearLogs('error');
      }
    })
    SheetListItem({
      showIcon: false,
      title: L10n.t('task_clear_waiting', '清除等待中'),
      onSelect: (): void => {
        p.close();
        void p.ctrl.clearLogs('waiting');
      }
    })
    SheetListItem({
      showIcon: false,
      title: L10n.t('task_clear_all', '清除全部'),
      onSelect: (): void => {
        p.close();
        void p.ctrl.clearLogs('all');
      }
    })
  }
  .padding({ bottom: 28 })
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}
