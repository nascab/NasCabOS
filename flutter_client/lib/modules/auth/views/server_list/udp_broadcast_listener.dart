import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// UDP广播监听工具类
class UdpBroadcastListener {
  static const int _broadcastPort = 8888;
  RawDatagramSocket? _socket;
  bool _isListening = false;

  /// 服务器发现回调函数
  Function(Map<String, dynamic>)? _onServerDiscovered;

  /// 设置服务器发现回调
  void setOnServerDiscovered(Function(Map<String, dynamic>) callback) {
    _onServerDiscovered = callback;
  }

  /// 开始监听UDP广播
  Future<void> startListening() async {
    if (kIsWeb) {
      print('UDP广播监听在Web平台上不支持');
      return;
    }
    if (_isListening) {
      print('UDP监听器已经在运行中');
      return;
    }

    try {
      // 创建UDP socket
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _broadcastPort,
        reuseAddress: true,
      );

      // 监听广播消息
      _socket!.listen(
        (RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket!.receive();
            if (datagram != null) {
              final data = datagram.data;
              final sender = datagram.address;

              // 将接收到的数据转换为字符串
              final message = String.fromCharCodes(data);
              // print(message);
              try {
                // 解析JSON消息
                final Map<String, dynamic> serverInfo = json.decode(message);

                // 验证必需字段
                if (serverInfo.containsKey('service') &&
                    serverInfo['service'] == 'nascab-pro-service' &&
                    serverInfo.containsKey('host') &&
                    serverInfo.containsKey('port')) {
                  // 添加发送者IP信息
                  serverInfo['discovered_ip'] = sender.address;

                  // 调用服务器发现回调
                  if (_onServerDiscovered != null) {
                    _onServerDiscovered!(serverInfo);
                  }

                  // print(
                  //   '📡 发现服务器: ${serverInfo['hostname']} (${serverInfo['host']}:${serverInfo['port']})',
                  // );
                }
              } catch (e) {
                print('❌ 解析UDP消息失败: $e');
              }
            }
          }
        },
        onError: (error) {
          print('❌ UDP监听错误: $error');
        },
        onDone: () {
          print('✅ UDP监听完成');
          _isListening = false;
        },
      );

      _isListening = true;
      print('🎯 UDP广播监听器已启动，监听端口: $_broadcastPort');
      print('等待接收广播消息...');
    } catch (e) {
      print('❌ 启动UDP监听失败: $e');
      _isListening = false;
    }
  }

  /// 停止监听UDP广播
  Future<void> stopListening() async {
    stopListeningSync();
  }

  /// 同步关闭 socket，供 GetX [onClose] 等必须立即释放端口的场景使用。
  void stopListeningSync() {
    if (!_isListening && _socket == null) {
      return;
    }
    try {
      _socket?.close();
      _socket = null;
      _isListening = false;
      print('🛑 UDP广播监听器已停止');
    } catch (e) {
      print('❌ 停止UDP监听失败: $e');
      _socket = null;
      _isListening = false;
    }
  }

  /// 检查是否正在监听
  bool get isListening => _isListening;

  /// 获取监听端口
  int get listeningPort => _broadcastPort;

  /// 析构函数，确保资源被正确释放
  void dispose() {
    stopListeningSync();
  }
}
