import { PageScaffold } from '../../../common/PageScaffold';
import { TimelineController } from '../../controllers/TimelineController';
import { PhotoTimelineView } from './PhotoTimelineView';
import { PhotoMultiSelectBar } from './PhotoMultiSelectBar';

/** 照片时间线路由页参数（对齐 Flutter AppPhotoTimelineRoutePage） */
export class PhotoTimelinePageParam {
  title: string = '';
  listType: string = 'timeline';
  albumId: number = 0;
  collectionId: number = 0;
  smartAlbumId: number = 0;
  faceId: number = 0;
  placeName: string = '';
  loadTheDay: boolean = false;
  geohash: string = '';
  year: number = 0;
}

/**
 * 照片时间线独立路由页（收藏/那年今天/相册/合集/智能相册/人脸/地点/附近照片均复用此页）：
 * AppBar + 时间线视图 + 多选底部操作栏。
 */
@ComponentV2
export struct PhotoTimelinePage {
  @Param param: PhotoTimelinePageParam = new PhotoTimelinePageParam();
  @Param popPage: () => void = (): void => {
  };
  private ctrl: TimelineController = new TimelineController();

  aboutToAppear(): void {
    this.ctrl.configure(
      this.param.listType,
      this.param.albumId,
      this.param.collectionId,
      this.param.smartAlbumId,
      this.param.faceId,
      this.param.placeName,
      this.param.loadTheDay,
      this.param.geohash,
      this.param.year,
      true);
    void this.ctrl.refreshTimeline();
  }

  build() {
    PageScaffold({
      title: this.param.title,
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.PageContent()
      }
    })
  }

  @Builder
  PageContent() {
    Column() {
      PhotoTimelineView({ ctrl: this.ctrl, showSearchAction: true })
        .layoutWeight(1)
      if (this.ctrl.isMultiSelectMode) {
        PhotoMultiSelectBar({ ctrl: this.ctrl })
      }
    }
    .width('100%')
    .height('100%')
  }
}
