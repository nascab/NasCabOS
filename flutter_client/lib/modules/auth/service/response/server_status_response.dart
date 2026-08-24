/// 服务器状态响应数据模型
class ServerStatusResponse {
  final bool success;
  final String? message;
  final bool isNasCabServer;
  final Map<String, dynamic>? serverData;
  final String? serverId;

  ServerStatusResponse({
    this.serverId,
    required this.success,
    this.message,
    required this.isNasCabServer,
    this.serverData,
  });

  factory ServerStatusResponse.fromJson(Map<String, dynamic> json, int code) {
    // 检查是否是完整的响应格式（包含success字段）
    // 这可能是仅data字段的内容
    return ServerStatusResponse(
      serverId: json['serverId'],
      success: true, // 当从dataParser调用时，假设success为true
      message: null,
      isNasCabServer: json['isNasCabServer'],
      serverData: json['serverData'],
    );
  }

  @override
  String toString() {
    return 'ServerStatusResponse{serverId: $serverId, success: $success, message: $message, isNasCabServer: $isNasCabServer, serverData: $serverData}';
  }
}
