import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { APIClient } from '../core/network/APIClient';
import { NetworkConfig } from '../core/network/NetworkConfig';
import { P2PService } from '../p2p/P2PService';
import { P2pChannelUtil } from '../p2p/P2pProtocol';
import { HeaderMap } from '../common/HeaderMap';

/**
 * 壁纸图片加载器：对应 Flutter SessionWallpaperBackground + CustomExtendedImage。
 * 壁纸接口仅校验 Authorization Bearer；直连模式直接 http 拉取，
 * P2P 模式通过 WebRTC 数据通道拉取字节后解码为 PixelMap。
 */
export class WallpaperLoader {
  /** 相对地址拼接 baseUrl（对应 Flutter _resolveWithBaseUrl） */
  static resolveUrl(raw: string): string {
    const url = raw.trim();
    if (url.length === 0) {
      return '';
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    const base = APIClient.getInstance().baseUrl.trim();
    if (base.length === 0) {
      return url;
    }
    if (base.endsWith('/') && url.startsWith('/')) {
      return `${base.substring(0, base.length - 1)}${url}`;
    }
    if (!base.endsWith('/') && !url.startsWith('/')) {
      return `${base}/${url}`;
    }
    return `${base}${url}`;
  }

  /** 加载壁纸字节（自动选择直连/P2P 通道），带重试（对应 Flutter _loadWithRetry） */
  static async loadBytes(resolvedUrl: string, maxAttempts: number = 3): Promise<Uint8Array> {
    let lastError: Error = new Error('wallpaper_load_failed');
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        await WallpaperLoader.sleep(250 * Math.pow(2, attempt - 1));
      }
      try {
        const bytes = APIClient.getInstance().isP2pMode
          ? await WallpaperLoader.loadBytesViaP2p(resolvedUrl)
          : await WallpaperLoader.loadBytesDirect(resolvedUrl);
        if (bytes.length > 0) {
          return bytes;
        }
      } catch (e) {
        lastError = e instanceof Error ? e : new Error(`${e}`);
      }
    }
    throw lastError;
  }

  /** 解码为 PixelMap（调用方负责 release） */
  static async loadPixelMap(resolvedUrl: string): Promise<image.PixelMap> {
    const bytes = await WallpaperLoader.loadBytes(resolvedUrl);
    const source = image.createImageSource(bytes.buffer as ArrayBuffer);
    const pixelMap = await source.createPixelMap();
    await source.release();
    return pixelMap;
  }

  private static async loadBytesDirect(resolvedUrl: string): Promise<Uint8Array> {
    const token = APIClient.getInstance().accessToken;
    const header: Record<string, string> = {};
    if (token && token.length > 0) {
      header['Authorization'] = `Bearer ${token}`;
    }
    const req = http.createHttp();
    try {
      const response = await req.request(resolvedUrl, {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 30000,
        usingProtocol: http.HttpProtocol.HTTP1_1,
        remoteValidation: 'skip',
      });
      if (response.responseCode !== 200) {
        throw new Error(`wallpaper_http_${response.responseCode}`);
      }
      return new Uint8Array(response.result as ArrayBuffer);
    } finally {
      req.destroy();
    }
  }

  private static async loadBytesViaP2p(resolvedUrl: string): Promise<Uint8Array> {
    const base = NetworkConfig.P2P_BASE_URL;
    let path = resolvedUrl;
    if (resolvedUrl.startsWith(base)) {
      path = resolvedUrl.substring(base.length);
    }
    if (!path.startsWith('/')) {
      path = `/${path}`;
    }
    const headers = new HeaderMap();
    const token = APIClient.getInstance().accessToken;
    if (token && token.length > 0) {
      headers.set('Authorization', `Bearer ${token}`);
    }
    const channel = P2pChannelUtil.resolvePath(path);
    const response = await P2PService.getInstance().sendOnChannel(
      channel,
      'GET',
      path,
      headers,
      new Uint8Array(0),
      60000
    );
    if (response.status !== 200) {
      throw new Error(`wallpaper_http_${response.status}`);
    }
    return response.bodyBytes;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => setTimeout(resolve, ms));
  }
}
