import { Want } from '@kit.AbilityKit';
import { L10n } from '../../../core/localization/L10n';
import { NavUtil } from '../../../common/NavUtil';
import { WindowStore } from '../../../common/WindowStore';
import { AppTheme } from '../../../core/theme/AppTheme';
import { AppRouter } from '../../../router/AppRouter';
import { MessageApiService } from '../services/MessageApiService';
import { LEVEL_FILTER_ALL, MessageItem } from '../models/MessageModels';

/** 重要等级色（对齐 Flutter Colors.orange） */
const LEVEL_COLOR_IMPORTANT: string = '#F9A825';
/** 紧急等级色（对齐 Flutter Colors.red） */
const LEVEL_COLOR_URGENT: string = '#E53935';

/**
 * 消息中心控制器（对齐 Flutter MessageCenterController）：
 * 分页加载、等级筛选、标记已读、删除/清空、消息动作（openUrl/openApp）。
 */
@ObservedV2
export class MessageCenterController {
  @Trace messages: MessageItem[] = [];
  @Trace currentPage: number = 1;
  @Trace pageSize: number = 20;
  @Trace total: number = 0;
  @Trace totalPages: number = 0;
  @Trace unreadCount: number = 0;
  /** 当前等级筛选（LEVEL_FILTER_ALL=-1 表示全部） */
  @Trace selectedLevel: number = LEVEL_FILTER_ALL;
  @Trace searchKeyword: string = '';
  @Trace isLoading: boolean = false;
  @Trace hasMore: boolean = true;

  /** 初始化：加载首页与未读数（对齐 Flutter onInit） */
  init(): void {
    void this.loadMessages(true);
    void this.loadUnreadCount();
  }

  /**
   * 加载消息（对齐 Flutter loadMessages）。
   * @param refresh true=重置到第一页；false=加载当前页（追加）
   */
  async loadMessages(refresh: boolean = false): Promise<void> {
    if (this.isLoading) {
      return;
    }
    if (refresh) {
      this.currentPage = 1;
      this.messages = [];
      this.hasMore = true;
    }
    if (!this.hasMore && !refresh) {
      return;
    }
    this.isLoading = true;
    try {
      const levelForApi: number | undefined =
        this.selectedLevel === LEVEL_FILTER_ALL ? undefined : this.selectedLevel;
      const keywordForApi: string | undefined =
        this.searchKeyword.length === 0 ? undefined : this.searchKeyword;
      const res = await MessageApiService.getMessages(
        this.currentPage, this.pageSize, levelForApi, keywordForApi);
      if (!res.success || res.data === undefined) {
        return;
      }
      const record: Record<string, Object> = res.data as Record<string, Object>;
      const rawItems: Object | undefined = record['items'];
      const items: MessageItem[] = [];
      if (rawItems !== undefined && Array.isArray(rawItems)) {
        const arr: Object[] = rawItems as Object[];
        arr.forEach((e: Object): void => {
          items.push(MessageItem.fromJson(e as Record<string, Object>));
        });
      }
      if (refresh) {
        this.messages = items;
      } else {
        this.messages = this.messages.concat(items);
      }

      this.total = MessageItem.toInt(record['total']);
      this.totalPages = MessageItem.toInt(record['totalPages']);
      if (this.currentPage >= this.totalPages || items.length < this.pageSize) {
        this.hasMore = false;
      }
    } catch (e) {
      console.error('[Message] 加载消息失败: ' + `${e}`);
    } finally {
      this.isLoading = false;
    }
  }

  /** 触底加载更多（对齐 Flutter loadMore） */
  async loadMore(): Promise<void> {
    if (this.isLoading || !this.hasMore) {
      return;
    }
    this.currentPage++;
    await this.loadMessages();
  }

  /** 下拉刷新（对齐 Flutter refreshMessages） */
  async refreshMessages(): Promise<void> {
    await this.loadMessages(true);
    await this.loadUnreadCount();
  }

  /** 加载未读数量（对齐 Flutter loadUnreadCount） */
  async loadUnreadCount(): Promise<void> {
    try {
      const res = await MessageApiService.getUnreadCount();
      if (res.success && res.data !== undefined) {
        const record: Record<string, Object> = res.data as Record<string, Object>;
        this.unreadCount = MessageItem.toInt(record['count']);
      }
    } catch (e) {
      console.error('[Message] 加载未读数量失败: ' + `${e}`);
    }
  }

  /** 标记单条已读（对齐 Flutter markAsRead） */
  async markAsRead(messageId: number): Promise<void> {
    try {
      const res = await MessageApiService.markAsRead(messageId);
      if (!res.success) {
        return;
      }
      const hit: MessageItem | undefined =
        this.messages.find((m: MessageItem): boolean => m.id === messageId);
      if (hit !== undefined && hit.readStatus === 0) {
        hit.readStatus = 1;
        if (this.unreadCount > 0) {
          this.unreadCount--;
        }
      }
    } catch (e) {
      console.error('[Message] 标记已读失败: ' + `${e}`);
    }
  }

  /** 标记全部已读（对齐 Flutter markAllAsRead，并实际更新本地已读状态） */
  async markAllAsRead(): Promise<void> {
    try {
      const res = await MessageApiService.markAsRead(undefined);
      if (!res.success) {
        return;
      }
      this.messages.forEach((m: MessageItem): void => {
        m.readStatus = 1;
      });
      this.unreadCount = 0;
    } catch (e) {
      console.error('[Message] 标记全部已读失败: ' + `${e}`);
    }
  }

  /** 删除单条消息（对齐 Flutter deleteMessage） */
  async deleteMessage(messageId: number): Promise<void> {
    try {
      const res = await MessageApiService.deleteMessage(messageId);
      if (!res.success) {
        return;
      }
      this.messages = this.messages.filter((m: MessageItem): boolean => m.id !== messageId);
      this.total = this.messages.length;
      await this.loadUnreadCount();
    } catch (e) {
      console.error('[Message] 删除消息失败: ' + `${e}`);
    }
  }

  /** 清空消息（对齐 Flutter clearMessages，按当前等级筛选清空） */
  async clearMessages(): Promise<void> {
    try {
      const levelForApi: number | undefined =
        this.selectedLevel === LEVEL_FILTER_ALL ? undefined : this.selectedLevel;
      const res = await MessageApiService.clearMessages(levelForApi);
      if (!res.success) {
        return;
      }
      this.messages = [];
      this.total = 0;
      await this.loadUnreadCount();
    } catch (e) {
      console.error('[Message] 清空消息失败: ' + `${e}`);
    }
  }

  /** 按等级筛选（对齐 Flutter filterByLevel） */
  filterByLevel(level: number): void {
    this.selectedLevel = level;
    void this.refreshMessages();
  }

  /** 点击消息：未读先标记已读，再执行动作（对齐 Flutter onMessageTap） */
  async onMessageTap(item: MessageItem): Promise<void> {
    if (item.readStatus === 0) {
      await this.markAsRead(item.id);
    }
    this.handleAction(item.action);
  }

  /**
   * 处理消息动作（对齐 Flutter _handleAction）：
   * - openUrl：系统浏览器打开外部链接；
   * - openApp：跳转应用内对应模块。
   */
  private handleAction(action: Record<string, Object> | undefined): void {
    if (action === undefined) {
      return;
    }
    const type: string = MessageItem.toStr(action['type']).trim();
    if (type.length === 0 || type === 'none') {
      return;
    }

    if (type === 'openUrl') {
      const url: string = MessageItem.toStr(action['url']).trim();
      if (url.length === 0) {
        return;
      }
      const ctx = WindowStore.appContext;
      if (!ctx) {
        return;
      }
      const want: Want = { action: 'ohos.want.action.viewData', uri: url };
      void ctx.startAbility(want).catch((e: Object): void => {
        console.warn('[Message] 打开外部链接失败: ' + `${e}`);
      });
      return;
    }

    if (type === 'openApp') {
      const app: string = MessageItem.toStr(action['app']).trim();
      if (app.length === 0) {
        return;
      }
      const route: string | undefined = MessageCenterController.routeOfApp(app);
      if (route !== undefined) {
        // 参数缺省：Index pageMap 各分支会回退构造默认参数
        NavUtil.push(route);
      }
    }
  }

  /** app id → 鸿蒙路由名（对齐首页 HomePage.openApp 的映射；未知应用返回 undefined） */
  private static routeOfApp(app: string): string | undefined {
    switch (app) {
      case 'setting':
        return AppRouter.SETTINGS;
      case 'folder':
        return AppRouter.FILES;
      case 'upload':
        return AppRouter.UPLOAD_CENTER;
      case 'download':
        return AppRouter.DOWNLOAD_CENTER;
      case 'photo':
        return AppRouter.PHOTO_MAIN;
      case 'movie':
        return AppRouter.VIDEO_MAIN;
      case 'music':
        return AppRouter.MUSIC_MAIN;
      case 'book':
        return AppRouter.BOOK_MAIN;
      case 'note':
        return AppRouter.NOTES_MAIN;
      case 'security':
        return AppRouter.SECURITY_CENTER;
      case 'process':
        return AppRouter.PROCESS_LIST;
      case 'monitor':
        return AppRouter.MONITOR_PAGE;
      case 'terminal':
        return AppRouter.TERMINAL_PAGE;
      case 'transmission':
        return AppRouter.TRANSMISSION_PAGE;
      case 'docker':
        return AppRouter.DOCKER_PAGE;
      case 'user':
        return AppRouter.USER_MANAGEMENT;
      case 'mounts':
        return AppRouter.FILE_MOUNT;
      case 'share':
      case 'file_share_server':
        return AppRouter.SHARE_SERVER_MAIN;
      case 'backup':
        return AppRouter.FILE_BACKUP;
      case 'photo_backup':
        return AppRouter.PHOTO_BACKUP;
      case 'media_tool':
        return AppRouter.MEDIA_TOOL_ENTRY;
      case 'encrypted':
        return AppRouter.ENCRYPTED_SPACE_MAIN;
      case 'nascab_service':
        return AppRouter.SERVICE_MAIN;
      default:
        return undefined;
    }
  }

  /** 等级文案（对齐 Flutter getLevelText） */
  levelText(level: number): string {
    switch (level) {
      case 1:
        return L10n.t('important', '重要');
      case 2:
        return L10n.t('urgent', '紧急');
      default:
        return L10n.t('normal', '普通');
    }
  }

  /** 等级颜色（对齐 Flutter getLevelColor） */
  levelColor(level: number): string {
    switch (level) {
      case 1:
        return LEVEL_COLOR_IMPORTANT;
      case 2:
        return LEVEL_COLOR_URGENT;
      default:
        return AppTheme.current().subText;
    }
  }
}

/**
 * 将消息创建时间格式化为本地时间文本（对齐 Flutter _formatLocalTime）：
 * 支持秒/毫秒时间戳与日期字符串；输出 yyyy-MM-dd HH:mm。
 */
export function formatMessageTime(raw: string): string {
  const s: string = raw.trim();
  if (s.length === 0) {
    return '';
  }
  let ms: number = 0;
  const n: number = Number(s);
  if (!Number.isNaN(n) && /^\d+$/.test(s)) {
    ms = n > 10000000000 ? n : n * 1000;
  } else {
    // Date.parse 兼容 'yyyy-MM-dd HH:mm:ss' 与 ISO 文本
    ms = Date.parse(s.includes(' ') && !s.includes('T') ? s.replace(' ', 'T') : s);
  }
  if (Number.isNaN(ms)) {
    return s;
  }
  const dt: Date = new Date(ms);
  const two: (x: number) => string = (x: number): string => `${x}`.padStart(2, '0');
  return `${dt.getFullYear()}-${two(dt.getMonth() + 1)}-${two(dt.getDate())} `
    + `${two(dt.getHours())}:${two(dt.getMinutes())}`;
}
