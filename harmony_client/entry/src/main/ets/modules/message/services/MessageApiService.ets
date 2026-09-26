import { APIClient } from '../../../core/network/APIClient';
import { APIResponse } from '../../../core/network/APIResponse';

/**
 * 消息 API 服务（对齐 Flutter message_api_service.dart）。
 * 直连服务器，基于全局 APIClient；data 字段为 Object，由控制器解析。
 */
export class MessageApiService {
  private static readonly basePath: string = '/api/message';

  /** 分页查询消息列表 */
  static async getMessages(page: number, pageSize: number,
    level: number | undefined, keyword: string | undefined): Promise<APIResponse<Object>> {
    const query: Map<string, string> = new Map<string, string>();
    query.set('page', `${page}`);
    query.set('pageSize', `${pageSize}`);
    if (level !== undefined) {
      query.set('level', `${level}`);
    }
    if (keyword !== undefined && keyword.length > 0) {
      query.set('keyword', keyword);
    }
    return APIClient.getInstance().apiGet<Object>(`${MessageApiService.basePath}/list`, query);
  }

  /** 新增消息（对齐 Flutter addMessage；消息中心页面不使用，保留接口对齐） */
  static async addMessage(title: string, message: string,
    action: Object | undefined, level: number, isPublic: number): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = {
      'title': title,
      'message': message,
      'level': level,
      'isPublic': isPublic
    };
    if (action !== undefined) {
      body['action'] = action;
    }
    return APIClient.getInstance().apiPost<Object>(`${MessageApiService.basePath}/add`, body);
  }

  /** 标记已读：传 messageId 标记单条；不传标记全部 */
  static async markAsRead(messageId: number | undefined): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = {};
    if (messageId !== undefined) {
      body['messageId'] = messageId;
    }
    return APIClient.getInstance().apiPost<Object>(`${MessageApiService.basePath}/markAsRead`, body);
  }

  /** 删除单条消息 */
  static async deleteMessage(messageId: number): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'messageId': messageId };
    return APIClient.getInstance().apiPost<Object>(`${MessageApiService.basePath}/delete`, body);
  }

  /** 清空消息（可按等级） */
  static async clearMessages(level: number | undefined): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = {};
    if (level !== undefined) {
      body['level'] = level;
    }
    return APIClient.getInstance().apiPost<Object>(`${MessageApiService.basePath}/clear`, body);
  }

  /** 获取未读消息数量 */
  static async getUnreadCount(): Promise<APIResponse<Object>> {
    return APIClient.getInstance().apiGet<Object>(`${MessageApiService.basePath}/unreadCount`);
  }
}
