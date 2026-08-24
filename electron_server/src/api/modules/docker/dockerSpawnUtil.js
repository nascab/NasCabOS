const { AsyncLocalStorage } = require('async_hooks');
const { spawn } = require('child_process');
const { withAugmentedPath } = require('../../../utils/shellEnvUtil');

const DOCKER_PROBE_TIMEOUT_MS = 12 * 1000;
const DOCKER_COMMAND_TIMEOUT_MS = 90 * 1000;
const SHELL_COMMAND_TIMEOUT_MS = 60 * 1000;

const requestStore = new AsyncLocalStorage();
const requestChildren = new WeakMap();

function runWithRequest(req, fn) {
  if (typeof fn !== 'function') {
    return Promise.resolve();
  }
  if (!req) {
    return Promise.resolve().then(fn);
  }
  return requestStore.run({ req }, fn);
}

function trackRequestChild(req, child) {
  if (!req || !child) return;
  let children = requestChildren.get(req);
  if (!children) {
    children = new Set();
    requestChildren.set(req, children);
  }
  children.add(child);
  const untrack = () => {
    const set = requestChildren.get(req);
    if (set) set.delete(child);
  };
  child.once('close', untrack);
  child.once('error', untrack);
}

function killRequestChildren(req) {
  if (!req) return;
  const children = requestChildren.get(req);
  if (!children || children.size === 0) return;
  for (const child of Array.from(children)) {
    killProcessTree(child);
  }
  children.clear();
}

function killProcessTree(child) {
  if (!child || child.killed) return;
  const pid = child.pid;
  if (!pid) {
    try {
      child.kill();
    } catch (_) {}
    return;
  }
  if (process.platform === 'win32') {
    try {
      spawn('taskkill', ['/PID', String(pid), '/T', '/F'], {
        windowsHide: true,
        stdio: 'ignore',
      });
    } catch (_) {
      try {
        child.kill();
      } catch (_2) {}
    }
    return;
  }
  try {
    child.kill('SIGTERM');
  } catch (_) {}
  setTimeout(() => {
    if (child.exitCode != null || child.killed) return;
    try {
      child.kill('SIGKILL');
    } catch (_2) {}
  }, 1500).unref?.();
}

function runSpawn(commandName, args, options = {}) {
  const timeoutMs = options.timeoutMs === 0
    ? 0
    : Math.max(0, Number(options.timeoutMs || DOCKER_COMMAND_TIMEOUT_MS) || DOCKER_COMMAND_TIMEOUT_MS);
  const trackReq = options.trackRequest === false
    ? null
    : (options.req || (requestStore.getStore() && requestStore.getStore().req) || null);

  return new Promise((resolve, reject) => {
    let settled = false;
    let stdout = '';
    let stderr = '';
    let timer = null;

    const child = spawn(commandName, args, {
      env: {
        ...withAugmentedPath(process.env),
        ...withAugmentedPath(options.env || {}),
      },
      cwd: options.cwd || process.cwd(),
      windowsHide: true,
      stdio: options.stdio || ['pipe', 'pipe', 'pipe'],
    });

    if (trackReq) {
      trackRequestChild(trackReq, child);
    }

    const finish = (result, isError = false) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      if (isError) reject(result);
      else resolve(result);
    };

    if (timeoutMs > 0) {
      timer = setTimeout(() => {
        killProcessTree(child);
        finish({
          code: -1,
          stdout,
          stderr,
          timedOut: true,
          message: `Command timed out after ${timeoutMs}ms`,
        });
      }, timeoutMs);
      if (typeof timer.unref === 'function') timer.unref();
    }

    if (child.stdout) {
      child.stdout.on('data', chunk => {
        stdout += String(chunk || '');
        if (typeof options.onStdout === 'function') {
          options.onStdout(chunk);
        }
      });
    }
    if (child.stderr) {
      child.stderr.on('data', chunk => {
        stderr += String(chunk || '');
        if (typeof options.onStderr === 'function') {
          options.onStderr(chunk);
        }
      });
    }

    child.on('error', error => finish(error, true));
    child.on('close', code => {
      finish({
        code: Number(code) || 0,
        stdout,
        stderr,
        timedOut: false,
      });
    });

    if (options.stdin) {
      try {
        child.stdin.write(options.stdin);
      } catch (_) {}
    }
    if (options.endStdin !== false && child.stdin) {
      try {
        child.stdin.end();
      } catch (_) {}
    }

    if (typeof options.setup === 'function') {
      options.setup(child);
    }
  });
}

module.exports = {
  DOCKER_PROBE_TIMEOUT_MS,
  DOCKER_COMMAND_TIMEOUT_MS,
  SHELL_COMMAND_TIMEOUT_MS,
  runWithRequest,
  killRequestChildren,
  killProcessTree,
  runSpawn,
  trackRequestChild,
};
