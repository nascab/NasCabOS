import { TimelinePhotoItem } from '../../photo/models/PhotoModels';

/**
 * 图片浏览器条目（对齐 Flutter CustomGalleryController galleryItems 的 Map 字段）。
 * url / liveVideoUrl 由控制器 configure 时异步构建。
 */
@ObservedV2
export class GalleryItem {
  type: string = 'image';
  path: string = '';
  name: string = '';
  photoId: number = 0;
  width: number = 0;
  height: number = 0;
  isLvp: number = 0;
  isMergeLvp: number = 0;
  liveFilename: string = '';
  rawFilename: string = '';
  fileHash: string = '';
  @Trace url: string = '';
  /** Live Photo 视频 URL（空表示非 Live Photo 或无视频文件） */
  @Trace liveVideoUrl: string = '';
}

/** 图片浏览器页参数（对齐 Flutter Get.to CustomGallery 前的控制器配置） */
export class GalleryPageParam {
  items: GalleryItem[] = [];
  initialIndex: number = 0;
  showInfo: boolean = true;
  /** 删除成功后回调（photoId），timeline 同步移除 */
  onDeleted?: (photoId: number) => void;
}

/** TimelinePhotoItem → GalleryItem（对齐 Flutter photo_timeline_media openMedia 图片映射） */
export function galleryItemFromTimelinePhoto(p: TimelinePhotoItem): GalleryItem {
  const it = new GalleryItem();
  it.type = 'image';
  it.path = p.fullpath;
  it.name = p.filename;
  it.photoId = p.id;
  it.width = p.width;
  it.height = p.height;
  it.isLvp = p.isLvp;
  it.isMergeLvp = p.isMergeLvp;
  it.liveFilename = p.liveFilename;
  it.rawFilename = p.rawFilename;
  it.fileHash = p.fileHash;
  return it;
}
