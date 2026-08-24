const winston = require('winston');
const path = require('path');
const config = require('../config/config');

// 自定义日志格式
const logFormat = winston.format.combine(
  winston.format.timestamp({
    format: 'YYYY-MM-DD HH:mm:ss',
  }),
  winston.format.errors({ stack: true }),
  winston.format.json()
);

// 控制台输出格式
const consoleFormat = winston.format.combine(
  winston.format.colorize(),
  winston.format.timestamp({
    format: 'YYYY-MM-DD HH:mm:ss',
  }),
  winston.format.printf(({ timestamp, level, message, ...meta }) => {
    let log = `${timestamp} [${level}]: ${message}`;

    if (Object.keys(meta).length > 0) {
      log += ` ${JSON.stringify(meta)}`;
    }

    // 发送日志到主进程事件总线，用于UI显示
    try {
      process.emit('log-entry', { timestamp, level, message, meta });
    } catch (e) {
      // 忽略发送失败
    }

    return log;
  })
);

const recentLogs = [];
let logSeq = 0;
function pushRecent(level, message, meta) {
  recentLogs.push({ seq: ++logSeq, timestamp: new Date().toISOString(), level, message, meta });
  if (recentLogs.length > 500) recentLogs.shift();
}
const loggerInstance =
  // 创建logger实例
  winston.createLogger({
    level: config.logging.level,
    format: logFormat,
    defaultMeta: {}, //默认打印的后缀
    transports: [
      // 控制台输出
      new winston.transports.Console({
        format: consoleFormat,
      }),
    ],
  });

// 文件输出（如果启用）
if (config.logging.file.enabled) {
  loggerInstance.add(
    new winston.transports.File({
      filename: path.join(config.logging.file.path, 'error.log'),
      level: 'error',
      maxsize: 1024 * 1024, // 1MB
      maxFiles: 1,
    })
  );

  loggerInstance.add(
    new winston.transports.File({
      filename: path.join(config.logging.file.path, 'combined.log'),
      maxsize: 1024 * 1024, // 1MB
      maxFiles: 1,
    })
  );
}

// 自定义日志方法
class Logger {
  /**
   * 记录HTTP请求日志
   */
  static http(req, res, responseTime) {
    const logData = {
      method: req.method,
      url: req.url,
      statusCode: res.statusCode,
      userAgent: req.get('User-Agent'),
      ip: req.ip || req.connection.remoteAddress,
      responseTime: `${responseTime}ms`,
    };

    if (req.user) {
      logData.userId = req.user.id;
    }
    loggerInstance.info('HTTP Request', logData);
    pushRecent('info', 'HTTP Request', logData);
  }

  /**
   * 记录错误日志
   */
  static error(message, error = null, meta = {}) {
    const logData = {
      ...meta,
    };

    if (error) {
      logData.error = {
        message: error.message,
        stack: error.stack,
      };
    }

    loggerInstance.error(message, logData);
    pushRecent('error', message, logData);
  }

  /**
   * 记录业务操作日志
   */
  static business(operation, userId, details = {}) {
    const meta = {
      operation,
      userId,
      details,
    };
    loggerInstance.info('Business Operation', meta);
    pushRecent('info', 'Business Operation', meta);
  }

  /**
   * 记录数据库操作日志
   */
  static database(operation, query, duration, userId = null) {
    const meta = {
      operation,
      query: this.sanitizeQuery(query),
      duration: `${duration}ms`,
      userId,
    };
    loggerInstance.debug('Database Operation', meta);
    pushRecent('debug', 'Database Operation', meta);
  }

  /**
   * 记录安全相关日志
   */
  static security(event, userId, details = {}) {
    const meta = {
      event,
      userId,
      details,
    };
    // loggerInstance.warn('Security Event', meta);
    pushRecent('warn', 'Security Event', meta);
  }

  /**
   * 记录性能日志
   */
  static performance(operation, duration, details = {}) {
    const meta = {
      operation,
      duration: `${duration}ms`,
      ...details,
    };
    loggerInstance.info('Performance', meta);
    pushRecent('info', 'Performance', meta);
  }

  /**
   * 清理敏感信息的查询
   */
  static sanitizeQuery(query) {
    if (typeof query === 'string') {
      // 移除密码等敏感信息
      return query.replace(/password=['"][^'"]*['"]/gi, "password='***'");
    }
    return query;
  }

  /**
   * 记录调试信息
   */
  static debug(message, meta = {}) {
    loggerInstance.debug(message, meta);
    pushRecent('debug', message, meta);
  }

  /**
   * 记录信息
   */
  static info(message, meta = {}) {
    loggerInstance.info(message, meta);
    pushRecent('info', message, meta);
  }

  /**
   * 记录警告
   */
  static warn(message, meta = {}) {
    loggerInstance.warn(message, meta);
    pushRecent('warn', message, meta);
  }
  static getRecentLogs() {
    return recentLogs.slice(-500);
  }
  static getRecentAfter(lastSeq = 0) {
    return recentLogs.filter(l => (l.seq || 0) > lastSeq);
  }
}

module.exports = Logger;
