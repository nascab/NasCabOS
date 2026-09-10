import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { AppEventBus } from '../../../common/AppEventBus';
import { LanguageService } from '../../../core/localization/LanguageService';
import { PageScaffold } from '../../../common/PageScaffold';
import { DialogUtil } from '../../../common/DialogUtil';
import { EmptyState } from '../../../common/components/EmptyState';
import { MediaToolTaskController } from '../controllers/MediaToolControllers';
import { MediaToolTaskItem } from '../models/MediaToolModels';
import { MediaToolRoutes, MediaToolVideoTransPageParam } from '../router/MediaToolRoutes';
import { MediaToolTaskCard } from './parts/MediaToolTaskCard';
import { VideoTransDialog } from './parts/VideoTransDialog';

/**
 * 视频转换任务页（对齐 Flutter VideoTransView appMode 移动端形态）：
 * 标题栏（帮助/刷新/新建）+ 任务卡片列表 + 新建/编辑弹窗（VideoTransDialog）。
 */
@ComponentV2
export struct MediaToolVideoTransPage {
  @Param param: MediaToolVideoTransPageParam = new MediaToolVideoTransPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: MediaToolTaskController = new MediaToolTaskController('video_trans');
  @Local dialogOpen: boolean = false;
  @Local dialogItem: MediaToolTaskItem | undefined = undefined;
  @Local localeBump: number = 0;
  private localeListener: (data: string) => void = (_data: string): void => {
    this.localeBump++;
  };

  aboutToAppear(): void {
    AppEventBus.on(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    this.ctrl.startPolling();
  }

  aboutToDisappear(): void {
    AppEventBus.off(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    this.ctrl.stopPolling();
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private titleText(): string {
    return L10n.t('media_tool_menu_video_trans', '视频转换');
  }

  private showHelp(): void {
    void DialogUtil.showInfoDialog(
      this.titleText(),
      L10n.t('media_tool_menu_video_trans_help', '批量转换服务器目录中的视频格式'));
  }

  private openCreate(): void {
    this.dialogItem = undefined;
    this.dialogOpen = true;
  }

  private openEdit(item: MediaToolTaskItem): void {
    this.dialogItem = item;
    this.dialogOpen = true;
  }

  build() {
    PageScaffold({
      title: this.titleText(),
      showBack: true,
      statusBarBg: AppTheme.current().pageBg,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.TitleActions()
      },
      content: (): void => {
        this.PageContent()
      },
      overlayContent: (): void => {
        this.DialogOverlay()
      }
    })
  }

  @Builder
  TitleActions() {
    SymbolGlyph($r('sys.symbol.questionmark_circle'))
      .fontSize(22)
      .fontColor([this.palette().appBarFg])
      .onClick((): void => {
        this.showHelp();
      })
    SymbolGlyph($r('sys.symbol.arrow_clockwise'))
      .fontSize(22)
      .fontColor([this.palette().appBarFg])
      .onClick((): void => {
        void this.ctrl.refreshList(true);
      })
    SymbolGlyph($r('sys.symbol.plus'))
      .fontSize(22)
      .fontColor([this.palette().appBarFg])
      .onClick((): void => {
        this.openCreate();
      })
  }

  @Builder
  PageContent() {
    Column() {
      if (this.ctrl.isLoading && this.ctrl.tasks.length === 0) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(this.palette().primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.ctrl.errorText.trim().length > 0 && this.ctrl.tasks.length === 0) {
        Column() {
          EmptyState({ message: this.ctrl.errorText.trim() })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.ctrl.tasks.length === 0) {
        Column() {
          EmptyState({ message: L10n.t('no_data', '暂无数据') })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.ctrl.tasks, (item: MediaToolTaskItem) => {
            ListItem() {
              MediaToolTaskCard({
                ctrl: this.ctrl,
                kind: 'video_trans',
                item: item,
                onEdit: (): void => {
                  this.openEdit(item);
                }
              })
            }
          }, (item: MediaToolTaskItem): string => `${item.id}_${item.status}_${item.progress}`
            + `_${item.lastError.length}_${item.totalFiles}_${item.doneFiles}`
            + `_${this.ctrl.isOpLoading(item.id)}`)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().pageBg)
    .opacity(this.localeBump >= 0 ? 1 : 1)
  }

  @Builder
  DialogOverlay() {
    if (this.dialogOpen) {
      VideoTransDialog({
        ctrl: this.ctrl,
        initial: this.dialogItem,
        onDismiss: (): void => {
          this.dialogOpen = false;
        }
      })
    }
  }
}
