import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { FileController } from '../../controllers/FileController';
import { showFileMoreSheet } from '../FileSheets';

/**
 * 文件多选操作栏（通用组件，对齐 Flutter app_file_multi_select_bar）：
 * 收藏 / 下载 / 删除 / 更多 / 取消。
 */
@ComponentV2
export struct FileMultiSelectBarView {
  @Param ctrl: FileController = new FileController(false);

  private async confirmDeleteSelected(): Promise<void> {
    const count = `${this.ctrl.selected.length}`;
    const content = L10n.t('folder_delete_confirm', '确定删除这 @fileCount 项吗？',
      L10n.paramsOf('fileCount', count));
    if (this.ctrl.shellSupported) {
      await DialogUtil.showConfirmThreeButtonsDialog(
        L10n.t('need_confirm', '需要确认'),
        content,
        (): void => {
          void this.ctrl.deleteSelectedEntries(false);
        },
        (): void => {
          void this.ctrl.deleteSelectedEntries(true);
        },
        L10n.cancel,
        L10n.t('delete', '删除'),
        L10n.t('put_in_recycle_bin', '放入回收站'));
    } else {
      const confirmed = await DialogUtil.showConfirmDialog(
        L10n.t('need_confirm', '需要确认'), content);
      if (confirmed === true) {
        await this.ctrl.deleteSelectedEntries(false);
      }
    }
  }

  build() {
    Row() {
      this.MultiSelectAction(
        this.ctrl.currentModule === 'favorites' ? $r('sys.symbol.star') : $r('sys.symbol.star_fill'),
        this.ctrl.currentModule === 'favorites' ?
          L10n.t('unfavorite', '取消收藏') : L10n.t('folder_add_favorite', '添加到收藏'),
        this.ctrl.selected.length > 0, false, (): void => {
          const inFav = this.ctrl.currentModule === 'favorites';
          const paths = this.ctrl.getSelected();
          if (paths.length === 0) {
            return;
          }
          const fut = inFav ? this.ctrl.removeFavorites(paths) : this.ctrl.addFavorites(paths);
          void fut.then((ok: boolean): void => {
            ToastUtil.show(ok ? L10n.t('operation_success', '操作成功') : L10n.operationFailed);
            this.ctrl.clearSelect();
          });
        })
      this.MultiSelectAction(
        $r('sys.symbol.square_and_arrow_down'),
        L10n.t('download', '下载'),
        this.ctrl.selected.length > 0, false, (): void => {
          // 下载依赖传输模块（未迁移）
          ToastUtil.show(L10n.featureComingSoon);
        })
      this.MultiSelectAction(
        $r('sys.symbol.trash'),
        L10n.t('delete', '删除'),
        this.ctrl.selected.length > 0, true, (): void => {
          void this.confirmDeleteSelected();
        })
      this.MultiSelectAction(
        $r('sys.symbol.more'),
        L10n.t('more', '更多'),
        this.ctrl.selected.length > 0, false, (): void => {
          showFileMoreSheet(this.ctrl);
        })
      Divider()
        .vertical(true)
        .height(36)
        .color(AppTheme.current().divider)
      Column({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(22)
          .fontColor([AppTheme.current().onSurface])
        Text(L10n.cancel)
          .fontSize(10)
          .fontColor(AppTheme.current().onSurface)
      }
      .justifyContent(FlexAlign.Center)
      .width(64)
      .padding({ top: 6, bottom: 6 })
      .onClick((): void => {
        this.ctrl.exitMultiSelectMode();
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
    .shadow({ radius: 12, color: '#1A000000', offsetY: -2 })
    // 多选栏同样延伸到底部安全区，保持与 tab 栏一致的底色
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  MultiSelectAction(icon: Resource, label: string, enabled: boolean, danger: boolean, onTap: () => void) {
    Column({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([enabled ? (danger ? '#E53935' : AppTheme.current().onSurface) : AppTheme.current().hint])
      Text(label)
        .fontSize(10)
        .fontColor(enabled ? (danger ? '#E53935' : AppTheme.current().onSurface) : AppTheme.current().hint)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .padding({ top: 6, bottom: 6 })
    .onClick((): void => {
      if (enabled) {
        onTap();
      }
    })
  }
}
