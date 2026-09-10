/**
 * 媒体工具模块路由（对齐 Flutter mediaTool 模块移动端结构：
 * 入口 AppMediaToolEntryView + 各子工具 AppMediaToolSubPage）。
 */

/** 媒体工具模块页面名常量（主线程 AppRouter 接线用） */
export class MediaToolRoutes {
  /** 媒体工具入口（分组菜单页，对齐 AppMediaToolEntryView） */
  static readonly MEDIA_TOOL_ENTRY: string = 'MediaToolEntryPage';
  /** 图片压缩转换（对齐 pageKey: image.compress） */
  static readonly IMAGE_COMPRESS: string = 'MediaToolImageCompressPage';
  /** 图片批量压缩任务（对齐 pageKey: image.batch_compress） */
  static readonly IMG_BATCH_COMPRESS: string = 'MediaToolImgBatchCompressPage';
  /** 视频转换任务（对齐 pageKey: video.trans） */
  static readonly VIDEO_TRANS: string = 'MediaToolVideoTransPage';
  /** 音频转换任务（对齐 pageKey: audio.trans） */
  static readonly AUDIO_TRANS: string = 'MediaToolAudioTransPage';
  /** 媒体整理任务（对齐 pageKey: other.media_arrange） */
  static readonly MEDIA_ARRANGE: string = 'MediaToolMediaArrangePage';
}

/** 媒体工具入口页参数（页面无入参，保留空类以对齐路由接线惯例） */
export class MediaToolEntryPageParam {
}

/** 图片压缩转换页参数 */
export class MediaToolImageCompressPageParam {
}

/** 图片批量压缩页参数 */
export class MediaToolImgBatchCompressPageParam {
}

/** 视频转换页参数 */
export class MediaToolVideoTransPageParam {
}

/** 音频转换页参数 */
export class MediaToolAudioTransPageParam {
}

/** 媒体整理页参数 */
export class MediaToolMediaArrangePageParam {
}
