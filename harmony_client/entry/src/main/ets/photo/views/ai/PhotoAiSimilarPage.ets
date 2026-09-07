import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { EmptyState } from '../../../common/components/EmptyState';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { CircleCheckbox } from '../../../common/components/CircleCheckbox';
import { PageScaffold } from '../../../common/PageScaffold';
import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { TimelinePhotoItem } from '../../models/PhotoModels';
import { AiSimilarGroupItem } from '../../models/PhotoAiModels';
import { PhotoAiSimilarController } from '../../controllers/PhotoAiSimilarController';

/**
 * AI 相似照片（照片去重）页（对齐 Flutter AiSimilarView 移动端）：
 * 分组卡片列表（组内相似照片网格）+ 每组默认勾选（保留最大文件）+ 底部批量放入回收站 + 每页组数/重置/刷新。
 */

/** 相似照片路由参数（对齐 Flutter AiSimilarView 无参构造） */
export class PhotoAiSimilarPageParam {
}

/** 每页组数选项（对齐 Flutter pageSizeOptions = [10, 20, 50, 100]） */
const PAGE_SIZE_OPTIONS: number[] = [10, 20, 50, 100];

// ===== 每页组数弹层（对齐 Flutter PopupMenuButton<int> per_page_groups） =====

class SimilarPageSizeSheetParams extends SheetParamsBase {
  ctrl: PhotoAiSimilarController = new PhotoAiSimilarController();
}

@Builder
function SimilarPageSizeSheetContent(p: SimilarPageSizeSheetParams) {
  Column() {
    SheetHandle()
    ForEach(PAGE_SIZE_OPTIONS, (v: number) => {
      SheetListItem({
        icon: $r('sys.symbol.list_bullet'),
        title: L10n.t('per_page_groups', '每页 @count 组', L10n.paramsOf('count', `${v}`)),
        showCheck: true,
        checked: p.ctrl.pageSize === v,
        onSelect: (): void => {
          p.ctrl.setPageSize(v);
          p.close();
        }
      })
    }, (v: number) => `page_size_${v}`)
    Blank().height(24)
  }
  .width('100%')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

// ===== 相似照片格（对齐 Flutter _AiSimilarPhotoTile 移动端） =====

@ComponentV2
struct SimilarPhotoTile {
  @Param photo: TimelinePhotoItem = new TimelinePhotoItem();
  @Param ctrl: PhotoAiSimilarController = new PhotoAiSimilarController();
  @Local tinyUrl: string = '';

  aboutToAppear(): void {
    void this.resolveUrl();
  }

  /** item 复用变化时重新解析缩略图地址 */
  @Monitor('photo', 'photo.fullpath')
  onPhotoChange(): void {
    this.tinyUrl = '';
    void this.resolveUrl();
  }

  private async resolveUrl(): Promise<void> {
    const path = this.photo.fullpath;
    if (path.length === 0) {
      return;
    }
    try {
      const url = await ApiUrls.getTinyUrl(path);
      if (this.photo.fullpath === path) {
        this.tinyUrl = url;
      }
    } catch (_e) {
      this.tinyUrl = '';
    }
  }

  /** 文件大小展示（KB/MB/GB，对齐 Flutter FileUtil.formatSize） */
  private formatSize(bytes: number): string {
    if (bytes <= 0) {
      return '0B';
    }
    const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
    let value = bytes;
    let idx = 0;
    while (value >= 1024 && idx < units.length - 1) {
      value = value / 1024;
      idx++;
    }
    const rounded = idx === 0 ? `${value}` : value.toFixed(1);
    return `${rounded}${units[idx]}`;
  }

  build() {
    Column({ space: 4 }) {
      Stack() {
        Image(this.tinyUrl.length > 0 ? this.tinyUrl : $rawfile('icons/no_data.png'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(6)
          .draggable(false)
          .alt($rawfile('icons/no_data.png'))

        // 选中遮罩（对齐 Flutter selected 覆盖层）
        if (this.ctrl.isSelected(this.photo.id)) {
          Column()
            .width('100%')
            .height('100%')
            .borderRadius(6)
            .backgroundColor(AppTheme.withAlpha(AppTheme.current().primary, 0.28))
            .border({ width: 2, color: AppTheme.current().primary })
        }

        // 左上角勾选（移动端常显，对齐 Flutter check_circle/radio_button_unchecked）
        CircleCheckbox({
          value: this.ctrl.isSelected(this.photo.id),
          uncheckedBorderColor: '#FFFFFF',
          onChanged: (_c: boolean): void => {
            this.ctrl.togglePhotoSelection(this.photo.id);
          }
        })
          .position({ x: 6, y: 6 })
      }
      .width('100%')
      .aspectRatio(1)
      .onClick(() => {
        // 图片浏览器未迁移，点击展示路径信息（对齐移动端路径点击的 info 弹窗）
        DialogUtil.showInfoDialog(L10n.t('path', '路径'), this.photo.fullpath);
      })

      Text(this.formatSize(this.ctrl.photoSize(this.photo)))
        .fontSize(12)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(this.photo.fullpath)
        .fontSize(12)
        .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.7))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .onClick(() => {
          DialogUtil.showInfoDialog(L10n.t('path', '路径'), this.photo.fullpath);
        })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}

// ===== 页面 =====

@ComponentV2
export struct PhotoAiSimilarPage {
  @Param param: PhotoAiSimilarPageParam = new PhotoAiSimilarPageParam();
  @Param popPage: () => void = (): void => {
  };
  /** 视口宽度（用于计算组内网格列数） */
  @Local viewWidth: number = 0;
  private ctrl: PhotoAiSimilarController = new PhotoAiSimilarController();

  aboutToAppear(): void {
    this.ctrl.init();
  }

  // ===== 交互 =====

  private gridColumnCount(): number {
    if (this.viewWidth <= 0) {
      return 3;
    }
    // 对齐 Flutter crossAxisCount = (width / 140).floor().clamp(3, 10)
    return Math.min(10, Math.max(3, Math.floor(this.viewWidth / 140)));
  }

  /** 组内照片按列数分块（避免嵌套滚动，行内 layoutWeight 均分） */
  private photoRows(group: AiSimilarGroupItem): TimelinePhotoItem[][] {
    const cols = this.gridColumnCount();
    const rows: TimelinePhotoItem[][] = [];
    let row: TimelinePhotoItem[] = [];
    for (const p of group.photos) {
      row.push(p);
      if (row.length === cols) {
        rows.push(row);
        row = [];
      }
    }
    if (row.length > 0) {
      rows.push(row);
    }
    return rows;
  }

  /** 末行不满列时的占位下标（保证各格宽度一致） */
  private placeholderIndices(row: TimelinePhotoItem[]): number[] {
    const missing = this.gridColumnCount() - row.length;
    const out: number[] = [];
    for (let i = 0; i < missing; i++) {
      out.push(i);
    }
    return out;
  }

  private openPageSizeSheet(): void {
    const p = new SimilarPageSizeSheetParams();
    p.ctrl = this.ctrl;
    SheetUtil.present(p, wrapBuilder(SimilarPageSizeSheetContent));
  }

  private confirmReset(): void {
    DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('photo_ai_similar_reset_confirm', '将清空已有去重结果并重新计算，确定继续？'),
      (): void => {
        void this.doReset();
      },
      L10n.t('ok', '确定'),
      L10n.t('cancel', '取消'));
  }

  private async doReset(): Promise<void> {
    void DialogUtil.showLoading(L10n.loading);
    try {
      const ok = await this.ctrl.resetSimilarScan();
      if (!ok) {
        return;
      }
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      await this.ctrl.refreshGroups(false);
    } finally {
      void DialogUtil.dismissLoading();
    }
  }

  private confirmTrashSelected(): void {
    if (this.ctrl.selectedPhotoIds.length === 0) {
      return;
    }
    void this.ctrl.trashSelectedPhotos();
  }

  // ===== UI =====

  build() {
    PageScaffold({
      title: L10n.t('photo_menu_ai_similar', '照片去重'),
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

  /** 标题栏右侧操作：每页组数/重置/刷新（对齐 Flutter AppBar actions） */
  @Builder
  TitleActions() {
    Row({ space: 6 }) {
      BorderedIconButton({
        icon: $r('sys.symbol.list_bullet'),
        onTap: (): void => {
          this.openPageSizeSheet();
        }
      })
      if (CurrentUserStore.getInstance().isAdmin) {
        BorderedIconButton({
          icon: $r('sys.symbol.minus_circle'),
          onTap: (): void => {
            this.confirmReset();
          }
        })
      }
      BorderedIconButton({
        icon: $r('sys.symbol.arrow_counterclockwise'),
        onTap: (): void => {
          void this.ctrl.refreshGroups(false);
        }
      })
    }
  }

  @Builder
  PageContent() {
    Column() {
      this.Body()

      // 底部选择操作栏（对齐 Flutter _AiSimilarSelectionBar）
      if (this.ctrl.selectedPhotoIds.length > 0) {
        this.SelectionBar()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  Body() {
    if (this.ctrl.isLoading && this.ctrl.groups.length === 0) {
      Column() {
        LoadingProgress()
          .width(36)
          .height(36)
          .color(AppTheme.current().primary)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (!this.ctrl.similarEnabled) {
      // 功能未开启（对齐 Flutter _AiSimilarList similarEnabled 分支，按钮仅管理员可见）
      Column({ space: 14 }) {
        Text(L10n.t('photo_dedup_disabled', '照片去重未开启'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
          .textAlign(TextAlign.Center)
        if (CurrentUserStore.getInstance().isAdmin) {
          Button(L10n.t('photo_ai_enable_now', '立即开启'))
            .fontSize(15)
            .fontColor(AppTheme.current().buttonText)
            .backgroundColor(AppTheme.current().buttonBg)
            .height(44)
            .width(160)
            .onClick(() => {
              void this.ctrl.enableSimilarRecognition();
            })
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.ctrl.groups.length === 0) {
      // 首页为空且还有下一页时由控制器自动补页（对齐 Flutter hasMore 分支）
      if (this.ctrl.hasMore) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(AppTheme.current().primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        EmptyState({ message: L10n.t('no_data', '暂无数据') })
          .width('100%')
          .height('100%')
      }
    } else {
      this.ListContent()
    }
  }

  /** 分组列表（对齐 Flutter _AiSimilarList ListView：内边距 16/14/16/72） */
  @Builder
  ListContent() {
    List({ space: 12 }) {
      ForEach(this.ctrl.groups, (group: AiSimilarGroupItem) => {
        ListItem() {
          this.GroupCard(group)
        }
      }, (group: AiSimilarGroupItem) => `similar_group_${group.id}_${group.photos.length}`)
      ListItem() {
        this.Footer()
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 72 })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.viewWidth = Number(newArea.width);
    })
    // 滚动到接近底部自动加载更多（对齐 Flutter scrollController 监听）
    .onScrollIndex((_start: number, end: number) => {
      if (end >= this.ctrl.groups.length - 1) {
        void this.ctrl.loadMore();
      }
    })
    .scrollBar(BarState.Off)
  }

  /** 分组卡片（对齐 Flutter _AiSimilarGroupCard：提示文案 + 组号 + 照片网格） */
  @Builder
  GroupCard(group: AiSimilarGroupItem) {
    Column({ space: 10 }) {
      Row() {
        Text(L10n.t('photo_ai_similar_group_hint', '勾选要删除的相似照片'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
          .layoutWeight(1)
        Text(`${group.id}`)
          .fontSize(12)
          .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
      }
      .width('100%')

      ForEach(this.photoRows(group), (row: TimelinePhotoItem[]) => {
        Row({ space: 6 }) {
          ForEach(row, (photo: TimelinePhotoItem) => {
            SimilarPhotoTile({ photo: photo, ctrl: this.ctrl })
              .layoutWeight(1)
          }, (photo: TimelinePhotoItem) => `photo_${photo.id}`)
          // 末行不满列时占位补齐（保证格宽一致）
          ForEach(this.placeholderIndices(row), (idx: number) => {
            Column()
              .layoutWeight(1)
          }, (idx: number) => `placeholder_${idx}`)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (row: TimelinePhotoItem[]) => row.map((p: TimelinePhotoItem): string => `${p.id}`).join('_'))
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .backgroundColor(AppTheme.current().cardBg)
  }

  @Builder
  Footer() {
    Row() {
      if (this.ctrl.isLoading) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(AppTheme.current().primary)
      } else if (this.ctrl.hasMore) {
        Text(L10n.t('photo_ai_similar_load_more', '加载更多重复照片'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .onClick(() => {
            void this.ctrl.loadMore();
          })
      }
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
  }

  /** 底部选择操作栏（对齐 Flutter _AiSimilarSelectionBar：已选数 + 取消 + 放入照片回收站） */
  @Builder
  SelectionBar() {
    Row() {
      Text(L10n.t('selected_photos_only', '已选：@count 张',
        L10n.paramsOf('count', `${this.ctrl.selectedPhotoIds.length}`)))
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Blank()
      Text(L10n.t('cancel', '取消'))
        .fontSize(14)
        .fontColor(AppTheme.current().primary)
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .onClick(() => {
          this.ctrl.clearSelection();
        })
      Button(L10n.t('put_in_photo_trash', '放入照片回收站'))
        .fontSize(13)
        .fontColor(AppTheme.current().buttonText)
        .backgroundColor(AppTheme.current().buttonBg)
        .height(36)
        .margin({ left: 8 })
        .onClick(() => {
          this.confirmTrashSelected();
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .border({ width: { top: 1 }, color: AppTheme.current().divider })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}
