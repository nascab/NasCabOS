import { hilog } from '@kit.PerformanceAnalysisKit';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { FileController } from '../controllers/FileController';
import { AppImage } from '../../../common/components/AppImage';

/**
 * 文件缩略图（对齐 Flutter AppFileThumb）：
 * 本地类型图标常驻底层；图片/视频/raw → 网络缩略图覆盖在上层；视频叠加播放角标。
 * 网络图统一走 AppImage（与 video 模块 VideoCoverImage 一致）：Bearer 下载、磁盘/内存缓存、
 * 同 URL 去重；/api/file/tiny 服务端异步生成（>100MB 视频/慢 IO 转 worker，单帧最长 180s）
 * 返回 404/202 时由 AppImageLoader 在传输层持续轮询（202 最长 180s），组件销毁仍后台落盘，
 * 解决大视频缩略图首次访问在文件浏览器永远加载不出来的问题。
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
  private resolveSeq: number = 0;

  aboutToAppear(): void {
    void this.resolveTiny();
  }

  /** 列表复用导致条目变化时重新解析缩略图 URL */
  @Monitor('path', 'name', 'type', 'virtualType', 'isCustomPath')
  onSourceChange(): void {
    this.tinyUrl = '';
    void this.resolveTiny();
  }

  private isNetworkKind(): boolean {
    if (this.virtualType === 'custom_add' || this.isCustomPath) {
      return false;
    }
    return FileController.iconFor(this.name, this.path, this.type) === 'tiny';
  }

  private async resolveTiny(): Promise<void> {
    const seq = ++this.resolveSeq;
    if (!this.isNetworkKind()) {
      return;
    }
    try {
      const url = await ApiUrls.getTinyUrl(this.path, Math.max(256, Math.round(this.thumbSize * 2)));
      if (seq === this.resolveSeq) {
        this.tinyUrl = url;
        hilog.info(0x8801, 'TinyThumb', 'FileThumb request tiny for type=%{public}s path=%{public}s',
          this.type, this.path);
      }
    } catch (_e) {
      if (seq === this.resolveSeq) {
        this.tinyUrl = '';
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 本地类型图标常驻底层：网络缩略图未就绪/202 异步生成期间直接露出视频/文件图标，
      // 缩略图加载成功后由上层 AppImage 覆盖（loadingTransparent，等待中不显示灰块）
      Image(this.localIcon())
        .width(this.thumbSize)
        .height(this.thumbSize)
        .objectFit(ImageFit.Contain)
        .draggable(false)
      if (this.tinyUrl.length > 0) {
        AppImage({
          url: this.tinyUrl,
          objectFit: ImageFit.Cover,
          imageRadius: 10,
          showLoadingSpin: false,
          loadingTransparent: true
        })
          .width(this.thumbSize)
          .height(this.thumbSize)
      }
      // 对齐 Flutter AppFileThumb：视频始终叠加播放角标（缩略图加载中也显示）
      if (this.type === 'video') {
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
    const icon = FileController.iconFor(this.name, this.path, this.type);
    if (icon === 'tiny') {
      // 网络缩略图未就绪时的底层占位：视频用视频图标，图片/raw 用通用文件图标
      return this.type === 'video' ? $rawfile('icons/file/video.png') : $rawfile('icons/file/file.png');
    }
    return $rawfile(icon);
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
