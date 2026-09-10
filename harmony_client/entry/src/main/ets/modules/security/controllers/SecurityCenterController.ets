import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { L10n } from '../../../core/localization/L10n';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { SecurityBlacklistItem, SecurityDevice } from '../models/SecurityModels';
import { SecurityApiService } from '../services/SecurityApiService';
import { SecurityPageKeys } from '../router/SecurityRoutes';

/**
 * 安全中心控制器（对齐 Flutter SecurityCenterController；@ObservedV2 + @Trace 驱动 V2 刷新）。
 * 随页面创建/销毁（对齐 Flutter SecurityCenterScope 每次 Get.put/Get.delete 的生命周期），
 * 页面 aboutToAppear 调 onInit()，aboutToDisappear 调 onClose()。
 *
 * 自动保存语义（对齐 Flutter debounce Worker）：banEnabled / bypassLanAuth 变更后
 * 450ms 内无后续变更才提交 setConfig；配置首次装载完成前不触发。
 */
@ObservedV2
export class SecurityCenterController {
  /** 当前面板 key（security.best_practices / security.settings / security.ip_blacklist / security.devices） */
  @Trace currentPageKey: string = SecurityPageKeys.BEST_PRACTICES;
  @Trace banEnabled: boolean = true;
  @Trace bypassLanAuth: boolean = true;
  /** 密码错误次数输入（Flutter maxFailedAttemptsController 对应） */
  @Trace maxFailedAttemptsText: string = '5';
  /** 封禁分钟数输入（Flutter banMinutesController 对应） */
  @Trace banMinutesText: string = '1';
  @Trace blacklist: SecurityBlacklistItem[] = [];
  @Trace devices: SecurityDevice[] = [];

  private autoSaveEnabled: boolean = false;
  private hydrating: boolean = false;
  private autoSaving: boolean = false;
  private pendingAutoSave: boolean = false;
  private banEnabledTimer: number = -1;
  private bypassLanAuthTimer: number = -1;

  get isAdmin(): boolean {
    return CurrentUserStore.getInstance().isAdmin;
  }

  /** 页面进入初始化（对齐 onInit） */
  onInit(): void {
    if (!this.isAdmin) {
      this.currentPageKey = SecurityPageKeys.DEVICES;
      void this.loadDevices(false);
      return;
    }
    this.autoSaveEnabled = false;
    void this.bootstrap();
  }

  /** 页面退出清理（对齐 onClose：撤销未触发的防抖定时器） */
  onClose(): void {
    if (this.banEnabledTimer >= 0) {
      clearTimeout(this.banEnabledTimer);
      this.banEnabledTimer = -1;
    }
    if (this.bypassLanAuthTimer >= 0) {
      clearTimeout(this.bypassLanAuthTimer);
      this.bypassLanAuthTimer = -1;
    }
  }

  private async bootstrap(): Promise<void> {
    await this.loadConfig(false);
    this.autoSaveEnabled = true;
    await this.loadBlacklist(false);
  }

  // ===== 面板切换（对齐 selectPage） =====

  selectPage(key: string): void {
    if (!this.isAdmin && key !== SecurityPageKeys.DEVICES) {
      this.currentPageKey = SecurityPageKeys.DEVICES;
      return;
    }
    this.currentPageKey = key;
    if (key === SecurityPageKeys.DEVICES) {
      void this.loadDevices(false);
    }
  }

  // ===== 配置读写（对齐 loadConfig/saveConfig/_autoSaveConfig） =====

  /** UI 开关回调：等价于 Flutter `ctrl.banEnabled.value = v`（Worker 防抖自动保存） */
  setBanEnabled(v: boolean): void {
    this.banEnabled = v;
    if (this.banEnabledTimer >= 0) {
      clearTimeout(this.banEnabledTimer);
    }
    this.banEnabledTimer = setTimeout((): void => {
      this.banEnabledTimer = -1;
      void this.autoSaveConfig();
    }, 450);
  }

  /** UI 开关回调：等价于 Flutter `ctrl.bypassLanAuth.value = v` */
  setBypassLanAuth(v: boolean): void {
    this.bypassLanAuth = v;
    if (this.bypassLanAuthTimer >= 0) {
      clearTimeout(this.bypassLanAuthTimer);
    }
    this.bypassLanAuthTimer = setTimeout((): void => {
      this.bypassLanAuthTimer = -1;
      void this.autoSaveConfig();
    }, 450);
  }

  onMaxFailedAttemptsInput(v: string): void {
    this.maxFailedAttemptsText = v;
  }

  onBanMinutesInput(v: string): void {
    this.banMinutesText = v;
  }

  /** 对齐 Flutter int.tryParse：全串为整数才解析，非法/<=0 回退默认值 */
  private parsePositiveInt(input: string, fallback: number): number {
    const s = input.trim();
    if (!/^[+-]?\d+$/.test(s)) {
      return fallback;
    }
    const v = Number(s);
    if (!Number.isFinite(v) || v <= 0) {
      return fallback;
    }
    return Math.trunc(v);
  }

  private async autoSaveConfig(): Promise<void> {
    if (!this.autoSaveEnabled || this.hydrating) {
      return;
    }
    if (this.autoSaving) {
      this.pendingAutoSave = true;
      return;
    }
    this.autoSaving = true;
    try {
      const maxFailedAttempts = this.parsePositiveInt(this.maxFailedAttemptsText, 5);
      const banMinutes = this.parsePositiveInt(this.banMinutesText, 1);
      const res = await SecurityApiService.setConfig(
        this.banEnabled, maxFailedAttempts, banMinutes, this.bypassLanAuth);
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      await this.loadConfig(false);
    } finally {
      this.autoSaving = false;
      if (this.pendingAutoSave) {
        this.pendingAutoSave = false;
        void this.autoSaveConfig();
      }
    }
  }

  async loadConfig(showLoading: boolean): Promise<void> {
    if (showLoading) {
      await DialogUtil.showLoading(L10n.loading);
    }
    this.hydrating = true;
    try {
      const res = await SecurityApiService.getConfig();
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      const data = res.data;
      if (data === undefined) {
        return;
      }
      this.banEnabled = data.banEnabled;
      this.maxFailedAttemptsText = `${data.maxFailedAttempts}`;
      this.banMinutesText = `${data.banMinutes}`;
      this.bypassLanAuth = data.bypassLanAuth;
    } finally {
      this.hydrating = false;
      if (showLoading) {
        await DialogUtil.dismissLoading();
      }
    }
  }

  async saveConfig(): Promise<void> {
    const maxFailedAttempts = this.parsePositiveInt(this.maxFailedAttemptsText, 5);
    const banMinutes = this.parsePositiveInt(this.banMinutesText, 1);
    const res = await SecurityApiService.setConfig(
      this.banEnabled, maxFailedAttempts, banMinutes, this.bypassLanAuth);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return;
    }
    await this.loadConfig(false);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  // ===== IP 黑名单（对齐 loadBlacklist/deleteIp/clearBlacklist） =====

  async loadBlacklist(showLoading: boolean): Promise<void> {
    if (showLoading) {
      await DialogUtil.showLoading(L10n.loading);
    }
    try {
      const res = await SecurityApiService.listIpBlacklist();
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      this.blacklist = res.data ?? [];
    } finally {
      if (showLoading) {
        await DialogUtil.dismissLoading();
      }
    }
  }

  async deleteIp(ip: string): Promise<void> {
    const p = ip.trim();
    if (p.length === 0) {
      return;
    }
    const ok = await DialogUtil.showConfirmDialog(
      L10n.t('confirm', '确认'), L10n.t('delete', '删除'));
    if (ok !== true) {
      return;
    }
    const res = await SecurityApiService.deleteIpBlacklist(p);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return;
    }
    await this.loadBlacklist(false);
    ToastUtil.show(L10n.t('delete_success', '删除成功'));
  }

  async clearBlacklist(): Promise<void> {
    const ok = await DialogUtil.showConfirmDialog(
      L10n.t('tip', '提示'), `${L10n.t('task_clear_all', '清空全部')} ?`);
    if (ok !== true) {
      return;
    }
    const res = await SecurityApiService.clearIpBlacklist();
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return;
    }
    await this.loadBlacklist(false);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  // ===== 设备管理（对齐 loadDevices/kickDevice） =====

  async loadDevices(showLoading: boolean): Promise<void> {
    if (showLoading) {
      await DialogUtil.showLoading(L10n.loading);
    }
    try {
      const res = await SecurityApiService.listDevices();
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      this.devices = res.data ?? [];
    } finally {
      if (showLoading) {
        await DialogUtil.dismissLoading();
      }
    }
  }

  async kickDevice(deviceId: string): Promise<void> {
    const id = deviceId.trim();
    if (id.length === 0) {
      return;
    }
    const ok = await DialogUtil.showConfirmDialog(
      L10n.t('confirm', '确认'), L10n.t('security.device_kick_confirm', '确认踢出该设备吗？'));
    if (ok !== true) {
      return;
    }
    const res = await SecurityApiService.kickDevice(id);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return;
    }
    await this.loadDevices(false);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }
}
