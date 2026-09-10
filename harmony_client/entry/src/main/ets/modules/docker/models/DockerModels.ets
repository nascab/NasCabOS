import { L10n } from '../../../core/localization/L10n';

/**
 * Docker 模块数据模型（对齐 Flutter controller 中动态 Map 数据的字段读取）：
 * 镜像 / 容器（含端口映射与卷挂载）/ 异步任务 / 任务日志 / 创建容器编辑项。
 */

/** 安全字符串化（JSON 边界字段类型不稳定，统一字符串化；undefined/null 返回空串） */
export function dockerStr(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  return `${v}`;
}

/** 安全取数字（非有限数字返回 undefined，对齐 Flutter `progress is num` 判断） */
export function dockerNum(v: Object | undefined | null): number | undefined {
  if (typeof v === 'number' && Number.isFinite(v)) {
    return v;
  }
  return undefined;
}

function asRec(v: Object | undefined | null): Record<string, Object> {
  if (v === undefined || v === null || typeof v !== 'object' || Array.isArray(v)) {
    return {} as Record<string, Object>;
  }
  return v as Record<string, Object>;
}

function asArr(v: Object | undefined | null): Object[] {
  if (v === undefined || v === null || !Array.isArray(v)) {
    return [];
  }
  return v as Object[];
}

/** 镜像（GET /api/docker/images/list 列表项） */
export class DockerImage {
  id: string = '';
  reference: string = '';
  repository: string = '';
  tag: string = '';
  size: string = '';
  createdAt: string = '';

  static fromJson(rec: Record<string, Object>): DockerImage {
    const m = new DockerImage();
    m.id = dockerStr(rec['id']);
    m.reference = dockerStr(rec['reference']);
    m.repository = dockerStr(rec['repository']);
    m.tag = dockerStr(rec['tag']);
    m.size = dockerStr(rec['size']);
    m.createdAt = dockerStr(rec['createdAt']);
    return m;
  }
}

/** 端口映射条目（容器展示与创建容器编辑共用） */
export class DockerPortBinding {
  hostIp: string = '';
  hostPort: string = '';
  containerPort: string = '';
  protocol: string = 'tcp';

  static fromJson(rec: Record<string, Object>): DockerPortBinding {
    const m = new DockerPortBinding();
    m.hostIp = dockerStr(rec['hostIp']);
    m.hostPort = dockerStr(rec['hostPort']);
    m.containerPort = dockerStr(rec['containerPort']);
    const proto = dockerStr(rec['protocol']).toLowerCase();
    m.protocol = proto.length > 0 ? proto : 'tcp';
    return m;
  }

  /** 容器端口展示值（对齐 Flutter：containerPort 已含 /protocol 时原样，否则补上） */
  displayContainerPort(): string {
    if (this.containerPort.includes('/')) {
      return this.containerPort;
    }
    return `${this.containerPort}/${this.protocol}`;
  }

  /** 端口映射展示文案（对齐 Flutter _ContainerCard ports 标签文本） */
  displayText(): string {
    const cp = this.displayContainerPort();
    if (this.hostPort.length === 0) {
      return cp;
    }
    const host = this.hostIp.length > 0 ? `${this.hostIp}:` : '';
    return `${host}${this.hostPort} -> ${cp}`;
  }
}

/** 卷挂载条目 */
export class DockerMountInfo {
  source: string = '';
  target: string = '';
  readOnly: boolean = false;

  static fromJson(rec: Record<string, Object>): DockerMountInfo {
    const m = new DockerMountInfo();
    m.source = dockerStr(rec['source']);
    m.target = dockerStr(rec['target']);
    m.readOnly = rec['readOnly'] === true;
    return m;
  }

  /** 挂载展示文案（对齐 Flutter `source -> target(ro)`） */
  displayText(roLabel: string, rwLabel: string): string {
    const mode = this.readOnly ? roLabel : rwLabel;
    return `${this.source} -> ${this.target}(${mode})`;
  }
}

/** 容器（GET /api/docker/containers/list 列表项） */
export class DockerContainer {
  id: string = '';
  name: string = '';
  image: string = '';
  state: string = '';
  status: string = '';
  ports: DockerPortBinding[] = [];
  mounts: DockerMountInfo[] = [];

  static fromJson(rec: Record<string, Object>): DockerContainer {
    const c = new DockerContainer();
    c.id = dockerStr(rec['id']);
    c.name = dockerStr(rec['name']);
    c.image = dockerStr(rec['image']);
    c.state = dockerStr(rec['state']).trim();
    c.status = dockerStr(rec['status']).trim();
    c.ports = asArr(rec['ports']).map((item: Object): DockerPortBinding => {
      return DockerPortBinding.fromJson(asRec(item));
    });
    c.mounts = asArr(rec['mounts']).map((item: Object): DockerMountInfo => {
      return DockerMountInfo.fromJson(asRec(item));
    });
    return c;
  }

  isRunning(): boolean {
    return this.state === 'running';
  }

  /** 状态徽标文案（status 优先，state 兜底） */
  badgeText(): string {
    return this.status.length > 0 ? this.status : this.state;
  }
}

/** 异步任务（GET /api/docker/tasks/list items 列表项） */
export class DockerTask {
  id: string = '';
  title: string = '';
  type: string = '';
  status: string = '';
  /** 进度（0-100 数字时才展示进度条，对齐 Flutter `progress is num`） */
  progress: number | undefined = undefined;
  command: string = '';

  static fromJson(rec: Record<string, Object>): DockerTask {
    const t = new DockerTask();
    t.id = dockerStr(rec['id']);
    t.title = dockerStr(rec['title']);
    t.type = dockerStr(rec['type']);
    t.status = dockerStr(rec['status']).trim().toLowerCase();
    t.progress = dockerNum(rec['progress']);
    t.command = dockerStr(rec['command']).trim();
    return t;
  }

  /** 可取消（queued / running） */
  canCancel(): boolean {
    return this.status === 'queued' || this.status === 'running';
  }
}

/** 任务日志行（GET /api/docker/tasks/logs items 列表项） */
export class DockerTaskLog {
  text: string = '';
  source: string = '';
  ts: string = '';

  static fromJson(rec: Record<string, Object>): DockerTaskLog {
    const l = new DockerTaskLog();
    l.text = dockerStr(rec['text']);
    l.source = dockerStr(rec['source']);
    l.ts = dockerStr(rec['ts']);
    return l;
  }

  /** 日志行格式化（对齐 Flutter _formatTaskLogLine：[source] ts  text） */
  formatLine(): string {
    return `[${this.source}] ${this.ts}  ${this.text}`;
  }
}

/** 创建容器时的镜像下拉项（对齐 Flutter _buildCreateContainerImageOptions） */
export class DockerImageOption {
  id: string = '';
  repository: string = '';
  tag: string = '';
  label: string = '';
}

/** 创建容器环境变量编辑项 */
export class DockerEnvVar {
  key: string = '';
  value: string = '';

  constructor(key: string, value: string) {
    this.key = key;
    this.value = value;
  }
}

/** 重启策略选项（value + L10n key，对齐 Flutter _restartPolicyOptions） */
export class DockerRestartPolicyOption {
  value: string = '';
  labelKey: string = '';

  constructor(value: string, labelKey: string) {
    this.value = value;
    this.labelKey = labelKey;
  }
}

export const DOCKER_RESTART_POLICY_OPTIONS: DockerRestartPolicyOption[] = [
  new DockerRestartPolicyOption('no', 'docker_restart_no'),
  new DockerRestartPolicyOption('unless-stopped', 'docker_restart_unless_stopped'),
  new DockerRestartPolicyOption('always', 'docker_restart_always'),
  new DockerRestartPolicyOption('on-failure', 'docker_restart_on_failure')
];

/** 从镜像列表构建创建容器的可选镜像项（对齐 Flutter _buildCreateContainerImageOptions） */
export function buildDockerImageOptions(images: DockerImage[]): DockerImageOption[] {
  const options: DockerImageOption[] = [];
  images.forEach((item: DockerImage): void => {
    const repository = item.repository.trim();
    const tag = item.tag.trim();
    const id = item.id.trim();
    if (repository.length === 0 || repository === '<none>' || tag.length === 0
      || tag === '<none>' || id.length === 0) {
      return;
    }
    const opt = new DockerImageOption();
    opt.id = id;
    opt.repository = repository;
    opt.tag = tag;
    opt.label = `${repository}:${tag}`;
    options.push(opt);
  });
  return options;
}

/** 镜像归档文件名校验（对齐 Flutter _isDockerImageArchivePath） */
export function isDockerImageArchivePath(path: string): boolean {
  const lower = path.trim().toLowerCase();
  return lower.endsWith('.tar') || lower.endsWith('.tar.gz') || lower.endsWith('.tgz');
}

/** 任务状态展示翻译（对齐 Flutter _translateTaskStatus） */
export function translateTaskStatus(status: string): string {
  const normalized = status.trim().toLowerCase();
  if (normalized === 'queued') {
    return L10n.t('docker_task_status_queued', '排队中');
  }
  if (normalized === 'running') {
    return L10n.t('docker_task_status_running', '运行中');
  }
  if (normalized === 'success') {
    return L10n.t('docker_task_status_success', '成功');
  }
  if (normalized === 'failed') {
    return L10n.t('docker_task_status_failed', '失败');
  }
  if (normalized === 'cancelled') {
    return L10n.t('docker_task_status_cancelled', '已取消');
  }
  return normalized.length === 0 ? '--' : normalized;
}

/** 任务类型展示翻译（对齐 Flutter _translateTaskType） */
export function translateTaskType(type: string): string {
  const normalized = type.trim().toLowerCase();
  if (normalized === 'start_docker') {
    return L10n.t('docker_task_type_start_docker', '启动 Docker');
  }
  if (normalized === 'stop_docker') {
    return L10n.t('docker_task_type_stop_docker', '停止 Docker');
  }
  if (normalized === 'pull_image') {
    return L10n.t('docker_task_type_pull_image', '拉取镜像');
  }
  if (normalized === 'import_image') {
    return L10n.t('docker_task_type_import_image', '导入镜像');
  }
  if (normalized === 'container_logs') {
    return L10n.t('docker_task_type_container_logs', '容器日志');
  }
  return normalized.length === 0 ? '--' : normalized.split('_').join(' ');
}
