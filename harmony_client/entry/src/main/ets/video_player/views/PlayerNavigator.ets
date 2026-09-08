import { AppRouter } from '../../router/AppRouter';
import { NavUtil } from '../../common/NavUtil';
import { PlayerPlaylistItem } from '../models/PlayerModels';
import { VideoPlayerPageParam } from '../router/PlayerRoutes';

/**
 * Record 列表 → 播放列表条目（对齐 Flutter 直接透传 Map 的行为，过滤空 path）。
 * 兼容服务器 playlist（path/name/internalPath）与详情页构建条目（path/name/nfo_name）。
 */
export function toPlayerPlaylist(records: Record<string, Object>[]): PlayerPlaylistItem[] {
  const out: PlayerPlaylistItem[] = [];
  for (const r of records) {
    const it = PlayerPlaylistItem.fromRecord(r);
    if (it.path.trim().length > 0) {
      out.push(it);
    }
  }
  return out;
}

/** 打开视频播放器页（对齐 Flutter AppRoutes.toVideoPlayer） */
export function openVideoPlayer(playlist: PlayerPlaylistItem[], initialIndex: number,
  ignoreFindSub: number): void {
  const p = new VideoPlayerPageParam();
  p.playlist = playlist;
  p.initialIndex = initialIndex;
  p.ignoreFindSub = ignoreFindSub;
  NavUtil.push(AppRouter.VIDEO_PLAYER, p);
}
