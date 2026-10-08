import { PlayerPlaylistItem } from '../models/PlayerModels';

/**
 * 视频播放器页路由参数（对齐 Flutter AppVideoPlayerPage 构造参数 + toVideoPlayer args）。
 */
export class VideoPlayerPageParam {
  playlist: PlayerPlaylistItem[] = [];
  initialIndex: number = 0;
  /** info 请求是否忽略查找外挂字幕（0 忽略） */
  ignoreFindSub: number = 1;
}
