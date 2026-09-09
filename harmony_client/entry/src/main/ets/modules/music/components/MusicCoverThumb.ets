import { ApiUrls } from '../../../core/network/ApiUrls';
import { AppImage } from '../../../common/components/AppImage';

/**
 * 音乐封面缩略图（行/卡片通用）：无内嵌封面或加载失败时按流派/种子回退到本地封面图。
 * 对齐 Flutter _CoverThumb / _pickFallbackCoverAsset 行为。
 */
@ComponentV2
export struct MusicCoverThumb {
  @Param filePath: string = '';
  @Param hasInnerCover: number = 0;
  @Param genre: string = '';
  @Param seedId: number = 0;
  @Param boxSize: number = 46;
  @Param radius: number = 8;

  @Local private url: string = '';
  private coverToken: number = 0;

  aboutToAppear(): void {
    this.resolve();
  }

  @Monitor('filePath')
  onFilePathChange(): void {
    this.resolve();
  }

  private resolve(): void {
    const p = this.filePath.trim();
    if (p.length === 0 || this.hasInnerCover !== 1) {
      this.url = '';
      return;
    }
    const token = ++this.coverToken;
    ApiUrls.getMusicCoverUrl(p, 120).then((u: string): void => {
      if (token !== this.coverToken) {
        return;
      }
      this.url = u;
    }).catch((_e: Object): void => {
      if (token === this.coverToken) {
        this.url = '';
      }
    });
  }

  private fallbackAsset(): string {
    // 对齐 Flutter _pickFallbackCoverAsset：流派前 6 张，否则 other 1-20
    const raw = this.genre.trim().toLowerCase();
    const parts = raw.split(/[\/,;|]/).map((e: string): string => e.trim());
    const head = parts.length > 0 ? parts[0] : '';
    const normalized = head.replace(/[^a-z0-9]/g, '');
    const genres = ['blues', 'classical', 'country', 'gospel', 'hiphop', 'pop', 'rock'];
    const id = Math.abs(this.seedId);
    if (normalized.length > 0 && genres.indexOf(normalized) >= 0) {
      const idx = (id % 6) + 1;
      return `music/covers/${normalized}${idx}.jpg`;
    }
    const idx = (id % 20) + 1;
    return `music/covers/other${idx}.jpg`;
  }

  build() {
    Stack() {
      if (this.url.length > 0) {
        AppImage({ url: this.url, showLoadingSpin: false })
      } else {
        Image($rawfile(this.fallbackAsset()))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      }
    }
    .width(this.boxSize)
    .height(this.boxSize)
    .borderRadius(this.radius)
    .clip(true)
  }
}
