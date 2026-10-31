import { PreferencesStore } from '../../../core/storage/PreferencesStore';

/** 本地持久化键 */
const KEY_VIEW_MODE: string = 'music_view_mode';
/** 支持的显示模式：网格 / 列表 */
const VIEW_MODES: string[] = ['grid', 'list'];
const DEFAULT_VIEW_MODE: string = 'grid';

/**
 * 音乐列表显示模式全局状态（单例）：
 * - 歌曲/收藏列表与专辑/艺人列表共享同一份模式，任一页面切换后其他页面同步；
 * - 首次访问时从本地 Preferences 恢复，切换时立即写回，跨启动保持一致。
 */
@ObservedV2
export class MusicViewModeStore {
  private static instance: MusicViewModeStore | undefined = undefined;

  static getInstance(): MusicViewModeStore {
    if (MusicViewModeStore.instance === undefined) {
      MusicViewModeStore.instance = new MusicViewModeStore();
    }
    return MusicViewModeStore.instance;
  }

  @Trace viewMode: string = DEFAULT_VIEW_MODE;
  private loaded: boolean = false;

  private constructor() {
  }

  get isList(): boolean {
    return this.viewMode === 'list';
  }

  /** 从本地恢复显示模式（幂等：成功读取后不再重复读取） */
  ensureLoaded(): void {
    if (this.loaded) {
      return;
    }
    try {
      const saved = PreferencesStore.getInstance().getString(KEY_VIEW_MODE);
      if (saved !== undefined && VIEW_MODES.includes(saved)) {
        this.viewMode = saved;
      }
      this.loaded = true;
    } catch (_e) {
    }
  }

  /** 切换显示模式并持久化 */
  setViewMode(mode: string): void {
    if (!VIEW_MODES.includes(mode) || this.viewMode === mode) {
      return;
    }
    this.viewMode = mode;
    try {
      void PreferencesStore.getInstance().setString(KEY_VIEW_MODE, mode);
    } catch (_e) {
    }
  }

  toggle(): void {
    this.setViewMode(this.viewMode === 'grid' ? 'list' : 'grid');
  }
}
