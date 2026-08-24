class MessageService {
  constructor(knex) {
    this.knex = knex;
    this.table = 'message';
  }

  /**
   * action 字段数据格式（存储在 DB 为 JSON 字符串，接口返回为对象）：
   * - 不处理：null / undefined / {} / {"type":"none"}
   * - 跳转外部网页：{"type":"openUrl","url":"https://example.com"}
   * - 打开内部窗口/应用：{"type":"openApp","app":"folder"}
   */
  async addMessage({ uid = 0, title = '', message, action = null, level = 0, isPublic = 1 }) {
    if (!message || typeof message !== 'string' || !message.trim()) {
      throw new Error('消息内容不能为空');
    }

    const safeTitle = typeof title === 'string' ? title.trim() : '';

    let actionJson = null;
    if (action !== null && action !== undefined) {
      if (typeof action === 'string') {
        const s = action.trim();
        if (s) {
          try {
            const parsed = JSON.parse(s);
            actionJson = JSON.stringify(parsed);
          } catch (_) {
            actionJson = null;
          }
        }
      } else if (typeof action === 'object') {
        try {
          actionJson = JSON.stringify(action);
        } catch (_) {
          actionJson = null;
        }
      }
    }

    const row = {
      uid: Number(uid) || 0,
      title: safeTitle,
      message: message.trim(),
      action: actionJson,
      read_status: 0,
      level: Number(level) || 0,
      is_public: Number(isPublic) !== 0 ? 1 : 0,
      create_time: new Date(),
    };

    const inserted = await this.knex(this.table).insert(row);
    const id = Array.isArray(inserted) ? inserted[0] : inserted;
    let actionObj = null;
    if (row.action && typeof row.action === 'string') {
      try {
        actionObj = JSON.parse(row.action);
      } catch (_) {
        actionObj = null;
      }
    }
    return { id, ...row, action: actionObj };
  }

  async getMessages({ uid = 0, page = 1, pageSize = 20, level = null, keyword = null, isAdmin = false }) {
    const userId = Number(uid) || 0;
    const pageNum = Math.max(1, Number(page) || 1);
    const size = Math.max(1, Math.min(100, Number(pageSize) || 20));
    const offset = (pageNum - 1) * size;

    let query = this.knex(this.table);

    if (isAdmin) {
      query = query.where(function () {
        this.where('is_public', 1).orWhere('is_public', 0);
      });
    } else {
      query = query.where(function () {
        this.where('is_public', 1).orWhere('uid', userId);
      });
    }

    if (level !== null && level !== undefined && level !== '') {
      query = query.where('level', Number(level));
    }

    if (keyword && typeof keyword === 'string' && keyword.trim()) {
      query = query.where('message', 'like', `%${keyword.trim()}%`);
    }

    const total = await query.clone().count('* as count').first();
    const rows = await query.orderBy('create_time', 'desc').limit(size).offset(offset);

    const items = (rows || []).map(r => {
      const title = r && typeof r.title === 'string' ? r.title : '';
      let actionObj = null;
      if (r && r.action && typeof r.action === 'string') {
        try {
          actionObj = JSON.parse(r.action);
        } catch (_) {
          actionObj = null;
        }
      } else if (r && r.action && typeof r.action === 'object') {
        actionObj = r.action;
      }
      return { ...r, title, action: actionObj };
    });

    return {
      items,
      total: total ? Number(total.count) : 0,
      page: pageNum,
      pageSize: size,
      totalPages: Math.ceil((total ? Number(total.count) : 0) / size),
    };
  }

  async markAsRead({ uid = 0, messageId = null, isAdmin = false }) {
    const userId = Number(uid) || 0;
    const msgId = Number(messageId);

    let query = this.knex(this.table);

    if (isAdmin) {
      if (msgId) {
        query = query.where('id', msgId);
      }
    } else {
      if (msgId) {
        query = query.where('id', msgId).where(function () {
          this.where('is_public', 1).orWhere('uid', userId);
        });
      } else {
        query = query.where(function () {
          this.where('is_public', 1).orWhere('uid', userId);
        });
      }
    }

    const affected = await query.update({ read_status: 1 });
    return { updated: affected };
  }

  async deleteMessage({ uid = 0, messageId = null, isAdmin = false }) {
    const userId = Number(uid) || 0;
    const msgId = Number(messageId);

    if (!msgId) {
      throw new Error('消息ID不能为空');
    }

    let query = this.knex(this.table).where('id', msgId);

    if (!isAdmin) {
      query = query.where(function () {
        this.where('is_public', 1).orWhere('uid', userId);
      });
    }

    const affected = await query.del();
    return { deleted: affected > 0 };
  }

  async clearMessages({ uid = 0, level = null, isAdmin = false }) {
    const userId = Number(uid) || 0;

    let query = this.knex(this.table);

    if (!isAdmin) {
      query = query.where(function () {
        this.where('is_public', 1).orWhere('uid', userId);
      });
    }

    if (level !== null && level !== undefined && level !== '') {
      query = query.where('level', Number(level));
    }

    const affected = await query.del();
    return { deleted: affected };
  }

  async getUnreadCount({ uid = 0, isAdmin = false }) {
    const userId = Number(uid) || 0;

    let query = this.knex(this.table).where('read_status', 0);

    if (isAdmin) {
      query = query.where(function () {
        this.where('is_public', 1).orWhere('is_public', 0);
      });
    } else {
      query = query.where(function () {
        this.where('is_public', 1).orWhere('uid', userId);
      });
    }

    const result = await query.count('* as count').first();
    return result ? Number(result.count) : 0;
  }
}

module.exports = {
  MessageService,
};
