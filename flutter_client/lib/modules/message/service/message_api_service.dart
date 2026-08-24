import 'package:get/get.dart';
import '../../../core/api/base_api_service.dart';

class MessageApiService extends BaseApiService {
  static MessageApiService get instance => Get.isRegistered<MessageApiService>()
      ? Get.find<MessageApiService>()
      : MessageApiService();

  Future<Map<String, dynamic>> getMessages({
    int page = 1,
    int pageSize = 20,
    int? level,
    String? keyword,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (level != null) {
      queryParams['level'] = level.toString();
    }
    if (keyword != null && keyword.isNotEmpty) {
      queryParams['keyword'] = keyword;
    }

    final response = await apiGet<Map<String, dynamic>>(
      '/api/message/list',
      queryParams: queryParams,
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> addMessage({
    String title = '',
    required String message,
    Map<String, dynamic>? action,
    int level = 0,
    int isPublic = 1,
  }) async {
    final response = await apiPost<Map<String, dynamic>>(
      '/api/message/add',
      body: {
        'title': title,
        'message': message,
        if (action != null) 'action': action,
        'level': level,
        'isPublic': isPublic,
      },
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> markAsRead({int? messageId}) async {
    final response = await apiPost<Map<String, dynamic>>(
      '/api/message/markAsRead',
      body: {if (messageId != null) 'messageId': messageId},
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> deleteMessage({required int messageId}) async {
    final response = await apiPost<Map<String, dynamic>>(
      '/api/message/delete',
      body: {'messageId': messageId},
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> clearMessages({int? level}) async {
    final response = await apiPost<Map<String, dynamic>>(
      '/api/message/clear',
      body: {if (level != null) 'level': level},
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> getUnreadCount() async {
    final response = await apiGet<Map<String, dynamic>>(
      '/api/message/unreadCount',
    );
    return response.data ?? {};
  }
}
