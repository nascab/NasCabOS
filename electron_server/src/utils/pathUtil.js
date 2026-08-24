const path = require('path');

class PathUtil {
  /**
   * 规范化路径，用于“相等/包含”比较：
   * - 先 resolve 成绝对路径
   * - 去掉尾部多余的分隔符（根路径除外）
   * - Windows 下按不区分大小写处理
   */
  static normalizeFsPathForCompare(p) {
    if (p === undefined || p === null) return '';
    const raw = String(p).trim();
    if (!raw) return '';
    const resolved = path.resolve(raw);
    const root = path.parse(resolved).root;

    let out = resolved;
    while (out.length > root.length && /[\\/]/.test(out[out.length - 1])) {
      out = out.slice(0, -1);
    }

    if (process.platform === 'win32') return out.toLowerCase();
    return out;
  }

  /**
   * 判断 parent 是否为 child 的父目录（严格父级，不包含相等）
   * 注意：需要输入已 normalize 的路径（建议使用 normalizeFsPathForCompare）
   */
  static isAncestorPath(parent, child) {
    if (!parent || !child) return false;
    if (parent === child) return false;
    const root = path.parse(parent).root;
    if (parent === root) return child.startsWith(parent);
    return child.startsWith(parent + path.sep);
  }

  /**
   * 判断两条路径是否冲突：相等 / 互相包含（任一方是另一方的父级/子级）
   */
  static isMutualConflictPath(a, b) {
    const aa = PathUtil.normalizeFsPathForCompare(a);
    const bb = PathUtil.normalizeFsPathForCompare(b);
    if (!aa || !bb) return false;
    return aa === bb || PathUtil.isAncestorPath(aa, bb) || PathUtil.isAncestorPath(bb, aa);
  }

  /**
   * 判断一组路径中是否存在冲突：任意两条路径相等或互相包含
   */
  static hasMutualConflictInList(paths) {
    if (!Array.isArray(paths) || paths.length < 2) return false;
    const normalized = paths.map(p => PathUtil.normalizeFsPathForCompare(p)).filter(Boolean);
    for (let i = 0; i < normalized.length; i++) {
      for (let j = i + 1; j < normalized.length; j++) {
        if (PathUtil.isMutualConflictPath(normalized[i], normalized[j])) return true;
      }
    }
    return false;
  }
}

module.exports = PathUtil;
