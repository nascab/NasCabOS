import 'package:NasCabOS/utils/cache_manager.dart';
import '../beans/server_info_bean.dart';

/// 服务器存储服务 - 负责服务器信息的本地存储
class ServerStorageService {
  static const String _serversKey = 'saved_servers';
  static const String _lastSelectedServerKey = 'last_selected_server';

  static String _normalizedUsername(ServerInfoBean server) {
    return (server.username ?? '').trim();
  }

  static String _normalizeUrlValue(String url) {
    final input = url.trim();
    if (input.isEmpty) return '';
    try {
      final uri = Uri.tryParse(input);
      if (uri == null) return input.toLowerCase();
      final scheme = uri.scheme.toLowerCase();
      final host = uri.host.toLowerCase();
      final port = uri.hasPort ? ':${uri.port}' : '';
      final path = uri.path.replaceAll(RegExp(r'/+$'), '');
      return '$scheme://$host$port$path';
    } catch (_) {
      return input.toLowerCase();
    }
  }

  static String _normalizedIdentityUrl(ServerInfoBean server) {
    final input = _normalizeUrlValue((server.userInputUrl ?? '').trim());
    if (input.isNotEmpty) return input;
    return _normalizeUrlValue(server.serverUrl.trim());
  }

  static bool _isUserManagedUrlIdentity(ServerInfoBean server) {
    return _normalizeUrlValue((server.userInputUrl ?? '').trim()).isNotEmpty;
  }

  static bool _isPairManagedIdentity(ServerInfoBean server) {
    if (_isUserManagedUrlIdentity(server)) return false;
    return (server.pairCode ?? '').trim().isNotEmpty || server.isP2p;
  }

  static String _stableIdentity(ServerInfoBean server) {
    final explicitInputUrl = _normalizeUrlValue((server.userInputUrl ?? '').trim());
    if (explicitInputUrl.isNotEmpty) {
      return 'manual-url:$explicitInputUrl';
    }

    final serverId = server.serverId.trim();
    if (_isPairManagedIdentity(server) && serverId.isNotEmpty) {
      return 'pair-sid:$serverId';
    }

    final identityUrl = _normalizedIdentityUrl(server);
    if (identityUrl.isNotEmpty) return 'url:$identityUrl';

    if (serverId.isNotEmpty) return 'sid:$serverId';

    final host = server.serverHost.trim().toLowerCase();
    final httpPort = server.serverPortHttp.trim();
    final httpsPort = server.serverPortHttps.trim();
    final port = httpPort.isNotEmpty ? httpPort : httpsPort;
    if (host.isNotEmpty && port.isNotEmpty) {
      return 'host:$host:$port';
    }

    final lanIpv4 = (server.lanIpv4 ?? '').trim();
    if (lanIpv4.isNotEmpty && port.isNotEmpty) {
      return 'lan:$lanIpv4:$port';
    }

    final code = (server.pairCode ?? '').trim();
    if (code.isNotEmpty) return 'pair:$code';

    final hostName = server.serverHostName.trim().toLowerCase();
    final serverName = server.serverName.trim().toLowerCase();
    return 'name:$hostName|$serverName';
  }

  static String _uniqueKey(ServerInfoBean server) {
    final username = _normalizedUsername(server);
    final identity = _stableIdentity(server);
    return 'u:$username|id:$identity';
  }

  static bool isSameIdentity(ServerInfoBean left, ServerInfoBean right) {
    return _uniqueKey(left) == _uniqueKey(right);
  }

  static ServerInfoBean _mergeByPreference(
    ServerInfoBean existing,
    ServerInfoBean incoming,
  ) {
    final out = ServerInfoBean(
      serverId: incoming.serverId.trim().isNotEmpty
          ? incoming.serverId
          : existing.serverId,
      serverUrl: incoming.serverUrl.trim().isNotEmpty
          ? incoming.serverUrl
          : existing.serverUrl,
      userInputUrl: (incoming.userInputUrl ?? '').trim().isNotEmpty
          ? incoming.userInputUrl
          : existing.userInputUrl,
      lanIpv4: (incoming.lanIpv4 ?? '').trim().isNotEmpty
          ? incoming.lanIpv4
          : existing.lanIpv4,
      lanHttpPort: (incoming.lanHttpPort ?? '').trim().isNotEmpty
          ? incoming.lanHttpPort
          : existing.lanHttpPort,
      lanHttpsPort: (incoming.lanHttpsPort ?? '').trim().isNotEmpty
          ? incoming.lanHttpsPort
          : existing.lanHttpsPort,
      serverName: incoming.serverName.trim().isNotEmpty
          ? incoming.serverName
          : existing.serverName,
      serverHost: incoming.serverHost.trim().isNotEmpty
          ? incoming.serverHost
          : existing.serverHost,
      serverPortHttp: incoming.serverPortHttp.trim().isNotEmpty
          ? incoming.serverPortHttp
          : existing.serverPortHttp,
      serverPortHttps: incoming.serverPortHttps.trim().isNotEmpty
          ? incoming.serverPortHttps
          : existing.serverPortHttps,
      serverHostName: incoming.serverHostName.trim().isNotEmpty
          ? incoming.serverHostName
          : existing.serverHostName,
      customHostname: () {
        final inc = incoming.customHostname;
        if (inc != null) {
          final t = inc.trim();
          return t.isEmpty ? null : t;
        }
        return existing.customHostname;
      }(),
      serverPlatform: incoming.serverPlatform.trim().isNotEmpty
          ? incoming.serverPlatform
          : existing.serverPlatform,
      isAutoScanned: existing.isAutoScanned && incoming.isAutoScanned,
      isLocalServer: existing.isLocalServer || incoming.isLocalServer,
      isP2p: false,
      pairCode: (incoming.pairCode ?? '').trim().isNotEmpty
          ? incoming.pairCode
          : existing.pairCode,
      username: (incoming.username ?? '').trim().isNotEmpty
          ? incoming.username
          : existing.username,
      password: (incoming.password ?? '').trim().isNotEmpty
          ? incoming.password
          : existing.password,
      accessToken: (incoming.accessToken ?? '').trim().isNotEmpty
          ? incoming.accessToken
          : existing.accessToken,
      refreshToken: (incoming.refreshToken ?? '').trim().isNotEmpty
          ? incoming.refreshToken
          : existing.refreshToken,
      lastLoginTime: incoming.lastLoginTime ?? existing.lastLoginTime,
      needInputPwdEveryTime: incoming.needInputPwdEveryTime,
    );

    out.isP2p =
        out.serverUrl.trim().isEmpty && (out.pairCode ?? '').trim().isNotEmpty;
    return out;
  }

  static List<ServerInfoBean> _dedupeByUniqueKey(List<ServerInfoBean> list) {
    final byKey = <String, ServerInfoBean>{};
    for (final s in list) {
      final key = _uniqueKey(s);
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = s;
      } else {
        byKey[key] = _mergeByPreference(existing, s);
      }
    }
    return byKey.values.toList();
  }

  /// 保存服务器列表到本地存储
  static Future<bool> saveServers(List<ServerInfoBean> servers) async {
    try {
      // 将服务器列表转换为JSON格式
      final normalized = _dedupeByUniqueKey(servers);
      final serversJson = normalized.map((server) => server.toJson()).toList();

      // 使用CacheManager存储
      return await CacheManager().setJson(_serversKey, serversJson);
    } catch (e) {
      print('保存服务器列表失败: $e');
      return false;
    }
  }

  /// 从本地存储加载服务器列表
  static List<ServerInfoBean> loadServers() {
    try {
      final serversJson = CacheManager().getJson(_serversKey);

      if (serversJson is List) {
        final list = serversJson
            .map((item) {
              if (item is Map<String, dynamic>) {
                item['isAutoScanned'] = false;
                return ServerInfoBean.fromJson(item);
              }
              return null;
            })
            .where((server) => server != null)
            .cast<ServerInfoBean>()
            .toList();
        return _dedupeByUniqueKey(list);
      }

      return [];
    } catch (e) {
      print('加载服务器列表失败: $e');
      return [];
    }
  }

  /// 添加单个服务器到存储
  static Future<bool> addServer(ServerInfoBean server) async {
    try {
      final currentServers = loadServers();

      final incomingKey = _uniqueKey(server);
      final existingIndex = currentServers.indexWhere((s) {
        return _uniqueKey(s) == incomingKey;
      });

      if (existingIndex >= 0) {
        currentServers[existingIndex] = _mergeByPreference(
          currentServers[existingIndex],
          server,
        );
      } else {
        currentServers.add(server);
      }

      return await saveServers(currentServers);
    } catch (e) {
      print('添加服务器失败: $e');
      return false;
    }
  }

  /// 从存储中删除服务器
  static Future<bool> removeServer(ServerInfoBean serverItem) async {
    try {
      final currentServers = loadServers();
      final targetKey = _uniqueKey(serverItem);
      final updatedServers = currentServers.where((server) {
        return _uniqueKey(server) != targetKey;
      }).toList();
      return await saveServers(updatedServers);
    } catch (e) {
      print('删除服务器失败: $e');
      return false;
    }
  }

  /// 更新当前会话对应条目的自定义主机名（设置页保存后同步本地库）
  static Future<void> updateServerCustomHostnameForSession({
    required String serverId,
    required String username,
    String? customHostname,
  }) async {
    try {
      final sid = serverId.trim();
      final u = username.trim();
      if (sid.isEmpty) return;
      final servers = loadServers();
      var changed = false;
      for (var i = 0; i < servers.length; i++) {
        if (servers[i].serverId.trim() == sid &&
            _normalizedUsername(servers[i]) == u) {
          servers[i].customHostname = customHostname;
          changed = true;
          break;
        }
      }
      if (changed) {
        await saveServers(servers);
      }
    } catch (_) {}
  }

  /// 更新服务器信息
  static Future<bool> updateServer(ServerInfoBean updatedServer) async {
    try {
      final currentServers = loadServers();

      final targetKey = _uniqueKey(updatedServer);
      final index = currentServers.indexWhere((server) {
        return _uniqueKey(server) == targetKey;
      });

      if (index >= 0) {
        currentServers[index] = _mergeByPreference(
          currentServers[index],
          updatedServer,
        );
        return await saveServers(currentServers);
      }

      return false;
    } catch (e) {
      print('更新服务器失败: $e');
      return false;
    }
  }

  /// 保存最后选择的服务器
  static Future<bool> saveLastSelectedServer(ServerInfoBean server) async {
    try {
      return await CacheManager().setJson(
        _lastSelectedServerKey,
        server.toJson(),
      );
    } catch (e) {
      print('保存最后选择的服务器失败: $e');
      return false;
    }
  }

  /// 获取最后选择的服务器
  static ServerInfoBean? getLastSelectedServer() {
    try {
      final serverJson = CacheManager().getJson(_lastSelectedServerKey);

      if (serverJson is Map<String, dynamic>) {
        return ServerInfoBean.fromJson(serverJson);
      }

      return null;
    } catch (e) {
      print('获取最后选择的服务器失败: $e');
      return null;
    }
  }

  /// 清除所有服务器数据
  static Future<bool> clearAll() async {
    try {
      await CacheManager().remove(_serversKey);
      await CacheManager().remove(_lastSelectedServerKey);
      return true;
    } catch (e) {
      print('清除服务器数据失败: $e');
      return false;
    }
  }

  /// 检查服务器是否已存在
  static bool serverExists(String serverUrl) {
    final servers = loadServers();
    return servers.any((server) => server.serverUrl == serverUrl);
  }

  /// 获取服务器数量
  static int getServerCount() {
    return loadServers().length;
  }
}
