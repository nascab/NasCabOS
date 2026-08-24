const os = require('os');
const path = require('path');
const fs = require('fs-extra');
const tableConfig = require('../../../db/table/tableConfig');
const dockerTaskManager = require('./dockerTaskManager');
const { requestDockerTask } = require('./dockerTaskIpcClient');
const { withAugmentedPath } = require('../../../utils/shellEnvUtil');
const {
  DOCKER_PROBE_TIMEOUT_MS,
  SHELL_COMMAND_TIMEOUT_MS,
  runSpawn,
} = require('./dockerSpawnUtil');
const {
  DockerEngineClient,
  parseMemoryToBytes,
  parseCpusToNano,
} = require('./dockerEngineClient');

const READY_CACHE_TTL_MS = 5000;
const READY_FAIL_CACHE_TTL_MS = 2500;

class DockerApiError extends Error {
  constructor(code, statusCode = 500, message = '', data = null, args = []) {
    super(message || code);
    this.code = code || 'common.ERROR';
    this.statusCode = Number(statusCode) || 500;
    this.data = data;
    this.args = Array.isArray(args) ? args : [];
  }
}

function trimText(value) {
  return value == null ? '' : String(value).trim();
}

function splitCsv(value) {
  return trimText(value)
    .split(',')
    .map(item => item.trim())
    .filter(Boolean);
}

function parseBool(value, defaultValue = false) {
  if (typeof value === 'boolean') return value;
  const raw = trimText(value).toLowerCase();
  if (!raw) return defaultValue;
  if (['1', 'true', 'yes', 'on'].includes(raw)) return true;
  if (['0', 'false', 'no', 'off'].includes(raw)) return false;
  return defaultValue;
}

function parsePositiveInt(value, fallback = null) {
  if (value === '' || value == null) return fallback;
  const num = Number(value);
  if (!Number.isInteger(num) || num < 0) return fallback;
  return num;
}

function shellQuote(value) {
  const s = String(value == null ? '' : value);
  if (!s) return "''";
  if (/^[A-Za-z0-9_./:=,@%-]+$/.test(s)) return s;
  return `'${s.replace(/'/g, `'\\''`)}'`;
}

function splitCommandString(command) {
  const raw = trimText(command);
  if (!raw) return [];
  const result = [];
  let current = '';
  let quote = '';
  let escape = false;
  for (const char of raw) {
    if (escape) {
      current += char;
      escape = false;
      continue;
    }
    if (char === '\\') {
      escape = true;
      continue;
    }
    if (quote) {
      if (char === quote) {
        quote = '';
      } else {
        current += char;
      }
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      continue;
    }
    if (/\s/.test(char)) {
      if (current) {
        result.push(current);
        current = '';
      }
      continue;
    }
    current += char;
  }
  if (current) result.push(current);
  return result;
}

function safeJsonParse(text, fallback = null) {
  try {
    return JSON.parse(text);
  } catch (_) {
    return fallback;
  }
}

function isJsonObject(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function parseDockerJsonLines(stdout) {
  return String(stdout || '')
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(Boolean)
    .map(line => safeJsonParse(line, null))
    .filter(Boolean);
}

function buildImageReference({ registry, image, tag, imageId }) {
  const imageName = trimText(image);
  const id = trimText(imageId);
  if (!imageName || imageName === '<none>') {
    if (!id) {
      throw new DockerApiError('docker.INVALID_IMAGE_REF', 400);
    }
    return id;
  }
  const registryHost = trimText(registry).replace(/\/+$/, '');
  const imageRef = registryHost && !imageName.startsWith(registryHost) ? `${registryHost}/${imageName}` : imageName;
  const rawTag = trimText(tag);
  const imageTag = !rawTag || rawTag === '<none>' ? 'latest' : rawTag;
  return imageRef.includes(':') ? imageRef : `${imageRef}:${imageTag}`;
}

function buildImageDisplayReference({ repository, tag, id }) {
  const repo = trimText(repository);
  const imageTag = trimText(tag);
  const imageId = trimText(id);
  if (repo === '<none>' && imageTag === '<none>') return '<none>';
  if (repo && imageTag) return `${repo}:${imageTag}`;
  return repo || imageId || '';
}

function isSupportedDockerImageArchive(filePath) {
  const lower = trimText(filePath).toLowerCase();
  return lower.endsWith('.tar') || lower.endsWith('.tar.gz') || lower.endsWith('.tgz');
}

function normalizeProxyUrl(value) {
  const raw = trimText(value);
  if (!raw) return '';
  if (raw.includes('://')) return raw;
  return `http://${raw}`;
}

function validateProxyUrl(value) {
  const normalized = normalizeProxyUrl(value);
  if (!normalized) return '';
  let parsed;
  try {
    parsed = new URL(normalized);
  } catch (_) {
    throw new DockerApiError('docker.INVALID_PROXY_URL', 400);
  }
  if (!parsed.hostname || !['http:', 'https:'].includes(parsed.protocol)) {
    throw new DockerApiError('docker.INVALID_PROXY_URL', 400);
  }
  return normalized;
}

function sanitizeEnvList(input) {
  if (Array.isArray(input)) {
    return input
      .map(item => {
        if (typeof item === 'string') return item.trim();
        if (item && typeof item === 'object') {
          const key = trimText(item.key || item.name);
          if (!key) return '';
          const value = item.value == null ? '' : String(item.value);
          return `${key}=${value}`;
        }
        return '';
      })
      .filter(Boolean);
  }
  if (input && typeof input === 'object') {
    return Object.entries(input)
      .filter(([key]) => trimText(key))
      .map(([key, value]) => `${trimText(key)}=${value == null ? '' : String(value)}`);
  }
  return [];
}

function sanitizePortBindings(input) {
  const list = Array.isArray(input) ? input : [];
  return list.map(item => {
    const containerPort = parsePositiveInt(item && (item.containerPort || item.target));
    const hostPort = parsePositiveInt(item && (item.hostPort || item.published));
    const hostIp = trimText(item && (item.hostIp || item.hostIP));
    const protocol = trimText(item && item.protocol).toLowerCase() || 'tcp';
    if (!containerPort || !hostPort || !['tcp', 'udp'].includes(protocol)) {
      throw new DockerApiError('docker.INVALID_PORT_BINDING', 400);
    }
    return {
      containerPort,
      hostPort,
      hostIp,
      protocol,
    };
  });
}

function sanitizeVolumeBindings(input) {
  const list = Array.isArray(input) ? input : [];
  return list.map(item => {
    const source = trimText(item && (item.source || item.hostPath));
    const target = trimText(item && (item.target || item.containerPath));
    const readOnly = parseBool(item && (item.readOnly || item.read_only), false);
    if (!source || !target) {
      throw new DockerApiError('docker.INVALID_VOLUME_BINDING', 400);
    }
    return {
      source,
      target,
      readOnly,
    };
  });
}

function buildPortMap(ports) {
  const result = [];
  if (!ports || typeof ports !== 'object') return result;
  for (const [containerPort, bindings] of Object.entries(ports)) {
    const normalizedBindings = Array.isArray(bindings) ? bindings : [];
    if (normalizedBindings.length === 0) {
      result.push({
        containerPort,
        hostPort: '',
        hostIp: '',
      });
      continue;
    }
    for (const item of normalizedBindings) {
      result.push({
        containerPort,
        hostPort: item && item.HostPort ? String(item.HostPort) : '',
        hostIp: item && item.HostIp ? String(item.HostIp) : '',
      });
    }
  }
  return result;
}

function mapApiImageItem(img) {
  const tags = Array.isArray(img.RepoTags) ? img.RepoTags.filter(Boolean) : [];
  let repository = '<none>';
  let tag = '<none>';
  if (tags.length > 0) {
    const ref = tags[0];
    const idx = ref.lastIndexOf(':');
    if (idx > 0) {
      repository = ref.slice(0, idx);
      tag = ref.slice(idx + 1);
    } else {
      repository = ref;
      tag = 'latest';
    }
  }
  let digest = '';
  if (Array.isArray(img.RepoDigests) && img.RepoDigests[0]) {
    const at = img.RepoDigests[0].indexOf('@');
    digest = at >= 0 ? img.RepoDigests[0].slice(at + 1) : img.RepoDigests[0];
  }
  return {
    id: img.Id || '',
    repository,
    tag,
    digest,
    createdAt: img.Created ? new Date(img.Created * 1000).toISOString() : '',
    createdSince: '',
    size: img.Size != null ? String(img.Size) : '',
    reference: buildImageDisplayReference({
      repository,
      tag,
      id: img.Id || '',
    }),
  };
}

function buildCreateContainerSpec({
  imageRef,
  commandList,
  envList,
  ports,
  volumes,
  resources,
  payload,
}) {
  const hostConfig = {};
  const exposedPorts = {};
  if (ports.length > 0) {
    hostConfig.PortBindings = {};
    ports.forEach(item => {
      const key = `${item.containerPort}/${item.protocol}`;
      hostConfig.PortBindings[key] = [{
        HostPort: String(item.hostPort),
        HostIp: item.hostIp || '',
      }];
      exposedPorts[key] = {};
    });
  }
  if (volumes.length > 0) {
    hostConfig.Binds = volumes.map(item => `${item.source}:${item.target}${item.readOnly ? ':ro' : ''}`);
  }
  const memory = parseMemoryToBytes(resources.memory);
  if (memory != null) hostConfig.Memory = memory;
  const memorySwap = parseMemoryToBytes(resources.memorySwap);
  if (memorySwap != null) hostConfig.MemorySwap = memorySwap;
  const nanoCpus = parseCpusToNano(resources.cpus);
  if (nanoCpus != null) hostConfig.NanoCPUs = nanoCpus;
  const restartPolicy = trimText(payload.restartPolicy);
  if (restartPolicy) {
    hostConfig.RestartPolicy = { Name: restartPolicy };
  }

  const body = {
    Image: imageRef,
    Env: envList,
  };
  if (Object.keys(exposedPorts).length > 0) {
    body.ExposedPorts = exposedPorts;
  }
  if (commandList.length > 0) body.Cmd = commandList;
  const workingDir = trimText(payload.workingDir);
  if (workingDir) body.WorkingDir = workingDir;
  const entrypoint = trimText(payload.entrypoint);
  if (entrypoint) body.Entrypoint = [entrypoint];
  if (Object.keys(hostConfig).length > 0) body.HostConfig = hostConfig;
  const network = trimText(payload.network);
  if (network) {
    body.NetworkingConfig = {
      EndpointsConfig: {
        [network]: {},
      },
    };
  }
  return body;
}

function mapDockerFailure(errorOrMessage) {
  if (errorOrMessage && typeof errorOrMessage === 'object') {
    if (errorOrMessage.timedOut === true) {
      return new DockerApiError('docker.DOCKER_UNAVAILABLE', 503, 'Docker command timed out');
    }
    const statusCode = Number(errorOrMessage.statusCode) || 0;
    const statusMessage = trimText(errorOrMessage.message);
    if (statusCode === 404) {
      const lower = statusMessage.toLowerCase();
      if (lower.includes('container')) {
        return new DockerApiError('docker.CONTAINER_NOT_FOUND', 404, statusMessage);
      }
      return new DockerApiError('docker.IMAGE_NOT_FOUND', 404, statusMessage);
    }
    if (statusCode === 400) {
      const lower = statusMessage.toLowerCase();
      if (lower.includes('invalid reference format') || lower.includes('invalid image')) {
        return new DockerApiError('docker.INVALID_IMAGE_REF', 400, statusMessage);
      }
      if (lower.includes('invalid volume') || lower.includes('invalid mount')) {
        return new DockerApiError('docker.INVALID_VOLUME_BINDING', 400, statusMessage);
      }
      if (lower.includes('invalid containerport') || lower.includes('invalid hostport') || lower.includes('port')) {
        return new DockerApiError('docker.INVALID_PORT_BINDING', 400, statusMessage);
      }
      if (lower.includes('container name')) {
        return new DockerApiError('docker.CONTAINER_NAME_CONFLICT', 409, statusMessage);
      }
      return new DockerApiError('docker.COMMAND_FAILED', 400, statusMessage);
    }
    if (statusCode === 403) {
      return new DockerApiError('docker.IMAGE_PULL_DENIED', 403, statusMessage);
    }
    if (statusCode === 409) {
      const lower = statusMessage.toLowerCase();
      if (lower.includes('port is already allocated')) {
        return new DockerApiError('docker.PORT_ALREADY_ALLOCATED', 409, statusMessage);
      }
      if (lower.includes('already in use') || lower.includes('is using its referenced image')) {
        return new DockerApiError('docker.IMAGE_IN_USE', 409, statusMessage);
      }
      if (lower.includes('container name')) {
        return new DockerApiError('docker.CONTAINER_NAME_CONFLICT', 409, statusMessage);
      }
      return new DockerApiError('docker.CONTAINER_CONFLICT', 409, statusMessage);
    }
    if (statusCode === 503 || statusCode === 499) {
      return new DockerApiError('docker.DOCKER_UNAVAILABLE', 503, statusMessage || 'Docker engine unavailable');
    }
  }
  const raw = typeof errorOrMessage === 'string'
    ? errorOrMessage
    : trimText([
      errorOrMessage && errorOrMessage.stderr,
      errorOrMessage && errorOrMessage.stdout,
      errorOrMessage && errorOrMessage.message,
    ].filter(Boolean).join('\n'));
  const lower = raw.toLowerCase();
  if (!lower) return new DockerApiError('docker.COMMAND_FAILED', 500, raw);
  if (lower.includes('command timed out') || lower.includes('timed out after')) {
    return new DockerApiError('docker.DOCKER_UNAVAILABLE', 503, raw || 'Docker command timed out');
  }
  if (lower.includes('api version') || lower.includes('minimum supported api version') || lower.includes('maximum supported api version')) {
    return new DockerApiError('docker.DOCKER_UNAVAILABLE', 503, raw);
  }
  if (
    lower.includes('spawn docker enoent') ||
    lower.includes('docker: command not found') ||
    lower.includes('commandnotfoundexception') ||
    (lower.includes('objectnotfound: (docker:string)') && lower.includes('fullyqualifiederrorid'))
  ) {
    return new DockerApiError('docker.DOCKER_COMMAND_NOT_FOUND', 500, raw);
  }
  if (
    lower.includes('cannot connect to the docker daemon') ||
    lower.includes('cannot connect to the docker daemon at') ||
    lower.includes('failed to connect to the docker api at') ||
    lower.includes('check if the path is correct and if the daemon is running') ||
    lower.includes('is the docker daemon running') ||
    lower.includes('docker daemon is not running') ||
    lower.includes('error during connect') ||
    lower.includes('econnrefused') ||
    lower.includes('connect enoent') ||
    lower.includes('connect eacces') ||
    lower.includes('this error may indicate that the docker daemon is not running') ||
    lower.includes('docker desktop is not running') ||
    (lower.includes('dial unix') && lower.includes('docker.sock')) ||
    (lower.includes('open //./pipe/docker_engine') && lower.includes('the system cannot find the file specified'))
  ) {
    return new DockerApiError('docker.DOCKER_UNAVAILABLE', 503, raw);
  }
  if (lower.includes('no such image')) {
    return new DockerApiError('docker.IMAGE_NOT_FOUND', 404, raw);
  }
  if (lower.includes('manifest for') && lower.includes('not found')) {
    return new DockerApiError('docker.IMAGE_NOT_FOUND', 404, raw);
  }
  if (lower.includes(`pull access denied`) || lower.includes('requested access to the resource is denied') || lower.includes('authentication required')) {
    return new DockerApiError('docker.IMAGE_PULL_DENIED', 403, raw);
  }
  if (lower.includes('no such container')) {
    return new DockerApiError('docker.CONTAINER_NOT_FOUND', 404, raw);
  }
  if (lower.includes('container name') && lower.includes('already in use')) {
    return new DockerApiError('docker.CONTAINER_NAME_CONFLICT', 409, raw);
  }
  if (lower.includes('port is already allocated')) {
    return new DockerApiError('docker.PORT_ALREADY_ALLOCATED', 409, raw);
  }
  if (lower.includes('invalid reference format')) {
    return new DockerApiError('docker.INVALID_IMAGE_REF', 400, raw);
  }
  if (lower.includes('invalid volume specification') || lower.includes('invalid mount config')) {
    return new DockerApiError('docker.INVALID_VOLUME_BINDING', 400, raw);
  }
  if (lower.includes('invalid containerport') || lower.includes('invalid hostport') || lower.includes('port format')) {
    return new DockerApiError('docker.INVALID_PORT_BINDING', 400, raw);
  }
  if (
    (lower.includes('conflict') && lower.includes('image is being used by running container')) ||
    (lower.includes('conflict') && lower.includes('container') && lower.includes('is using its referenced image'))
  ) {
    return new DockerApiError('docker.IMAGE_IN_USE', 409, raw);
  }
  if (lower.includes('no space left on device') || lower.includes('cannot allocate memory') || lower.includes('insufficient memory')) {
    return new DockerApiError('docker.RESOURCE_INSUFFICIENT', 507, raw);
  }
  if (lower.includes('conflict')) {
    return new DockerApiError('docker.CONTAINER_CONFLICT', 409, raw);
  }
  return new DockerApiError('docker.COMMAND_FAILED', 500, raw);
}

class DockerService {
  constructor(options = {}) {
    this.engine = new DockerEngineClient();
    this.KEY_HTTP_PROXY = 'dockerHttpProxy';
    this.KEY_HTTPS_PROXY = 'dockerHttpsProxy';
    this.KEY_NO_PROXY = 'dockerNoProxy';
    this.taskTransport = trimText(options.taskTransport) || 'ipc';
    this.daemonConfigPath = trimText(options.daemonConfigPath || process.env.DOCKER_DAEMON_CONFIG_PATH);
    this._readyCache = { at: 0, info: null, error: null };
    this._readyInFlight = null;
  }

  _useLocalTaskTransport() {
    return this.taskTransport === 'local';
  }

  async _requestTaskWorker(action, payload = {}, timeoutMs = 15000) {
    if (this._useLocalTaskTransport()) {
      throw new DockerApiError('common.ERROR', 500);
    }
    const response = await requestDockerTask(action, payload, { timeoutMs });
    if (response && response.ok === true) {
      return response.data;
    }
    const error = response && response.error && typeof response.error === 'object' ? response.error : {};
    throw new DockerApiError(
      error.code || 'common.ERROR',
      error.statusCode || 500,
      error.message || '',
      error.data !== undefined ? error.data : null,
      Array.isArray(error.args) ? error.args : []
    );
  }

  async runCommand(commandName, args, options = {}) {
    const timeoutMs = options.timeoutMs === 0
      ? 0
      : (options.timeoutMs != null ? options.timeoutMs : SHELL_COMMAND_TIMEOUT_MS);
    try {
      return await runSpawn(commandName, args, {
        ...options,
        timeoutMs,
      });
    } catch (error) {
      throw error instanceof DockerApiError ? error : mapDockerFailure(error);
    }
  }

  _getReadyCache(now = Date.now()) {
    const cache = this._readyCache;
    if (!cache || !cache.at) return null;
    const ttl = cache.info ? READY_CACHE_TTL_MS : READY_FAIL_CACHE_TTL_MS;
    if (now - cache.at > ttl) return null;
    if (cache.error) throw cache.error;
    return cache.info;
  }

  _setReadyCache(info, error = null) {
    this._readyCache = {
      at: Date.now(),
      info: info || null,
      error: error || null,
    };
  }

  invalidateReadyCache() {
    this._readyCache = { at: 0, info: null, error: null };
    this._readyInFlight = null;
  }

  async resolveDaemonConfigPath() {
    const candidates = [];
    if (this.daemonConfigPath) candidates.push(this.daemonConfigPath);
    if (process.platform === 'win32') {
      const programData = trimText(process.env.ProgramData) || 'C:\\ProgramData';
      candidates.push(path.join(programData, 'docker', 'config', 'daemon.json'));
    } else {
      candidates.push('/etc/docker/daemon.json');
      candidates.push(path.join(os.homedir(), '.docker', 'daemon.json'));
    }
    for (const filePath of candidates) {
      if (filePath && await fs.pathExists(filePath)) {
        return filePath;
      }
    }
    return candidates.find(Boolean) || '/etc/docker/daemon.json';
  }

  validateDaemonConfigContent(content) {
    const raw = String(content == null ? '' : content);
    const trimmed = raw.trim();
    if (!trimmed) {
      throw new DockerApiError('docker.INVALID_CONFIG_JSON', 400, 'Docker config file content cannot be empty.');
    }
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (error) {
      throw new DockerApiError('docker.INVALID_CONFIG_JSON', 400, `Docker config file is not valid JSON: ${error.message}`);
    }
    if (!isJsonObject(parsed)) {
      throw new DockerApiError('docker.INVALID_CONFIG_JSON', 400, 'Docker config file must be a JSON object.');
    }
    return {
      parsed,
      content: raw.endsWith('\n') ? raw : `${raw}\n`,
    };
  }

  describeDaemonConfig(content) {
    const raw = String(content == null ? '' : content);
    const trimmed = raw.trim();
    if (!trimmed) {
      return {
        content: '{\n}\n',
        jsonValid: true,
        jsonType: 'object',
        validationMessage: '',
      };
    }
    try {
      const parsed = JSON.parse(raw);
      if (!isJsonObject(parsed)) {
        return {
          content: raw,
          jsonValid: false,
          jsonType: Array.isArray(parsed) ? 'array' : typeof parsed,
          validationMessage: 'Docker config file must be a JSON object.',
        };
      }
      return {
        content: raw,
        jsonValid: true,
        jsonType: 'object',
        validationMessage: '',
      };
    } catch (error) {
      return {
        content: raw,
        jsonValid: false,
        jsonType: 'invalid',
        validationMessage: error.message,
      };
    }
  }

  async getDaemonConfig() {
    const configPath = await this.resolveDaemonConfigPath();
    const exists = await fs.pathExists(configPath);
    const rawContent = exists ? await fs.readFile(configPath, 'utf8') : '{\n}\n';
    const configInfo = this.describeDaemonConfig(rawContent);
    return {
      path: configPath,
      exists,
      ...configInfo,
    };
  }

  async saveDaemonConfig(payload) {
    const configPath = await this.resolveDaemonConfigPath();
    const configInfo = this.validateDaemonConfigContent(payload && payload.content);
    await fs.ensureDir(path.dirname(configPath));
    await fs.writeFile(configPath, configInfo.content, 'utf8');
    return {
      path: configPath,
      exists: true,
      content: configInfo.content,
      jsonValid: true,
      jsonType: 'object',
      validationMessage: '',
    };
  }

  buildStartCommands() {
    if (process.platform === 'win32') {
      return [
        {
          command: 'powershell.exe',
          args: ['-NoProfile', '-Command', 'Start-Service docker'],
        },
      ];
    }
    if (process.platform === 'darwin') {
      return [
        {
          command: 'open',
          args: ['-a', 'Docker'],
        },
      ];
    }
    return [
      {
        command: 'systemctl',
        args: ['start', 'docker'],
      },
      {
        command: 'service',
        args: ['docker', 'start'],
      },
    ];
  }

  buildStopCommands() {
    if (process.platform === 'win32') {
      return [
        {
          command: 'powershell.exe',
          args: ['-NoProfile', '-Command', 'Stop-Service docker'],
        },
      ];
    }
    if (process.platform === 'darwin') {
      return [
        {
          command: 'osascript',
          args: ['-e', 'quit app "Docker"'],
          allowFailure: true,
        },
      ];
    }
    return [
      {
        command: 'systemctl',
        args: ['stop', 'docker'],
      },
      {
        command: 'service',
        args: ['docker', 'stop'],
      },
    ];
  }

  async isMacDockerAppRunning() {
    const result = await this.runCommand('pgrep', ['-x', 'Docker']);
    return result.code === 0 && trimText(result.stdout).length > 0;
  }

  async waitForMacDockerAppState(shouldBeRunning, timeoutMs = 15000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const running = await this.isMacDockerAppRunning();
      if (running === shouldBeRunning) {
        return true;
      }
      await sleep(500);
    }
    return false;
  }

  async _startDockerNow() {
    const commands = this.buildStartCommands();
    let lastErrorMessage = '';
    if (process.platform === 'darwin') {
      for (const item of commands) {
        const result = await this.runCommand(item.command, item.args);
        if (result.code !== 0 && !item.allowFailure) {
          lastErrorMessage = trimText(result.stderr || result.stdout);
          break;
        }
      }
      if (!lastErrorMessage) {
        return {
          started: true,
          platform: process.platform,
        };
      }
      throw new DockerApiError('docker.START_FAILED', 500, lastErrorMessage || 'Failed to start Docker.');
    }
    for (const item of commands) {
      const result = await this.runCommand(item.command, item.args);
      if (result.code === 0) {
        return {
          started: true,
          platform: process.platform,
        };
      }
      lastErrorMessage = trimText(result.stderr || result.stdout);
    }
    throw new DockerApiError('docker.START_FAILED', 500, lastErrorMessage || 'Failed to start Docker.');
  }

  async _stopDockerNow() {
    const commands = this.buildStopCommands();
    let lastErrorMessage = '';
    if (process.platform === 'darwin') {
      for (const item of commands) {
        const result = await this.runCommand(item.command, item.args);
        if (result.code !== 0 && !item.allowFailure) {
          lastErrorMessage = trimText(result.stderr || result.stdout);
          break;
        }
      }
      if (!lastErrorMessage) {
        return {
          stopped: true,
          platform: process.platform,
        };
      }
      throw new DockerApiError('docker.STOP_FAILED', 500, lastErrorMessage || 'Failed to stop Docker.');
    }
    for (const item of commands) {
      const result = await this.runCommand(item.command, item.args);
      if (result.code === 0) {
        return {
          stopped: true,
          platform: process.platform,
        };
      }
      lastErrorMessage = trimText(result.stderr || result.stdout);
    }
    throw new DockerApiError('docker.STOP_FAILED', 500, lastErrorMessage || 'Failed to stop Docker.');
  }

  async startDocker(payload = {}) {
    this.invalidateReadyCache();
    if (!this._useLocalTaskTransport()) {
      return await this._requestTaskWorker('startDocker', payload || {}, 30000);
    }
    return await this._startDockerLocal(payload);
  }

  async _startDockerLocal() {
    const dedupeKey = 'docker_service:start';
    const task = dockerTaskManager.createTask({
      type: 'start_docker',
      title: 'Docker',
      dedupeKey,
      metadata: {
        action: 'start',
      },
      runner: async ctx => {
        ctx.appendLog('Starting Docker service...', 'stdout');
        const result = await this._startDockerNow();
        ctx.setResult(result);
        ctx.appendLog('Docker service start request completed.', 'stdout');
      },
    });
    return this.getTask(task.id);
  }

  async stopDocker(payload = {}) {
    this.invalidateReadyCache();
    if (!this._useLocalTaskTransport()) {
      return await this._requestTaskWorker('stopDocker', payload || {}, 30000);
    }
    return await this._stopDockerLocal(payload);
  }

  async _stopDockerLocal() {
    const dedupeKey = 'docker_service:stop';
    const task = dockerTaskManager.createTask({
      type: 'stop_docker',
      title: 'Docker',
      dedupeKey,
      metadata: {
        action: 'stop',
      },
      runner: async ctx => {
        ctx.appendLog('Stopping Docker service...', 'stdout');
        const result = await this._stopDockerNow();
        ctx.setResult(result);
        ctx.appendLog('Docker service stop request completed.', 'stdout');
      },
    });
    return this.getTask(task.id);
  }

  async ensureDockerReady() {
    const cached = this._getReadyCache();
    if (cached) return cached;
    if (this._readyInFlight) {
      return this._readyInFlight;
    }
    this._readyInFlight = this._probeDockerReady()
      .finally(() => {
        this._readyInFlight = null;
      });
    return this._readyInFlight;
  }

  async _probeDockerReady() {
    try {
      await this.engine.ping({ timeoutMs: DOCKER_PROBE_TIMEOUT_MS });
      const info = await this.engine.info({ timeoutMs: DOCKER_PROBE_TIMEOUT_MS });
      this._setReadyCache(info);
      return info;
    } catch (error) {
      const normalized = error instanceof DockerApiError ? error : mapDockerFailure(error);
      this._setReadyCache(null, normalized);
      throw normalized;
    }
  }

  async getProxyConfig(options = {}) {
    if (!options.skipReadyCheck) {
      await this.ensureDockerReady();
    }
    const [httpProxy, httpsProxy, noProxy] = await Promise.all([
      tableConfig.getConfigByKey(this.KEY_HTTP_PROXY),
      tableConfig.getConfigByKey(this.KEY_HTTPS_PROXY),
      tableConfig.getConfigByKey(this.KEY_NO_PROXY),
    ]);
    return {
      httpProxy: trimText(httpProxy),
      httpsProxy: trimText(httpsProxy),
      noProxy: trimText(noProxy),
    };
  }

  async buildDockerEnv() {
    const proxy = await this.getProxyConfig({ skipReadyCheck: true });
    const env = {};
    if (proxy.httpProxy) {
      env.HTTP_PROXY = proxy.httpProxy;
      env.http_proxy = proxy.httpProxy;
    }
    if (proxy.httpsProxy) {
      env.HTTPS_PROXY = proxy.httpsProxy;
      env.https_proxy = proxy.httpsProxy;
    }
    if (proxy.noProxy) {
      env.NO_PROXY = proxy.noProxy;
      env.no_proxy = proxy.noProxy;
    }
    return env;
  }

  async getStatus() {
    const info = await this.ensureDockerReady();
    const proxy = await this.getProxyConfig({ skipReadyCheck: true });
    return {
      available: true,
      dockerHost: this.engine.getDockerHostLabel(),
      httpProxy: proxy.httpProxy,
      httpsProxy: proxy.httpsProxy,
      noProxy: proxy.noProxy,
      serverVersion: info.ServerVersion || '',
      operatingSystem: info.OperatingSystem || '',
      architecture: info.Architecture || '',
      containers: info.Containers || 0,
      containersRunning: info.ContainersRunning || 0,
      containersPaused: info.ContainersPaused || 0,
      containersStopped: info.ContainersStopped || 0,
      images: info.Images || 0,
      name: info.Name || os.hostname(),
    };
  }

  async setProxyConfig(payload) {
    await this.ensureDockerReady();
    const httpProxy = validateProxyUrl(payload && payload.httpProxy);
    const httpsProxy = validateProxyUrl(payload && payload.httpsProxy);
    const noProxy = trimText(payload && payload.noProxy);
    const ok = await Promise.all([
      tableConfig.setConfigByKey(this.KEY_HTTP_PROXY, httpProxy),
      tableConfig.setConfigByKey(this.KEY_HTTPS_PROXY, httpsProxy),
      tableConfig.setConfigByKey(this.KEY_NO_PROXY, noProxy),
    ]);
    if (!ok.every(Boolean)) {
      throw new DockerApiError('docker.CONFIG_SAVE_FAILED', 500);
    }
    return {
      httpProxy,
      httpsProxy,
      noProxy,
    };
  }

  async getConfig() {
    return this.getDaemonConfig();
  }

  async listImages() {
    await this.ensureDockerReady();
    const images = await this.engine.listImages({ all: true });
    if (!Array.isArray(images)) return [];
    return images.map(mapApiImageItem);
  }

  async inspectImage(imageRef) {
    await this.ensureDockerReady();
    return await this.engine.inspectImage(imageRef);
  }

  async deleteImage(payload) {
    await this.ensureDockerReady();
    const imageId = trimText(payload && (payload.imageId || payload.id || payload.image));
    const reference = trimText(payload && (payload.reference || payload.imageRef));
    const target = reference && !reference.startsWith('<none>') ? reference : imageId;
    if (!target) throw new DockerApiError('docker.IMAGE_NOT_FOUND', 404);
    const commandText = `DELETE /images/${target}`;
    console.info('[docker.deleteImage] attempt', {
      imageId,
      reference,
      target,
      command: commandText,
    });
    const consumers = await this.findContainersUsingImage({ imageId, reference });
    if (consumers.length > 0) {
      throw new DockerApiError(
        'docker.IMAGE_IN_USE',
        409,
        `Image is referenced by ${consumers.length} container(s)`,
        { containers: consumers, imageId, reference, target, command: commandText }
      );
    }
    try {
      await this.engine.deleteImage(target);
    } catch (error) {
      const normalized = error instanceof DockerApiError ? error : mapDockerFailure(error);
      const raw = trimText(error && error.message).toLowerCase();
      const canForceByReference = Boolean(
        reference &&
          !reference.startsWith('<none>') &&
          (raw.includes('unable to remove repository reference') ||
            (raw.includes('conflict') && raw.includes('must be forced')) ||
            normalized.code === 'docker.IMAGE_IN_USE')
      );
      if (!canForceByReference) {
        normalized.data = {
          ...(normalized.data && typeof normalized.data === 'object' ? normalized.data : {}),
          imageId,
          reference,
          target,
          command: commandText,
        };
        console.warn('[docker.deleteImage] failed', normalized.data);
        throw normalized;
      }
      try {
        await this.engine.deleteImage(reference, { force: true });
      } catch (forceError) {
        const forceNormalized = forceError instanceof DockerApiError ? forceError : mapDockerFailure(forceError);
        forceNormalized.data = {
          ...(forceNormalized.data && typeof forceNormalized.data === 'object' ? forceNormalized.data : {}),
          imageId,
          reference,
          target,
          command: `DELETE /images/${reference}?force=true`,
        };
        console.warn('[docker.deleteImage] force failed', forceNormalized.data);
        throw forceNormalized;
      }
      return {
        imageId: imageId || target,
        reference: reference || target,
        command: `DELETE /images/${reference}?force=true`,
        output: '',
        forced: true,
      };
    }
    return {
      imageId: imageId || target,
      reference: reference || target,
      command: commandText,
      output: '',
    };
  }

  async tagImage(payload = {}) {
    await this.ensureDockerReady();
    const imageId = trimText(payload.imageId || payload.id || payload.image);
    const sourceReference = trimText(payload.sourceReference || payload.reference || payload.from);
    const repository = trimText(payload.repository || payload.name || payload.imageName);
    const tag = trimText(payload.tag);
    if (!imageId) throw new DockerApiError('docker.IMAGE_NOT_FOUND', 404);
    if (!repository || !tag) throw new DockerApiError('docker.INVALID_IMAGE_REF', 400);
    const targetRef = `${repository}:${tag}`;
    if (sourceReference && sourceReference === targetRef) {
      return {
        imageId,
        reference: targetRef,
        command: '',
        unchanged: true,
      };
    }
    await this.engine.tagImage(imageId, { repo: repository, tag });
    if (sourceReference && sourceReference !== targetRef && !sourceReference.startsWith('<none>')) {
      try {
        await this.engine.deleteImage(sourceReference);
      } catch (error) {
        await this.engine.deleteImage(targetRef).catch(() => {});
        throw error instanceof DockerApiError ? error : mapDockerFailure(error);
      }
    }
    return {
      imageId,
      reference: targetRef,
      command: `POST /images/${imageId}/tag?repo=${repository}&tag=${tag}`,
    };
  }

  async pullImage(payload) {
    if (!this._useLocalTaskTransport()) {
      return await this._requestTaskWorker('pullImage', payload || {}, 30000);
    }
    return await this._pullImageLocal(payload);
  }

  async _pullImageLocal(payload) {
    await this.ensureDockerReady();
    const imageRef = buildImageReference(payload || {});
    const registry = trimText(payload && payload.registry);
    const username = trimText(payload && payload.username);
    const password = trimText(payload && payload.password);
    const dedupeKey = `pull:${imageRef}`;
    const task = dockerTaskManager.createTask({
      type: 'pull_image',
      title: imageRef,
      dedupeKey,
      metadata: {
        imageRef,
        registry,
      },
      runner: async ctx => {
        const abortController = new AbortController();
        ctx.task.cancel = () => {
          abortController.abort();
          return true;
        };
        try {
          if (username && password) {
            ctx.appendLog(`Authenticating with registry ${registry || imageRef.split('/')[0]}`, 'stdout');
          }
          await this.engine.pullImage(imageRef, {
            auth: username && password
              ? { username, password, registry: registry || imageRef.split('/')[0] }
              : null,
            signal: abortController.signal,
            checkCancelled: () => ctx.ensureRunning(),
            onProgress: line => ctx.appendLog(line, 'stdout'),
          });
          ctx.setResult({
            imageRef,
            command: `POST /images/create?fromImage=${imageRef}`,
          });
        } catch (error) {
          throw error instanceof DockerApiError ? error : mapDockerFailure(error);
        }
      },
    });
    return this.getTask(task.id);
  }

  async importImage(payload) {
    if (!this._useLocalTaskTransport()) {
      return await this._requestTaskWorker('importImage', payload || {}, 30000);
    }
    return await this._importImageLocal(payload);
  }

  async _importImageLocal(payload = {}) {
    await this.ensureDockerReady();
    const archivePath = trimText(payload.archivePath || payload.filePath || payload.path);
    if (!archivePath) {
      throw new DockerApiError('docker.IMAGE_ARCHIVE_REQUIRED', 400);
    }
    if (!isSupportedDockerImageArchive(archivePath)) {
      throw new DockerApiError('docker.INVALID_IMAGE_ARCHIVE', 400);
    }
    const resolvedPath = path.resolve(archivePath);
    const exists = await fs.pathExists(resolvedPath);
    if (!exists) {
      throw new DockerApiError('docker.IMAGE_ARCHIVE_NOT_FOUND', 404);
    }
    const stat = await fs.stat(resolvedPath);
    if (!stat.isFile()) {
      throw new DockerApiError('docker.INVALID_IMAGE_ARCHIVE', 400);
    }
    const dedupeKey = `import:${resolvedPath}`;
    const task = dockerTaskManager.createTask({
      type: 'import_image',
      title: path.basename(resolvedPath),
      dedupeKey,
      metadata: {
        archivePath: resolvedPath,
      },
      runner: async ctx => {
        const abortController = new AbortController();
        ctx.task.cancel = () => {
          abortController.abort();
          return true;
        };
        const lines = [];
        try {
          await this.engine.loadImage(resolvedPath, {
            signal: abortController.signal,
            checkCancelled: () => ctx.ensureRunning(),
            onProgress: line => {
              lines.push(line);
              ctx.appendLog(line, 'stdout');
            },
          });
          ctx.setResult({
            archivePath: resolvedPath,
            command: `POST /images/load (${path.basename(resolvedPath)})`,
            output: trimText(lines.join('\n')),
          });
        } catch (error) {
          throw error instanceof DockerApiError ? error : mapDockerFailure(error);
        }
      },
    });
    return this.getTask(task.id);
  }

  async listContainers(payload = {}) {
    await this.ensureDockerReady();
    const status = trimText(payload.status);
    const mergeCreatedIntoExited = status === 'exited';
    const filters = {};
    if (status && !mergeCreatedIntoExited) {
      filters.status = [status];
    }
    const list = await this.engine.listContainers({
      all: true,
      filters: Object.keys(filters).length > 0 ? filters : null,
    });
    let normalized = Array.isArray(list) ? list : [];
    if (mergeCreatedIntoExited) {
      normalized = normalized.filter(item => {
        const state = trimText(item && item.State).toLowerCase();
        return state === 'exited' || state === 'created';
      });
    }
    const ids = normalized.map(item => item.Id).filter(Boolean);
    const inspectMap = await this.inspectContainers(ids, { skipReadyCheck: true });
    return normalized.map(item => {
      const inspect = inspectMap.get(item.Id) || {};
      const mounts = Array.isArray(inspect.Mounts)
        ? inspect.Mounts.map(mount => ({
            type: mount.Type || '',
            source: mount.Source || '',
            target: mount.Destination || '',
            readOnly: mount.RW === false,
          }))
        : [];
      const names = Array.isArray(item.Names) ? item.Names.join(', ') : trimText(item.Names);
      return {
        id: item.Id || '',
        name: names,
        image: item.Image || '',
        imageId: inspect.Image || item.ImageID || '',
        imageRef: (inspect.Config && inspect.Config.Image) || item.Image || '',
        command: item.Command || '',
        state: item.State || '',
        status: item.Status || '',
        createdAt: inspect.Created || '',
        ports: buildPortMap(inspect.NetworkSettings && inspect.NetworkSettings.Ports),
        mounts,
      };
    });
  }

  async inspectContainers(ids, options = {}) {
    if (!options.skipReadyCheck) {
      await this.ensureDockerReady();
    }
    if (!Array.isArray(ids) || ids.length === 0) return new Map();
    const map = new Map();
    const results = await Promise.all(ids.map(async id => {
      try {
        const inspect = await this.engine.inspectContainer(id);
        return { id, inspect };
      } catch (_) {
        return { id, inspect: null };
      }
    }));
    results.forEach(({ id, inspect }) => {
      if (!inspect) return;
      map.set(id, inspect);
      if (inspect.Id) map.set(inspect.Id, inspect);
    });
    return map;
  }

  async findContainersUsingImage({ imageId = '', reference = '' } = {}) {
    const containers = await this.listContainers({});
    const normalizedId = trimText(imageId);
    const normalizedRef = trimText(reference);
    return containers
      .filter(item => {
        const itemImageId = trimText(item.imageId);
        const itemImageRef = trimText(item.imageRef || item.image);
        if (normalizedId && itemImageId && itemImageId === normalizedId) return true;
        if (normalizedRef && itemImageRef && itemImageRef === normalizedRef) return true;
        return false;
      })
      .map(item => ({
        id: item.id || '',
        name: item.name || '',
        image: item.image || '',
        imageId: item.imageId || '',
        imageRef: item.imageRef || '',
        state: item.state || '',
        status: item.status || '',
      }));
  }

  async createContainer(payload = {}) {
    await this.ensureDockerReady();
    const imageRef = buildImageReference({
      image: payload.image,
      registry: payload.registry,
      tag: payload.tag,
      imageId: payload.imageId || payload.id,
    });
    await this.inspectImage(imageRef);

    const name = trimText(payload.name);
    const envList = sanitizeEnvList(payload.env || payload.environment);
    const ports = sanitizePortBindings(payload.ports);
    const volumes = sanitizeVolumeBindings(payload.volumes);
    const resources = payload.resources && typeof payload.resources === 'object' ? payload.resources : {};
    const commandList = Array.isArray(payload.command) ? payload.command.map(item => String(item)) : splitCommandString(payload.command);
    const spec = buildCreateContainerSpec({
      imageRef,
      commandList,
      envList,
      ports,
      volumes,
      resources,
      payload,
    });
    const created = await this.engine.createContainer(spec, { name });
    const containerId = trimText(created && created.Id);
    if (!containerId) throw new DockerApiError('docker.COMMAND_FAILED', 500, 'Failed to create container');
    const inspectMap = await this.inspectContainers([containerId], { skipReadyCheck: true });
    const inspect = inspectMap.get(containerId) || null;
    return {
      id: containerId,
      image: imageRef,
      name: inspect && inspect.Name ? String(inspect.Name).replace(/^\//, '') : name,
      state: inspect && inspect.State && inspect.State.Status ? inspect.State.Status : 'created',
      command: `POST /containers/create${name ? `?name=${name}` : ''}`,
    };
  }

  async startContainer(payload) {
    await this.ensureDockerReady();
    const containerId = trimText(payload && (payload.containerId || payload.id));
    if (!containerId) throw new DockerApiError('docker.CONTAINER_NOT_FOUND', 404);
    await this.engine.startContainer(containerId);
    return {
      id: containerId,
      status: 'running',
      command: `POST /containers/${containerId}/start`,
      output: containerId,
    };
  }

  async stopContainer(payload) {
    await this.ensureDockerReady();
    const containerId = trimText(payload && (payload.containerId || payload.id));
    if (!containerId) throw new DockerApiError('docker.CONTAINER_NOT_FOUND', 404);
    const timeout = parsePositiveInt(payload && payload.timeout, 10);
    await this.engine.stopContainer(containerId, { timeout });
    return {
      id: containerId,
      status: 'stopped',
      command: `POST /containers/${containerId}/stop?t=${timeout}`,
      output: containerId,
    };
  }

  async deleteContainer(payload) {
    await this.ensureDockerReady();
    const containerId = trimText(payload && (payload.containerId || payload.id));
    if (!containerId) throw new DockerApiError('docker.CONTAINER_NOT_FOUND', 404);
    const force = parseBool(payload && payload.force, false);
    await this.engine.deleteContainer(containerId, { force });
    return {
      id: containerId,
      removed: true,
      force,
      command: `DELETE /containers/${containerId}${force ? '?force=true' : ''}`,
      output: containerId,
    };
  }

  async getContainerLogs(payload = {}) {
    const follow = parseBool(payload.streamOutput || payload.follow, false);
    if (follow && !this._useLocalTaskTransport()) {
      return await this._requestTaskWorker('getContainerLogs', payload, 20000);
    }
    return await this._getContainerLogsLocal(payload);
  }

  async _getContainerLogsLocal(payload = {}) {
    await this.ensureDockerReady();
    const containerId = trimText(payload.containerId || payload.id);
    if (!containerId) throw new DockerApiError('docker.CONTAINER_NOT_FOUND', 404);
    const tail = parsePositiveInt(payload.tail, 200);
    const since = trimText(payload.since);
    const until = trimText(payload.until);
    const follow = parseBool(payload.streamOutput || payload.follow, false);

    if (follow) {
      const task = dockerTaskManager.createTask({
        type: 'container_logs',
        title: containerId,
        dedupeKey: `logs:${containerId}`,
        metadata: {
          containerId,
          follow: true,
          tail,
          since,
          until,
        },
        runner: async ctx => {
          const abortController = new AbortController();
          ctx.task.cancel = () => {
            abortController.abort();
            return true;
          };
          try {
            await this.engine.getContainerLogs(containerId, {
              tail,
              since,
              until,
              follow: true,
              signal: abortController.signal,
              checkCancelled: () => ctx.ensureRunning(),
              onLine: (line, source) => ctx.appendLog(line, source),
            });
            if (ctx.task.status === 'cancelled') return;
            ctx.setResult({
              containerId,
              followed: true,
            });
          } catch (error) {
            if (ctx.task.status === 'cancelled') return;
            throw error instanceof DockerApiError ? error : mapDockerFailure(error);
          }
        },
      });
      return this.getTask(task.id);
    }

    const lines = await this.engine.getContainerLogs(containerId, {
      tail,
      since,
      until,
      follow: false,
    });
    const items = lines.map(item => ({ text: item.text }));
    return {
      containerId,
      items,
      total: items.length,
      followed: false,
      command: `GET /containers/${containerId}/logs`,
    };
  }

  async listTasks(query) {
    if (!this._useLocalTaskTransport()) {
      return await this._requestTaskWorker('listTasks', query || {}, 10000);
    }
    return await this._listTasksLocal(query);
  }

  async _listTasksLocal(query) {
    return {
      items: dockerTaskManager.listTasks(query),
    };
  }

  async getTask(id) {
    if (!this._useLocalTaskTransport()) {
      return await this._requestTaskWorker('getTask', { taskId: id }, 10000);
    }
    return await this._getTaskLocal(id);
  }

  async _getTaskLocal(id) {
    const task = dockerTaskManager.getTask(id);
    if (!task) throw new DockerApiError('docker.TASK_NOT_FOUND', 404);
    return task;
  }

  async getTaskLogs(payload = {}) {
    if (!this._useLocalTaskTransport()) {
      return await this._requestTaskWorker('getTaskLogs', payload, 10000);
    }
    return await this._getTaskLogsLocal(payload);
  }

  async _getTaskLogsLocal(payload = {}) {
    const taskId = trimText(payload.taskId || payload.id);
    if (!taskId) throw new DockerApiError('docker.TASK_NOT_FOUND', 404);
    const logs = dockerTaskManager.getTaskLogs(taskId, payload.offset, payload.limit);
    if (!logs) throw new DockerApiError('docker.TASK_NOT_FOUND', 404);
    return {
      taskId,
      ...logs,
    };
  }

  async cancelTask(payload = {}) {
    if (!this._useLocalTaskTransport()) {
      return await this._requestTaskWorker('cancelTask', payload, 10000);
    }
    return await this._cancelTaskLocal(payload);
  }

  async _cancelTaskLocal(payload = {}) {
    const taskId = trimText(payload.taskId || payload.id);
    if (!taskId) throw new DockerApiError('docker.TASK_NOT_FOUND', 404);
    const task = dockerTaskManager.cancelTask(taskId);
    if (!task) throw new DockerApiError('docker.TASK_NOT_FOUND', 404);
    return await this._getTaskLocal(taskId);
  }

  async deleteTask(payload = {}) {
    if (!this._useLocalTaskTransport()) {
      return await this._requestTaskWorker('deleteTask', payload, 10000);
    }
    return await this._deleteTaskLocal(payload);
  }

  async _deleteTaskLocal(payload = {}) {
    const taskId = trimText(payload.taskId || payload.id);
    if (!taskId) throw new DockerApiError('docker.TASK_NOT_FOUND', 404);
    const task = dockerTaskManager.deleteTask(taskId);
    if (task == null) throw new DockerApiError('docker.TASK_NOT_FOUND', 404);
    if (task === false) {
      throw new DockerApiError('docker.TASK_DELETE_RUNNING_FORBIDDEN', 409, 'Task is still running');
    }
    return {
      id: taskId,
      deleted: true,
    };
  }
}

module.exports = {
  DockerService,
  DockerApiError,
  mapDockerFailure,
};
