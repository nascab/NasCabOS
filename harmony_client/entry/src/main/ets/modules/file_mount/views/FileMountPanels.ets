import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { DialogUtil } from '../../../common/DialogUtil';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { EmptyState } from '../../../common/components/EmptyState';
import { GlassCard } from '../../../common/components/GlassCard';
import { FileBrowserParam } from '../../../files/views/FileBrowserPage';
import { MountItem } from '../models/FileMountModels';
import { OpenlistDriverI18n } from '../services/OpenlistDriverI18n';
import { FileMountRoutes, FileMountEditPageParam, OpenlistMountEditPageParam } from '../router/FileMountRoutes';
import { FileMountController, OpenlistMountController } from '../controllers/FileMountControllers';

/**
 * 远程挂载列表面板（对齐 Flutter _MountListPanel / _OpenlistMountListPanel 的 showHeader: false
 * 移动端形态：刷新/新增动作由主页标题栏承担，这里只渲染加载/空态/错误/列表）。
 */

/** 挂载列表主体（文件协议挂载，对齐 _MountListPanel） */
@ComponentV2
export struct MountListPanel {
  @Require @Param ctrl: FileMountController;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    if (this.ctrl.isLoading && this.ctrl.mounts.length === 0) {
      this.LoadingBody()
    } else if (this.ctrl.errorText.trim().length > 0 && this.ctrl.mounts.length === 0) {
      this.EmptyBody(this.ctrl.errorText.trim())
    } else if (this.ctrl.mounts.length === 0) {
      this.EmptyBody('')
    } else {
      List({ space: 8 }) {
        ForEach(this.ctrl.mounts, (item: MountItem) => {
          ListItem() {
            MountItemCard({ item: item, ctrl: this.ctrl })
          }
        }, (item: MountItem): string => `${item.id}_${item.status}_${item.name}_${item.remote}`
          + `_${item.lastErrorFull.length}_${this.ctrl.isOpLoading(item.id)}`)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }

  @Builder
  LoadingBody() {
    Column() {
      LoadingProgress()
        .width(32)
        .height(32)
        .color(this.palette().primary)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  EmptyBody(message: string) {
    Column() {
      EmptyState({ message: message })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

/** 网盘挂载列表主体（对齐 _OpenlistMountListPanel） */
@ComponentV2
export struct OpenlistMountListPanel {
  @Require @Param ctrl: OpenlistMountController;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    if (this.ctrl.isLoading && this.ctrl.mounts.length === 0) {
      this.LoadingBody()
    } else if (this.ctrl.errorText.trim().length > 0 && this.ctrl.mounts.length === 0) {
      this.EmptyBody(this.ctrl.errorText.trim())
    } else if (this.ctrl.mounts.length === 0) {
      this.EmptyBody('')
    } else {
      List({ space: 8 }) {
        ForEach(this.ctrl.mounts, (item: MountItem) => {
          ListItem() {
            OpenlistMountItemCard({ item: item, ctrl: this.ctrl })
          }
        }, (item: MountItem): string => `${item.id}_${item.status}_${item.name}_${item.displayMountPath}`
          + `_${item.lastError.length}_${this.ctrl.isOpLoading(item.id)}`)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }

  @Builder
  LoadingBody() {
    Column() {
      LoadingProgress()
        .width(32)
        .height(32)
        .color(this.palette().primary)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  EmptyBody(message: string) {
    Column() {
      EmptyState({ message: message })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

/** 状态文案（对齐 Flutter _statusText） */
function mountStatusText(status: string): string {
  if (status === 'running') {
    return L10n.t('file_mount_status_running', '运行中');
  }
  if (status === 'stopped') {
    return L10n.t('file_mount_status_stopped', '已停止');
  }
  if (status === 'error') {
    return L10n.t('file_mount_status_error', '异常');
  }
  return status;
}

/** 状态色（对齐 Flutter _statusColor） */
function mountStatusColor(status: string): string {
  const p = AppTheme.current();
  if (status === 'running') {
    return p.primary;
  }
  if (status === 'error') {
    return p.error;
  }
  return AppTheme.withAlpha(p.onSurface, 0.65);
}

/** 打开挂载路径所在目录（对齐 Flutter _openFolderInFileBrowser：跳转文件管理页） */
function openFolderInFileBrowser(targetPath: string): void {
  const target = targetPath.trim();
  if (target.length === 0) {
    return;
  }
  const param = new FileBrowserParam();
  param.initialPath = target;
  param.isRootPage = false;
  NavUtil.push(AppRouter.FILES, param);
}

/** 文件协议挂载卡片（对齐 _buildItem） */
@ComponentV2
struct MountItemCard {
  @Require @Param item: MountItem;
  @Require @Param ctrl: FileMountController;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private showFullError(): void {
    void DialogUtil.showInfoDialog(
      L10n.t('file_mount_last_error', '错误信息'), this.item.lastErrorFull);
  }

  build() {
    GlassCard({ padValue: 12, cornerRadius: 14 }) {
      Column() {
        // 行 1：名称 + 状态
        Row() {
          Text(this.item.displayName)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(mountStatusText(this.item.status))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(mountStatusColor(this.item.status))
            .margin({ left: 8 })
        }
        .width('100%')

        KeyValueRow({
          label: L10n.t('file_mount_mount_path', '挂载父路径'),
          value: this.item.mountPath,
          viewPath: this.item.mountPath
        })
          .margin({ top: 8 })
        KeyValueRow({
          label: L10n.t('file_mount_remote', '远程地址'),
          value: this.item.remote
        })
          .margin({ top: 6 })
        if (this.item.lastErrorFull.trim().length > 0) {
          KeyValueRow({
            label: L10n.t('file_mount_last_error', '错误信息'),
            value: this.item.lastErrorFull.split('\n')[0].trim(),
            valueColor: this.palette().error,
            onValueTap: (): void => {
              this.showFullError();
            }
          })
            .margin({ top: 6 })
        }

        // 行 2：操作按钮
        Row({ space: 8 }) {
          PanelButton({
            label: this.item.canStop
              ? L10n.t('file_mount_stop', '停止') : L10n.t('file_mount_start', '启动'),
            icon: this.item.canStop ? $r('sys.symbol.stop_circle') : $r('sys.symbol.play_circle'),
            primary: true,
            btnEnabled: !this.ctrl.isOpLoading(this.item.id),
            loading: this.ctrl.isOpLoading(this.item.id),
            onTap: (): void => {
              if (this.item.canStop) {
                void this.ctrl.stop(this.item.id);
              } else if (this.item.canStart) {
                void this.ctrl.start(this.item.id);
              }
            }
          })
          PanelButton({
            label: L10n.t('edit', '编辑'),
            icon: $r('sys.symbol.square_and_pencil'),
            primary: false,
            btnEnabled: !this.item.isRunning && !this.ctrl.isOpLoading(this.item.id),
            loading: false,
            onTap: (): void => {
              void this.openEditor();
            }
          })
          PanelButton({
            label: L10n.t('delete', '删除'),
            icon: $r('sys.symbol.trash'),
            primary: false,
            btnEnabled: this.item.id > 0,
            loading: false,
            onTap: (): void => {
              void this.ctrl.remove(this.item.id);
            }
          })
        }
        .width('100%')
        .margin({ top: 10 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  private async openEditor(): Promise<void> {
    const allowed = await this.ctrl.ensureWinfspReady();
    if (!allowed) {
      return;
    }
    const p = new FileMountEditPageParam();
    p.initial = this.item;
    NavUtil.push(FileMountRoutes.PAGE_MOUNT_EDIT, p);
  }
}

/** 网盘挂载卡片（对齐 _OpenlistMountListPanel._buildItem） */
@ComponentV2
struct OpenlistMountItemCard {
  @Require @Param item: MountItem;
  @Require @Param ctrl: OpenlistMountController;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    GlassCard({ padValue: 12, cornerRadius: 14 }) {
      Column() {
        Row() {
          Text(this.item.displayName)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(mountStatusText(this.item.status))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(mountStatusColor(this.item.status))
            .margin({ left: 8 })
        }
        .width('100%')

        KeyValueRow({
          label: L10n.t('openlist_mount_driver', '网盘类型'),
          value: OpenlistDriverI18n.driverName(this.item.driver)
        })
          .margin({ top: 8 })
        KeyValueRow({
          label: L10n.t('file_mount_mount_path', '挂载父路径'),
          value: this.item.displayMountPath,
          viewPath: this.item.displayMountPath
        })
          .margin({ top: 6 })
        if (this.item.lastError.trim().length > 0) {
          KeyValueRow({
            label: L10n.t('file_mount_last_error', '错误信息'),
            value: this.item.lastError.split('\n')[0],
            valueColor: this.palette().error
          })
            .margin({ top: 6 })
        }

        Row({ space: 8 }) {
          PanelButton({
            label: this.item.canStop
              ? L10n.t('file_mount_stop', '停止') : L10n.t('file_mount_start', '启动'),
            icon: this.item.canStop ? $r('sys.symbol.stop_circle') : $r('sys.symbol.play_circle'),
            primary: true,
            btnEnabled: !this.ctrl.isOpLoading(this.item.id),
            loading: this.ctrl.isOpLoading(this.item.id),
            onTap: (): void => {
              if (this.item.canStop) {
                void this.ctrl.stop(this.item.id);
              } else if (this.item.canStart) {
                void this.ctrl.start(this.item.id);
              }
            }
          })
          PanelButton({
            label: L10n.t('edit', '编辑'),
            icon: $r('sys.symbol.square_and_pencil'),
            primary: false,
            btnEnabled: !this.item.isRunning && !this.ctrl.isOpLoading(this.item.id),
            loading: false,
            onTap: (): void => {
              void this.openEditor();
            }
          })
          PanelButton({
            label: L10n.t('delete', '删除'),
            icon: $r('sys.symbol.trash'),
            primary: false,
            btnEnabled: this.item.id > 0,
            loading: false,
            onTap: (): void => {
              void this.ctrl.remove(this.item.id);
            }
          })
        }
        .width('100%')
        .margin({ top: 10 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  private async openEditor(): Promise<void> {
    const allowed = await this.ctrl.ensureWinfspReady();
    if (!allowed) {
      return;
    }
    await this.ctrl.loadDrivers();
    const p = new OpenlistMountEditPageParam();
    p.initial = this.item;
    NavUtil.push(FileMountRoutes.PAGE_OPENLIST_EDIT, p);
  }
}

/**
 * 键值行（对齐 _KeyValueRow / _OpenlistKeyValueRow）：
 * 固定宽标签 + 值；viewPath 非空时前置 [查看] 链接跳转文件页。
 */
@ComponentV2
struct KeyValueRow {
  @Param label: string = '';
  @Param value: string = '';
  @Param viewPath: string = '';
  @Param valueColor: string = '';
  @Param onValueTap: () => void = (): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private text(): string {
    return this.value.length > 0 ? this.value : '-';
  }

  private canView(): boolean {
    return this.viewPath.trim().length > 0 && this.text() !== '-';
  }

  build() {
    Row() {
      Text(this.label)
        .fontSize(12)
        .fontColor(this.palette().subText)
        .width(110)
      if (this.canView()) {
        Text(`[${L10n.t('perm_view', '查看')}]`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().primary)
          .margin({ right: 8 })
          .onClick((): void => {
            openFolderInFileBrowser(this.viewPath);
          })
      }
      Text(this.text())
        .fontSize(12)
        .fontColor(this.valueColor.length > 0 ? this.valueColor : this.palette().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .onClick((): void => {
          this.onValueTap();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}

/**
 * 面板操作按钮（对齐 Flutter CustomButton：图标 + 文字胶囊，primary 填充/次要描边）。
 */
@ComponentV2
struct PanelButton {
  @Param label: string = '';
  @Param icon: Resource = $r('sys.symbol.plus');
  @Param primary: boolean = false;
  @Param btnEnabled: boolean = true;
  /** 加载态：图标替换为小加载圈（对齐 Flutter opLoading 时嵌入的 CircularProgressIndicator） */
  @Param loading: boolean = false;
  @Param onTap: () => void = (): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Row({ space: 5 }) {
      if (this.loading) {
        LoadingProgress()
          .width(15)
          .height(15)
          .color(this.primary ? this.palette().buttonText : this.palette().onSurface)
      } else {
        SymbolGlyph(this.icon)
          .fontSize(15)
          .fontColor([this.primary ? this.palette().buttonText : this.palette().onSurface])
      }
      Text(this.label)
        .fontSize(13)
        .fontColor(this.primary ? this.palette().buttonText : this.palette().onSurface)
        .maxLines(1)
    }
    .padding({ left: 12, right: 12, top: 7, bottom: 7 })
    .borderRadius(18)
    .backgroundColor(this.primary ? this.palette().buttonBg : AppTheme.withAlpha(this.palette().onSurface, 0.06))
    .border({
      width: 1,
      color: this.primary ? this.palette().buttonBg : this.palette().divider
    })
    .opacity(this.btnEnabled ? 1 : 0.45)
    .onClick((): void => {
      if (this.btnEnabled) {
        this.onTap();
      }
    })
  }
}
