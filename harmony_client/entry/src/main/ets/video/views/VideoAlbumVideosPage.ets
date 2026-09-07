import { L10n } from '../../core/localization/L10n';
import { VideoAlbumVideosPageParam, VideoListPageParam } from '../router/VideoRoutes';
import { VideoListPage } from './VideoListPage';

/**
 * 相册视频列表页（对齐 Flutter AppVideoAlbumVideosPage）：
 * 自建相册/智能相册/照片合集的视频列表，带"名称-类型"标题栏；
 * 直接复用 VideoListPage（其内部已含标题栏与工具栏）。
 */
@ComponentV2
export struct VideoAlbumVideosPage {
  @Param param: VideoAlbumVideosPageParam = new VideoAlbumVideosPageParam();
  @Param popPage: () => void = (): void => {
  };

  /** 导航标题：名称-类型后缀（对齐 _navTitle） */
  private navTitle(): string {
    const suffix = this.param.albumId > 0
      ? L10n.t('video_custom_album_title', '自建相册')
      : (this.param.collectionId > 0
        ? L10n.t('video_collection_title', '照片合集')
        : (this.param.smartAlbumId > 0 ? L10n.t('video_smart_album_title', '智能相册')
          : L10n.t('video_menu_albums', '相册')));
    return `${this.param.title}-${suffix}`;
  }

  private listParam(): VideoListPageParam {
    const p = new VideoListPageParam();
    p.title = this.navTitle();
    p.initialMediaType = '';
    p.listType = '';
    p.albumId = this.param.albumId;
    p.smartAlbumId = this.param.smartAlbumId;
    p.collectionId = this.param.collectionId;
    return p;
  }

  build() {
    VideoListPage({
      param: this.listParam(),
      popPage: (): void => {
        this.popPage();
      }
    })
  }
}
