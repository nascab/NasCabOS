/**
 * 消息中心数据模型（对齐 Flutter message_center_controller.dart 中的 MessageItem）。
 */

/**
 * 单条系统消息。
 * readStatus 用 @Trace 观察：标记已读时直接修改，列表自动刷新（替代 Flutter 重建对象）。
 */
@ObservedV2
export class MessageItem {
  id: number = 0;
  uid: number = 0;
  title: string = '';
  message: string = '';
  /** 动作参数（如 { type: 'openUrl', url: '...' }），无动作为 undefined */
  action: Record<string, Object> | undefined = undefined;
  /** 已读状态：0=未读，1=已读 */
  @Trace readStatus: number = 0;
  /** 等级：0=普通，1=重要，2=紧急 */
  level: number = 0;
  /** 是否公开：0/1 */
  isPublic: number = 0;
  /** 创建时间（原始字符串，可能为时间戳或日期文本） */
  createTime: string = '';

  /** 从 JSON 对象构造（容错：数字/字符串混型字段统一转换） */
  static fromJson(json: Record<string, Object>): MessageItem {
    const item: MessageItem = new MessageItem();
    item.id = MessageItem.toInt(json['id']);
    item.uid = MessageItem.toInt(json['uid']);
    item.title = MessageItem.toStr(json['title']);
    item.message = MessageItem.toStr(json['message']);
    item.action = MessageItem.parseAction(json['action']);
    item.readStatus = MessageItem.toInt(json['read_status']);
    item.level = MessageItem.toInt(json['level']);
    item.isPublic = MessageItem.toInt(json['is_public']) === 0 ? 0 : 1;
    item.createTime = MessageItem.toStr(json['create_time']);
    return item;
  }

  /** 容错转数字：number 直接取；字符串尝试解析；失败为 0 */
  static toInt(v: Object | undefined): number {
    if (v === undefined || v === null) {
      return 0;
    }
    if (typeof v === 'number') {
      return v;
    }
    const n: number = Number(`${v}`);
    return Number.isNaN(n) ? 0 : Math.trunc(n);
  }

  /** 容错转字符串 */
  static toStr(v: Object | undefined): string {
    if (v === undefined || v === null) {
      return '';
    }
    return `${v}`;
  }

  /**
   * 解析 action：
   * - 对象 → 直接使用；
   * - 字符串（可能是 JSON 文本）→ 尝试 JSON.parse；
   * - 其它/解析失败 → undefined。
   */
  static parseAction(v: Object | undefined): Record<string, Object> | undefined {
    if (v === undefined || v === null) {
      return undefined;
    }
    if (typeof v === 'object' && !Array.isArray(v)) {
      return v as Record<string, Object>;
    }
    if (typeof v === 'string') {
      const s: string = (v as string).trim();
      if (s.length === 0) {
        return undefined;
      }
      try {
        const parsed: Object = JSON.parse(s) as Object;
        if (typeof parsed === 'object' && !Array.isArray(parsed)) {
          return parsed as Record<string, Object>;
        }
      } catch (_e) {
        // 非法 JSON 视为无动作
      }
    }
    return undefined;
  }
}

/** 等级筛选值（-1=全部，对齐 Flutter 菜单中的 -1 项） */
export const LEVEL_FILTER_ALL: number = -1;
