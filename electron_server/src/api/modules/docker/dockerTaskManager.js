const os = require('os');
const {
  DOCKER_COMMAND_TIMEOUT_MS,
  runSpawn,
  killProcessTree,
} = require('./dockerSpawnUtil');

function nowIso() {
  return new Date().toISOString();
}

function splitLines(buffer, chunk) {
  const text = buffer + String(chunk || '');
  const parts = text.split(/\r?\n/);
  return {
    lines: parts.slice(0, -1),
    remain: parts[parts.length - 1] || '',
  };
}

function shellQuote(value) {
  const s = String(value == null ? '' : value);
  if (!s) return "''";
  if (/^[A-Za-z0-9_./:=,@%-]+$/.test(s)) return s;
  return `'${s.replace(/'/g, `'\\''`)}'`;
}

class DockerTaskManager {
  constructor() {
    this.tasks = new Map();
    this.runningByKey = new Map();
    this.logLimit = 4000;
  }

  createTask(options) {
    const dedupeKey = String(options && options.dedupeKey ? options.dedupeKey : '').trim();
    if (dedupeKey) {
      const existingId = this.runningByKey.get(dedupeKey);
      if (existingId) {
        const existing = this.tasks.get(existingId);
        if (existing && (existing.status === 'queued' || existing.status === 'running')) {
          return existing;
        }
        this.runningByKey.delete(dedupeKey);
      }
    }

    const id = `docker_task_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    const task = {
      id,
      type: String(options && options.type ? options.type : 'command'),
      title: String(options && options.title ? options.title : 'Docker Task'),
      dedupeKey,
      status: 'queued',
      progress: null,
      createdAt: nowIso(),
      startedAt: null,
      finishedAt: null,
      exitCode: null,
      errorCode: '',
      errorMessage: '',
      metadata: options && options.metadata && typeof options.metadata === 'object' ? { ...options.metadata } : {},
      command: options && options.command ? String(options.command) : '',
      logs: [],
      result: null,
      canCancel: true,
    };

    this.tasks.set(id, task);
    if (dedupeKey) this.runningByKey.set(dedupeKey, id);

    Promise.resolve()
      .then(async () => {
        task.status = 'running';
        task.startedAt = nowIso();
        await options.runner(this._buildContext(task));
        if (task.status === 'running') {
          task.status = 'success';
          task.finishedAt = nowIso();
          task.canCancel = false;
        }
      })
      .catch(error => {
        if (task.status !== 'cancelled') {
          task.status = 'failed';
        }
        task.errorCode = error && error.code ? String(error.code) : 'docker.COMMAND_FAILED';
        task.errorMessage = error && error.message ? String(error.message) : '';
        task.result = error && error.data !== undefined ? error.data : null;
        task.finishedAt = nowIso();
        task.canCancel = false;
      })
      .finally(() => {
        if (dedupeKey && this.runningByKey.get(dedupeKey) === id) {
          this.runningByKey.delete(dedupeKey);
        }
      });

    return task;
  }

  _buildContext(task) {
    return {
      task,
      setProgress: progress => {
        const num = Number(progress);
        task.progress = Number.isFinite(num) ? Math.max(0, Math.min(100, num)) : null;
      },
      appendLog: (line, source = 'stdout') => {
        const text = String(line == null ? '' : line).trimEnd();
        if (!text) return;
        task.logs.push({
          ts: nowIso(),
          source,
          text,
        });
        if (task.logs.length > this.logLimit) {
          task.logs.splice(0, task.logs.length - this.logLimit);
        }
      },
      setResult: result => {
        task.result = result;
      },
      markCancelled: () => {
        task.status = 'cancelled';
        task.finishedAt = nowIso();
        task.canCancel = false;
      },
      runCommand: (command, args, runOptions = {}) => this.runCommand(task, command, args, runOptions),
      ensureRunning: () => {
        if (task.status === 'cancelled') {
          const error = new Error('Task cancelled');
          error.code = 'docker.TASK_CANCELLED';
          throw error;
        }
      },
    };
  }

  runCommand(task, command, args, options = {}) {
    const timeoutMs = options.timeoutMs === 0
      ? 0
      : (options.timeoutMs != null ? options.timeoutMs : DOCKER_COMMAND_TIMEOUT_MS);
    let stdout = '';
    let stderr = '';
    let stdoutRemain = '';
    let stderrRemain = '';
    let childRef = null;

    const onLine = (line, source) => {
      if (!line) return;
      this._buildContext(task).appendLog(line, source);
      if (typeof options.onLine === 'function') {
        options.onLine(line, source);
      }
    };

    task.command = [command, ...args].map(shellQuote).join(' ');

    return runSpawn(command, args, {
      ...options,
      timeoutMs,
      trackRequest: false,
      setup(child) {
        childRef = child;
        task.childPid = child.pid || null;
        task.cancel = () => {
          if (!childRef) return false;
          killProcessTree(childRef);
          return true;
        };
      },
      onStdout(chunk) {
        stdout += String(chunk || '');
        const parsed = splitLines(stdoutRemain, chunk);
        stdoutRemain = parsed.remain;
        parsed.lines.forEach(line => onLine(line, 'stdout'));
      },
      onStderr(chunk) {
        stderr += String(chunk || '');
        const parsed = splitLines(stderrRemain, chunk);
        stderrRemain = parsed.remain;
        parsed.lines.forEach(line => onLine(line, 'stderr'));
      },
    }).then(result => {
      task.childPid = null;
      if (stdoutRemain) onLine(stdoutRemain, 'stdout');
      if (stderrRemain) onLine(stderrRemain, 'stderr');
      return result;
    }).catch(error => {
      task.childPid = null;
      throw error;
    });
  }

  listTasks(query = {}) {
    const statusFilter = String(query.status || '').trim().toLowerCase();
    const items = Array.from(this.tasks.values())
      .filter(task => (statusFilter ? task.status === statusFilter : true))
      .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
    return items.map(task => this._serializeTask(task, false));
  }

  getTask(id) {
    const task = this.tasks.get(String(id || '').trim());
    return task ? this._serializeTask(task, true) : null;
  }

  getTaskLogs(id, offset = 0, limit = 200) {
    const task = this.tasks.get(String(id || '').trim());
    if (!task) return null;
    const start = Math.max(0, Number(offset) || 0);
    const size = Math.max(1, Math.min(1000, Number(limit) || 200));
    return {
      items: task.logs.slice(start, start + size),
      total: task.logs.length,
      offset: start,
      limit: size,
      hasMore: start + size < task.logs.length,
    };
  }

  cancelTask(id) {
    const task = this.tasks.get(String(id || '').trim());
    if (!task) return null;
    if (task.status !== 'queued' && task.status !== 'running') return task;
    if (typeof task.cancel === 'function') {
      task.cancel();
    }
    task.status = 'cancelled';
    task.finishedAt = nowIso();
    task.canCancel = false;
    return task;
  }

  deleteTask(id) {
    const taskId = String(id || '').trim();
    const task = this.tasks.get(taskId);
    if (!task) return null;
    if (task.status === 'queued' || task.status === 'running') return false;
    this.tasks.delete(taskId);
    if (task.dedupeKey && this.runningByKey.get(task.dedupeKey) === taskId) {
      this.runningByKey.delete(task.dedupeKey);
    }
    return task;
  }

  _serializeTask(task, includeLogs) {
    return {
      id: task.id,
      type: task.type,
      title: task.title,
      status: task.status,
      progress: task.progress,
      createdAt: task.createdAt,
      startedAt: task.startedAt,
      finishedAt: task.finishedAt,
      exitCode: task.exitCode,
      errorCode: task.errorCode,
      errorMessage: task.errorMessage,
      metadata: { ...task.metadata },
      command: task.command,
      canCancel: task.canCancel === true && (task.status === 'queued' || task.status === 'running'),
      result: task.result,
      logCount: task.logs.length,
      logs: includeLogs ? task.logs.slice() : undefined,
      host: os.hostname(),
    };
  }
}

module.exports = new DockerTaskManager();
