import { ApiUrls } from '../../core/network/ApiUrls';
import { FileController } from '../controllers/FileController';

/**
 * 文件缩略图（对齐 Flutter AppFileThumb）：
 * 图片/视频/raw → 网络缩略图；其余 → 本地类型图标；视频叠加播放角标。
 */
@ComponentV2
export struct FileThumb {
  @Param name: string = '';
  @Param type: string = '';
  @Param path: string = '';
  @Param thumbSize: number = 80;
  @Param virtualType: string = '';
  @Param isCustomPath: boolean = false;
  @Local tinyUrl: string = '';

  aboutToAppear(): void {
    void this.resolveTiny();
  }

  private isNetworkKind(): boolean {
    if (this.virtualType === 'custom_add' || this.isCustomPath) {
      return false;
    }
    return FileController.iconFor(this.name, this.path, this.type) === 'tiny';
  }

  private async resolveTiny(): Promise<void> {
    if (!this.isNetworkKind()) {
      return;
    }
    try {
      const url = await ApiUrls.getTinyUrl(this.path, Math.max(256, Math.round(this.thumbSize * 2)));
      this.tinyUrl = url;
    } catch (_e) {
      this.tinyUrl = '';
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.tinyUrl.length > 0) {
        Image(this.tinyUrl)
          .width(this.thumbSize)
          .height(this.thumbSize)
          .borderRadius(10)
          .objectFit(ImageFit.Cover)
          .alt($rawfile('icons/file/file.png'))
          .draggable(false)
      } else {
        Image(this.localIcon())
          .width(this.thumbSize)
          .height(this.thumbSize)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      }
      if (this.type === 'video' && (this.tinyUrl.length > 0 || this.isNetworkKind())) {
        this.PlayOverlay()
      }
    }
  }

  private localIcon(): Resource {
    if (this.virtualType === 'custom_add') {
      return $rawfile('icons/file/folder_add.png');
    }
    if (this.isCustomPath && this.type === 'dir') {
      return $rawfile('icons/file/folder_custom.png');
    }
    return $rawfile(FileController.iconFor(this.name, this.path, this.type));
  }

  @Builder
  PlayOverlay() {
    Column() {
      SymbolGlyph($r('sys.symbol.play_fill'))
        .fontSize(Math.max(14, this.thumbSize * 0.28 * 0.78))
        .fontColor(['#FFFFFF'])
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width(this.thumbSize * 0.28)
    .height(this.thumbSize * 0.28)
    .borderRadius(this.thumbSize * 0.14)
    .backgroundColor('#99000000')
  }
}
