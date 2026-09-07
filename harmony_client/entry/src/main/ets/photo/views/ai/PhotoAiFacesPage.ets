import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { DialogUtil, DialogResult } from '../../../common/DialogUtil';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { EmptyState } from '../../../common/components/EmptyState';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { CircleCheckbox } from '../../../common/components/CircleCheckbox';
import { PageScaffold } from '../../../common/PageScaffold';
import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { AiFaceItem } from '../../models/PhotoAiModels';
import { PhotoAiFacesController } from '../../controllers/PhotoAiFacesController';

/**
 * AI 人脸页（对齐 Flutter AiFacesView 移动端）：
 * 人脸卡片网格（圆形头像 + 名字 + 数量）+ 状态过滤/搜索/刷新/管理设置 + 多选底部操作栏。
 */

/** 人脸路由参数（预留给 AI 主页深链：指定人脸直接进入对应时间线） */
export class PhotoAiFacesPageParam {
  faceId?: number = undefined;
  name?: string = undefined;
}

// ===== 状态过滤弹层（对齐 Flutter _showStatusFilterSheet） =====

class FaceFilterSheetParams extends SheetParamsBase {
  ctrl: PhotoAiFacesController = new PhotoAiFacesController();
}

@Builder
function FaceFilterSheetContent(p: FaceFilterSheetParams) {
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

// ===== 管理操作弹层（对齐 Flutter AppBar PopupMenuButton：设置/重置） =====

class FaceAdminSheetParams extends SheetParamsBase {
  onSettings: () => void = (): void => {
  };
  onReset: () => void = (): void => {
  };
}

@Builder
function FaceAdminSheetContent(p: FaceAdminSheetParams) {
  Column() {
    SheetHandle()
    SheetListItem({
      icon: $r('sys.symbol.gearshape'),
      title: L10n.t('setting', '设置'),
      onSelect: (): void => {
        p.close();
        p.onSettings();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.arrow_counterclockwise'),
      title: L10n.t('reset', '重置'),
      onSelect: (): void => {
        p.close();
        p.onReset();
      }
    })
    Blank().height(24)
  }
  .width('100%')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

// ===== 人脸卡片操作弹层（对齐 Flutter showMobileMenu：下载/重命名/显示|隐藏） =====

class FaceActionSheetParams extends SheetParamsBase {
  face: AiFaceItem = new AiFaceItem();
  ctrl: PhotoAiFacesController = new PhotoAiFacesController();
  onRename: (face: AiFaceItem) => void = (_f: AiFaceItem): void => {
  };
}

@Builder
function FaceActionSheetContent(p: FaceActionSheetParams) {
  Column() {
    SheetHandle()
    SheetListItem({
      icon: $r('sys.symbol.square_and_arrow_down'),
      title: L10n.t('download', '下载'),
      onSelect: (): void => {
        p.close();
        p.ctrl.downloadSelected();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.square_and_pencil'),
      title: L10n.t('rename', '重命名'),
      onSelect: (): void => {
        p.close();
        p.onRename(p.face);
      }
    })
    SheetListItem({
      icon: p.face.isHide ? $r('sys.symbol.eye') : $r('sys.symbol.eye_slash'),
      title: p.face.isHide ? L10n.t('face_action_show', '显示') : L10n.t('face_action_hide', '隐藏'),
      onSelect: (): void => {
        p.close();
        void p.ctrl.setFaceHidden(p.face, !p.face.isHide);
      }
    })
    Blank().height(24)
  }
  .width('100%')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

// ===== 自动隐藏设置弹窗（对齐 Flutter openAutoHideSettings 的 AlertDialog + 下拉选项） =====

class AutoHideDialogInfo {
  title: string = '';
  subtitle: string = '';
  currentValue: number = 0;
  onConfirm: (value: number) => void = (_v: number): void => {
  };
  onDismiss: () => void = (): void => {
  };
}

@ComponentV2
struct FaceAutoHideDialog {
  @Param info: AutoHideDialogInfo = new AutoHideDialogInfo();
  @Local selected: number = 0;
  /** 选项值与文案 key（对齐 Flutter [0, 3, 5, 10]） */
  private optionValues: number[] = [0, 3, 5, 10];

  aboutToAppear(): void {
    this.selected = this.info.currentValue;
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          this.info.onDismiss();
        })

      Column() {
        Text(this.info.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .width('100%')
        Text(this.info.subtitle)
          .fontSize(12)
          .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.8))
          .margin({ top: 6 })
          .width('100%')
        Column() {
          ForEach(this.optionValues, (v: number) => {
            Row({ space: 12 }) {
              Text(L10n.t(`photo_ai_auto_hide_face_album_option_${v}`, `${v}`))
                .fontSize(14)
                .fontColor(AppTheme.current().onSurface)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (this.selected === v) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(18)
                  .fontColor([AppTheme.current().primary])
              }
            }
            .width('100%')
            .padding({ top: 11, bottom: 11 })
            .onClick(() => {
              this.selected = v;
            })
          }, (v: number) => `auto_hide_${v}`)
        }
        .margin({ top: 12 })
        .width('100%')
        .borderRadius(10)
        .border({ width: 1, color: AppTheme.current().inputBorder })

        Row({ space: 8 }) {
          Button(L10n.t('cancel', '取消'))
            .fontSize(14)
            .fontColor(AppTheme.current().primary)
            .backgroundColor(Color.Transparent)
            .height(36)
            .onClick(() => {
              this.info.onDismiss();
            })
          Button(L10n.t('ok', '确定'))
            .fontSize(14)
            .fontColor(AppTheme.current().buttonText)
            .backgroundColor(AppTheme.current().buttonBg)
            .height(36)
            .onClick(() => {
              this.info.onConfirm(this.selected);
            })
        }
        .justifyContent(FlexAlign.End)
        .margin({ top: 16 })
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
}

// ===== 人脸卡片（对齐 Flutter AiFacesItemCard 移动端） =====

@ComponentV2
struct FaceGridItem {
  @Param face: AiFaceItem = new AiFaceItem();
  @Param ctrl: PhotoAiFacesController = new PhotoAiFacesController();
  @Param avatarSize: number = 92;
  /** 点击卡片操作弹层（重命名入口由页面处理） */
  @Param onOpenActions: (face: AiFaceItem) => void = (_f: AiFaceItem): void => {
  };
  @Param onOpen: (face: AiFaceItem) => void = (_f: AiFaceItem): void => {
  };
  @Local avatarUrl: string = '';

  aboutToAppear(): void {
    void this.resolveUrl();
  }

  /** item 复用变化时重新解析头像地址 */
  @Monitor('face', 'face.faceId')
  onFaceChange(): void {
    this.avatarUrl = '';
    void this.resolveUrl();
  }

  private async resolveUrl(): Promise<void> {
    const faceId = this.face.faceId;
    if (faceId <= 0) {
      return;
    }
    try {
      const url = await ApiUrls.getFaceImageUrl(faceId, 240, 85, this.face.coverFileHash);
      if (this.face.faceId === faceId) {
        this.avatarUrl = url;
      }
    } catch (_e) {
      this.avatarUrl = '';
    }
  }

  private hasName(): boolean {
    return this.face.name.trim().length > 0;
  }

  private isAdmin(): boolean {
    return CurrentUserStore.getInstance().isAdmin;
  }

  build() {
    Column({ space: 6 }) {
      Stack() {
        // 圆形头像（对齐 Flutter ClipOval + getFaceImageUrl）
        Column() {
          Image(this.avatarUrl.length > 0 ? this.avatarUrl : $rawfile('icons/no_data.png'))
            .width(this.avatarSize)
            .height(this.avatarSize)
            .objectFit(ImageFit.Cover)
            .borderRadius(this.avatarSize / 2)
            .draggable(false)
            .alt($rawfile('icons/no_data.png'))
        }
        .width(this.avatarSize)
        .height(this.avatarSize)
        .borderRadius(this.avatarSize / 2)
        .border({
          width: this.ctrl.isSelected(this.face.faceId) ? 2 : 1,
          color: this.ctrl.isSelected(this.face.faceId)
            ? AppTheme.current().primary
            : AppTheme.withAlpha(AppTheme.current().onSurface, 0.08)
        })
        .clip(true)

        // 选中遮罩
        if (this.ctrl.isSelected(this.face.faceId)) {
          Column()
            .width(this.avatarSize)
            .height(this.avatarSize)
            .borderRadius(this.avatarSize / 2)
            .backgroundColor(AppTheme.withAlpha(AppTheme.current().primary, 0.14))
        }

        // 多选勾选（多选模式下显示，长按进入）
        if (this.ctrl.selectionMode) {
          CircleCheckbox({
            value: this.ctrl.isSelected(this.face.faceId),
            uncheckedBorderColor: '#FFFFFF',
            onChanged: (_c: boolean): void => {
              this.ctrl.toggleSelected(this.face.faceId);
            }
          })
            .position({ x: 0, y: 0 })
        }

        // 管理员卡片操作入口（对齐 Flutter showMobileMenu PopupMenuButton）
        if (this.isAdmin() && !this.ctrl.selectionMode) {
          Column() {
            SymbolGlyph($r('sys.symbol.more'))
              .fontSize(14)
              .fontColor(['#FFFFFF'])
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .width(28)
          .height(28)
          .borderRadius(14)
          .backgroundColor('#4D000000')
          .position({ x: this.avatarSize - 28, y: 0 })
          .onClick(() => {
            this.onOpenActions(this.face);
          })
        }
      }
      .width(this.avatarSize)
      .height(this.avatarSize)

      // 名字/添加名字/未命名
      if (this.hasName()) {
        Text(this.face.name.trim())
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else if (this.isAdmin()) {
        Text(L10n.t('face_add_name', '添加名字'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().primary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.onOpenActions(this.face);
          })
      } else {
        Text(L10n.t('face_unnamed', '未命名'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      // 照片数（仅管理员显示）
      if (this.isAdmin()) {
        Text(L10n.t('total_count', '共 @count 张', L10n.paramsOf('count', `${this.face.faceCount}`)))
          .fontSize(10)
          .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding({ top: 6, bottom: 6, left: 6, right: 6 })
    .borderRadius(12)
    .border({
      width: 1,
      color: this.ctrl.isSelected(this.face.faceId)
        ? AppTheme.withAlpha(AppTheme.current().primary, 0.45)
        : Color.Transparent
    })
    .backgroundColor(this.ctrl.isSelected(this.face.faceId)
      ? AppTheme.withAlpha(AppTheme.current().primary, 0.08)
      : Color.Transparent)
    .onClick(() => {
      if (this.ctrl.selectionMode) {
        this.ctrl.toggleSelected(this.face.faceId);
        return;
      }
      this.onOpen(this.face);
    })
    .gesture(LongPressGesture({ duration: 500 })
      .onAction(() => {
        this.ctrl.toggleSelected(this.face.faceId);
      }))
  }
}

// ===== 页面 =====

@ComponentV2
export struct PhotoAiFacesPage {
  @Param param: PhotoAiFacesPageParam = new PhotoAiFacesPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local refreshing: boolean = false;
  /** 视口宽度（用于计算网格列数与头像大小） */
  @Local viewWidth: number = 0;
  @Local showAutoHideDialog: boolean = false;
  @Local autoHideInfo: AutoHideDialogInfo = new AutoHideDialogInfo();
  private ctrl: PhotoAiFacesController = new PhotoAiFacesController();

  aboutToAppear(): void {
    // param.faceId/name 预留给 AI 主页深链，本页当前不消费（对齐 Flutter AiFacesView 无参构造）
    void this.param;
    this.ctrl.init();
  }

  // ===== 交互 =====

  private gridColumnCount(): number {
    if (this.viewWidth <= 0) {
      return 3;
    }
    return Math.min(10, Math.max(3, Math.floor(this.viewWidth / 150)));
  }

  private columnsTemplate(): string {
    const parts: string[] = [];
    for (let i = 0; i < this.gridColumnCount(); i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  /** 头像尺寸（对齐 Flutter avatarSize = (itemWidth - 12).clamp(64, 108)） */
  private avatarSize(): number {
    if (this.viewWidth <= 0) {
      return 92;
    }
    const count = this.gridColumnCount();
    const itemWidth = (this.viewWidth - 32 - 12 * (count - 1)) / count;
    return Math.min(108, Math.max(64, itemWidth - 12));
  }

  private openSearch(): void {
    DialogUtil.showInputDialog(L10n.t('search', '搜索'), L10n.t('face_search_hint', '搜索名字'),
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
    const p = new FaceFilterSheetParams();
    p.ctrl = this.ctrl;
    SheetUtil.present(p, wrapBuilder(FaceFilterSheetContent));
  }

  private openAdminSheet(): void {
    const p = new FaceAdminSheetParams();
    p.onSettings = (): void => {
      this.openAutoHideSettings();
    };
    p.onReset = (): void => {
      this.confirmResetFaces();
    };
    SheetUtil.present(p, wrapBuilder(FaceAdminSheetContent));
  }

  private openFaceActions(face: AiFaceItem): void {
    const isAdmin = CurrentUserStore.getInstance().isAdmin;
    if (!isAdmin) {
      return;
    }
    // 未命名卡片点击名字区域 = 重命名；有名卡片 more = 操作弹层
    if (face.name.trim().length === 0) {
      void this.renameFace(face);
      return;
    }
    const p = new FaceActionSheetParams();
    p.face = face;
    p.ctrl = this.ctrl;
    p.onRename = (f: AiFaceItem): void => {
      void this.renameFace(f);
    };
    SheetUtil.present(p, wrapBuilder(FaceActionSheetContent));
  }

  /** 重命名弹窗（对齐 Flutter DialogUtil.showInputDialog + validator） */
  private async renameFace(face: AiFaceItem): Promise<void> {
    const r = await DialogUtil.showInputDialog(
      L10n.t('face_name_dialog_title', '设置名字'),
      L10n.t('face_name_dialog_hint', '请输入人物名字（最多30个字）'),
      face.name.trim(),
      L10n.t('ok', '确定'),
      L10n.t('cancel', '取消'),
      (value: string): string | undefined => {
        const t = value.trim();
        if (t.length === 0) {
          return L10n.t('name_cannot_be_empty', '名称不能为空');
        }
        if (t.length > 30) {
          return L10n.t('face_name_too_long', '最多30个字');
        }
        return undefined;
      });
    if (typeof r !== 'string') {
      return;
    }
    const name = (r as string).trim();
    if (name.length === 0) {
      return;
    }
    await this.ctrl.renameFace(face, name);
  }

  /** 自动隐藏设置（对齐 Flutter openAutoHideSettings：加载当前值 → 选择 → 保存） */
  private async openAutoHideSettings(): Promise<void> {
    if (!CurrentUserStore.getInstance().isAdmin) {
      return;
    }
    void DialogUtil.showLoading(L10n.loading);
    const current = await this.ctrl.loadFaceMinShowCount();
    void DialogUtil.dismissLoading();

    const info = new AutoHideDialogInfo();
    info.title = L10n.t('photo_ai_auto_hide_face_album', '自动隐藏人物相册');
    info.subtitle = L10n.t('photo_ai_auto_hide_face_album_subtitle', '隐藏照片少于一定数量的相册');
    info.currentValue = current;
    info.onConfirm = (value: number): void => {
      this.showAutoHideDialog = false;
      if (value === current) {
        return;
      }
      this.saveAutoHide(value);
    };
    info.onDismiss = (): void => {
      this.showAutoHideDialog = false;
    };
    this.autoHideInfo = info;
    this.showAutoHideDialog = true;
  }

  private async saveAutoHide(value: number): Promise<void> {
    void DialogUtil.showLoading(L10n.loading);
    try {
      await this.ctrl.saveFaceMinShowCount(value);
    } finally {
      void DialogUtil.dismissLoading();
    }
  }

  private confirmResetFaces(): void {
    if (!CurrentUserStore.getInstance().isAdmin) {
      return;
    }
    DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('face_reset_confirm', '所有人脸数据将被清空,然后重新识别,是否确认?'),
      (): void => {
        void this.doResetFaces();
      },
      L10n.t('ok', '确定'),
      L10n.t('cancel', '取消'));
  }

  private async doResetFaces(): Promise<void> {
    void DialogUtil.showLoading(L10n.t('face_reset_loading', '正在重置人脸识别...'));
    try {
      await this.ctrl.resetFaces();
    } finally {
      void DialogUtil.dismissLoading();
    }
  }

  private confirmMergeSelected(): void {
    DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('face_merge_confirm', '人物合并后无法拆分,是否确认合并?'),
      (): void => {
        void this.ctrl.mergeSelected();
      },
      L10n.t('ok', '确定'),
      L10n.t('cancel', '取消'));
  }

  // ===== UI =====

  build() {
    PageScaffold({
      title: L10n.t('photo_menu_ai_face', '人脸识别'),
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.TitleActions()
      },
      content: (): void => {
        this.PageContent()
      },
      // 弹窗必须在 NavDestination 内部挂载；组件实例化只能放在 @Builder 方法中
      overlayContent: (): void => {
        this.AutoHideDialogOverlay()
      }
    })
  }

  /** 人脸自动隐藏设置弹窗浮层 */
  @Builder
  AutoHideDialogOverlay() {
    if (this.showAutoHideDialog) {
      FaceAutoHideDialog({ info: this.autoHideInfo })
    }
  }

  /** 标题栏右侧操作：过滤/搜索/刷新/管理设置（对齐 Flutter AppBar actions） */
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
          void this.ctrl.refreshFaces();
        }
      })
      if (CurrentUserStore.getInstance().isAdmin) {
        BorderedIconButton({
          icon: $r('sys.symbol.more'),
          onTap: (): void => {
            this.openAdminSheet();
          }
        })
      }
    }
  }

  @Builder
  PageContent() {
    Column() {
      Refresh({ refreshing: this.refreshing }) {
        this.Body()
      }
      .onRefreshing(() => {
        this.refreshing = true;
        this.ctrl.refreshFaces().finally(() => {
          this.refreshing = false;
        });
      })
      .width('100%')
      .layoutWeight(1)

      // 多选底部操作栏（对齐 Flutter AiFacesMultiSelectBottomBar）
      if (this.ctrl.selectionMode) {
        this.MultiSelectBar()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  Body() {
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
    } else if (!this.ctrl.faceEnabled) {
      // 功能未开启（对齐 Flutter AiFacesGrid faceEnabled 分支）
      Column({ space: 14 }) {
        Text(L10n.t('photo_ai_face_disabled', '人脸识别未开启'))
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
            void this.ctrl.enableFaceRecognition();
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

  /** 人脸网格（对齐 Flutter AiFacesGrid：宽/150 列数 3~10，间距 12，内边距 16） */
  @Builder
  GridContent() {
    Grid() {
      ForEach(this.ctrl.items, (face: AiFaceItem) => {
        GridItem() {
          FaceGridItem({
            face: face,
            ctrl: this.ctrl,
            avatarSize: this.avatarSize(),
            onOpenActions: (f: AiFaceItem): void => {
              this.openFaceActions(f);
            },
            onOpen: (f: AiFaceItem): void => {
              this.ctrl.openFace(f);
            }
          })
        }
      }, (face: AiFaceItem) => `face_${face.faceId}_${face.name}_${face.isHide}`)
      // 页脚：加载中 / 没有更多 / 加载更多
      GridItem() {
        this.Footer()
      }
    }
    .columnsTemplate(this.columnsTemplate())
    .columnsGap(12)
    .rowsGap(12)
    .padding(16)
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.viewWidth = Number(newArea.width);
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
      } else if (this.ctrl.hasMore) {
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

  /** 多选底部操作栏（对齐 Flutter AiFacesMultiSelectBottomBar：显示/隐藏/合并/下载/取消） */
  @Builder
  MultiSelectBar() {
    Row() {
      Text(L10n.t('face_selected_count', '已选择 @count 个',
        L10n.paramsOf('count', `${this.ctrl.selectedFaceIds.length}`)))
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (CurrentUserStore.getInstance().isAdmin) {
        if (this.ctrl.statusFilter === 'all') {
          // 全部过滤下同时提供显示/隐藏（对齐 Flutter isAll 分支）
          this.BarTextEnabled(L10n.t('face_action_show', '显示'), true, (): void => {
            void this.ctrl.batchSetHidden(false);
          })
          this.BarTextEnabled(L10n.t('face_action_hide', '隐藏'), true, (): void => {
            void this.ctrl.batchSetHidden(true);
          })
        } else {
          this.BarTextEnabled(this.batchHideLabel(), true, (): void => {
            void this.ctrl.batchSetHidden(this.batchHideTarget());
          })
        }
        this.BarTextEnabled(L10n.t('face_action_merge', '合并人脸'),
          this.ctrl.selectedFaceIds.length >= 2, (): void => {
          this.confirmMergeSelected();
        })
      }
      this.BarTextEnabled(L10n.t('download', '下载'), true, (): void => {
        this.ctrl.downloadSelected();
      })
      this.BarTextEnabled(L10n.t('cancel', '取消'), true, (): void => {
        this.ctrl.exitSelectionMode();
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .border({ width: { top: 1 }, color: AppTheme.current().divider })
    .backgroundColor(AppTheme.current().surfaceBg)
  }

  /** 批量隐藏按钮文案（对齐 Flutter isAll 双按钮 / 单按钮切换逻辑） */
  private batchHideLabel(): string {
    if (this.ctrl.statusFilter === 'all') {
      return L10n.t('face_action_hide', '隐藏');
    }
    const isHideList = this.ctrl.statusFilter === 'hide' || this.ctrl.statusFilter === 'hidden';
    return isHideList ? L10n.t('face_action_show', '显示') : L10n.t('face_action_hide', '隐藏');
  }

  /** 批量隐藏目标状态 */
  private batchHideTarget(): boolean {
    if (this.ctrl.statusFilter === 'all') {
      return true;
    }
    return !(this.ctrl.statusFilter === 'hide' || this.ctrl.statusFilter === 'hidden');
  }

  /** 文字按钮（带启用态，对齐 Flutter onPressed == null 置灰） */
  @Builder
  BarTextEnabled(label: string, enabled: boolean, onTap: () => void) {
    Text(label)
      .fontSize(14)
      .fontColor(enabled ? AppTheme.current().primary : AppTheme.withAlpha(AppTheme.current().primary, 0.4))
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .onClick(() => {
        if (enabled) {
          onTap();
        }
      })
  }
}
