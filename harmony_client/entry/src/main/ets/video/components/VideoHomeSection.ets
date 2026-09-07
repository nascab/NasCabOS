import { AppTheme } from '../../core/theme/AppTheme';
import { VideoHomeItemBean } from '../models/VideoModels';
import { VideoListController } from '../controllers/VideoListController';
import { VideoItemPoster } from './VideoItemPoster';

/**
 * 首页横向海报区块（对齐 Flutter _AppVideoHorizontalSection）：
 * 标题行（标题 + 右箭头，可点击跳列表）+ 横向滚动海报行，
 * 海报宽度 = 屏宽/3 × 海报缩放记忆，高度含文字区 54。
 */
@ComponentV2
export struct VideoHomeSection {
  @Param title: string = '';
  @Param items: VideoHomeItemBean[] = [];
  @Param showProgress: boolean = false;
  @Param onTapTitle: () => void = (): void => {
  };
  @Param onDeleted: (item: VideoHomeItemBean) => void = (_item: VideoHomeItemBean): void => {
  };
  @Param onFavoriteChanged: (item: VideoHomeItemBean, isFav: boolean) => void =
    (_item: VideoHomeItemBean, _isFav: boolean): void => {
    };
  @Local sectionWidth: number = 0;

  private posterWidth(): number {
    const width = this.sectionWidth > 0 ? this.sectionWidth : 360;
    const padding = 16;
    const spacing = 10;
    const baseItemWidth = (width - padding * 2 - spacing * 2) / 3;
    VideoListController.ensureSharedPosterScaleLoaded();
    return baseItemWidth * VideoListController.sharedPosterScale;
  }

  build() {
    Column() {
      // 标题行（可点击）
      Row({ space: 15 }) {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.65)])
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 14, bottom: 10 })
      .onClick(() => {
        this.onTapTitle();
      })

      // 横向海报行
      Scroll() {
        Row({ space: 10 }) {
          ForEach(this.items, (item: VideoHomeItemBean) => {
            Column() {
              VideoItemPoster({
                item: item,
                progress: this.showProgress ? item.progress : 0,
                onDeleted: (deleted: VideoHomeItemBean): void => {
                  this.onDeleted(deleted);
                },
                onFavoriteChanged: (isFav: boolean): void => {
                  this.onFavoriteChanged(item, isFav);
                }
              })
            }
            .width(this.posterWidth())
            .alignItems(HorizontalAlign.Center)
          }, (item: VideoHomeItemBean) => `${item.id}_${item.isFavorite ? 1 : 0}`)
        }
        .alignItems(VerticalAlign.Top)
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(this.posterWidth() * 1.5 + 54)
      .onAreaChange((_o: Area, n: Area) => {
        this.sectionWidth = Number(n.width);
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
