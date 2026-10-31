import { L10n } from '../../../core/localization/L10n';
import { NavUtil } from '../../../common/NavUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { AppRouter } from '../../../router/AppRouter';
import { DownloadService } from '../../transfer/services/DownloadService';
import { DownloadTarget } from '../../transfer/models/DownloadModels';
import { MusicListItem } from '../models/MusicModels';

/** 单条音乐的下载目标：系列（专辑/歌手等）按文件夹递归，单曲按文件 */
export function musicDownloadTargetOf(item: MusicListItem): DownloadTarget {
  if (item.isSeries) {
    return { path: item.path.trim(), isDirHint: true };
  }
  return { path: item.resolvePlayablePath().trim(), isDirHint: false };
}

/**
 * 批量下载音乐条目（走全局下载中心，对齐照片/影音/图书模块）：
 * 入队后直接跳转下载中心；无有效路径时静默返回。
 */
export function downloadMusicItems(items: MusicListItem[]): void {
  const targets: DownloadTarget[] = [];
  for (const it of items) {
    const t: DownloadTarget = musicDownloadTargetOf(it);
    if (t.path.length > 0) {
      targets.push(t);
    }
  }
  if (targets.length === 0) {
    return;
  }
  NavUtil.push(AppRouter.DOWNLOAD_CENTER);
  void DownloadService.getInstance().enqueue(targets).then((added: number): void => {
    if (added > 0) {
      ToastUtil.show(L10n.t('task_added', '任务已添加'));
    }
  });
}
