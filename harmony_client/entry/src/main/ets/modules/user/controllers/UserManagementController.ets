import { L10n } from '../../../core/localization/L10n';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { AuthService } from '../../../auth/AuthService';
import {
  FileOperationLog, FileLogListResponse, LoginRecord, PermissionGroup,
  UserPermissionItem, UserProfile, flattenPermissions, groupPermissions
} from '../models/UserModels';
import { UserApiService, UserApiResult } from '../services/UserApiService';

const PAGE_LIMIT: number = 20;

/**
 * 用户管理控制器（对齐 Flutter UserManagementController；@ObservedV2 + @Trace 驱动 V2 刷新）。
 * 模块内单例：用户列表页与详情页共享（对齐 Flutter GetView 共享 controller）。
 * 移动端形态：selectedIds 收敛为 selectedId 单选（Flutter 移动端分支每次 clear+add 单值）。
 */
@ObservedV2
export class UserManagementController {
  private static instance: UserManagementController | undefined = undefined;

  static getInstance(): UserManagementController {
    if (UserManagementController.instance === undefined) {
      UserManagementController.instance = new UserManagementController();
    }
    return UserManagementController.instance;
  }

  // ===== 用户列表 =====
  @Trace users: UserProfile[] = [];
  /** 当前选中用户（移动端单选；-1 表示无） */
  @Trace selectedId: number = -1;
  @Trace loading: boolean = false;
  @Trace keyword: string = '';
  @Trace usersPage: number = 1;
  @Trace usersHasMore: boolean = true;
  @Trace usersLoadingMore: boolean = false;

  // ===== 登录记录 =====
  @Trace loginRecords: LoginRecord[] = [];
  @Trace loginRecordsPage: number = 1;
  @Trace loginRecordsHasMore: boolean = true;
  @Trace loginRecordsLoading: boolean = false;

  // ===== 操作日志 =====
  @Trace operationLogs: FileOperationLog[] = [];
  @Trace operationLogsPage: number = 1;
  @Trace operationLogsHasMore: boolean = true;
  @Trace operationLogsLoading: boolean = false;
  @Trace operationLogsTotal: number = 0;
  @Trace operationLogsKeyword: string = '';

  // ===== 每用户缓存（Map 整体重赋值以触发 V2 刷新） =====
  @Trace permissionsMap: Map<number, PermissionGroup[]> = new Map<number, PermissionGroup[]>();
  @Trace twofaStatusMap: Map<number, Object> = new Map<number, Object>();
  @Trace twofaSetupMap: Map<number, Object> = new Map<number, Object>();
  @Trace twofaLoadingMap: Map<number, boolean> = new Map<number, boolean>();

  private initialized: boolean = false;
  private searchTimer: number = -1;
  private opLogSearchTimer: number = -1;

  /** 页面进入初始化（对齐 onInit 的 fetchUsers；仅首次生效） */
  ensureInit(): void {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    void this.fetchUsers();
  }

  private onSelectedChanged(): void {
    // 切换用户时清除旧用户缓存（对齐 ever(selectedIds) 监听）
    this.permissionsMap = new Map<number, PermissionGroup[]>();
    this.twofaStatusMap = new Map<number, Object>();
    this.twofaSetupMap = new Map<number, Object>();
    this.operationLogs = [];
    this.operationLogsTotal = 0;
    this.operationLogsPage = 1;
    this.operationLogsHasMore = true;
  }

  /** 选中用户并刷新登录记录（对齐列表卡片 onTap：clear+add+refreshLoginRecords） */
  selectUser(uid: number): void {
    if (this.selectedId !== uid) {
      this.selectedId = uid;
      this.onSelectedChanged();
    }
    void this.refreshLoginRecords(uid);
  }

  getCurrentUser(): UserProfile | undefined {
    for (const u of this.users) {
      if (u.id === this.selectedId) {
        return u;
      }
    }
    return undefined;
  }

  /** 用户类型标签（user_type_$type，缺省按 user） */
  userTypeLabel(type: string): string {
    return L10n.t(`user_type_${type}`, type);
  }

  // ===== 用户列表（对齐 fetchUsers/loadMoreUsers） =====

  /** 搜索输入（对齐 CustomExpandableSearchBar onChanged + onDebouncedChanged 500ms） */
  onSearchChanged(v: string): void {
    this.keyword = v;
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      void this.fetchUsers();
    }, 500);
  }

  async fetchUsers(): Promise<void> {
    this.loading = true;
    try {
      this.usersPage = 1;
      this.usersHasMore = true;
      const res = await UserApiService.fetchUsers(1, PAGE_LIMIT, this.keyword);
      if (!res.success || res.data === undefined) {
        DialogUtil.showErrorDialog(L10n.t('user_mgmt_fetch_failed', '获取用户失败'));
        return;
      }
      const casted = res.data;
      this.users = casted;
      this.usersHasMore = casted.length >= PAGE_LIMIT;
      this.usersPage = this.usersHasMore ? 2 : 1;
      // 用户列表可能已更新，清理权限缓存（对齐 fetchUsers 内缓存清理）
      this.permissionsMap = new Map<number, PermissionGroup[]>();
      if (this.users.length > 0) {
        const firstId = this.users[0].id;
        this.selectUser(firstId);
      } else {
        this.selectedId = -1;
        this.onSelectedChanged();
        this.loginRecords = [];
        this.loginRecordsPage = 1;
        this.loginRecordsHasMore = true;
      }
    } finally {
      this.loading = false;
    }
  }

  async loadMoreUsers(): Promise<void> {
    if (this.loading || this.usersLoadingMore || !this.usersHasMore) {
      return;
    }
    this.usersLoadingMore = true;
    try {
      const page = this.usersPage;
      const res = await UserApiService.fetchUsers(page, PAGE_LIMIT, this.keyword);
      if (!res.success || res.data === undefined) {
        return;
      }
      const casted = res.data;
      if (casted.length === 0) {
        this.usersHasMore = false;
        return;
      }
      const merged: UserProfile[] = this.users.slice();
      casted.forEach((u: UserProfile): void => {
        merged.push(u);
      });
      this.users = merged;
      this.usersHasMore = casted.length >= PAGE_LIMIT;
      if (this.usersHasMore) {
        this.usersPage = page + 1;
      }
    } finally {
      this.usersLoadingMore = false;
    }
  }

  // ===== 用户增删改（对齐 createUser/updateUser/deleteSelected） =====

  async createUser(username: string, password: string,
    userRemark: string, phone: string): Promise<boolean> {
    const res = await UserApiService.createUser(username, password, userRemark, phone);
    await this.fetchUsers();
    const ok = res.success;
    if (!ok) {
      DialogUtil.showErrorDialog(
        res.message.length > 0 ? res.message : L10n.t('user_mgmt_create_failed', '创建用户失败'));
    } else {
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
    }
    return ok;
  }

  /** password 为明文，非空时内部混淆（等价 Flutter 表单控制器先 obfuscate 再提交） */
  async updateUser(id: number, username: string | undefined, password: string | undefined,
    isActive: boolean | undefined, userRemark: string | undefined,
    phone: string | undefined): Promise<boolean> {
    const obfPassword = password !== undefined && password.length > 0
      ? AuthService.obfuscatePassword(password) : undefined;
    const res = await UserApiService.updateUser(id, username, obfPassword, isActive,
      userRemark, phone);
    await this.fetchUsers();
    if (!res.success) {
      DialogUtil.showErrorDialog(
        res.message.length > 0 ? res.message : L10n.t('user_mgmt_update_failed', '更新用户失败'));
    } else {
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
    }
    return res.success;
  }

  async deleteSelected(): Promise<boolean> {
    if (this.selectedId < 0) {
      return true;
    }
    const res = await UserApiService.deleteUsers([this.selectedId]);
    if (res.success) {
      await this.fetchUsers();
      ToastUtil.show(L10n.t('delete_success', '删除成功'));
    } else {
      DialogUtil.showErrorDialog(
        res.message.length > 0 ? res.message : L10n.t('operation_failed', '操作失败'));
    }
    return res.success;
  }

  // ===== 权限（对齐 getPermissions/setPermissions） =====

  hasPermissions(uid: number): boolean {
    return this.permissionsMap.has(uid);
  }

  getPermissions(uid: number): PermissionGroup[] {
    return this.permissionsMap.get(uid) ?? [];
  }

  /** 拉取并缓存用户权限；失败时缓存空列表（对齐 getPermissions） */
  async loadPermissions(uid: number): Promise<void> {
    if (this.permissionsMap.has(uid)) {
      return;
    }
    try {
      const res = await UserApiService.getUserPermissions(uid);
      if (res.data === undefined) {
        throw new Error(res.message);
      }
      this.permissionsMap = this.withMapEntry(this.permissionsMap, uid,
        groupPermissions(res.data));
    } catch (_e) {
      DialogUtil.showErrorDialog(
        L10n.t('user_mgmt_permissions_fetch_failed', '获取权限失败'));
      this.permissionsMap = this.withMapEntry(this.permissionsMap, uid, []);
    }
  }

  async setPermissions(uid: number, groups: PermissionGroup[]): Promise<boolean> {
    const res = await UserApiService.setUserPermissions(uid, flattenPermissions(groups));
    if (res.success) {
      this.permissionsMap = this.withMapEntry(this.permissionsMap, uid, groups);
    } else {
      DialogUtil.showErrorDialog(
        res.message.length > 0 ? res.message : L10n.t('operation_failed', '操作失败'));
    }
    return res.success;
  }

  private withMapEntry<V>(src: Map<number, V>, uid: number, value: V): Map<number, V> {
    const next = new Map<number, V>();
    src.forEach((v: V, k: number): void => {
      next.set(k, v);
    });
    next.set(uid, value);
    return next;
  }

  // ===== 登录记录（对齐 refreshLoginRecords/loadMoreLoginRecords） =====

  async refreshLoginRecords(uid: number, limit: number = 20): Promise<void> {
    this.loginRecordsLoading = true;
    try {
      const res = await UserApiService.getLoginRecords(uid, 1, limit);
      if (res.data === undefined) {
        return;
      }
      const list = res.data;
      this.loginRecords = list;
      this.loginRecordsHasMore = list.length >= limit;
      if (this.loginRecordsHasMore) {
        this.loginRecordsPage = 2;
      }
    } finally {
      this.loginRecordsLoading = false;
    }
  }

  async loadMoreLoginRecords(limit: number = 20): Promise<void> {
    if (this.loginRecordsLoading || !this.loginRecordsHasMore) {
      return;
    }
    if (this.selectedId < 0) {
      return;
    }
    const uid = this.selectedId;
    this.loginRecordsLoading = true;
    try {
      const page = this.loginRecordsPage;
      const res = await UserApiService.getLoginRecords(uid, page, limit);
      if (res.data === undefined) {
        return;
      }
      const list = res.data;
      if (list.length === 0) {
        this.loginRecordsHasMore = false;
        return;
      }
      const merged: LoginRecord[] = this.loginRecords.slice();
      list.forEach((r: LoginRecord): void => {
        merged.push(r);
      });
      this.loginRecords = merged;
      this.loginRecordsHasMore = list.length >= limit;
      if (this.loginRecordsHasMore) {
        this.loginRecordsPage = page + 1;
      }
    } finally {
      this.loginRecordsLoading = false;
    }
  }

  // ===== 操作日志（对齐 refreshOperationLogs/loadMoreOperationLogs + debounce 搜索） =====

  onOperationLogsSearchChanged(v: string): void {
    this.operationLogsKeyword = v;
    if (this.opLogSearchTimer >= 0) {
      clearTimeout(this.opLogSearchTimer);
    }
    this.opLogSearchTimer = setTimeout((): void => {
      this.opLogSearchTimer = -1;
      if (this.selectedId < 0) {
        return;
      }
      void this.refreshOperationLogs(this.selectedId);
    }, 500);
  }

  async refreshOperationLogs(uid: number, pageSize: number = 20): Promise<void> {
    this.operationLogsLoading = true;
    try {
      const keyword = this.operationLogsKeyword.trim();
      const res = await UserApiService.getUserFileLogs(uid, undefined, 1, pageSize,
        ['SUCCESS'], keyword.length > 0 ? keyword : undefined);
      if (!res.success || res.data === undefined) {
        this.operationLogs = [];
        this.operationLogsTotal = 0;
        this.operationLogsHasMore = false;
        return;
      }
      this.applyOperationLogsPage(res.data, false);
    } finally {
      this.operationLogsLoading = false;
    }
  }

  async loadMoreOperationLogs(pageSize: number = 20): Promise<void> {
    if (this.operationLogsLoading || !this.operationLogsHasMore) {
      return;
    }
    if (this.selectedId < 0) {
      return;
    }
    const uid = this.selectedId;
    this.operationLogsLoading = true;
    try {
      const page = this.operationLogsPage;
      const keyword = this.operationLogsKeyword.trim();
      const res = await UserApiService.getUserFileLogs(uid, undefined, page, pageSize,
        ['SUCCESS'], keyword.length > 0 ? keyword : undefined);
      if (!res.success || res.data === undefined) {
        this.operationLogsHasMore = false;
        return;
      }
      this.applyOperationLogsPage(res.data, true);
    } finally {
      this.operationLogsLoading = false;
    }
  }

  private applyOperationLogsPage(data: FileLogListResponse, append: boolean): void {
    this.operationLogsTotal = data.total;
    if (append && data.list.length === 0) {
      this.operationLogsHasMore = false;
      return;
    }
    if (append) {
      const merged: FileOperationLog[] = this.operationLogs.slice();
      data.list.forEach((l: FileOperationLog): void => {
        merged.push(l);
      });
      this.operationLogs = merged;
    } else {
      this.operationLogs = data.list;
    }
    this.operationLogsHasMore = this.operationLogs.length < this.operationLogsTotal;
    if (this.operationLogsHasMore) {
      this.operationLogsPage = (append ? this.operationLogsPage : 1) + 1;
    }
  }

  // ===== 2FA（对齐 getTwofaStatus/refreshTwofaStatus/setupTwofa/enableTwofa/resetTwofa） =====

  private setTwofaLoading(uid: number, v: boolean): void {
    const next = new Map<number, boolean>();
    this.twofaLoadingMap.forEach((lv: boolean, k: number): void => {
      next.set(k, lv);
    });
    next.set(uid, v);
    this.twofaLoadingMap = next;
  }

  isTwofaLoading(uid: number): boolean {
    return this.twofaLoadingMap.get(uid) === true;
  }

  getTwofaStatus(uid: number): Record<string, Object> {
    const cached = this.twofaStatusMap.get(uid);
    if (cached !== undefined) {
      return cached as Record<string, Object>;
    }
    const empty: Record<string, Object> = {};
    return empty;
  }

  /** 拉取 2FA 状态并缓存（对齐 getTwofaStatus：失败缓存空对象） */
  async loadTwofaStatus(uid: number): Promise<void> {
    if (this.twofaStatusMap.has(uid)) {
      return;
    }
    try {
      this.setTwofaLoading(uid, true);
      const data = await UserApiService.getUser2faStatus(uid);
      const next = new Map<number, Object>();
      this.twofaStatusMap.forEach((v: Object, k: number): void => {
        next.set(k, v);
      });
      next.set(uid, data);
      this.twofaStatusMap = next;
    } catch (_e) {
      this.twofaStatusMap = this.withMapEntry(this.twofaStatusMap, uid,
        {} as Record<string, Object>);
    } finally {
      this.setTwofaLoading(uid, false);
    }
  }

  async refreshTwofaStatus(uid: number): Promise<void> {
    try {
      this.setTwofaLoading(uid, true);
      const data = await UserApiService.getUser2faStatus(uid);
      const next = new Map<number, Object>();
      this.twofaStatusMap.forEach((v: Object, k: number): void => {
        next.set(k, v);
      });
      next.set(uid, data);
      this.twofaStatusMap = next;
    } catch (_e) {
      DialogUtil.showErrorDialog(L10n.t('operation_failed', '操作失败'));
    } finally {
      this.setTwofaLoading(uid, false);
    }
  }

  /** 生成绑定信息（对齐 setupTwofa：成功返回数据并刷新状态，失败弹错返回 undefined） */
  async setupTwofa(uid: number, accountName: string | undefined):
    Promise<Record<string, Object> | undefined> {
    try {
      this.setTwofaLoading(uid, true);
      const data = await UserApiService.setupUser2fa(uid, undefined, accountName);
      const next = new Map<number, Object>();
      this.twofaSetupMap.forEach((v: Object, k: number): void => {
        next.set(k, v);
      });
      next.set(uid, data);
      this.twofaSetupMap = next;
      await this.refreshTwofaStatus(uid);
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      return data;
    } catch (e) {
      DialogUtil.showErrorDialog(`${e}`);
      return undefined;
    } finally {
      this.setTwofaLoading(uid, false);
    }
  }

  async enableTwofa(uid: number, code: string): Promise<boolean> {
    try {
      this.setTwofaLoading(uid, true);
      const cachedSetup = this.twofaSetupMap.get(uid);
      const setup: Record<string, Object> = cachedSetup === undefined
        ? {} as Record<string, Object>
        : cachedSetup as Record<string, Object>;
      const rawSecret = setup['secret'];
      const secret = typeof rawSecret === 'string' ? rawSecret : undefined;
      const res: UserApiResult<Record<string, Object>> =
        await UserApiService.enableUser2fa(uid, code, secret);
      if (!res.success) {
        DialogUtil.showErrorDialog(
          res.message.length > 0 ? res.message : L10n.t('operation_failed', '操作失败'));
        return false;
      }
      if (res.data !== undefined) {
        const merged = new Map<number, Object>();
        this.twofaSetupMap.forEach((v: Object, k: number): void => {
          merged.set(k, v);
        });
        merged.set(uid, res.data);
        this.twofaSetupMap = merged;
      }
      await this.refreshTwofaStatus(uid);
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      return true;
    } finally {
      this.setTwofaLoading(uid, false);
    }
  }

  async resetTwofa(uid: number): Promise<boolean> {
    this.setTwofaLoading(uid, true);
    try {
      const res = await UserApiService.resetUser2fa(uid);
      if (res.success) {
        const next = new Map<number, Object>();
        this.twofaSetupMap.forEach((v: Object, k: number): void => {
          next.set(k, v);
        });
        next.delete(uid);
        this.twofaSetupMap = next;
        await this.refreshTwofaStatus(uid);
        ToastUtil.show(L10n.t('operation_success', '操作成功'));
        return true;
      }
      DialogUtil.showErrorDialog(
        res.message.length > 0 ? res.message : L10n.t('operation_failed', '操作失败'));
      return false;
    } finally {
      this.setTwofaLoading(uid, false);
    }
  }
}
