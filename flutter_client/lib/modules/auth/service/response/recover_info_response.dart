/// 找回密码信息响应数据模型
class RecoverInfoResponse {
  final bool success;
  final String? message;
  final String? question;
  final String? username;

  RecoverInfoResponse({
    required this.success,
    this.message,
    this.question,
    this.username,
  });

  factory RecoverInfoResponse.fromJson(Map<String, dynamic> json) {
    return RecoverInfoResponse(
      success: true, // 当从dataParser调用时，假设success为true
      message: null,
      question: json['securityQuestion'],
      username: json['username'],
    );
  }

  @override
  String toString() {
    return 'RecoverInfoResponse{success: $success, message: $message, question: $question, username: $username}';
  }
}
