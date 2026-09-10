import { L10n } from '../../../core/localization/L10n';
import { WindowStore } from '../../../common/WindowStore';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { APIClient } from '../../../core/network/APIClient';
import { ServiceApiService, NASCAB_WEBSITE_BASE_URL } from '../services/ServiceApiService';
import { svcRecord } from '../models/ServiceModels';
import { ServiceMainController } from './ServiceMainController';

/**
 * NasCab 账号控制器（对齐 Flutter NasCabAccountController）。
 * 移动端 login 分支固定走 App 不支持提示（对齐 Flutter DeviceUtils.isMobile 分支，
 * PC/WEB 的 OAuth 弹窗与回调页流程不在迁移范围）。
 * 全局单例，登录态变化后联动刷新 ServiceMainController 远程访问状态。
 */
@ObservedV2
export class NasCabAccountController {
  private static instance: NasCabAccountController | undefined = undefined;

  static getInstance(): NasCabAccountController {
    if (!NasCabAccountController.instance) {
      NasCabAccountController.instance = new NasCabAccountController();
    }
    return NasCabAccountController.instance;
  }

  /** 用户信息（undefined/空对象 = 未登录，对齐 Flutter Rxn<Map>） */
  @Trace user: Record<string, Object> | undefined = undefined;
  @Trace isLoading: boolean = false;
  @Trace errorText: string = '';

  get isLoggedIn(): boolean {
    return this.user !== undefined && Object.keys(this.user).length > 0;
  }

  /** 查询当前用户（对齐 Flutter refreshUser） */
  async refreshUser(): Promise<void> {
    this.isLoading = true;
    this.errorText = '';
    try {
      const res = await ServiceApiService.query();
      if (!res.success) {
        const msg = (res.message ?? '').trim();
        this.errorText = msg.length > 0 ? msg : L10n.t('network_failure', '网络请求失败，请检查服务器连接');
        this.user = undefined;
        return;
      }
      const data = svcRecord(res.data);
      if (Object.keys(data).length === 0) {
        this.user = undefined;
        return;
      }
      this.user = data;
    } catch (_e) {
      this.errorText = L10n.t('network_failure', '网络请求失败，请检查服务器连接');
      this.user = undefined;
    } finally {
      this.isLoading = false;
    }
  }

  /** 强制刷新用户与会员信息（对齐 Flutter refreshAccount） */
  async refreshAccount(): Promise<void> {
    this.isLoading = true;
    this.errorText = '';
    try {
      const res = await ServiceApiService.refresh();
      if (res.code === 401) {
        this.errorText = L10n.t('service_nascab_session_expired', '您的账号登录状态已过期，请重新登陆');
        this.user = undefined;
        return;
      }
      if (!res.success) {
        const msg = (res.message ?? '').trim();
        this.errorText = msg.length > 0 ? msg : L10n.t('network_failure', '网络请求失败，请检查服务器连接');
        return;
      }
      const data = svcRecord(res.data);
      if (Object.keys(data).length === 0) {
        this.user = undefined;
        return;
      }
      this.user = data;
      await ServiceMainController.getInstance().refreshRemoteAccess();
    } catch (_e) {
      this.errorText = L10n.t('network_failure', '网络请求失败，请检查服务器连接');
    } finally {
      this.isLoading = false;
    }
  }

  /** 退出登录（对齐 Flutter logout，含 P2P 连接确认） */
  async logout(): Promise<void> {
    if (await this.p2pDisconnectConfirm()) {
      return;
    }
    const confirmed = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('service_nascab_logout_confirm', '确定退出当前账号吗？'),
      undefined,
      L10n.t('ok', '确定'),
      L10n.t('cancel', '取消'));
    if (confirmed !== true) {
      return;
    }
    await DialogUtil.showLoading(L10n.t('service_nascab_logging_out', '正在退出...'));
    try {
      const res = await ServiceApiService.logout();
      if (!res.success) {
        const msg = (res.message ?? '').trim();
        ToastUtil.show(msg.length > 0 ? msg : L10n.t('operation_failed', '操作失败'));
        return;
      }
      this.user = undefined;
      await ServiceMainController.getInstance().refreshRemoteAccess();
      ToastUtil.show(L10n.t('service_nascab_logged_out', '已退出登录'));
    } catch (_e) {
      ToastUtil.show(L10n.t('network_failure', '网络请求失败，请检查服务器连接'));
    } finally {
      await DialogUtil.dismissLoading(true);
    }
  }

  /** 登录（移动端 App 不支持 OAuth 流程，对齐 Flutter DeviceUtils.isMobile 分支） */
  async login(): Promise<void> {
    ToastUtil.show(L10n.t('service_nascab_app_not_supported', 'App端暂不支持登录，请使用PC端或网页端登录'));
  }

  /** 切换账号（对齐 Flutter switchAccount，含 P2P 连接确认） */
  async switchAccount(): Promise<void> {
    if (await this.p2pDisconnectConfirm()) {
      return;
    }
    await this.login();
  }

  /** P2P 连接中断确认；返回 true 表示用户已取消操作 */
  private async p2pDisconnectConfirm(): Promise<boolean> {
    if (!APIClient.getInstance().isP2pMode) {
      return false;
    }
    const confirmed = await DialogUtil.showConfirmDialog(
      L10n.t('tip', '提示'),
      L10n.t('service_nascab_p2p_logout_switch_confirm',
        '您当前处于P2P连接中，登出或切换账号会导致连接立刻断开，将无法进行后续操作，是否确认？'),
      undefined,
      L10n.t('ok', '确定'),
      L10n.t('cancel', '取消'));
    return confirmed !== true;
  }

  // ===== 官网页面跳转（均带 tempCode + language） =====

  /** 打开购买会员页面（对齐 Flutter openPurchaseUrl） */
  async openPurchaseUrl(): Promise<boolean> {
    return this.openUrlWithTempCode('order');
  }

  /** 个人中心 */
  async openUserCenterUrl(): Promise<void> {
    await this.openUrlWithTempCode('userCenter');
  }

  /** 我的设备 */
  async openMyDevicesUrl(): Promise<void> {
    await this.openUrlWithTempCode('devices');
  }

  /** 推广页 */
  async openPromotionUrl(): Promise<void> {
    await this.openUrlWithTempCode('promotion');
  }

  /** 版本区别（无需 code） */
  async openVipDiffUrl(): Promise<void> {
    try {
      const url = `${NASCAB_WEBSITE_BASE_URL}/others/vipDiff.html?language=${L10n.locale}`;
      this.openExternal(url);
    } catch (_e) {
      ToastUtil.show(L10n.t('network_failure', '网络请求失败，请检查服务器连接'));
    }
  }

  private async openUrlWithTempCode(path: string): Promise<boolean> {
    if (!this.isLoggedIn) {
      ToastUtil.show(L10n.t('service_nascab_not_logged_in', '未登录'));
      return false;
    }
    try {
      const res = await ServiceApiService.getTempCode();
      if (!res.success) {
        const msg = (res.message ?? '').trim();
        ToastUtil.show(msg.length > 0 ? msg : L10n.t('operation_failed', '操作失败'));
        return false;
      }
      const data = svcRecord(res.data);
      const code = `${data['code'] ?? ''}`.trim();
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
}
