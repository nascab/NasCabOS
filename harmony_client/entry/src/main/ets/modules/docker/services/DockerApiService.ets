import { APIClient } from '../../../core/network/APIClient';
import { APIResponse } from '../../../core/network/APIResponse';
import { DockerImage, DockerContainer, DockerTask, DockerTaskLog } from '../models/DockerModels';

/**
 * Docker 模块 API 服务（对齐 Flutter modules/docker/service/docker_api_service.dart）。
 * 请求路径、方法、参数与超时完全一致；apiErrorKey 取自响应外层 code 字符串
 * （如 docker.DOCKER_UNAVAILABLE），供控制器映射友好错误文案。
 */
export class DockerApiResult<T> {
  success: boolean = false;
  message: string = '';
  data: T | undefined = undefined;
  /** 业务错误键（如 docker.DOCKER_UNAVAILABLE），成功时为空 */
  apiErrorKey: string = '';
  code: number = 0;

  static ok<D>(data: D | undefined, message: string = '', code: number = 0): DockerApiResult<D> {
    const r = new DockerApiResult<D>();
    r.success = true;
    r.data = data;
    r.message = message;
    r.code = code;
    return r;
  }

  static fail<D>(message: string, apiErrorKey: string = '', code: number = 0): DockerApiResult<D> {
    const r = new DockerApiResult<D>();
    r.success = false;
    r.message = message;
    r.apiErrorKey = apiErrorKey;
    r.code = code;
    return r;
  }
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

/** 从 APIResponse 提取 apiErrorKey（响应外层 code 为字符串时即业务错误键） */
function errorKeyOf(res: APIResponse<Object>): string {
  const raw = res.rawResponse;
  if (raw === undefined || raw === null) {
    return '';
  }
  const code = raw.code;
  return typeof code === 'string' ? code.trim() : '';
}

export class DockerApiService {
  /** GET 并解析 data 为 Record */
  static async getRecord(endpoint: string, query?: Map<string, string>,
    timeoutMs?: number): Promise<DockerApiResult<Record<string, Object>>> {
    const res = await APIClient.getInstance().apiGet<Object>(endpoint, query, timeoutMs);
    if (!res.success) {
      return DockerApiResult.fail<Record<string, Object>>(res.message ?? '', errorKeyOf(res), res.code ?? 0);
    }
    return DockerApiResult.ok<Record<string, Object>>(asRec(res.data), res.message ?? '', res.code ?? 0);
  }

  /** POST 并解析 data 为 Record */
  static async postRecord(endpoint: string, body?: Object,
    timeoutMs?: number): Promise<DockerApiResult<Record<string, Object>>> {
    const res = await APIClient.getInstance().apiPost<Object>(endpoint, body, undefined, timeoutMs);
    if (!res.success) {
      return DockerApiResult.fail<Record<string, Object>>(res.message ?? '', errorKeyOf(res), res.code ?? 0);
    }
    return DockerApiResult.ok<Record<string, Object>>(asRec(res.data), res.message ?? '', res.code ?? 0);
  }

  /** GET 并解析 data 为数组 */
  static async getArray(endpoint: string, query?: Map<string, string>,
    timeoutMs?: number): Promise<DockerApiResult<Object[]>> {
    const res = await APIClient.getInstance().apiGet<Object>(endpoint, query, timeoutMs);
    if (!res.success) {
      return DockerApiResult.fail<Object[]>(res.message ?? '', errorKeyOf(res), res.code ?? 0);
    }
    return DockerApiResult.ok<Object[]>(asArr(res.data), res.message ?? '', res.code ?? 0);
  }

  // ===== 服务状态与配置（对齐 Flutter DockerApiService） =====

  /** Docker 引擎状态（GET /api/docker/status） */
  static getStatus(): Promise<DockerApiResult<Record<string, Object>>> {
    return DockerApiService.getRecord('/api/docker/status');
  }

  /** Docker 配置（GET /api/docker/config） */
  static getConfig(): Promise<DockerApiResult<Record<string, Object>>> {
    return DockerApiService.getRecord('/api/docker/config');
  }

  /** 保存配置文件内容（POST /api/docker/config/save，超时 20s） */
  static saveConfig(content: string): Promise<DockerApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'content': content };
    return DockerApiService.postRecord('/api/docker/config/save', body, 20000);
  }

  /** 启动 Docker（POST /api/docker/start，超时 20s） */
  static startDocker(): Promise<DockerApiResult<Record<string, Object>>> {
    return DockerApiService.postRecord('/api/docker/start', {} as Record<string, Object>, 20000);
  }

  /** 停止 Docker（POST /api/docker/stop，超时 20s） */
  static stopDocker(): Promise<DockerApiResult<Record<string, Object>>> {
    return DockerApiService.postRecord('/api/docker/stop', {} as Record<string, Object>, 20000);
  }

  /** 设置代理配置（POST /api/docker/config/proxy） */
  static setProxyConfig(httpProxy: string, httpsProxy: string,
    noProxy: string): Promise<DockerApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'httpProxy': httpProxy,
      'httpsProxy': httpsProxy,
      'noProxy': noProxy
    };
    return DockerApiService.postRecord('/api/docker/config/proxy', body);
  }

  // ===== 镜像 =====

  /** 镜像列表（GET /api/docker/images/list） */
  static async listImages(): Promise<DockerApiResult<DockerImage[]>> {
    const res = await DockerApiService.getArray('/api/docker/images/list');
    if (!res.success) {
      return DockerApiResult.fail<DockerImage[]>(res.message, res.apiErrorKey, res.code);
    }
    const list: DockerImage[] = [];
    res.data!.forEach((item: Object): void => {
      list.push(DockerImage.fromJson(asRec(item)));
    });
    return DockerApiResult.ok<DockerImage[]>(list, res.message, res.code);
  }

  /** 拉取镜像（POST /api/docker/images/pull，创建异步任务） */
  static pullImage(image: string, registry: string, tag: string, username: string,
    password: string): Promise<DockerApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'image': image,
      'registry': registry,
      'tag': tag,
      'username': username,
      'password': password
    };
    return DockerApiService.postRecord('/api/docker/images/pull', body);
  }

  /** 导入镜像归档（POST /api/docker/images/import，超时 20s） */
  static importImage(archivePath: string): Promise<DockerApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'archivePath': archivePath };
    return DockerApiService.postRecord('/api/docker/images/import', body, 20000);
  }

  /** 删除镜像（POST /api/docker/images/delete） */
  static deleteImage(imageId: string, reference: string): Promise<DockerApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'imageId': imageId, 'reference': reference };
    return DockerApiService.postRecord('/api/docker/images/delete', body);
  }

  /** 修改镜像标签（POST /api/docker/images/tag） */
  static tagImage(imageId: string, repository: string, tag: string,
    sourceReference: string): Promise<DockerApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'imageId': imageId,
      'repository': repository,
      'tag': tag,
      'sourceReference': sourceReference
    };
    return DockerApiService.postRecord('/api/docker/images/tag', body);
  }

  // ===== 容器 =====

  /** 容器列表（GET /api/docker/containers/list?status=） */
  static async listContainers(status: string): Promise<DockerApiResult<DockerContainer[]>> {
    const trimmed = status.trim();
    const query = trimmed.length > 0 ? new Map<string, string>([['status', trimmed]]) : undefined;
    const res = await DockerApiService.getArray('/api/docker/containers/list', query);
    if (!res.success) {
      return DockerApiResult.fail<DockerContainer[]>(res.message, res.apiErrorKey, res.code);
    }
    const list: DockerContainer[] = [];
    res.data!.forEach((item: Object): void => {
      list.push(DockerContainer.fromJson(asRec(item)));
    });
    return DockerApiResult.ok<DockerContainer[]>(list, res.message, res.code);
  }

  /** 创建容器（POST /api/docker/containers/create，超时 20s） */
  static createContainer(body: Record<string, Object>): Promise<DockerApiResult<Record<string, Object>>> {
    return DockerApiService.postRecord('/api/docker/containers/create', body, 20000);
  }

  /** 启动容器（POST /api/docker/containers/start） */
  static startContainer(id: string): Promise<DockerApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'containerId': id };
    return DockerApiService.postRecord('/api/docker/containers/start', body);
  }

  /** 停止容器（POST /api/docker/containers/stop，默认 10s 宽限） */
  static stopContainer(id: string, timeout: number = 10): Promise<DockerApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'containerId': id, 'timeout': timeout };
    return DockerApiService.postRecord('/api/docker/containers/stop', body);
  }

  /** 删除容器（POST /api/docker/containers/delete） */
  static deleteContainer(id: string, force: boolean): Promise<DockerApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'containerId': id, 'force': force };
    return DockerApiService.postRecord('/api/docker/containers/delete', body);
  }

  /** 容器日志（GET /api/docker/containers/logs；跟踪模式超时 10s，普通 20s） */
  static getContainerLogs(containerId: string, since: string, until: string, tail: number,
    streamOutput: boolean): Promise<DockerApiResult<Record<string, Object>>> {
    const query = new Map<string, string>();
    query.set('containerId', containerId);
    query.set('since', since);
    query.set('until', until);
    query.set('tail', `${tail}`);
    query.set('streamOutput', `${streamOutput}`);
    return DockerApiService.getRecord('/api/docker/containers/logs', query, streamOutput ? 10000 : 20000);
  }

  // ===== 异步任务 =====

  /** 任务列表（GET /api/docker/tasks/list，data: {items: [...]}） */
  static async listTasks(): Promise<DockerApiResult<DockerTask[]>> {
    const res = await DockerApiService.getRecord('/api/docker/tasks/list');
    if (!res.success) {
      return DockerApiResult.fail<DockerTask[]>(res.message, res.apiErrorKey, res.code);
    }
    const list: DockerTask[] = [];
    asArr(res.data!['items']).forEach((item: Object): void => {
      list.push(DockerTask.fromJson(asRec(item)));
    });
    return DockerApiResult.ok<DockerTask[]>(list, res.message, res.code);
  }

  /** 任务详情（GET /api/docker/tasks/detail?taskId=） */
  static getTask(taskId: string): Promise<DockerApiResult<Record<string, Object>>> {
    const query = new Map<string, string>([['taskId', taskId]]);
    return DockerApiService.getRecord('/api/docker/tasks/detail', query);
  }

  /** 任务日志（GET /api/docker/tasks/logs?taskId=&offset=&limit=，data: {items: [...]}） */
  static async getTaskLogs(taskId: string, offset: number = 0,
    limit: number = 200): Promise<DockerApiResult<DockerTaskLog[]>> {
    const query = new Map<string, string>();
    query.set('taskId', taskId);
    query.set('offset', `${offset}`);
    query.set('limit', `${limit}`);
    const res = await DockerApiService.getRecord('/api/docker/tasks/logs', query);
    if (!res.success) {
      return DockerApiResult.fail<DockerTaskLog[]>(res.message, res.apiErrorKey, res.code);
    }
    const list: DockerTaskLog[] = [];
    asArr(res.data!['items']).forEach((item: Object): void => {
      list.push(DockerTaskLog.fromJson(asRec(item)));
    });
    return DockerApiResult.ok<DockerTaskLog[]>(list, res.message, res.code);
  }

  /** 取消任务（POST /api/docker/tasks/cancel） */
  static cancelTask(taskId: string): Promise<DockerApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'taskId': taskId };
    return DockerApiService.postRecord('/api/docker/tasks/cancel', body);
  }

  /** 删除任务（POST /api/docker/tasks/delete） */
  static deleteTask(taskId: string): Promise<DockerApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'taskId': taskId };
    return DockerApiService.postRecord('/api/docker/tasks/delete', body);
  }
}
