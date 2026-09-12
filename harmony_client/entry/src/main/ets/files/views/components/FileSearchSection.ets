import { AppTheme } from '../../../core/theme/AppTheme';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { L10n } from '../../../core/localization/L10n';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { FileController } from '../../controllers/FileController';
import { showFileSearchOptionsSheet } from '../FileSheets';

/**
 * 文件搜索栏（通用组件，对齐 Flutter app_file_search_bar）：
 * 搜索输入 + 搜索选项按钮 + 作用域/类型筛选 chips。
 */
@ComponentV2
export struct FileSearchSection {
  @Param ctrl: FileController = new FileController(false);

  private hasSearchState(): boolean {
    return this.ctrl.searchQuery.trim().length > 0 ||
      this.ctrl.searchScope !== 'current' ||
      this.ctrl.filterType !== 'all';
  }

  private scopeLabel(): string {
    const scope = this.ctrl.searchScope;
    if (scope === 'subtree') {
      return L10n.t('file_search_scope_current_dir_subtree', '当前目录及子目录');
    }
    if (scope === 'global') {
      return L10n.t('file_search_scope_global', '全局搜索');
    }
    return L10n.t('file_search_scope_current_dir', '当前目录');
  }

  private filterLabel(): string {
    switch (this.ctrl.filterType) {
      case 'dir':
        return L10n.t('dir', '文件夹');
      case 'document':
        return L10n.t('folder_filter_document', '文档');
      case 'video':
        return L10n.t('folder_filter_video', '视频');
      case 'audio':
        return L10n.t('folder_filter_audio', '音频');
      case 'image':
        return L10n.t('folder_filter_image', '图片');
      case 'archive':
        return L10n.t('folder_filter_archive', '压缩包');
      case 'file':
        return L10n.t('file', '文件');
      default:
        return L10n.t('all', '全部');
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        SearchInputBar({
          hintText: L10n.t('folder_search_placeholder', '搜索'),
          text: this.ctrl.searchQuery,
          onChanged: (v: string): void => {
            this.ctrl.setSearchQuery(v);
          },
          onClear: (): void => {
            this.ctrl.setSearchQuery('');
          }
        })
          .layoutWeight(1)
        if (this.ctrl.globalSearchLoading) {
          Column() {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(AppTheme.current().primary)
          }
          .width(36)
          .height(36)
          .borderRadius(10)
          .border({ width: 1, color: AppTheme.current().primary })
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().primary, 0.12))
        } else {
          BorderedIconButton({
            icon: $r('sys.symbol.slider_horizontal_2'),
            fillColor: this.hasSearchState() ?
              AppTheme.withAlpha(AppTheme.current().primary, 0.12) : '',
            onTap: (): void => {
              showFileSearchOptionsSheet(this.ctrl);
            }
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.hasSearchState()) {
        Column({ space: 8 }) {
          this.SearchChip(this.scopeLabel(), this.ctrl.globalSearchLoading && this.ctrl.searchScope !== 'current')
          this.SearchChip(this.filterLabel(), false)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 8 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 4, bottom: 10 })
  }

  @Builder
  SearchChip(label: string, loading: boolean) {
    Row({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontColor(AppTheme.current().onSurface)
      if (loading) {
        LoadingProgress()
          .width(14)
          .height(14)
          .color(AppTheme.current().primary)
      }
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .borderRadius(999)
    .border({ width: 1, color: AppTheme.current().divider })
    .backgroundColor(AppTheme.current().surfaceBg)
    .onClick((): void => {
      showFileSearchOptionsSheet(this.ctrl);
    })
  }
}
