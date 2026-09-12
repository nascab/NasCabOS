import { AppTheme } from '../../../core/theme/AppTheme';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { L10n } from '../../../core/localization/L10n';
import { DialogUtil } from '../../../common/DialogUtil';
import { FileController } from '../../controllers/FileController';
import { showFileFilterSheet, showFileSortSheet } from '../FileSheets';

/**
 * 文件视图工具栏（通用组件，对齐 Flutter app_file_toolbar）：
 * 排序按钮（最近模块为清除记录）+ 显示隐藏 + 类型筛选 + 视图模式循环切换。
 */
@ComponentV2
export struct FileViewToolbar {
  @Param ctrl: FileController = new FileController(false);
  /** 视图按钮点击回调：传入时执行回调（如 folder_view 弹出视图选择 sheet），缺省循环切换 */
  @Param onViewPressed: (() => void) | undefined = undefined;

  private sortLabel(): string {
    switch (this.ctrl.sortMode) {
      case 'name_asc':
        return L10n.t('folder_picker_sort_name_asc', '名称升序');
      case 'name_desc':
        return L10n.t('folder_picker_sort_name_desc', '名称降序');
      case 'size_asc':
        return L10n.t('folder_picker_sort_size_asc', '大小升序');
      case 'size_desc':
        return L10n.t('folder_picker_sort_size_desc', '大小降序');
      case 'type_asc':
        return L10n.t('folder_picker_sort_type_asc', '类型升序');
      case 'type_desc':
        return L10n.t('folder_picker_sort_type_desc', '类型降序');
      case 'mtime_asc':
        return L10n.t('folder_picker_sort_mtime_asc', '修改时间升序');
      case 'mtime_desc':
      default:
        return L10n.t('folder_picker_sort_mtime_desc', '修改时间降序');
    }
  }

  private viewIcon(): Resource {
    switch (this.ctrl.viewMode) {
      case 'list':
        return $r('sys.symbol.list_bullet');
      // 大图标模式用 2x2 疏格，普通网格用通用网格线，与 Flutter grid_view/grid_on 对应
      case 'large_grid':
        return $r('sys.symbol.square_grid_2x2');
      case 'grid':
      default:
        return $r('sys.symbol.grid');
    }
  }

  private async clearRecentConfirm(): Promise<void> {
    const confirmed = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('recent_clear_confirm', '确定要清除最近访问记录吗？'));
    if (confirmed === true) {
      const ok = await this.ctrl.clearRecent();
      if (!ok) {
        DialogUtil.showErrorDialog(L10n.operationFailed);
      }
    }
  }

  build() {
    Row() {
      // 排序 / 清除最近
      Row({ space: 4 }) {
        if (this.ctrl.currentModule === 'recent') {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontColor([AppTheme.current().subText])
        }
        Text(this.ctrl.currentModule === 'recent' ?
          L10n.t('recent_clear', '清除记录') : this.sortLabel())
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
        if (this.ctrl.currentModule !== 'recent') {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(18)
            .fontColor([AppTheme.current().subText])
        }
      }
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .borderRadius(10)
      .onClick((): void => {
        if (this.ctrl.currentModule === 'recent') {
          void this.clearRecentConfirm();
          return;
        }
        showFileSortSheet(this.ctrl);
      })
      Blank()
      BorderedIconButton({
        icon: this.ctrl.showHidden ? $r('sys.symbol.eye') : $r('sys.symbol.eye_slash'),
        onTap: (): void => {
          void this.ctrl.toggleShowHidden();
        }
      })
      BorderedIconButton({
        icon: $r('sys.symbol.slider_horizontal_2'),
        active: this.ctrl.filterType !== 'all',
        onTap: (): void => {
          showFileFilterSheet(this.ctrl);
        }
      })
        .margin({ left: 10 })
      BorderedIconButton({
        icon: this.viewIcon(),
        onTap: (): void => {
          if (this.onViewPressed) {
            this.onViewPressed();
            return;
          }
          const modes: string[] = ['grid', 'large_grid', 'list'];
          const idx = modes.indexOf(this.ctrl.viewMode);
          this.ctrl.setViewMode(modes[(idx + 1) % modes.length]);
        }
      })
        .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }
}
