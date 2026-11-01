import { window } from '@kit.ArkUI';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { EmptyState } from '../../../common/components/EmptyState';
import { DownloadTaskItem } from '../models/DownloadModels';
import { TransferStatus } from '../models/TransferModels';
import { DownloadService } from '../services/DownloadService';
import { DownloadCenterController } from '../controllers/DownloadCenterController';
import { DownloadCenterTaskCard } from './DownloadCenterTaskCard';
import { DownloadCenterDownloadedTab } from './DownloadCenterDownloadedTab';

/** 页面参数（暂无外部入参，保留以统一 pageMap 传参模式） */
export class DownloadCenterParam {
}

/** 任务列表筛选维度（对应「全部」「下载中」「已失败」三个 Tab） */
export enum DownloadTaskFilter {
  ALL = 0,
  ACTIVE = 1,
  FAILED = 2
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
      // 顶栏为深色 appBar 底色，边框与图标统一使用浅色前景
      strokeColor: AppTheme.withAlpha(this.palette().appBarFg, 0.35),
      iconColor: this.palette().appBarFg,
      isEnabled: !this.centerCtrl.isRefreshingFiles,
      onTap: (): void => {
        void this.centerCtrl.promptClearAllHistory();
      }
    })
    BorderedIconButton({
      icon: $r('sys.symbol.arrow_clockwise'),
      strokeColor: AppTheme.withAlpha(this.palette().appBarFg, 0.35),
      iconColor: this.palette().appBarFg,
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
          DownloadCenterTaskTab({ filter: DownloadTaskFilter.ALL })
        }
        .tabBar(this.TabLabel(L10n.t('task_all', '全部'), 0))

        TabContent() {
          DownloadCenterTaskTab({ filter: DownloadTaskFilter.ACTIVE })
        }
        .tabBar(this.TabLabel(L10n.t('task_downloading', '下载中'), 1))

        TabContent() {
          DownloadCenterTaskTab({ filter: DownloadTaskFilter.FAILED })
        }
        .tabBar(this.TabLabel(L10n.t('task_failed', '已失败'), 2))

        TabContent() {
          DownloadCenterDownloadedTab({ ctrl: this.centerCtrl })
        }
        .tabBar(this.TabLabel(L10n.t('task_completed', '已完成'), 3))
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

}

/**
 * 下载任务列表（「全部」「下载中」「已失败」三个 Tab 复用）。
 *
 * 必须独立成组件：Tabs 内已构建的 TabContent 子树不会随父页重建而重新求值，
 * 若在页面 @Builder 里按值传入任务数组，列表会停留在首次构建时的快照
 * （进入页面后新增/清理任务都不刷新）。组件内部直接读取 @Trace 的
 * DownloadService.tasks，由该组件自身订阅变化。
 */
@ComponentV2
export struct DownloadCenterTaskTab {
  @Param filter: number = DownloadTaskFilter.ALL;
  /** 单例控制器；用 @Local 声明才能真正订阅其 @Trace 属性（普通成员不会建立依赖） */
  @Local service: DownloadService = DownloadService.getInstance();

  /** 按筛选维度取任务（createdTime 倒序） */
  private items(): DownloadTaskItem[] {
    const all: DownloadTaskItem[] = this.service.tasks;
    let list: DownloadTaskItem[] = [];
    if (this.filter === DownloadTaskFilter.ACTIVE) {
      list = all.filter((it: DownloadTaskItem): boolean =>
        it.status === TransferStatus.PENDING ||
        it.status === TransferStatus.UPLOADING ||
        it.status === TransferStatus.PAUSED);
    } else if (this.filter === DownloadTaskFilter.FAILED) {
      list = all.filter((it: DownloadTaskItem): boolean => it.status === TransferStatus.ERROR);
    } else {
      list = all.slice();
    }
    list.sort((a: DownloadTaskItem, b: DownloadTaskItem): number => b.createdTime - a.createdTime);
    return list;
  }

  build() {
    Column() {
      if (this.items().length === 0) {
        EmptyState({ message: L10n.t('task_empty', '暂无任务') })
      } else {
        List({ space: 10 }) {
          ForEach(this.items(), (item: DownloadTaskItem): void => {
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
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
