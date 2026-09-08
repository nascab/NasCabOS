import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { APIClient } from '../../../core/network/APIClient';
import { DialogUtil } from '../../../common/DialogUtil';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { AppImage } from '../../../common/components/AppImage';
import { EmptyState } from '../../../common/components/EmptyState';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { CircleCheckbox } from '../../../common/components/CircleCheckbox';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { PageScaffold } from '../../../common/PageScaffold';
import { TrashPhotoItem } from '../../models/PhotoModels';
import { PhotoTrashController } from '../../controllers/PhotoTrashController';
import { PhotoDateUtil } from '../../utils/PhotoDateUtil';

/** 回收站路由参数（对齐 Flutter AppPhotoTrashPage 无参构造） */
export class PhotoTrashPageParam {
}

// ===== 文件类型过滤弹层（对齐 Flutter _AppPhotoTrashBody._showFilterSheet） =====

class TrashFilterSheetParams extends SheetParamsBase {
  ctrl: PhotoTrashController = new PhotoTrashController();
}

@Builder
function TrashFilterSheetContent(p: TrashFilterSheetParams) {
  Column() {
    SheetHandle()
    SheetListItem({
      icon: $r('sys.symbol.square'),
      title: L10n.t('all', '全部'),
      showCheck: true,
      checked: p.ctrl.fileType === 'all',
      onSelect: (): void => {
        p.ctrl.changeFileType('all');
        p.close();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.picture'),
      title: L10n.t('timeline_photos', '照片'),
      showCheck: true,
      checked: p.ctrl.fileType === 'photo',
      onSelect: (): void => {
        p.ctrl.changeFileType('photo');
        p.close();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.video'),
      title: L10n.t('timeline_videos', '视频'),
      showCheck: true,
      checked: p.ctrl.fileType === 'video',
      onSelect: (): void => {
        p.ctrl.changeFileType('video');
        p.close();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.livephoto'),
      title: L10n.t('timeline_live_photos', '实况'),
      showCheck: true,
      checked: p.ctrl.fileType === 'livephoto',
      onSelect: (): void => {
        p.ctrl.changeFileType('livephoto');
        p.close();
      }
    })
    Blank().height(24)
  }
  .width('100%')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

// ===== 删除/清空确认弹窗（对齐 Flutter photo_trash_delete.dart 自定义 AlertDialog 结构） =====

/** 弹窗参数：正文 + 删除方式（系统回收站可用时显示）+ livephoto/raw 关联删除勾选 */
class TrashDeleteDialogInfo {
  /** 正文文案（删除选中=folder_delete_confirm；清空=delete_all_files） */
  content: string = '';
  /** 是否显示删除方式选择（服务器支持 shell 时显示，对齐 Flutter isShellSupported） */
  showRecycle: boolean = false;
  /** recycle 初始值（Flutter: bool recycle = isShellSupported） */
  initialRecycle: boolean = false;
  /** 是否显示 livephoto 关联删除勾选（对齐 Flutter hasLivePhoto；清空时恒显示） */
  showLivePhoto: boolean = false;
  /** 是否显示 raw 关联删除勾选（对齐 Flutter hasRawFile；清空时恒显示） */
  showRaw: boolean = false;
  onConfirm: (recycle: boolean, deleteLivePhotoFile: boolean, deleteRawFile: boolean) => void =
    (_recycle: boolean, _live: boolean, _raw: boolean): void => {
    };
  onDismiss: () => void = (): void => {
  };
}

@ComponentV2
struct TrashDeleteDialog {
  @Param info: TrashDeleteDialogInfo = new TrashDeleteDialogInfo();
  /** 删除方式：false=直接删除 true=放入系统回收站（对齐 Flutter StatefulBuilder 内部状态） */
  @Local recycle: boolean = false;
  @Local deleteLivePhotoFile: boolean = true;
  @Local deleteRawFile: boolean = true;

  aboutToAppear(): void {
    this.recycle = this.info.initialRecycle;
  }

  build() {
    Stack() {
      // 遮罩（点击关闭，对齐 Flutter 点击 dialog 外区域）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          this.info.onDismiss();
        })

      Column() {
        Text(L10n.t('need_confirm', '需要确认'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
        Text(this.info.content)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .margin({ top: 12 })
          .width('100%')

        // 删除方式选择（仅在服务器支持系统回收站时显示，对齐 Flutter isShellSupported 分支）
        if (this.info.showRecycle) {
          Row({ space: 6 }) {
            Radio({ value: 'direct', group: 'trash_delete' })
              .checked(!this.recycle)
              .radioStyle({ checkedBackgroundColor: AppTheme.current().primary })
              .onChange((on: boolean) => {
                if (on) {
                  this.recycle = false;
                }
              })
            Text(L10n.t('delete_direct', '直接删除'))
              .fontSize(14)
              .fontColor(AppTheme.current().onSurface)
            Blank()
            Radio({ value: 'recycle', group: 'trash_delete' })
              .checked(this.recycle)
              .radioStyle({ checkedBackgroundColor: AppTheme.current().primary })
              .onChange((on: boolean) => {
                if (on) {
                  this.recycle = true;
                }
              })
            Text(L10n.t('put_in_recycle_bin', '放入系统回收站'))
              .fontSize(14)
              .fontColor(AppTheme.current().onSurface)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 16 })
        }

        // 关联文件删除勾选（对齐 Flutter CheckboxListTile）
        if (this.info.showLivePhoto) {
          this.CheckRow(L10n.t('delete_related_livephoto', '删除关联的livephoto文件'),
            this.deleteLivePhotoFile, (on: boolean): void => {
              this.deleteLivePhotoFile = on;
            })
        }
        if (this.info.showRaw) {
          this.CheckRow(L10n.t('delete_related_raw_file', '删除关联的raw文件'),
            this.deleteRawFile, (on: boolean): void => {
              this.deleteRawFile = on;
            })
        }

        Row({ space: 8 }) {
          Button(L10n.cancel)
            .fontSize(14)
            .fontColor(AppTheme.current().primary)
            .backgroundColor(Color.Transparent)
            .height(36)
            .onClick(() => {
              this.info.onDismiss();
            })
          Button(L10n.ok)
            .fontSize(14)
            .fontColor(AppTheme.current().buttonText)
            .backgroundColor(AppTheme.current().buttonBg)
            .height(36)
            .onClick(() => {
              this.info.onConfirm(this.recycle, this.deleteLivePhotoFile, this.deleteRawFile);
            })
        }
        .justifyContent(FlexAlign.End)
        .margin({ top: 20 })
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .borderRadius(24)
      .backgroundColor(AppTheme.current().surfaceBg)
      .width('80%')
      .constraintSize({ minWidth: 280, maxWidth: 420 })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }

  /** 关联文件勾选行（对齐 Flutter CheckboxListTile leading 布局） */
  @Builder
  CheckRow(label: string, value: boolean, onChange: (on: boolean) => void) {
    Row({ space: 8 }) {
      Toggle({ type: ToggleType.Checkbox, isOn: value })
        .selectedColor(AppTheme.current().primary)
        .onChange((on: boolean) => {
          onChange(on);
        })
      Text(label)
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: 12 })
  }
}

// ===== 回收站网格单元（对齐 Flutter PhotoTrashItem 移动端交互） =====

@ComponentV2
struct TrashGridItem {
  @Param item: TrashPhotoItem = new TrashPhotoItem();
  @Param ctrl: PhotoTrashController = new PhotoTrashController();
  /** 单元格边长（勾选框定位用，与 TimelineController.cellExtent 模式一致） */
  @Param cellExtent: number = 100;
  @Local tinyUrl: string = '';

  aboutToAppear(): void {
    void this.resolveUrl();
  }

  /** item 复用变化时重新解析缩略图地址 */
  @Monitor('item', 'item.fullpath')
  onItemChange(): void {
    this.tinyUrl = '';
    void this.resolveUrl();
  }

  private async resolveUrl(): Promise<void> {
    const path = this.item.fullpath;
    if (path.length === 0) {
      return;
    }
    try {
      const url = await ApiUrls.getTinyUrl(path);
      if (this.item.fullpath === path) {
        this.tinyUrl = url;
      }
    } catch (_e) {
      this.tinyUrl = '';
    }
  }

  private showCheck(): boolean {
    return this.ctrl.isMultiSelectMode || this.ctrl.isSelected(this.item.id);
  }

  build() {
    Stack() {
      if (this.tinyUrl.length > 0) {
        AppImage({ url: this.tinyUrl, imageRadius: 4 })
      } else {
        Image($rawfile('icons/no_data.png'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(4)
          .draggable(false)
      }

      // 选中状态覆盖层（对齐 Flutter isSelected 遮罩）
      if (this.ctrl.isSelected(this.item.id)) {
        Column()
          .width('100%')
          .height('100%')
          .borderRadius(4)
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().primary, 0.3))
          .border({ width: 2, color: AppTheme.current().primary })
      }

      // 顶部信息行：视频播放图标+时长 / 实况标识（对齐 Flutter PhotoTrashItem type==2 / isLvp==1）
      Row() {
        Blank()
        if (this.item.type === 2) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(12)
              .fontColor(['#FFFFFF'])
            Text(PhotoDateUtil.formatDuration(this.item.duration))
              .fontSize(12)
              .fontColor('#FFFFFF')
          }
        } else if (this.item.isLvp === 1) {
          SymbolGlyph($r('sys.symbol.livephoto'))
            .fontSize(14)
            .fontColor(['#FFFFFF'])
            .shadow({ radius: 3, offsetX: 0, offsetY: 1, color: '#000000' })
        }
      }
      .width('100%')
      .padding({ left: 6, right: 6, top: 6 })
      .alignItems(VerticalAlign.Center)

      // 右下角多选勾选（对齐 Flutter CustomCheckbox isCircle）
      if (this.showCheck()) {
        CircleCheckbox({
          value: this.ctrl.isSelected(this.item.id),
          uncheckedBorderColor: '#FFFFFF',
          onChanged: (_c: boolean): void => {
            this.ctrl.toggleSelection(this.item.id);
          }
        })
          .position({ x: this.cellExtent - 28, y: this.cellExtent - 28 })
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .onClick(() => {
      if (this.ctrl.isMultiSelectMode) {
        this.ctrl.toggleSelection(this.item.id);
        return;
      }
      // 非多选模式点击：进入多选并选中当前项（对齐 Flutter onTap）
      this.ctrl.selectSingle(this.item.id);
    })
    .gesture(LongPressGesture({ duration: 500 })
      .onAction(() => {
        // 长按进入多选并选中当前项（对齐 Flutter onLongPress）
        if (!this.ctrl.isMultiSelectMode) {
          this.ctrl.selectSingle(this.item.id);
        }
      }))
  }
}

/**
 * 照片回收站页（对齐 Flutter AppPhotoTrashPage 移动端）：
 * 控制栏（排序/搜索/多选/过滤）+ 网格 + 底部操作栏（常规=恢复全部/清空，多选=恢复/删除/取消）。
 */
@ComponentV2
export struct PhotoTrashPage {
  @Param param: PhotoTrashPageParam = new PhotoTrashPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local refreshing: boolean = false;
  /** 视口宽度（用于计算网格列数） */
  @Local viewWidth: number = 0;
  @Local showDeleteDialog: boolean = false;
  @Local deleteDialogInfo: TrashDeleteDialogInfo = new TrashDeleteDialogInfo();
  private ctrl: PhotoTrashController = new PhotoTrashController();

  aboutToAppear(): void {
    this.ctrl.init();
  }

  // ===== 交互 =====

  private openFilterSheet(): void {
    const p = new TrashFilterSheetParams();
    p.ctrl = this.ctrl;
    SheetUtil.present(p, wrapBuilder(TrashFilterSheetContent));
  }

  /** 恢复全部（对齐 Flutter restoreAll：先确认） */
  private confirmRestoreAll(): void {
    DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('restore_all_confirm', '是否将全部照片恢复？'),
      (): void => {
        void this.ctrl.restoreAll();
      },
      L10n.t('ok', '确定'),
      L10n.t('cancel', '取消'));
  }

  /** 删除选中弹窗（对齐 Flutter deleteSelected 自定义对话框） */
  private openDeleteSelectedDialog(): void {
    const ids = this.ctrl.selectedIds.slice();
    if (ids.length === 0) {
      return;
    }
    const info = new TrashDeleteDialogInfo();
    info.content = L10n.t('folder_delete_confirm', '确定删除@fileCount个项目吗？',
      L10n.paramsOf('fileCount', `${ids.length}`));
    info.showRecycle = APIClient.getInstance().state.shellSupported;
    info.initialRecycle = info.showRecycle;
    info.showLivePhoto = this.ctrl.hasLivePhotoSelected();
    info.showRaw = this.ctrl.hasRawFileSelected();
    info.onConfirm = (recycle: boolean, live: boolean, raw: boolean): void => {
      this.showDeleteDialog = false;
      void this.ctrl.deleteSelected(ids, recycle, live, raw);
    };
    info.onDismiss = (): void => {
      this.showDeleteDialog = false;
    };
    this.deleteDialogInfo = info;
    this.showDeleteDialog = true;
  }

  /** 清空回收站弹窗（对齐 Flutter emptyTrash 自定义对话框：livephoto/raw 勾选恒显示） */
  private openEmptyTrashDialog(): void {
    const info = new TrashDeleteDialogInfo();
    info.content = L10n.t('delete_all_files', '删除所有文件');
    info.showRecycle = APIClient.getInstance().state.shellSupported;
    info.initialRecycle = info.showRecycle;
    info.showLivePhoto = true;
    info.showRaw = true;
    info.onConfirm = (recycle: boolean, live: boolean, raw: boolean): void => {
      this.showDeleteDialog = false;
      void this.ctrl.emptyTrash(recycle, live, raw);
    };
    info.onDismiss = (): void => {
      this.showDeleteDialog = false;
    };
    this.deleteDialogInfo = info;
    this.showDeleteDialog = true;
  }

  private isAllSelected(): boolean {
    return this.ctrl.items.length > 0 && this.ctrl.selectedIds.length === this.ctrl.items.length;
  }

  private columnsTemplate(): string {
    const count = this.ctrl.crossAxisCount;
    const parts: string[] = [];
    for (let i = 0; i < count; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  // ===== UI =====

  build() {
    PageScaffold({
      title: L10n.t('recycle_bin', '回收站'),
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      customBack: (): boolean => {
        // 多选模式下返回先退出多选（对齐 Flutter PopScope 习惯）
        if (this.ctrl.isMultiSelectMode) {
          this.ctrl.exitMultiSelectMode();
          return true;
        }
        return false;
      },
      actions: (): void => {
        this.TitleActions()
      },
      content: (): void => {
        this.PageContent()
      },
      // 弹窗必须在 NavDestination 内部挂载；组件实例化只能放在 @Builder 方法中
      overlayContent: (): void => {
        this.DeleteDialogOverlay()
      }
    })
  }

  /** 删除/清空确认弹窗浮层 */
  @Builder
  DeleteDialogOverlay() {
    if (this.showDeleteDialog) {
      TrashDeleteDialog({ info: this.deleteDialogInfo })
    }
  }

  /** 标题栏右侧操作：多选模式下显示全选切换（Flutter 移动端无此入口，HarmonyOS 补充在标题栏） */
  @Builder
  TitleActions() {
    if (this.ctrl.isMultiSelectMode) {
      BorderedIconButton({
        icon: $r('sys.symbol.checkmark_square_fill'),
        active: this.isAllSelected(),
        onTap: (): void => {
          this.ctrl.toggleSelectAll();
        }
      })
    }
  }

  @Builder
  PageContent() {
    Column() {
      // 控制栏：多选模式下隐藏（对齐 Flutter _AppPhotoTrashBody）
      if (!this.ctrl.isMultiSelectMode) {
        this.ControlBar()
      }

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
        } else if (this.ctrl.items.length === 0) {
          Column() {
            EmptyState({ message: L10n.t('recycle_bin_empty', '回收站中暂无文件') })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          this.GridContent()
        }
      }
      .onRefreshing(() => {
        this.refreshing = true;
        this.ctrl.refresh().finally(() => {
          this.refreshing = false;
        });
      })
      .width('100%')
      .layoutWeight(1)

      // 底部操作栏（有数据时常驻，对齐 Flutter _AppPhotoTrashBottomBar）
      if (this.ctrl.items.length > 0) {
        this.BottomBar()
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 控制栏：排序切换 + 搜索 + 多选 + 类型过滤（对齐 Flutter _AppPhotoTrashBody 顶栏顺序） */
  @Builder
  ControlBar() {
    Row({ space: 8 }) {
      // 排序顺序切换（Flutter 用 rotate_left/rotate_right，SDK 无 rotate_right 用箭头代替）
      BorderedIconButton({
        icon: this.ctrl.sortOrder === 'desc'
          ? $r('sys.symbol.arrow_counterclockwise')
          : $r('sys.symbol.arrow_clockwise'),
        onTap: (): void => {
          this.ctrl.toggleSortOrder();
        }
      })
      SearchInputBar({
        hintText: L10n.t('photo_timeline_search_hint', '照片搜索'),
        text: this.ctrl.keyword,
        onChanged: (v: string): void => {
          this.ctrl.onSearchChanged(v);
        },
        onClear: (): void => {
          this.ctrl.clearSearch();
        }
      })
        .layoutWeight(1)
      BorderedIconButton({
        icon: $r('sys.symbol.checkmark_square_fill'),
        onTap: (): void => {
          this.ctrl.toggleMultiSelectMode();
        }
      })
      BorderedIconButton({
        icon: $r('sys.symbol.slider_horizontal_2'),
        active: this.ctrl.fileType !== 'all',
        onTap: (): void => {
          this.openFilterSheet();
        }
      })
    }
    .width('100%')
    .height(52)
    .padding({ left: 10, right: 10 })
  }

  /** 照片网格（对齐 Flutter GridView：cellSize=100/spacing=2/padding=6，列数按宽度计算） */
  @Builder
  GridContent() {
    Grid() {
      ForEach(this.ctrl.items, (item: TrashPhotoItem) => {
        GridItem() {
          TrashGridItem({ item: item, ctrl: this.ctrl, cellExtent: this.ctrl.cellExtent })
            .aspectRatio(1)
        }
      }, (item: TrashPhotoItem) => `trash_${item.id}`)
      // 页脚：加载中 / 没有更多 / 加载更多
      GridItem() {
        this.Footer()
      }
    }
    .columnsTemplate(this.columnsTemplate())
    .columnsGap(2)
    .rowsGap(2)
    .padding({ left: 6, right: 6, top: 8, bottom: 16 })
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.viewWidth = Number(newArea.width);
      this.ctrl.updateLayout(this.viewWidth);
    })
    // 滚动到接近底部自动加载更多（对齐 Flutter scrollController 监听）
    .onScrollIndex((_start: number, end: number) => {
      if (end >= this.ctrl.items.length - 2) {
        void this.ctrl.loadMore();
      }
    })
  }

  @Builder
  Footer() {
    Row() {
      if (this.ctrl.isLoading) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(AppTheme.current().primary)
      } else if (!this.ctrl.hasMore) {
        Text(L10n.t('no_more', '没有更多'))
          .fontSize(12)
          .fontColor(AppTheme.current().hint)
      } else {
        Text(L10n.t('load_more', '加载更多'))
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

  /** 底部操作栏（对齐 Flutter _AppPhotoTrashBottomBar：多选=恢复/删除/取消，常规=恢复全部/清空） */
  @Builder
  BottomBar() {
    Row() {
      if (this.ctrl.isMultiSelectMode) {
        Text(L10n.t('items_selected', '已选择 @count 项',
          L10n.paramsOf('count', `${this.ctrl.selectedIds.length}`)))
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 8 })
        Blank()
        this.BarText(L10n.t('restore', '恢复'), AppTheme.current().primary,
          this.ctrl.selectedIds.length > 0, (): void => {
            void this.ctrl.restoreSelected(this.ctrl.selectedIds.slice());
          })
        this.BarText(L10n.t('delete', '删除'), AppTheme.current().error,
          this.ctrl.selectedIds.length > 0, (): void => {
            this.openDeleteSelectedDialog();
          })
        this.BarText(L10n.t('cancel', '取消'), AppTheme.current().primary, true, (): void => {
          this.ctrl.exitMultiSelectMode();
        })
      } else {
        Text(L10n.t('total_count', '共 @count 张', L10n.paramsOf('count', `${this.ctrl.items.length}`)))
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 8 })
        Blank()
        this.BarText(L10n.t('restore_all', '恢复全部'), AppTheme.current().primary, true, (): void => {
          this.confirmRestoreAll();
        })
        this.BarText(L10n.t('empty_trash', '清空回收站'), AppTheme.current().error, true, (): void => {
          this.openEmptyTrashDialog();
        })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
    .border({ width: { top: 1 }, color: AppTheme.current().divider })
    .backgroundColor(AppTheme.current().surfaceBg)
  }

  /** 文字按钮（对齐 Flutter TextButton；disabled 置灰） */
  @Builder
  BarText(label: string, color: string, enabled: boolean, onTap: () => void) {
    Text(label)
      .fontSize(14)
      .fontColor(enabled ? color : AppTheme.withAlpha(color, 0.4))
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .onClick(() => {
        if (enabled) {
          onTap();
        }
      })
  }
}
