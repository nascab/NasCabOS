import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { APIClient } from './APIClient';
import { NetworkConfig } from './NetworkConfig';

/**
 * 文件资源 URL 工具（对齐 Flutter api_controller_urls.dart）：
 * - getTinyUrl：缩略图 /api/file/tiny
 * - getRawFileUrl：原始文件 /api/file/rawFile
 * - getFaceImageUrl：人脸头像 /api/photo/face/image
 * 参数优先走 AES 加密（key=SHA256(serverId)，iv=SHA256(json) 前16位，AES-CBC+PKCS7，base64(iv+cipher)），
 * 失败时回退明文 query（与服务端行为一致）。
 */
export class ApiUrls {
  /** 人脸头像缓存时间戳（刷新后更新以避免图片缓存，对齐 Flutter faceImageTimestamp） */
  private static faceImageTimestamp: number = Date.now();

  /** 刷新人脸头像时间戳（对齐 Flutter refreshFaceImageTimestamp，列表刷新前调用） */
  static refreshFaceImageTimestamp(): void {
    ApiUrls.faceImageTimestamp = Date.now();
  }
  /** SHA-256 摘要（Hex 无关，直接返回字节） */
  private static async sha256(input: string): Promise<Uint8Array> {
    const md = cryptoFramework.createMd('SHA256');
    const encoder = new util.TextEncoder();
    const blob: cryptoFramework.DataBlob = { data: encoder.encodeInto(input) };
    await md.update(blob);
    const digest = await md.digest();
    return digest.data;
  }

  /** 加密参数：返回 aes 参数字符串（失败返回空串，由调用方回退明文） */
  static async encryptParams(params: Map<string, string>): Promise<string> {
    const serverId = APIClient.getInstance().state.serverId;
    if (serverId.length === 0) {
      return '';
    }
    try {
      const keyBytes = await ApiUrls.sha256(serverId);
      const obj: Record<string, string> = {};
      params.forEach((v: string, k: string) => {
        obj[k] = v;
      });
      const jsonStr = JSON.stringify(obj);
      // 与 Flutter 一致：IV 取参数内容哈希前16位，保证相同内容 URL 稳定，避免图片闪烁
      const hash = await ApiUrls.sha256(jsonStr);
      const ivBytes = hash.slice(0, 16);
      const generator = cryptoFramework.createSymKeyGenerator('AES256');
      const keyBlob: cryptoFramework.DataBlob = { data: keyBytes };
      const symKey = await generator.convertKey(keyBlob);
      const cipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
      const ivSpec: cryptoFramework.IvParamsSpec = {
        algName: 'IvParamsSpec',
        iv: { data: ivBytes } as cryptoFramework.DataBlob
      };
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, ivSpec);
      const encoder = new util.TextEncoder();
      const plainBlob: cryptoFramework.DataBlob = { data: encoder.encodeInto(jsonStr) };
      const out = await cipher.doFinal(plainBlob);
      // 组合 IV + 密文
      const combined = new Uint8Array(ivBytes.length + out.data.length);
      combined.set(ivBytes, 0);
      combined.set(out.data, ivBytes.length);
      const helper = new util.Base64Helper();
      return helper.encodeToStringSync(combined);
    } catch (_e) {
      return '';
    }
  }

  private static isP2p(): boolean {
    return APIClient.getInstance().state.baseUrl.trim() === NetworkConfig.P2P_BASE_URL;
  }

  /** 缩略图 URL（对齐 Flutter getTinyUrl） */
  static async getTinyUrl(filePath: string, size?: number): Promise<string> {
    const api = APIClient.getInstance();
    const base = api.state.baseUrl;
    const token = api.state.accessToken ?? '';
    const params = new Map<string, string>();
    params.set('path', filePath);
    if (token.length > 0) {
      params.set('accessToken', token);
    }
    const aes = await ApiUrls.encryptParams(params);
    if (aes.length > 0) {
      let url = `${base}/api/file/tiny?aes=${encodeURIComponent(aes)}`;
      if (ApiUrls.isP2p()) {
        url += `&path=${encodeURIComponent(filePath)}&p2pChannel=file`;
        if (token.length > 0) {
          url += `&accessToken=${encodeURIComponent(token)}`;
        }
        if (size !== undefined) {
          url += `&size=${encodeURIComponent(`${size}`)}`;
        }
      }
      return url;
    }
    let url = `${base}/api/file/tiny?path=${encodeURIComponent(filePath)}`;
    if (ApiUrls.isP2p()) {
      url += '&p2pChannel=file';
    }
    if (token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    if (size !== undefined) {
      url += `&size=${encodeURIComponent(`${size}`)}`;
    }
    return url;
  }

  /** 原始文件 URL（对齐 Flutter getRawFileUrl；与 getTinyUrl 一致始终携带 accessToken，服务器图片接口需要鉴权） */
  static async getRawFileUrl(filePath: string, withAccessToken: boolean = true): Promise<string> {
    const api = APIClient.getInstance();
    const base = api.state.baseUrl;
    const token = api.state.accessToken ?? '';
    const params = new Map<string, string>();
    params.set('path', filePath);
    if (withAccessToken && token.length > 0) {
      params.set('accessToken', token);
    }
    params.set('raw', '1');
    const aes = await ApiUrls.encryptParams(params);
    if (aes.length > 0) {
      let url = `${base}/api/file/rawFile?aes=${encodeURIComponent(aes)}`;
      if (ApiUrls.isP2p()) {
        url += `&path=${encodeURIComponent(filePath)}&p2pChannel=file&raw=1`;
        if (withAccessToken && token.length > 0) {
          url += `&accessToken=${encodeURIComponent(token)}`;
        }
      }
      return url;
    }
    let url = `${base}/api/file/rawFile?path=${encodeURIComponent(filePath)}&raw=1`;
    if (ApiUrls.isP2p()) {
      url += '&p2pChannel=file';
    }
    if (withAccessToken && token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    return url;
  }

  /**
   * 合并式 Live Photo 视频提取 URL（对齐 Flutter getMergeLvpVideoUrl）：
   * /api/file/mergeLvpVideo?path=&accessToken=（明文 query，与 Flutter 一致）
   */
  static getMergeLvpVideoUrl(filePath: string): string {
    const api = APIClient.getInstance();
    const base = api.state.baseUrl;
    const token = api.state.accessToken ?? '';
    let url = `${base}/api/file/mergeLvpVideo?path=${encodeURIComponent(filePath)}`;
    if (token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    return url;
  }

  /**
   * 人脸头像 URL（对齐 Flutter getFaceImageUrl）：
   * 参数 face_id/size/quality/t/accessToken，AES 加密失败时回退明文 query（与 getTinyUrl 策略一致）。
   */
  static async getFaceImageUrl(faceId: number, size: number = 240, quality: number = 85,
    fileHash: string = ''): Promise<string> {
    const api = APIClient.getInstance();
    const base = api.state.baseUrl;
    const token = api.state.accessToken ?? '';
    const params = new Map<string, string>();
    params.set('face_id', `${faceId}`);
    if (fileHash.trim().length > 0) {
      params.set('file_hash', fileHash.trim());
    }
    params.set('size', `${size}`);
    params.set('quality', `${quality}`);
    params.set('t', `${ApiUrls.faceImageTimestamp}`);
    if (token.length > 0) {
      params.set('accessToken', token);
    }
    const aes = await ApiUrls.encryptParams(params);
    if (aes.length > 0) {
      return `${base}/api/photo/face/image?aes=${encodeURIComponent(aes)}`;
    }
    let url = `${base}/api/photo/face/image?face_id=${encodeURIComponent(`${faceId}`)}`;
    if (fileHash.trim().length > 0) {
      url += `&file_hash=${encodeURIComponent(fileHash.trim())}`;
    }
    url += `&size=${encodeURIComponent(`${size}`)}&quality=${encodeURIComponent(`${quality}`)}`;
    url += `&t=${encodeURIComponent(`${ApiUrls.faceImageTimestamp}`)}`;
    if (token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    return url;
  }
}
