import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { NavUtil } from '../../../common/NavUtil';
import { WorkerProcessItem } from '../models/ProcessModels';
import { ProcessListController, formatProcessDisplayName } from '../controllers/ProcessListController';
import { ProcessListPageParam } from '../router/ProcessRoutes';

/**
 * 进程列表页（对齐 Flutter AppProcessListPage + ProcessListView 移动端分支）：
 * 标题栏 + 右对齐统计头（标题/数量/错误横幅）+ 进程卡片列表（3s 自动轮询）。
 */
@ComponentV2
export struct ProcessListPage {
  @Param param: ProcessListPageParam = new ProcessListPageParam();
  ctrl: ProcessListController = new ProcessListController();

  aboutToAppear(): void {
    this.ctrl.onInit();
  }

  aboutToDisappear(): void {
    this.ctrl.onClose();
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private countSummaryText(): string {
    return L10n.t('process.countSummary', '共 @count 个进程',
      L10n.paramsOf('count', `${this.ctrl.workers.length}`));
  }

  build() {
    PageScaffold({
      title: L10n.t('app_process', '进程'),
      showBack: true,
      onBack: (): void => {
        NavUtil.pop();
      },
      content: (): void => {
        this.PageContent()
      }
    })
  }

  @Builder
  PageContent() {
    if (this.ctrl.isInitialLoading) {
      Column() {
        LoadingProgress()
          .width(42)
          .height(42)
          .color(this.palette().primary)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        this.HeaderBlock()
        if (this.ctrl.workers.length === 0) {
          this.EmptyBlock()
        } else {
          this.ListBlock()
        }
      }
      .width('100%')
      .height('100%')
    }
  }

  /** 头部：右对齐标题 + 数量统计 + 错误横幅（对齐 _ProcessListLoadedView 头部） */
  @Builder
  HeaderBlock() {
    Column() {
      Text(L10n.t('process.title', '当前进程'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().onSurface)
        .width('100%')
        .textAlign(TextAlign.End)
      Text(this.countSummaryText())
        .fontSize(12)
        .fontColor(this.palette().subText)
        .width('100%')
        .textAlign(TextAlign.End)
        .margin({ top: 6 })
      if (this.ctrl.loadError.length > 0) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.icloud_slash'))
            .fontSize(18)
            .fontColor([this.palette().error])
          Text(this.ctrl.loadError)
            .fontSize(12)
            .fontColor(this.palette().error)
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(10)
        .backgroundColor(AppTheme.withAlpha(this.palette().error, 0.35))
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 16, bottom: 8 })
  }

  /** 空状态（对齐 workers.isEmpty 分支：列表图标 + process.empty 文案） */
  @Builder
  EmptyBlock() {
    Column() {
      SymbolGlyph($r('sys.symbol.list_bullet'))
        .fontSize(48)
        .fontColor([AppTheme.withAlpha(this.palette().onSurface, 0.45)])
      Text(L10n.t('process.empty', '暂无运行中的进程'))
        .fontSize(16)
        .fontColor(this.palette().subText)
        .textAlign(TextAlign.Center)
        .margin({ top: 12 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  /** 进程卡片列表（对齐 CustomScrollView + _ProcessCard） */
  @Builder
  ListBlock() {
    List() {
      ForEach(this.ctrl.workers, (item: WorkerProcessItem) => {
        ListItem() {
          this.ProcessCard(item)
        }
        .margin({ bottom: 2 })
      }, (item: WorkerProcessItem) => `${item.pid}_${item.startedAt}_${item.workerPath}`)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  /** 进程卡片：名称 + 用途说明（对齐 _ProcessCard） */
  @Builder
  ProcessCard(item: WorkerProcessItem) {
    Column() {
      Text(formatProcessDisplayName(item))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .lineHeight(18)
        .fontColor(this.palette().onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(L10n.t(item.purposeKey))
        .fontSize(12)
        .lineHeight(16)
        .fontColor(this.palette().subText)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 6 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor(AppTheme.withAlpha(this.palette().surfaceBg, 0.65))
    .border({ width: 1, color: AppTheme.withAlpha(this.palette().divider, 0.45) })
  }
}
