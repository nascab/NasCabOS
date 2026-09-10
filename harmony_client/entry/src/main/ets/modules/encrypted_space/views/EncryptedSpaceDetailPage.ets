import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { AppEventBus } from '../../../common/AppEventBus';
import { NavUtil } from '../../../common/NavUtil';
import { PageScaffold } from '../../../common/PageScaffold';
import { EmptyState } from '../../../common/components/EmptyState';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { AppImage } from '../../../common/components/AppImage';
import { EncryptedSpaceDetailController } from '../controllers/EncryptedSpaceDetailController';
import {
  EncryptedSpaceActiveSpace, EncryptedFileItem, encryptedSpaceFileIcon,
  encryptedSpaceSortLabelKey
} from '../models/EncryptedSpaceModels';
import { EncryptedSpaceApiService } from '../services/EncryptedSpaceApiService';
import {
  showEncryptedSortSheet, showEncryptedFilterSheet, showEncryptedUploadSourceSheet,
  showEncryptedFileActionSheet
} from '../components/EncryptedSpaceSheets';
import {
  EncryptedSpaceDetailPageParam, EncryptedSpaceViewerPageParam, EncryptedViewerItem
} from '../router/EncryptedSpaceRoutes';
import { AppRouter } from '../../../router/AppRouter';

/** 文件卡片高度与列宽（对齐 Flutter cellHeight 208 / desiredWidth 140） */
const FILE_CELL_HEIGHT = 208;
const FILE_DESIRED_WIDTH = 140;

/**
 * 加密空间详情页（对齐 Flutter AppEncryptedSpaceDetailPage）：
 * 搜索 + 排序/类型筛选/上传按钮行，分页文件网格（缩略图/图标 + 名称 + more），
 * 底部上传进度浮层，图片点击进查看器、视频进播放器、其他下载。
 */
@ComponentV2
export struct EncryptedSpaceDetailPage {
  @Param param: EncryptedSpaceDetailPageParam = new EncryptedSpaceDetailPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: EncryptedSpaceDetailController = new EncryptedSpaceDetailController(
    new EncryptedSpaceActiveSpace(0, '', '', ''));
  /** 主题变化刷新计数（AppTheme.current() 非响应式） */
  @Local themeTick: number = 0;
  @Local viewWidth: number = 0;
  @Local refreshing: boolean = false;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
  };

  aboutToAppear(): void {
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.ctrl = new EncryptedSpaceDetailController(new EncryptedSpaceActiveSpace(
      this.param.spaceId, this.param.token, this.param.name, this.param.path));
    void this.ctrl.loadSortFromPrefs().then((): Promise<void> => {
      return this.ctrl.refreshList(true);
    });
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.ctrl.release();
    // 返回时静默释放空间 token（对齐 Flutter WillPopScope → closeActiveSpace）
    void this.ctrl.deleteTokenSilently();
  }

  private th(): ThemePalette {
    return AppTheme.current();
  }

  private pageTitle(): string {
    const name = this.param.name.trim();
    return name.length > 0 ? name : `${this.param.spaceId}`;
  }

  private isDefaultSort(): boolean {
    return this.ctrl.sortField === 'original_time' && this.ctrl.sortOrder === 'desc';
  }

  private sortTooltip(): string {
    const key = encryptedSpaceSortLabelKey(this.ctrl.sortField, this.ctrl.sortOrder);
    return key.length > 0 ? L10n.t(key, key) : L10n.t('sort', '排序');
  }

  private gridColumnCount(): number {
    const width = this.viewWidth - 24;
    if (width <= 0) {
      return 2;
    }
    return Math.min(8, Math.max(2, Math.floor(width / FILE_DESIRED_WIDTH)));
  }

  private columnsTemplate(): string {
    const count = this.gridColumnCount();
    const parts: string[] = [];
    for (let i = 0; i < count; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  private async pullRefresh(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    try {
      await this.ctrl.refreshList(false);
    } finally {
      this.refreshing = false;
    }
  }

  /** ctrl.viewerVersion 变化 → 打开图片查看器（对齐 Flutter Get.to CustomGallery） */
  @Monitor('ctrl.viewerVersion')
  onViewerVersionChanged(): void {
    const clicked = this.ctrl.viewerItem;
    if (clicked === undefined || clicked.indexId <= 0) {
      return;
    }
    const images: EncryptedFileItem[] = [];
    let index = -1;
    for (const f of this.ctrl.files) {
      if (f.fileType !== 'image') {
        continue;
      }
      images.push(f);
      if (f.indexId === clicked.indexId) {
        index = images.length - 1;
      }
    }
    if (images.length === 0 || index < 0) {
      return;
    }
    const vp = new EncryptedSpaceViewerPageParam();
    vp.initialIndex = index;
    vp.onDeleted = (indexId: number): Promise<boolean> => {
      return this.ctrl.deleteFromGalleryFlow(indexId);
    };
    for (const img of images) {
      const name = img.displayTitle();
      const it = new EncryptedViewerItem();
      it.indexId = img.indexId;
      it.name = name;
      it.url = EncryptedSpaceApiService.buildDecodeUrl(
        this.ctrl.active.spaceId, this.ctrl.active.token, img.indexId, '', false, '');
      it.downloadUrl = EncryptedSpaceApiService.buildDecodeUrl(
        this.ctrl.active.spaceId, this.ctrl.active.token, img.indexId, '', true, name);
      vp.items.push(it);
    }
    NavUtil.push(AppRouter.ENCRYPTED_SPACE_VIEWER, vp);
  }

  build() {
    PageScaffold({
      title: this.pageTitle(),
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.Body()
      }
    })
  }

  @Builder
  Body() {
    Stack() {
      Column() {
        // 搜索在最左，排序、类型筛选、上传靠右（对齐 App 端工具行）
        Row({ space: 8 }) {
          SearchInputBar({
            hintText: L10n.t('search', '搜索'),
            text: this.ctrl.searchKeyword,
            onChanged: (v: string): void => {
              this.ctrl.onSearchChanged(v);
            },
            onClear: (): void => {
              this.ctrl.clearSearch();
            }
          })
            .layoutWeight(1)
          BorderedIconButton({
            icon: $r('sys.symbol.sort'),
            active: !this.isDefaultSort(),
            onTap: (): void => {
              showEncryptedSortSheet(this.ctrl.sortField, this.ctrl.sortOrder,
                (field: string, order: string): void => {
                  this.ctrl.setSort(field, order);
                });
            }
          })
          BorderedIconButton({
            icon: $r('sys.symbol.slider_horizontal_2'),
            active: this.ctrl.fileTypeFilter !== 'all',
            onTap: (): void => {
              showEncryptedFilterSheet(this.ctrl.fileTypeFilter,
                (value: string): void => {
                  this.ctrl.setFileTypeFilter(value);
                });
            }
          })
          BorderedIconButton({
            icon: $r('sys.symbol.upload'),
            onTap: (): void => {
              showEncryptedUploadSourceSheet((source: string): void => {
                void this.ctrl.uploadFilesFlow(source);
              });
            }
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8 })

        this.FileBody()
      }
      .width('100%')
      .height('100%')

      // 上传进度浮层（对齐 _EncryptedSpaceUploadProgressOverlay）
      if (this.ctrl.isUploading) {
        this.UploadOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  FileBody() {
    Stack() {
      if (this.ctrl.isLoading && this.ctrl.files.length === 0) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.th().primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.ctrl.errorText.length > 0) {
        Text(this.ctrl.errorText)
          .fontSize(14)
          .fontColor(this.th().subText)
          .width('100%')
          .height('100%')
          .textAlign(TextAlign.Center)
      } else if (this.ctrl.files.length === 0) {
        EmptyState({ message: L10n.t('encrypted_space_drop_hint', '将文件或文件夹拖动到此处上传') })
      } else {
        Refresh({ refreshing: this.refreshing }) {
          Grid() {
            ForEach(this.ctrl.files, (item: EncryptedFileItem, idx: number) => {
              GridItem() {
                EncryptedFileCard({
                  item: item,
                  ctrl: this.ctrl,
                  themeTick: this.themeTick
                })
              }
            }, (item: EncryptedFileItem, idx: number) => `${item.indexId}_${idx}`)
          }
          .columnsTemplate(this.columnsTemplate())
          .columnsGap(12)
          .rowsGap(12)
          .padding(12)
          .width('100%')
          .height('100%')
          .onAreaChange((_o: Area, n: Area) => {
            this.viewWidth = Number(n.width);
          })
          .onReachEnd((): void => {
            void this.ctrl.loadMore();
          })
        }
        .onRefreshing((): void => {
          this.pullRefresh();
        })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  UploadOverlay() {
    Row({ space: 8 }) {
      Column({ space: 8 }) {
        Text(this.uploadOverlayText())
          .fontSize(14)
          .fontColor(this.th().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Progress({ value: Math.round(this.ctrl.uploadingProgress * 100), total: 100,
          type: ProgressType.Linear })
          .width('100%')
          .height(4)
          .color(this.th().primary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(18)
        .fontColor([this.th().subText])
        .onClick(() => {
          void this.ctrl.cancelUploadFlow();
        })
    }
    .alignItems(VerticalAlign.Center)
    .padding({ left: 12, right: 8, top: 10, bottom: 10 })
    .borderRadius(14)
    .backgroundColor(this.th().surfaceBg)
    .border({ width: 1, color: this.th().divider })
    .width('100%')
    .margin({ left: 12, right: 12, bottom: 12 })
  }

  private uploadOverlayText(): string {
    const parts: string[] = [];
    const file = this.ctrl.uploadingFileName.trim();
    if (file.length > 0) {
      parts.push(file);
    }
    if (this.ctrl.uploadingIndex > 0 && this.ctrl.uploadingTotal > 0) {
      parts.push(`${this.ctrl.uploadingIndex}/${this.ctrl.uploadingTotal}`);
    }
    parts.push(`${Math.round(this.ctrl.uploadingProgress * 100)}%`);
    return parts.join(' ');
  }
}

/**
 * 文件卡片（对齐 Flutter _EncryptedSpaceFileCard App 端行为）：
 * 缩略图（tiny 解码 URL）或类型图标 + 视频播放角标，底部名称 + more 弹层（打开/下载/删除）。
 */
@ComponentV2
struct EncryptedFileCard {
  @Param item: EncryptedFileItem = new EncryptedFileItem();
  @Param ctrl: EncryptedSpaceDetailController =
    new EncryptedSpaceDetailController(new EncryptedSpaceActiveSpace(0, '', '', ''));
  @Param themeTick: number = 0;

  private th(): ThemePalette {
    return AppTheme.current();
  }

  private isMedia(): boolean {
    return this.item.fileType === 'image' || this.item.fileType === 'video';
  }

  private thumbUrl(): string {
    return EncryptedSpaceApiService.buildDecodeUrl(
      this.ctrl.active.spaceId, this.ctrl.active.token, this.item.indexId, 'tiny', false, '');
  }

  build() {
    Column() {
      // 缩略图区
      Stack() {
        if (!this.isMedia()) {
          Column() {
            Image(encryptedSpaceFileIcon(this.item.showName))
              .width(70)
              .height(70)
              .objectFit(ImageFit.Contain)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.th().cardBg)
        } else {
          AppImage({
            url: this.thumbUrl(),
            objectFit: ImageFit.Cover,
            showLoadingSpin: false
          })
            .width('100%')
            .height('100%')
          if (this.item.fileType === 'video') {
            Column() {
              SymbolGlyph($r('sys.symbol.play_fill'))
                .fontSize(22)
                .fontColor(['#FFFFFF'])
            }
            .justifyContent(FlexAlign.Center)
            .width(34)
            .height(34)
            .borderRadius(10)
            .backgroundColor('#8C000000')
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .borderRadius(10)
      .clip(true)

      // 名称 + more
      Row({ space: 4 }) {
        Text(this.item.displayTitle())
          .fontSize(14)
          .fontColor(this.th().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.more'))
          .fontSize(20)
          .fontColor([this.th().subText])
          .onClick(() => {
            showEncryptedFileActionSheet(this.isMedia(), (): void => {
              this.ctrl.openItem(this.item);
            }, (): void => {
              void this.ctrl.downloadItem(this.item);
            }, (): void => {
              void this.ctrl.deleteItemsFlow([this.item]);
            });
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .height(FILE_CELL_HEIGHT)
    .padding(10)
    .borderRadius(12)
    .backgroundColor(this.th().cardBg)
    .onClick(() => {
      this.ctrl.openItem(this.item);
    })
  }
}
