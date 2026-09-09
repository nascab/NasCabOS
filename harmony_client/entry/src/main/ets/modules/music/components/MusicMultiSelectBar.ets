import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';

/**
 * 音乐多选底部操作栏（对齐 Flutter MusicListMultiSelectBottomBar）：
 * 全选/反选 + 已选数量 + 收藏/下载/删除/加入歌单/移出歌单/退出多选。
 * 列表页与子列表页共用（回调驱动，不绑定控制器类型）。
 */
@ComponentV2
export struct MusicMultiSelectBar {
  @Param selectedCount: number = 0;
  @Param allSelected: boolean = false;
  @Param allFavorited: boolean = false;
  @Param isInPlayList: boolean = false;
  @Param onSelectAll: () => void = (): void => {
  };
  @Param onToggleFavorite: () => void = (): void => {
  };
  @Param onDownload: () => void = (): void => {
  };
  @Param onDelete: () => void = (): void => {
  };
  @Param onAddToPlayList: () => void = (): void => {
  };
  @Param onRemoveFromPlayList: () => void = (): void => {
  };
  @Param onCancel: () => void = (): void => {
  };

  private disabled(): boolean {
    return this.selectedCount <= 0;
  }

  @Builder
  private BarAction(icon: Resource, label: string, danger: boolean, enabled: boolean, onTap: () => void) {
    Column({ space: 2 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([enabled ? (danger ? '#E53935' : AppTheme.current().onSurface) : AppTheme.withAlpha(AppTheme.current().onSurface, 0.35)])
      Text(label)
        .fontSize(10)
        .fontColor(enabled ? (danger ? '#E53935' : AppTheme.current().subText) : AppTheme.withAlpha(AppTheme.current().onSurface, 0.35))
        .maxLines(1)
    }
    .padding({ left: 7, right: 7 })
    .onClick(() => {
      if (enabled) {
        onTap();
      }
    })
  }

  build() {
    Row() {
      Row({ space: 6 }) {
        // 复选框（方形，对齐 CustomCheckbox isCircle:false）
        Stack() {
          if (this.allSelected) {
            SymbolGlyph($r('sys.symbol.checkmark_square_fill'))
              .fontSize(20)
              .fontColor([AppTheme.current().primary])
          } else {
            SymbolGlyph($r('sys.symbol.checkmark_square'))
              .fontSize(20)
              .fontColor([AppTheme.current().hint])
          }
        }
        .width(24)
        .height(24)
        .onClick(() => {
          this.onSelectAll();
        })

        Text(this.allSelected ? L10n.t('timeline_deselect_all') : L10n.t('timeline_select_all'))
          .fontSize(13)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => {
            this.onSelectAll();
          })
        Text(`${this.selectedCount} ${L10n.t('selected')}`)
          .fontSize(13)
          .fontColor(AppTheme.current().subText)
          .maxLines(1)
          .margin({ left: 6 })
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      Row() {
        this.BarAction(this.allFavorited ? $r('sys.symbol.heart') : $r('sys.symbol.heart_fill'),
          this.allFavorited ? L10n.t('unfavorite') : L10n.t('favorites'), false, !this.disabled(),
          (): void => {
            this.onToggleFavorite();
          })
        this.BarAction($r('sys.symbol.download'), L10n.t('download'), false, !this.disabled(),
          (): void => {
            this.onDownload();
          })
        this.BarAction($r('sys.symbol.trash_fill'), L10n.t('delete'), true, !this.disabled(),
          (): void => {
            this.onDelete();
          })
        this.BarAction($r('sys.symbol.music_note_list'), L10n.t('add_to_play_list'), false, !this.disabled(),
          (): void => {
            this.onAddToPlayList();
          })
        if (this.isInPlayList) {
          this.BarAction($r('sys.symbol.xmark'), L10n.t('remove_from_play_list'), false, !this.disabled(),
            (): void => {
              this.onRemoveFromPlayList();
            })
        }
        this.BarAction($r('sys.symbol.xmark'), L10n.t('cancel'), false, true,
          (): void => {
            this.onCancel();
          })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 8 })
    .border({ width: { top: 1 }, color: AppTheme.current().divider })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}
