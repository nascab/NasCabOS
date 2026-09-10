import { APIClient } from '../../../core/network/APIClient';
import { AuthService } from '../../../auth/AuthService';
import {
  FileLogListResponse, LoginRecord, UserPermissionItem, UserProfile
} from '../models/UserModels';

/**
 * 用户管理 API 服务（对齐 Flutter modules/user/service/user_api_service.dart）。
 * 请求路径、方法与参数完全一致；createUser 与 Flutter 一致在服务层混淆密码。
 */
export class UserApiResult<T> {
  success: boolean = false;
  message: string = '';
  data: T | undefined = undefined;
  code: number = 0;

  static ok<D>(data: D | undefined): UserApiResult<D> {
    const r = new UserApiResult<D>();
    r.success = true;
    r.data = data;
    return r;
  }

  static fail<D>(message: string, code: number = 0): UserApiResult<D> {
    const r = new UserApiResult<D>();
    r.success = false;
    r.message = message;
    r.code = code;
    return r;
  }
}

function asRecord(v: Object | undefined | null): Record<string, Object> {
  if (v === undefined || v === null) {
    return {} as Record<string, Object>;
  }
  return v as Record<string, Object>;
}

function asArray(v: Object | undefined | null): Object[] {
  if (v === undefined || v === null || !Array.isArray(v)) {
    return [];
  }
  return v as Object[];
}

export class UserApiService {
  /** 用户分页列表（POST /api/user/list，取 data.items） */
  static async fetchUsers(page: number, limit: number,
    keyword: string): Promise<UserApiResult<UserProfile[]>> {
    const body: Record<string, Object> = {
      'page': page,
      'limit': limit,
      'keyword': keyword
    };
    const res = await APIClient.getInstance().apiPost<Object>('/api/user/list', body);
    if (!res.success) {
      return UserApiResult.fail<UserProfile[]>(res.message ?? '', res.code ?? 0);
    }
    const items = asArray(asRecord(res.data)['items']);
    const list: UserProfile[] = [];
    items.forEach((item: Object): void => {
      list.push(UserProfile.fromJson(asRecord(item)));
    });
    return UserApiResult.ok<UserProfile[]>(list);
  }

  /** 创建用户（POST /api/user/create；密码按 AuthApiService.obfuscatePassword 混淆） */
  static async createUser(username: string, password: string,
    userRemark: string, phone: string): Promise<UserApiResult<Object>> {
    const body: Record<string, Object> = {
      'username': username,
      'password': AuthService.obfuscatePassword(password)
    };
    if (userRemark.trim().length > 0) {
      body['user_remark'] = userRemark.trim();
    }
    if (phone.trim().length > 0) {
      body['phone'] = phone.trim();
    }
    const res = await APIClient.getInstance().apiPost<Object>('/api/user/create', body);
    if (!res.success) {
      return UserApiResult.fail<Object>(res.message ?? '', res.code ?? 0);
    }
    return UserApiResult.ok<Object>(res.data);
  }

  /** 更新用户（POST /api/user/update/$id；password 已由调用方混淆后传入，与 Flutter 一致） */
  static async updateUser(id: number, username: string | undefined,
    password: string | undefined, isActive: boolean | undefined,
    userRemark: string | undefined, phone: string | undefined): Promise<UserApiResult<Object>> {
    const body: Record<string, Object> = {};
    if (username !== undefined) {
      body['username'] = username;
    }
    if (password !== undefined) {
      body['password'] = password;
    }
    if (isActive !== undefined) {
      body['is_active'] = isActive;
    }
    if (userRemark !== undefined) {
      body['user_remark'] = userRemark;
    }
    if (phone !== undefined) {
      body['phone'] = phone;
    }
    const res = await APIClient.getInstance()
      .apiPost<Object>(`/api/user/update/${id}`, body);
    if (!res.success) {
      return UserApiResult.fail<Object>(res.message ?? '', res.code ?? 0);
    }
    return UserApiResult.ok<Object>(res.data);
  }

  /** 删除用户（POST /api/user/delete，body {ids}） */
  static async deleteUsers(ids: number[]): Promise<UserApiResult<Object>> {
    const body: Record<string, Object> = { 'ids': ids };
    const res = await APIClient.getInstance().apiPost<Object>('/api/user/delete', body);
    if (!res.success) {
      return UserApiResult.fail<Object>(res.message ?? '', res.code ?? 0);
    }
    return UserApiResult.ok<Object>(res.data);
  }

  /** 读取用户权限（POST /api/user/permissions/get，body {uid}） */
  static async getUserPermissions(uid: number): Promise<UserApiResult<UserPermissionItem[]>> {
    const body: Record<string, Object> = { 'uid': uid };
    const res = await APIClient.getInstance()
      .apiPost<Object>('/api/user/permissions/get', body);
    if (!res.success) {
      return UserApiResult.fail<UserPermissionItem[]>(res.message ?? '', res.code ?? 0);
    }
    const items = asArray(res.data);
    const list: UserPermissionItem[] = [];
    items.forEach((item: Object): void => {
      list.push(UserPermissionItem.fromJson(asRecord(item)));
    });
    return UserApiResult.ok<UserPermissionItem[]>(list);
  }

  /** 保存用户权限（POST /api/user/permissions/$uid，body {permissions: 扁平条目}） */
  static async setUserPermissions(uid: number,
    permissions: UserPermissionItem[]): Promise<UserApiResult<Object>> {
    const flat: Record<string, Object>[] = [];
    permissions.forEach((p: UserPermissionItem): void => {
      flat.push(p.toBody());
    });
    const body: Record<string, Object> = { 'permissions': flat };
    const res = await APIClient.getInstance()
      .apiPost<Object>(`/api/user/permissions/${uid}`, body);
    if (!res.success) {
      return UserApiResult.fail<Object>(res.message ?? '', res.code ?? 0);
    }
    return UserApiResult.ok<Object>(res.data);
  }

  /** 目录浏览（POST /api/file/list，body {path, onlyDir}；onlyDir 以字符串 'true'/'false' 传输，与 Flutter 一致） */
  static async listDirectory(path: string,
    onlyDir: boolean = true): Promise<UserApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'path': path,
      'onlyDir': onlyDir ? 'true' : 'false'
    };
    const res = await APIClient.getInstance().apiPost<Object>('/api/file/list', body);
    if (!res.success) {
      return UserApiResult.fail<Record<string, Object>>(res.message ?? '', res.code ?? 0);
    }
    return UserApiResult.ok<Record<string, Object>>(asRecord(res.data));
  }

  /** 登录记录分页（POST /api/user/login-records，body {uid,page,limit}，取 data.items） */
  static async getLoginRecords(uid: number, page: number,
    limit: number): Promise<UserApiResult<LoginRecord[]>> {
    const body: Record<string, Object> = {
      'uid': uid,
      'page': page,
      'limit': limit
    };
    const res = await APIClient.getInstance()
      .apiPost<Object>('/api/user/login-records', body);
    if (!res.success) {
      return UserApiResult.fail<LoginRecord[]>(res.message ?? '', res.code ?? 0);
    }
    const items = asArray(asRecord(res.data)['items']);
    const list: LoginRecord[] = [];
    items.forEach((item: Object): void => {
      list.push(LoginRecord.fromJson(asRecord(item)));
    });
    return UserApiResult.ok<LoginRecord[]>(list);
  }

  /** 用户文件操作日志（POST /api/user/file-log/list，dataParser 解析 FileLogListResponse） */
  static async getUserFileLogs(uid: number, types: string[] | undefined, page: number,
    pageSize: number, stateList: string[] | undefined,
    keyword: string | undefined): Promise<UserApiResult<FileLogListResponse>> {
    const body: Record<string, Object> = {
      'uid': uid,
      'page': page,
      'pageSize': pageSize
    };
    if (types !== undefined) {
      body['types'] = types;
    }
    if (stateList !== undefined) {
      body['stateList'] = stateList;
    }
    if (keyword !== undefined) {
      body['keyword'] = keyword;
    }
    const res = await APIClient.getInstance().apiPost<FileLogListResponse>(
      '/api/user/file-log/list', body, undefined, undefined, undefined,
      (data: Object, _code: number): FileLogListResponse =>
        FileLogListResponse.fromJson(asRecord(data)));
    if (!res.success) {
      return UserApiResult.fail<FileLogListResponse>(res.message ?? '', res.code ?? 0);
    }
    return UserApiResult.ok<FileLogListResponse>(res.data);
  }

  /** 2FA 状态（POST /api/user/2fa/status；失败时按 Flutter 语义抛错，由控制器捕获） */
  static async getUser2faStatus(uid: number): Promise<Record<string, Object>> {
    const body: Record<string, Object> = { 'uid': uid };
    const res = await APIClient.getInstance()
      .apiPost<Object>('/api/user/2fa/status', body);
    if (!res.success) {
      throw new Error(res.message ?? '');
    }
    return asRecord(res.data);
  }

  /** 生成 2FA 绑定信息（POST /api/user/2fa/setup；失败时按 Flutter 语义抛错） */
  static async setupUser2fa(uid: number, issuer: string | undefined,
    accountName: string | undefined): Promise<Record<string, Object>> {
    const body: Record<string, Object> = { 'uid': uid };
    if (issuer !== undefined) {
      body['issuer'] = issuer;
    }
    if (accountName !== undefined) {
      body['accountName'] = accountName;
    }
    const res = await APIClient.getInstance().apiPost<Object>('/api/user/2fa/setup', body);
    if (!res.success) {
      throw new Error(res.message ?? '');
    }
    return asRecord(res.data);
  }

  /** 启用 2FA（POST /api/user/2fa/enable，body {uid,code,secret?}） */
  static async enableUser2fa(uid: number, code: string,
    secret: string | undefined): Promise<UserApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'uid': uid,
      'code': code
    };
    if (secret !== undefined) {
      body['secret'] = secret;
    }
    const res = await APIClient.getInstance().apiPost<Object>('/api/user/2fa/enable', body);
    if (!res.success) {
      return UserApiResult.fail<Record<string, Object>>(res.message ?? '', res.code ?? 0);
    }
    return UserApiResult.ok<Record<string, Object>>(asRecord(res.data));
  }

  /** 重置 2FA（POST /api/user/2fa/reset，body {uid}） */
  static async resetUser2fa(uid: number): Promise<UserApiResult<Object>> {
    const body: Record<string, Object> = { 'uid': uid };
    const res = await APIClient.getInstance().apiPost<Object>('/api/user/2fa/reset', body);
    if (!res.success) {
      return UserApiResult.fail<Object>(res.message ?? '', res.code ?? 0);
    }
    return UserApiResult.ok<Object>(res.data);
  }
}
