import { window } from '@kit.ArkUI';
import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { PageScaffold } from '../../common/PageScaffold';
import { BorderedIconButton } from '../../common/components/BorderedIconButton';
import { EmptyState } from '../../common/components/EmptyState';
import { DownloadTaskItem } from '../models/DownloadModels';
import { TransferStatus } from '../models/TransferModels';
import { DownloadService } from '../services/DownloadService';
import { DownloadCenterController } from '../controllers/DownloadCenterController';
import { DownloadCenterTaskCard } from './DownloadCenterTaskCard';
import { DownloadCenterDownloadedTab } from './DownloadCenterDownloadedTab';

/** 页面参数（暂无外部入参，保留以统一 pageMap 传参模式） */
export class DownloadCenterParam {
}

/**
 * 下载中心（对齐 Flutter app_download_center_view.dart）：
 * 顶栏（清理历史 + 刷新）+ 下载中/已失败/已完成三个 Tab + 屏幕常亮。
 */
@ComponentV2
export struct DownloadCenterPage {
  @Param param: DownloadCenterParam = new DownloadCenterParam();
  @Param pushPage: (name: string, param?: object) => void = (_n: string, _p?: object): void => {
  };
  @Param popPage: () => void = (): void => {
  };
  @Local currentTab: number = 0;

  private service: DownloadService = DownloadService.getInstance();
  private centerCtrl: DownloadCenterController = new DownloadCenterController();

  aboutToAppear(): void {
    this.keepScreenOn(true);
  }

  aboutToDisappear(): void {
    this.keepScreenOn(false);
    this.centerCtrl.close();
  }

  /** 对齐 Flutter WakelockPlus：下载页面保持屏幕常亮 */
  private keepScreenOn(enable: boolean): void {
    try {
      window.getLastWindow(getContext(this)).then((w: window.Window): void => {
        w.setWindowKeepScreenOn(enable);
      });
    } catch (_e) {
      // 忽略窗口获取失败
    }
  }

  private palette() {
    return AppTheme.current();
  }

  /** 下载中/等待/暂停任务（createdTime 倒序，对齐 Flutter） */
  private get activeItems(): DownloadTaskItem[] {
    const list: DownloadTaskItem[] = this.service.tasks.filter((it: DownloadTaskItem): boolean =>
      it.status === TransferStatus.PENDING ||
      it.status === TransferStatus.UPLOADING ||
      it.status === TransferStatus.PAUSED);
    list.sort((a: DownloadTaskItem, b: DownloadTaskItem): number => b.createdTime - a.createdTime);
    return list;
  }

  /** 已失败任务（createdTime 倒序，对齐 Flutter） */
  private get failedItems(): DownloadTaskItem[] {
    const list: DownloadTaskItem[] = this.service.tasks.filter((it: DownloadTaskItem): boolean =>
      it.status === TransferStatus.ERROR);
    list.sort((a: DownloadTaskItem, b: DownloadTaskItem): number => b.createdTime - a.createdTime);
    return list;
  }

  build() {
    PageScaffold({
      title: L10n.t('home_download_center', '下载中心'),
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.HeaderActions()
      },
      content: (): void => {
        this.PageContent()
      }
    })
  }

  // ==================== 顶栏操作 ====================

  @Builder
  HeaderActions() {
    BorderedIconButton({
      icon: $r('sys.symbol.trash_circle'),
      iconColor: this.palette().onSurface,
      isEnabled: !this.centerCtrl.isRefreshingFiles,
      onTap: (): void => {
        void this.centerCtrl.promptClearAllHistory();
      }
    })
    BorderedIconButton({
      icon: $r('sys.symbol.arrow_clockwise'),
      iconColor: this.palette().onSurface,
      isEnabled: !this.centerCtrl.isRefreshingFiles,
      onTap: (): void => {
        void this.centerCtrl.loadFirstPage();
      }
    })
  }

  // ==================== Tab 标签 ====================

  @Builder
  TabLabel(label: string, index: number) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(15)
        .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === index ? this.palette().primary : this.palette().subText)
      Divider()
        .strokeWidth(2)
        .color(this.currentTab === index ? this.palette().primary : '#00000000')
        .width(36)
    }
    .constraintSize({ minWidth: 72 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .height('100%')
  }

  // ==================== 内容区 ====================

  @Builder
  PageContent() {
    Column() {
      Tabs({ index: this.currentTab, barPosition: BarPosition.Start }) {
        TabContent() {
          this.ActiveTab()
        }
        .tabBar(this.TabLabel(L10n.t('task_downloading', '下载中'), 0))

        TabContent() {
          this.FailedTab()
        }
        .tabBar(this.TabLabel(L10n.t('task_failed', '已失败'), 1))

        TabContent() {
          DownloadCenterDownloadedTab({ ctrl: this.centerCtrl })
        }
        .tabBar(this.TabLabel(L10n.t('task_completed', '已完成'), 2))
      }
      .barMode(BarMode.Fixed)
      .onChange((index: number): void => {
        this.currentTab = index;
      })
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  /** 下载中 Tab */
  @Builder
  ActiveTab() {
    if (this.activeItems.length === 0) {
      Column() {
        EmptyState({ message: L10n.t('task_empty', '暂无任务') })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 10 }) {
        ForEach(this.activeItems, (item: DownloadTaskItem): void => {
          ListItem() {
            DownloadCenterTaskCard({ task: item })
          }
        }, (item: DownloadTaskItem): string => item.id)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .padding(12)
    }
  }

  /** 已失败 Tab */
  @Builder
  FailedTab() {
    if (this.failedItems.length === 0) {
      Column() {
        EmptyState({ message: L10n.t('task_empty', '暂无任务') })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 10 }) {
        ForEach(this.failedItems, (item: DownloadTaskItem): void => {
          ListItem() {
            DownloadCenterTaskCard({ task: item })
          }
        }, (item: DownloadTaskItem): string => item.id)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .padding(12)
    }
  }
}
