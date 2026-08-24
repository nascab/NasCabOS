const os = require('os');

class UserUtil {
  isAdmin(user) {
    return user.type === 'admin' || user.type === 'super_admin';
  }

  isSuperAdmin(user) {
    return user && user.type === 'super_admin';
  }
}

// 创建单例实例
const userUtil = new UserUtil();
// 导出单例实例
module.exports = userUtil;
