import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { DialogUtil, DialogResult } from '../../../common/DialogUtil';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { AppImage } from '../../../common/components/AppImage';
import { EmptyState } from '../../../common/components/EmptyState';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { PageScaffold } from '../../../common/PageScaffold';
import { AiSceneItem } from '../../models/PhotoAiModels';
import { PhotoAiScenesController } from '../../controllers/PhotoAiScenesController';

/**
 * AI 场景页（对齐 Flutter AiScenesView 移动端）：
 * 场景卡片网格（圆角封面 + 名称 + 数量）+ 状态过滤/搜索/刷新；点击进入场景照片时间线。
 */

/** 场景路由参数（对齐 Flutter AiScenesView 无参构造） */
export class PhotoAiScenesPageParam {
}

// ===== 状态过滤弹层（对齐 Flutter _showStatusFilterSheet） =====

class SceneFilterSheetParams extends SheetParamsBase {
  ctrl: PhotoAiScenesController = new PhotoAiScenesController();
}

@Builder
function SceneFilterSheetContent(p: SceneFilterSheetParams) {
  Column() {
    SheetHandle()
    SheetListItem({
      icon: $r('sys.symbol.eye'),
      title: L10n.t('face_filter_visible', '可见的'),
      showCheck: true,
      checked: p.ctrl.statusFilter === 'visiable',
      onSelect: (): void => {
        p.ctrl.setStatusFilter('visiable');
        p.close();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.eye_slash'),
      title: L10n.t('face_filter_hidden', '隐藏的'),
      showCheck: true,
      checked: p.ctrl.statusFilter === 'hide',
      onSelect: (): void => {
        p.ctrl.setStatusFilter('hide');
        p.close();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.funnel'),
      title: L10n.t('all', '全部'),
      showCheck: true,
      checked: p.ctrl.statusFilter === 'all',
      onSelect: (): void => {
        p.ctrl.setStatusFilter('all');
        p.close();
      }
    })
    Blank().height(24)
  }
  .width('100%')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

// ===== 场景卡片（对齐 Flutter AiSceneItemCard） =====

@ComponentV2
struct SceneGridItem {
  @Param scene: AiSceneItem = new AiSceneItem();
  @Param coverSize: number = 104;
  @Param onOpen: (scene: AiSceneItem) => void = (_s: AiSceneItem): void => {
  };
  @Local coverUrl: string = '';

  aboutToAppear(): void {
    void this.resolveUrl();
  }

  /** item 复用变化时重新解析封面地址 */
  @Monitor('scene', 'scene.placeNameRaw')
  onSceneChange(): void {
    this.coverUrl = '';
    void this.resolveUrl();
  }

  private async resolveUrl(): Promise<void> {
    const path = this.scene.coverFullpath.trim();
    if (path.length === 0) {
      return;
    }
    try {
      const url = await ApiUrls.getTinyUrl(path);
      if (this.scene.coverFullpath.trim() === path) {
        this.coverUrl = url;
      }
    } catch (_e) {
      this.coverUrl = '';
    }
  }

  private displayName(): string {
    const name = this.scene.placeName.trim();
    return name.length > 0 ? name : L10n.t('scene_unnamed', '未命名场景');
  }

  build() {
    Column({ space: 6 }) {
      Stack() {
        if (this.coverUrl.length > 0) {
          AppImage({ url: this.coverUrl, imageRadius: 12 })
        } else {
          // 无封面占位（对齐 Flutter Icons.landscape_outlined 占位）
          Column() {
            SymbolGlyph($r('sys.symbol.picture'))
              .fontSize(40)
              .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.6)])
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .width(this.coverSize)
          .height(this.coverSize)
          .borderRadius(12)
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.06))
          .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.08) })
        }
      }
      .width(this.coverSize)
      .height(this.coverSize)

      Text(this.displayName())
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(L10n.t('total_count', '共 @count 张', L10n.paramsOf('count', `${this.scene.photoCount}`)))
        .fontSize(10)
        .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 6, bottom: 6, left: 6, right: 6 })
    .borderRadius(12)
    .onClick(() => {
      this.onOpen(this.scene);
    })
  }
}

// ===== 页面 =====

@ComponentV2
export struct PhotoAiScenesPage {
  @Param param: PhotoAiScenesPageParam = new PhotoAiScenesPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local refreshing: boolean = false;
  /** 视口宽度（用于计算网格列数与封面大小） */
  @Local viewWidth: number = 0;
  private ctrl: PhotoAiScenesController = new PhotoAiScenesController();

  aboutToAppear(): void {
    this.ctrl.init();
  }

  // ===== 交互 =====

  private gridColumnCount(): number {
    if (this.viewWidth <= 0) {
      return 3;
    }
    return Math.min(10, Math.max(3, Math.floor(this.viewWidth / 140)));
  }

  private columnsTemplate(): string {
    const parts: string[] = [];
    for (let i = 0; i < this.gridColumnCount(); i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  /** 封面尺寸（对齐 Flutter avatarSize = itemWidth.clamp(72, 118)） */
  private coverSize(): number {
    if (this.viewWidth <= 0) {
      return 104;
    }
    const count = this.gridColumnCount();
    const itemWidth = (this.viewWidth - 8 - 4 * (count - 1)) / count;
    return Math.min(118, Math.max(72, itemWidth));
  }

  private openSearch(): void {
    DialogUtil.showInputDialog(L10n.t('search', '搜索'), L10n.t('scene_search_hint', '搜索场景'),
      this.ctrl.keyword)
      .then((r: DialogResult | undefined) => {
        if (typeof r === 'string') {
          const v = r as string;
          if (v.trim().length === 0) {
            this.ctrl.clearSearch();
          } else {
            this.ctrl.onSearchChanged(v);
          }
        }
      });
  }

  private openFilterSheet(): void {
    const p = new SceneFilterSheetParams();
    p.ctrl = this.ctrl;
    SheetUtil.present(p, wrapBuilder(SceneFilterSheetContent));
  }

  // ===== UI =====

  build() {
    PageScaffold({
      title: L10n.t('photo_menu_ai_scene', '场景识别'),
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.TitleActions()
      },
      content: (): void => {
        this.PageContent()
      }
    })
  }

  /** 标题栏右侧操作：过滤/搜索/刷新（对齐 Flutter 移动端 AppBar actions，无重置入口） */
  @Builder
  TitleActions() {
    Row({ space: 6 }) {
      BorderedIconButton({
        icon: $r('sys.symbol.funnel'),
        onTap: (): void => {
          this.openFilterSheet();
        }
      })
      BorderedIconButton({
        icon: $r('sys.symbol.magnifyingglass'),
        onTap: (): void => {
          this.openSearch();
        }
      })
      BorderedIconButton({
        icon: $r('sys.symbol.arrow_counterclockwise'),
        onTap: (): void => {
          void this.ctrl.refreshScenes();
        }
      })
    }
  }

  @Builder
  PageContent() {
    Refresh({ refreshing: this.refreshing }) {
      if (this.ctrl.isLoading && this.ctrl.items.length === 0) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(AppTheme.current().primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (!this.ctrl.placeEnabled) {
        // 功能未开启（对齐 Flutter AiScenesGrid placeEnabled 分支）
        Column({ space: 14 }) {
          Text(L10n.t('photo_ai_scene_disabled', '场景识别未开启'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.current().onSurface)
            .textAlign(TextAlign.Center)
          Button(L10n.t('photo_ai_enable_now', '立即开启'))
            .fontSize(15)
            .fontColor(AppTheme.current().buttonText)
            .backgroundColor(AppTheme.current().buttonBg)
            .height(44)
            .width(160)
            .onClick(() => {
              void this.ctrl.enableSceneRecognition();
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.ctrl.items.length === 0) {
        EmptyState({ message: L10n.t('no_data', '暂无数据') })
          .width('100%')
          .height('100%')
      } else {
        this.GridContent()
      }
    }
    .onRefreshing(() => {
      this.refreshing = true;
      this.ctrl.refreshScenes().finally(() => {
        this.refreshing = false;
      });
    })
    .width('100%')
    .height('100%')
  }

  /** 场景网格（对齐 Flutter AiScenesGrid：宽/140 列数 3~10，间距 4，内边距 4） */
  @Builder
  GridContent() {
    Grid() {
      ForEach(this.ctrl.items, (scene: AiSceneItem) => {
        GridItem() {
          SceneGridItem({
            scene: scene,
            coverSize: this.coverSize(),
            onOpen: (s: AiSceneItem): void => {
              this.ctrl.openScene(s);
            }
          })
        }
      }, (scene: AiSceneItem) => `scene_${scene.placeNameRaw}_${scene.isHide}`)
    }
    .columnsTemplate(this.columnsTemplate())
    .columnsGap(4)
    .rowsGap(4)
    .padding(4)
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.viewWidth = Number(newArea.width);
    })
  }
}
