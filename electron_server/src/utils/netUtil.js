/**
 * 网络工具类
 * 提供网络相关的工具函数
 */

// 网络工具（中文注释）：网络地址检测与辅助能力
const os = require('os');

class NetUtil {
  /**
   * 检测IP是否为局域网IP
   * @param {string} ip - IP地址
   * @returns {boolean} 是否为局域网IP
   */
  static isPrivateIP(ip) {
    // 处理IPv6映射的IPv4地址
    if (ip.startsWith('::ffff:')) {
      ip = ip.substring(7); // 移除::ffff:前缀
    }

    // 检查本地回环地址
    if (ip === '127.0.0.1' || ip === 'localhost' || ip === '::1') {
      return true;
    }

    // 检查IPv4局域网地址段
    if (ip.includes('.')) {
      const parts = ip.split('.').map(part => parseInt(part, 10));
      if (parts.length === 4) {
        // 10.0.0.0/8
        if (parts[0] === 10) return true;

        // 172.16.0.0/12
        if (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) return true;

        // 192.168.0.0/16
        if (parts[0] === 192 && parts[1] === 168) return true;

        // 169.254.0.0/16 (链路本地地址)
        if (parts[0] === 169 && parts[1] === 254) return true;
      }
    }

    // 检查IPv6局域网地址段
    if (ip.includes(':')) {
      // fc00::/7 (ULA)
      if (ip.startsWith('fc') || ip.startsWith('fd')) return true;

      // fe80::/10 (链路本地地址)
      if (ip.startsWith('fe80:')) return true;
    }

    return false;
  }

  /**
   * 获取客户端IP地址
   * @param {object} req - Express请求对象
   * @returns {string} 客户端IP地址
   */
  static getClientIP(req) {
    return req.ip || req.connection.remoteAddress || req.socket.remoteAddress || 'unknown';
  }

  /**
   * 检查请求是否来自局域网
   * @param {object} req - Express请求对象
   * @returns {boolean} 是否来自局域网
   */
  static isPrivateNetworkRequest(req) {
    const clientIp = this.getClientIP(req);
    return this.isPrivateIP(clientIp);
  }

  /**
   * 获取IP地址类型
   * @param {string} ip - IP地址
   * @returns {string} IP类型 (IPv4, IPv6, unknown)
   */
  static getIPType(ip) {
    if (ip.includes('.')) {
      return 'IPv4';
    } else if (ip.includes(':')) {
      return 'IPv6';
    } else {
      return 'unknown';
    }
  }

  /**
   * 标准化IP地址
   * @param {string} ip - IP地址
   * @returns {string} 标准化后的IP地址
   */
  static normalizeIP(ip) {
    // 处理IPv6映射的IPv4地址
    if (ip.startsWith('::ffff:')) {
      return ip.substring(7);
    }

    // 处理IPv6压缩格式
    if (ip.includes('::')) {
      // 这里可以添加IPv6标准化逻辑
      return ip.toLowerCase();
    }

    return ip;
  }

  static getIPv4Addresses() {
    const nets = os.networkInterfaces() || {};
    const list = [];
    Object.keys(nets).forEach(name => {
      const arr = nets[name] || [];
      arr.forEach(n => {
        if (n.family === 'IPv4' && !n.internal) list.push(n.address);
      });
    });
    return list;
  }
}

module.exports = NetUtil;
