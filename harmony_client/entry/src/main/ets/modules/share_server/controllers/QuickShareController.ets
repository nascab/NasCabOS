import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import pasteboard from '@ohos.pasteboard';
import { APIClient } from '../../../core/network/APIClient';
import { NetworkConfig } from '../../../core/network/NetworkConfig';
import { L10n } from '../../../core/localization/L10n';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { QuickShareItem } from '../models/ShareServerModels';
import { QuickShareApiService, QuickShareListPayload } from '../services/ShareServerApiServices';

const QUICK_SHARE_AES_KEY = '!N@S#CB1298AS3HADSF!@';

/**
 * 快速分享控制器（对齐 Flutter QuickShareConfigController；@ObservedV2 + @Trace 驱动 V2 刷新）。
 * 随页面创建/销毁。
 */
@ObservedV2
export class QuickShareController {
  @Trace items: QuickShareItem[] = [];
  /** 已展示密码的分享 id 集合（对齐 Flutter revealPwdIds） */
  @Trace revealPwdIds: Set<number> = new Set<number>();
  @Trace p2pPairCode: string = '';
  /** token → 远程分享链接（异步 AES 加密后回填；pairCode 为空时保持为空 → 引导行） */
  @Trace remoteUrlByToken: Map<string, string> = new Map();

  // ===== 列表（对齐 refreshList） =====

  async refreshList(showLoading: boolean): Promise<void> {
    try {
      if (showLoading) {
        await DialogUtil.showLoading(L10n.loading);
      }
      const res = await QuickShareApiService.list();
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      const data = res.data as QuickShareListPayload;
      this.p2pPairCode = data.pairCode;
      this.items = data.items;
      void this.rebuildRemoteUrls();
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
    } finally {
      if (showLoading) {
        await DialogUtil.dismissLoading(true);
      }
    }
  }

  /** 逐条计算远程链接（对齐 Flutter buildRemoteShareUrl 同步计算；鸿蒙侧异步加密后回填） */
  private async rebuildRemoteUrls(): Promise<void> {
    const next = new Map<string, string>();
    const items = this.items;
    for (let i = 0; i < items.length; i++) {
      const token = items[i].token;
      if (token.trim().length === 0 || next.has(token)) {
        continue;
      }
      const url = await this.buildRemoteShareUrl(token);
      next.set(token, url);
    }
    this.remoteUrlByToken = next;
  }

  isPwdRevealed(id: number): boolean {
    return this.revealPwdIds.has(id);
  }

  togglePwdReveal(id: number): void {
    if (this.revealPwdIds.has(id)) {
      this.revealPwdIds.delete(id);
      return;
    }
    this.revealPwdIds.add(id);
  }

  // ===== 分享链接 =====

  /** Web URL language 参数（对齐 quickshare/i18n.js normalizeLocale：zh_CN → zh-CN，ar_AR → ar-SA） */
  private languageParam(): string {
    let code = L10n.locale.trim();
    if (code.length === 0) {
      return 'zh-CN';
    }
    if (code === 'ar_AR') {
      code = 'ar-SA';
    }
    return code.replace(/_/g, '-');
  }

  /** 本地 HTTP 根地址（P2P 时鸿蒙端暂无 LAN 信息，退回 baseUrl，对齐差异见报告） */
  private localHttpOrigin(): string {
    return QuickShareController.normalizeBaseUrl(APIClient.getInstance().baseUrl);
  }

  static normalizeBaseUrl(url: string): string {
    return url.trim().replace(/\/+$/, '');
  }

  buildLocalShareUrl(token: string): string {
    const base = this.localHttpOrigin();
    const safeToken = encodeURIComponent(token);
    const safeLang = encodeURIComponent(this.languageParam());
    return `${base}/quickshare/index.html?qt=${safeToken}&language=${safeLang}`;
  }

  async buildRemoteShareUrl(token: string): Promise<string> {
    const pairCode = this.p2pPairCode.trim();
    if (pairCode.length === 0) {
      return '';
    }
    const enc = await QuickShareController.encryptP2pPairCode(pairCode);
    if (enc.length === 0) {
      return '';
    }
    const base = NetworkConfig.SIGNAL_API_BASE_URL;
    const safeToken = encodeURIComponent(token);
    const safeLang = encodeURIComponent(this.languageParam());
    const safePc = encodeURIComponent(enc);
    return `${base}/quickshare/index.html?qt=${safeToken}&language=${safeLang}&pc=${safePc}`;
  }

  /**
   * P2P 配对码加密（对齐 Flutter _encryptP2pPairCode）：
   * key = SHA256(quickShareAesKey)，iv = SHA256(pairCode) 前 16 字节，AES-256-CBC+PKCS7，
   * 输出 base64(iv + cipher)。
   */
  private static async encryptP2pPairCode(pairCode: string): Promise<string> {
    const code = pairCode.trim();
    if (code.length === 0) {
      return '';
    }
    try {
      const encoder = new util.TextEncoder();
      const keyBytes = await QuickShareController.sha256Bytes(encoder.encodeInto(QUICK_SHARE_AES_KEY));
      const ivBytes = (await QuickShareController.sha256Bytes(encoder.encodeInto(code))).slice(0, 16);

      const generator = cryptoFramework.createSymKeyGenerator('AES256');
      const keyBlob: cryptoFramework.DataBlob = { data: keyBytes };
      const symKey = await generator.convertKey(keyBlob);
      const cipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
      const ivSpec: cryptoFramework.IvParamsSpec = {
        algName: 'IvParamsSpec',
        iv: { data: ivBytes } as cryptoFramework.DataBlob
      };
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, ivSpec);
      const out = await cipher.doFinal({ data: encoder.encodeInto(code) } as cryptoFramework.DataBlob);

      const combined = new Uint8Array(ivBytes.length + out.data.length);
      combined.set(ivBytes, 0);
      combined.set(out.data, ivBytes.length);
      return new util.Base64Helper().encodeToStringSync(combined);
    } catch (_e) {
      return '';
    }
  }

  private static async sha256Bytes(bytes: Uint8Array): Promise<Uint8Array> {
    const md = cryptoFramework.createMd('SHA256');
    const blob: cryptoFramework.DataBlob = { data: bytes };
    await md.update(blob);
    const digest = await md.digest();
    return digest.data;
  }

  // ===== 操作（对齐 copyText/createShare/deleteShare/cleanExpired） =====

  copyText(text: string): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setPasteData(data);
      ToastUtil.show(L10n.t('quick_share_copied', '已复制'));
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
    }
  }

  async createShare(path: string, pwd: string, remark: string | undefined,
    durationValue: number | undefined, durationUnit: string | undefined,
    noLimit: boolean | undefined): Promise<boolean> {
    try {
      await DialogUtil.showLoading(L10n.loading);
      const res = await QuickShareApiService.create(path, pwd, remark, durationValue,
        durationUnit, noLimit);
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return false;
      }
      await this.refreshList(false);
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      return true;
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
      return false;
    } finally {
      await DialogUtil.dismissLoading(true);
    }
  }

  async deleteShare(id: number): Promise<void> {
    try {
      await DialogUtil.showLoading(L10n.loading);
      const res = await QuickShareApiService.delete(id);
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      await this.refreshList(false);
      ToastUtil.show(L10n.t('delete_success', '删除成功'));
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
    } finally {
      await DialogUtil.dismissLoading(true);
    }
  }

  async cleanExpired(): Promise<void> {
    try {
      await DialogUtil.showLoading(L10n.loading);
      const res = await QuickShareApiService.cleanExpired();
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      await this.refreshList(false);
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
    } finally {
      await DialogUtil.dismissLoading(true);
    }
  }
}
