import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';

/**
 * 图书多选底部操作栏（对齐 Flutter AppBookMultiSelectBar 移动端 65 高）：
 * 4 个动作（图标+文字列）：删除（红）/ 收藏切换 / 加入书单 或 从书单移除。
 */
@ComponentV2
export struct BookMultiSelectBar {
  /** 已选数量 */
  @Param selectedCount: number = 0;
  /** 处于自建书单上下文：第 3 个动作变为“移出书单” */
  @Param inCustomList: boolean = false;
  /** 全部已选均为收藏时显示“取消收藏” */
  @Param allFavorited: boolean = false;
  @Param onDelete: () => void = (): void => {
  };
  @Param onToggleFavorite: () => void = (): void => {
  };
  @Param onAddToList: () => void = (): void => {
  };
  @Param onRemoveFromList: () => void = (): void => {
  };

  @Builder
  ActionItem(icon: Resource, label: string, danger: boolean, onTap: () => void) {
    Column({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([danger ? AppTheme.current().error : AppTheme.current().onSurface])
      Text(label)
        .fontSize(11)
        .fontColor(danger ? AppTheme.current().error : AppTheme.current().onSurface)
        .maxLines(1)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      onTap();
    })
  }

  build() {
    Row() {
      this.ActionItem($r('sys.symbol.trash'), L10n.t('delete', '删除'), true, (): void => {
        this.onDelete();
      })
      this.ActionItem(this.allFavorited ? $r('sys.symbol.heart_slash') : $r('sys.symbol.heart'),
        this.allFavorited ? L10n.t('unfavorite', '取消收藏') : L10n.t('favorites', '收藏'), false, (): void => {
        this.onToggleFavorite();
      })
      if (this.inCustomList) {
        this.ActionItem($r('sys.symbol.minus_circle'), L10n.t('remove_from_book_list', '移出书单'), false, (): void => {
          this.onRemoveFromList();
        })
      } else {
        this.ActionItem($r('sys.symbol.plus_circle'), L10n.t('add_to_book_list', '添加到书单'), false, (): void => {
          this.onAddToList();
        })
      }
    }
    .width('100%')
    .height(65)
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}
