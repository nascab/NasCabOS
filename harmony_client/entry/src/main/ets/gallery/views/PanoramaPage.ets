import { webview } from '@kit.ArkWeb';
import { L10n } from '../../core/localization/L10n';
import { PanoramaPageParam } from './GalleryPage';

/**
 * 全景图查看页（对齐 Flutter PanoramaGalleryPage）：
 * 全屏黑底查看等距柱状全景图，拖动环绕浏览；左上角关闭按钮。
 * 渲染使用本地 resource://rawfile/gallery/panorama.html（无外部依赖）。
 */
@ComponentV2
export struct PanoramaPage {
  @Param param: PanoramaPageParam = new PanoramaPageParam();
  @Param popPage: () => void = (): void => {
  };
  private webController: webview.WebviewController = new webview.WebviewController();

  build() {
    NavDestination() {
      Stack() {
        Web({ src: 'resource://rawfile/gallery/panorama.html', controller: this.webController })
          .width('100%')
          .height('100%')
          .backgroundColor('#000000')
          .javaScriptAccess(true)
          .zoomAccess(false)
          .onPageEnd((): void => {
            try {
              this.webController.runJavaScript(
                `initPano(${JSON.stringify(this.param.imageUrl)});`);
            } catch (_e) {
              // 页面未就绪时忽略
            }
          })

        // 左上角关闭按钮（SafeArea 12/12，对齐 Flutter）
        Column() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(24)
            .fontColor(['#FFFFFF'])
        }
        .justifyContent(FlexAlign.Center)
        .width(44)
        .height(44)
        .margin({ left: 12, top: 12 })
        .onClick((): void => {
          this.popPage();
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
    }
    .hideTitleBar(true)
    .backgroundColor('#000000')
    .onBackPressed((): boolean => {
      this.popPage();
      return true;
    })
  }
}
