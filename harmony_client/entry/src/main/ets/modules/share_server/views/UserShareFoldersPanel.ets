import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { DialogUtil } from '../../../common/DialogUtil';
import { GlassCard } from '../../../common/components/GlassCard';
import { EmptyState } from '../../../common/components/EmptyState';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';
import { UserShareFolderItem } from '../models/ShareServerModels';
import { ShareServerController } from '../controllers/ShareServerController';

/**
 * 用户共享目录面板（对齐 Flutter _UserShareFoldersPanel）：
 * 标题/帮助 + 刷新/添加 操作卡 + 共享目录卡片列表（缺失目录警告、允许下载开关、删除）。
 */
@ComponentV2
export struct UserShareFoldersPanel {
  @Param ctrl: ShareServerController = new ShareServerController();
  /** 主题变化刷新计数（主页传入，驱动本面板重渲染换色） */
  @Param themeTick: number = 0;

  private palette() {
    return AppTheme.current();
  }

  private isAdmin(): boolean {
    return this.ctrl.isAdmin;
  }

  /** 取路径末段（对齐 Flutter _basename：按 \ / 分割） */
  private basename(p: string): string {
    const s = p.trim();
    if (s.length === 0) {
      return '';
    }
    const parts = s.split(/[\\/]+/).filter((e: string): boolean => e.length > 0);
    return parts.length === 0 ? s : parts[parts.length - 1];
  }

  private refresh(): void {
    void this.ctrl.refreshUserShareFolders(true, false);
  }

  private addFolder(): void {
    pickTargetFolderViaSheet('', (paths: string[]): void => {
      const p = paths.length > 0 ? paths[0].trim() : '';
      if (p.length === 0) {
        return;
      }
      DialogUtil.showInputDialog(
        L10n.t('user_share_folders_add_title', '添加用户共享目录'),
        p,
        this.basename(p),
        L10n.ok,
        L10n.cancel
      ).then((r: string | number | boolean | undefined): void => {
        if (typeof r !== 'string') {
          return;
        }
        void this.ctrl.addUserShareFolder(p, r.trim(), undefined);
      });
    });
  }

  private removeFolder(p: string): void {
    DialogUtil.showConfirmDialog(L10n.delete,
      L10n.t('user_share_folders_delete_confirm', '确定移除该用户共享目录吗？'),
      (): void => {
        void this.ctrl.removeUserShareFolder(p);
      });
  }

  private isMissing(item: UserShareFolderItem): boolean {
    return !item.exists || !item.isDirectory;
  }

  build() {
    Column() {
      // 操作卡
      GlassCard({
        padValue: 12
      }) {
        Row() {
          Row({ space: 4 }) {
            Text(L10n.t('user_share_folders_title', '用户共享'))
              .fontSize(15)
              .fontColor(this.palette().onSurface)
            SymbolGlyph($r('sys.symbol.questionmark_circle'))
              .fontSize(17)
              .fontColor([this.palette().subText])
              .onClick(() => {
                DialogUtil.showInfoDialog(L10n.tip,
                  L10n.t('user_share_folder_tooltip',
                    '添加后，所有子用户无需单独设置即可读取用户共享文件夹(只读)，用于快速给全体子用户设置权限'));
              })
          }
          .layoutWeight(1)

          this.TextButton($r('sys.symbol.arrow_clockwise'),
            L10n.t('refresh', '刷新'), (): void => {
              this.refresh();
            }, 0)
          if (this.isAdmin()) {
            this.TextButton($r('sys.symbol.plus'), L10n.t('add', '添加'), (): void => {
              this.addFolder();
            }, 12)
          }
        }
        .width('100%')
      }

      // 列表
      if (this.ctrl.userShareFoldersLoading && this.ctrl.userShareFolders.length === 0) {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(this.palette().primary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.ctrl.userShareFolders.length === 0) {
        Column() {
          EmptyState({ message: L10n.t('user_share_folders_empty', '暂无用户共享目录') })
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        List({ space: 8 }) {
          ForEach(this.ctrl.userShareFolders, (item: UserShareFolderItem) => {
            ListItem() {
              this.FolderCard(item)
            }
          }, (item: UserShareFolderItem) => `${item.path}_${item.name}_${item.allowDownload}_${item.exists}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .margin({ top: 12 })
      }
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .opacity(this.themeTick >= 0 ? 1 : 1)
  }

  /** 文字+图标按钮（对齐 Flutter CustomButton text+icon；leftMargin 为左侧间距） */
  @Builder
  TextButton(icon: Resource, label: string, onTap: () => void, leftMargin: number) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(15)
        .fontColor([this.palette().primary])
      Text(label)
        .fontSize(13)
        .fontColor(this.palette().primary)
        .maxLines(1)
    }
    .margin({ left: leftMargin })
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .borderRadius(10)
    .border({ width: 1, color: this.palette().divider })
    .onClick(() => {
      onTap();
    })
  }

  /** 共享目录卡片（对齐 ListTile 行） */
  @Builder
  FolderCard(item: UserShareFolderItem) {
    GlassCard({
      padValue: 12
    }) {
      Row({ space: 12 }) {
        if (this.isMissing(item)) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
            .fontSize(22)
            .fontColor([this.palette().error])
        } else {
          Image($rawfile('icons/file/folder_share.png'))
            .width(22)
            .height(22)
            .objectFit(ImageFit.Contain)
            .draggable(false)
        }

        Column() {
          Text(item.name.length > 0 ? item.name : this.basename(item.path))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.isMissing(item)
            ? `${item.path}\n${L10n.t('user_share_folders_missing', '目录不存在或不可用')}`
            : item.path)
            .fontSize(12)
            .fontColor(this.isMissing(item) ? this.palette().error : this.palette().subText)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
            .width('100%')
          Row({ space: 8 }) {
            Text(L10n.t('allow_download', '允许下载'))
              .fontSize(12)
              .fontColor(this.palette().subText)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: item.allowDownload })
              .selectedColor(this.palette().primary)
              .enabled(this.isAdmin())
              .onChange((on: boolean) => {
                if (!this.isAdmin()) {
                  return;
                }
                void this.ctrl.setUserShareAllowDownload(item.path, on);
              })
          }
          .width('100%')
          .margin({ top: 8 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.isAdmin()) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontColor([this.palette().subText])
            .padding(4)
            .onClick(() => {
              this.removeFolder(item.path);
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
  }
}
