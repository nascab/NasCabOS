import { L10n } from '../../../core/localization/L10n';
import { APIClient } from '../../../core/network/APIClient';
import { WindowStore } from '../../../common/WindowStore';
import { ToastUtil } from '../../../common/ToastUtil';
import { P2pServer, BindP2pDeviceResult, svcRecord, svcStr } from '../models/ServiceModels';
import { ServiceApiService, svcBusinessCode, NASCAB_WEBSITE_BASE_URL } from '../services/ServiceApiService';
import { ServicePageKeys } from '../router/ServiceRoutes';

/** DDNS 最低服务端主版本（对齐 Flutter ServerVersionUtil.isAtLeast(serverVersion, 3)） */
const DDNS_MIN_SERVER_MAJOR: number = 3;

/** 业务错误码提示（对齐 Flutter：errKey.tr 能翻译则用译文，否则依次回退 message/errKey/操作失败） */
function toastBusinessError(errKey: string, resMsg: string): void {
  const key = errKey.trim();
  const msg = resMsg.trim();
  if (key.length > 0) {
    const translated = L10n.t(key, '');
    if (translated.length > 0 && translated !== key) {
      ToastUtil.show(translated);
    } else if (msg.length > 0) {
      ToastUtil.show(msg);
    } else {
      ToastUtil.show(key);
    }
  } else if (msg.length > 0) {
    ToastUtil.show(msg);
  } else {
    ToastUtil.show(L10n.t('operation_failed', '操作失败'));
  }
}

/**
 * 服务主控制器（对齐 Flutter ServiceMainController）：
 * 页内 tab 切换 + P2P 远程访问（含 3 秒配对码轮询）+ DDNS 状态与设置。
 * 全局单例（Flutter Get.put permanent: true 对应实现）。
 */
@ObservedV2
export class ServiceMainController {
  private static instance: ServiceMainController | undefined = undefined;

  static getInstance(): ServiceMainController {
    if (!ServiceMainController.instance) {
      ServiceMainController.instance = new ServiceMainController();
    }
    return ServiceMainController.instance;
  }

  /** 当前页 key（对齐 Flutter currentPageKey） */
  @Trace currentPageKey: string = ServicePageKeys.ACCOUNT_NASCAB;

  // ===== 远程访问（对齐 Flutter remoteAccess 状态组） =====
  @Trace remoteAccessEnabled: boolean = false;
  @Trace pairCode: string = '';
  @Trace p2pErrorCode: string = '';
  @Trace p2pConnectedDomain: string = '';
  @Trace p2pFixNodeDomain: string = '';
  @Trace p2pServers: P2pServer[] = [];
  @Trace remoteAccessLoading: boolean = false;
  @Trace nascabLoggedIn: boolean = false;

  // ===== DDNS（对齐 Flutter ddns 状态组；可空字符串字段用 '' 表示 null） =====
  @Trace ddnsEnabled: boolean = false;
  @Trace ddnsType: string = '';
  @Trace ddnsTypeDraft: string = '';
  @Trace ddnsDomain: string = '';
  @Trace ddnsBase: string = '';
  @Trace ddnsFullDomain: string = '';
  @Trace ddnsPublicIp: string = '';
  @Trace ddnsLastIp: string = '';
  @Trace ddnsLastTime: string = '';
  @Trace ddnsLastError: string = '';
  @Trace ddnsDeviceId: string = '';
  @Trace ddnsLoading: boolean = false;
  @Trace ddnsStatusReady: boolean = false;
  @Trace ddnsStatusLoadFailed: boolean = false;

  /** 配对码轮询定时器与开关（对齐 Flutter _pairCodePollTimer/_pairCodePollingActive） */
  private pairCodePollTimer: number = -1;
  private pairCodePollingActive: boolean = false;
  /** DDNS 默认类型自动保存标记（对齐 Flutter _autoTypeSaved） */
  private autoTypeSaved: boolean = false;

  // ===== 页面切换 =====

  selectPage(key: string): void {
    this.currentPageKey = key;
  }

  // ===== 配对码轮询（页面打开期间每 3 秒刷新一次） =====

  startPairCodePolling(): void {
    if (this.pairCodePollingActive) {
      return;
    }
    this.pairCodePollingActive = true;
    this.scheduleNextPairCodePoll();
  }

  stopPairCodePolling(): void {
    this.pairCodePollingActive = false;
    this.cancelPairCodePollTimer();
  }

  private cancelPairCodePollTimer(): void {
    if (this.pairCodePollTimer >= 0) {
      clearTimeout(this.pairCodePollTimer);
      this.pairCodePollTimer = -1;
    }
  }

  private scheduleNextPairCodePoll(): void {
    if (!this.pairCodePollingActive) {
      return;
    }
    this.cancelPairCodePollTimer();
    this.pairCodePollTimer = setTimeout((): void => {
      this.pairCodePollTimer = -1;
      this.refreshRemoteAccess(false).then((): void => {
        if (this.pairCodePollingActive) {
          this.scheduleNextPairCodePoll();
        }
      });
    }, 3000);
  }

  // ===== 远程访问 =====

  async refreshRemoteAccess(showLoading: boolean = true): Promise<void> {
    if (this.remoteAccessLoading) {
      return;
    }
    if (showLoading) {
      this.remoteAccessLoading = true;
    }
    try {
      const userRes = await ServiceApiService.query();
      const userRec = svcRecord(userRes.data);
      const loggedIn = Object.keys(userRec).length > 0;
      this.nascabLoggedIn = loggedIn;
      if (!loggedIn) {
        this.remoteAccessEnabled = false;
        this.pairCode = '';
        this.p2pErrorCode = '';
        this.p2pConnectedDomain = '';
        this.p2pFixNodeDomain = '';
        this.p2pServers = [];
        return;
      }
      const res = await ServiceApiService.getP2pRemoteAccess();
      if (res.success) {
        const data = svcRecord(res.data);
        this.remoteAccessEnabled = data['enabled'] === true;
        this.pairCode = svcStr(data['pairCode']).trim();
        this.p2pErrorCode = svcStr(data['errorCode']).trim();
        this.p2pConnectedDomain = svcStr(data['p2pConnectedDomain']).trim();
        this.p2pFixNodeDomain = svcStr(data['p2pFixNodeDomain']).trim();
        const rawServers = data['p2pServers'];
        const servers: P2pServer[] = [];
        if (Array.isArray(rawServers)) {
          for (const e of rawServers as Object[]) {
            const s = P2pServer.fromJson(svcRecord(e));
            if (s.domain.length > 0) {
              servers.push(s);
            }
          }
        }
        this.p2pServers = servers;
      }
    } finally {
      if (showLoading) {
        this.remoteAccessLoading = false;
      }
    }
  }

  async setRemoteAccessEnabled(enabled: boolean): Promise<boolean> {
    if (this.remoteAccessLoading) {
      return false;
    }
    this.remoteAccessLoading = true;
    try {
      if (enabled && !await this.ensureLoggedIn()) {
        return false;
      }
      const res = await ServiceApiService.setP2pRemoteAccess(enabled);
      if (!res.success) {
        return false;
      }
      this.remoteAccessEnabled = enabled;
      await this.refreshRemoteAccess();
      return true;
    } finally {
      this.remoteAccessLoading = false;
    }
  }

  async resetPairCode(): Promise<boolean> {
    if (this.remoteAccessLoading) {
      return false;
    }
    this.remoteAccessLoading = true;
    try {
      if (!await this.ensureLoggedIn()) {
        return false;
      }
      const res = await ServiceApiService.resetP2pPairCode();
      if (!res.success) {
        return false;
      }
      const code = ServiceApiService.pairCodeOf(res);
      if (code.length === 0) {
        return false;
      }
      this.pairCode = code;
      return true;
    } finally {
      this.remoteAccessLoading = false;
    }
  }

  async customPairCode(nextPairCode: string): Promise<boolean> {
    if (this.remoteAccessLoading) {
      return false;
    }
    this.remoteAccessLoading = true;
    try {
      if (!await this.ensureLoggedIn()) {
        return false;
      }
      const res = await ServiceApiService.customP2pPairCode(nextPairCode);
      if (!res.success) {
        toastBusinessError(svcBusinessCode(res), res.message ?? '');
        return false;
      }
      const code = ServiceApiService.pairCodeOf(res);
      if (code.length === 0) {
        return false;
      }
      this.pairCode = code;
      return true;
    } finally {
      this.remoteAccessLoading = false;
    }
  }

  async setP2pNodePreference(domain: string): Promise<boolean> {
    if (this.remoteAccessLoading) {
      return false;
    }
    this.remoteAccessLoading = true;
    try {
      if (!await this.ensureLoggedIn()) {
        return false;
      }
      const res = await ServiceApiService.setP2pNodePreference(domain);
      if (!res.success) {
        return false;
      }
      this.p2pFixNodeDomain = domain.trim();
      await this.refreshRemoteAccess(false);
      return true;
    } finally {
      this.remoteAccessLoading = false;
    }
  }

  /** 绑定当前设备到 NasCab 账号（用于 P2P 远程连接） */
  async bindP2pDevice(): Promise<BindP2pDeviceResult> {
    if (this.remoteAccessLoading) {
      return BindP2pDeviceResult.fail();
    }
    this.remoteAccessLoading = true;
    try {
      if (!await this.ensureLoggedIn()) {
        return BindP2pDeviceResult.fail();
      }
      const res = await ServiceApiService.bindP2pDevice();
      if (!res.success) {
        return BindP2pDeviceResult.fail(svcBusinessCode(res));
      }
      await this.refreshRemoteAccess();
      return BindP2pDeviceResult.ok();
    } finally {
      this.remoteAccessLoading = false;
    }
  }

  /** 打开「我的设备」页面（与账号页的「我的设备」一致） */
  async openMyDevicesUrl(): Promise<void> {
    if (!this.nascabLoggedIn) {
      ToastUtil.show(L10n.t('service_nascab_not_logged_in', '未登录'));
      return;
    }
    await this.openUrlWithTempCode('devices');
  }

  /** 带 tempCode 和 language 打开 nas.cab/user/[path]（对齐 Flutter _openUrlWithTempCode） */
  async openUrlWithTempCode(path: string): Promise<boolean> {
    try {
      const res = await ServiceApiService.getTempCode();
      if (!res.success) {
        const msg = (res.message ?? '').trim();
        ToastUtil.show(msg.length > 0 ? msg : L10n.t('operation_failed', '操作失败'));
        return false;
      }
      const data = svcRecord(res.data);
      const code = svcStr(data['code']).trim();
      if (code.length === 0) {
        ToastUtil.show(L10n.t('operation_failed', '操作失败'));
        return false;
      }
      const url = `${NASCAB_WEBSITE_BASE_URL}/user/${path}?code=${code}&language=${L10n.locale}`;
      this.openExternal(url);
      return true;
    } catch (_e) {
      ToastUtil.show(L10n.t('network_failure', '网络请求失败，请检查服务器连接'));
      return false;
    }
  }

  private openExternal(url: string): void {
    const ctx = WindowStore.appContext;
    if (ctx === undefined) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    ctx.openLink(url);
  }

  // ===== 登录状态辅助 =====

  /** 确保已获取登录态；未登录时重查一次（对齐 Flutter 各操作里的 query 兜底） */
  private async ensureLoggedIn(): Promise<boolean> {
    if (!this.nascabLoggedIn) {
      const userRes = await ServiceApiService.query();
      const userRec = svcRecord(userRes.data);
      this.nascabLoggedIn = Object.keys(userRec).length > 0;
    }
    return this.nascabLoggedIn;
  }

  // ===== DDNS =====

  /** 服务端版本是否低于 DDNS 最低要求（对齐 Flutter ServerVersionUtil.isAtLeast(ver, 3)） */
  isServerVersionTooLow(): boolean {
    const ver = `${APIClient.getInstance().state.serverVersion ?? ''}`.trim();
    const parts = ver.split('.');
    const major = parts.length > 0 ? Number(parts[0]) : 0;
    return !(Number.isFinite(major) && major >= DDNS_MIN_SERVER_MAJOR);
  }

  /** DDNS 页初始化：刷新状态并自动保存默认类型（对齐 Flutter ServiceDdnsView.initState） */
  async initDdns(): Promise<void> {
    if (this.isServerVersionTooLow()) {
      return;
    }
    await this.refreshDdnsStatus(false, true);
    if (this.autoTypeSaved) {
      return;
    }
    if (this.ddnsType.trim().length > 0) {
      return;
    }
    this.autoTypeSaved = true;
    await this.ensureDdnsTypeDefault(true);
  }

  async refreshDdnsStatus(showLoading: boolean = true, force: boolean = false): Promise<void> {
    if (this.ddnsLoading && !force) {
      return;
    }
    const shouldToggleLoading = (showLoading || !this.ddnsStatusReady) && !this.ddnsLoading;
    if (shouldToggleLoading) {
      this.ddnsLoading = true;
    }
    this.ddnsStatusLoadFailed = false;
    let requestSucceeded = false;
    try {
      const userRes = await ServiceApiService.query();
      if (!userRes.success) {
        return;
      }
      const userRec = svcRecord(userRes.data);
      const loggedIn = Object.keys(userRec).length > 0;
      this.nascabLoggedIn = loggedIn;
      if (!loggedIn) {
        this.ddnsEnabled = false;
        this.ddnsType = '';
        this.ddnsTypeDraft = '';
        this.ddnsDomain = '';
        this.ddnsBase = '';
        this.ddnsFullDomain = '';
        this.ddnsPublicIp = '';
        this.ddnsLastIp = '';
        this.ddnsLastTime = '';
        this.ddnsLastError = '';
        this.ddnsDeviceId = '';
        requestSucceeded = true;
        return;
      }
      const res = await ServiceApiService.getDdnsStatus();
      if (!res.success) {
        return;
      }
      const data = svcRecord(res.data);
      this.ddnsEnabled = data['enabled'] === true;
      const nextType = svcStr(data['ddnsType']).trim();
      this.ddnsType = nextType;
      this.ddnsDomain = svcStr(data['ddnsDomain']).trim();
      this.ddnsBase = svcStr(data['ddnsBase']).trim();
      this.ddnsFullDomain = svcStr(data['ddnsFullDomain']).trim();
      this.ddnsPublicIp = svcStr(data['publicIp']).trim();
      this.ddnsLastIp = svcStr(data['ddnsLastIp']).trim();
      this.ddnsLastTime = svcStr(data['ddnsLastTime']).trim();
      this.ddnsLastError = svcStr(data['ddnsLastError']).trim();
      this.ddnsDeviceId = svcStr(data['deviceId']).trim();
      requestSucceeded = true;
    } finally {
      if (requestSucceeded) {
        this.ddnsStatusReady = true;
        this.ddnsStatusLoadFailed = false;
      } else if (!this.ddnsStatusReady) {
        this.ddnsStatusLoadFailed = true;
      }
      if (shouldToggleLoading) {
        this.ddnsLoading = false;
      }
    }
  }

  async ensureDdnsTypeDefault(refresh: boolean = false): Promise<boolean> {
    if (this.ddnsLoading) {
      return false;
    }
    this.ddnsLoading = true;
    try {
      if (!await this.ensureLoggedIn()) {
        return false;
      }
      if (this.ddnsType.trim().length > 0) {
        this.ddnsTypeDraft = '';
        return true;
      }
      const nextType = this.ddnsTypeDraft.trim().length > 0 ? this.ddnsTypeDraft.trim() : 'ipv4';
      const res = await ServiceApiService.setDdnsType(nextType);
      if (!res.success) {
        return false;
      }
      this.ddnsType = nextType;
      this.ddnsTypeDraft = '';
      if (refresh) {
        await this.refreshDdnsStatus(false, true);
      }
      return true;
    } finally {
      this.ddnsLoading = false;
    }
  }

  async setDdnsEnabled(enabled: boolean): Promise<boolean> {
    if (this.ddnsLoading) {
      return false;
    }
    this.ddnsLoading = true;
    try {
      if (enabled) {
        if (!await this.ensureLoggedIn()) {
          return false;
        }
        if (this.ddnsDomain.trim().length === 0) {
          return false;
        }
        if (this.ddnsType.trim().length === 0) {
          const typeRes = await ServiceApiService.setDdnsType('ipv4');
          if (!typeRes.success) {
            return false;
          }
          this.ddnsType = 'ipv4';
          this.ddnsTypeDraft = '';
        }
      }
      const res = await ServiceApiService.setDdnsEnabled(enabled);
      if (!res.success) {
        return false;
      }
      this.ddnsEnabled = enabled;
      await this.refreshDdnsStatus(false, true);
      if (enabled) {
        setTimeout((): void => {
          void this.refreshDdnsStatus(false, true);
        }, 2000);
        setTimeout((): void => {
          void this.refreshDdnsStatus(false, true);
        }, 6000);
      }
      return true;
    } finally {
      this.ddnsLoading = false;
    }
  }

  async setDdnsTypeValue(nextType: string): Promise<boolean> {
    if (this.ddnsLoading) {
      return false;
    }
    this.ddnsLoading = true;
    try {
      if (!await this.ensureLoggedIn()) {
        return false;
      }
      const res = await ServiceApiService.setDdnsType(nextType.trim());
      if (!res.success) {
        return false;
      }
      this.ddnsTypeDraft = '';
      await this.refreshDdnsStatus(false, true);
      return true;
    } finally {
      this.ddnsLoading = false;
    }
  }

  async setDdnsDomainPrefix(ddnsDomainPrefix: string): Promise<boolean> {
    if (this.ddnsLoading) {
      return false;
    }
    this.ddnsLoading = true;
    try {
      if (!await this.ensureLoggedIn()) {
        return false;
      }
      const res = await ServiceApiService.setDdnsDomain(ddnsDomainPrefix.trim());
      if (!res.success) {
        toastBusinessError(svcBusinessCode(res), res.message ?? '');
        return false;
      }
      if (this.ddnsType.trim().length === 0) {
        const typeRes = await ServiceApiService.setDdnsType('ipv4');
        if (typeRes.success) {
          this.ddnsType = 'ipv4';
          this.ddnsTypeDraft = '';
        }
      }
      await this.refreshDdnsStatus(false, true);
      return true;
    } finally {
      this.ddnsLoading = false;
    }
  }
}
