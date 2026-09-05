import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';
import { L10n } from '../../core/localization/L10n';
import { APIClient } from '../../core/network/APIClient';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { AppearanceService } from '../AppsService';
import { WallpaperLoader } from '../WallpaperLoader';
import { ApiEnvelope, JsonCodec, WallpaperItemJson } from '../../common/JsonTypes';
import { P2PService } from '../../p2p/P2PService';
import { P2pChannelUtil } from '../../p2p/P2pProtocol';
import { HeaderMap } from '../../common/HeaderMap';

/** 壁纸缩略图：带认证的图片加载 */
@ComponentV2
struct WallpaperThumb {
  @Param url: string = '';
  @Local pixelMap: image.PixelMap | undefined = undefined;
  private loadSeq: number = 0;

  aboutToAppear(): void {
    void this.load();
  }

  private async load(): Promise<void> {
    const seq = ++this.loadSeq;
    const url = this.url;
    if (url.length === 0) {
      return;
    }
    try {
      const pm = await WallpaperLoader.loadPixelMap(url);
      if (seq === this.loadSeq) {
        this.pixelMap = pm;
      } else {
        await pm.release();
      }
    } catch (_e) {
      // 保持占位
    }
  }

  build() {
    Stack() {
      if (this.pixelMap) {
        Image(this.pixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#33FFFFFF')
      }
    }
    .width('100%')
    .height('100%')
  }
}

/** 手机端壁纸选择视图：对应 Flutter AppWallpaperPickerView */
@ComponentV2
export struct HomeWallpaperPicker {
  @Param onDismiss: () => void = () => {
  };
  /** 应用壁纸成功后的回调（用于刷新首页壁纸背景） */
  @Param onApplied: () => void = () => {
  };
  @Local wallpapers: WallpaperItemJson[] = [];
  @Local mode: string = 'fixed';
  @Local selectedName: string = '';
  @Local isLoading: boolean = true;
  @Local loadError: string = '';
  @Local isUploading: boolean = false;
  private crossCount: number = 3;

  aboutToAppear(): void {
    void this.loadWallpapers();
  }

  /** 服务器是否支持壁纸预览（对应 isServerVersionAtLeast(5)） */
  private supportsPreview(): boolean {
    const version = APIClient.getInstance().state.serverVersion ?? '';
    const m = /(\d+)/.exec(version);
    if (!m || m.length < 2) {
      return false; // unknownAsSupported: false
    }
    return Number(m[1]) >= 5;
  }

  private previewUrlFor(item: WallpaperItemJson): string {
    const raw = this.supportsPreview() ? (item.previewUrl ?? item.url ?? '') : (item.url ?? '');
    return WallpaperLoader.resolveUrl(raw);
  }

  private isCustom(item: WallpaperItemJson): boolean {
    return item.source === 'custom' || (item.url ?? '').includes('/customWallpaper/');
  }

  private async loadWallpapers(): Promise<void> {
    this.isLoading = true;
    this.loadError = '';
    const resp = await AppearanceService.getInstance().getWallpapers();
    if (!resp.success || !resp.data) {
      this.isLoading = false;
      this.loadError = resp.message ?? L10n.operationFailed;
      return;
    }
    this.wallpapers = resp.data;
    this.isLoading = false;
  }

  private async apply(): Promise<void> {
    if (this.mode === 'fixed' && this.selectedName.length === 0) {
      return;
    }
    const name = this.mode === 'fixed' ? this.selectedName : undefined;
    const resp = await AppearanceService.getInstance().setWallpaper(this.mode, name);
    if (!resp.success || !resp.data) {
      this.toast(resp.message ?? L10n.homeWallpaperSaveFailed);
      return;
    }
    CurrentUserStore.getInstance().setWallpaperFromJson(resp.data);
    this.onApplied();
    this.onDismiss();
    this.toast(L10n.homeWallpaperSaveSuccess);
  }

  private async pickAndUpload(): Promise<void> {
    if (this.isUploading) {
      return;
    }
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const opts = new photoAccessHelper.PhotoSelectOptions();
      opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opts.maxSelectNumber = 1;
      const result = await photoPicker.select(opts);
      const uris = result.photoUris;
      if (!uris || uris.length === 0) {
        return;
      }
      const uri = uris[0];
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      try {
        const stat = fileIo.statSync(file.fd);
        const buffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buffer);
        const filename = uri.substring(uri.lastIndexOf('/') + 1) || 'wallpaper';
        await this.uploadBytes(new Uint8Array(buffer), filename);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (_e) {
      this.toast(L10n.homeWallpaperUploadFailed);
    }
  }

  private async uploadBytes(bytes: Uint8Array, filename: string): Promise<void> {
    this.isUploading = true;
    try {
      const text = APIClient.getInstance().isP2pMode
        ? await this.uploadViaP2p(bytes, filename)
        : await this.uploadDirect(bytes, filename);
      const raw = JsonCodec.parseStr<ApiEnvelope>(text);
      const uploadedName = raw.success && raw.data ? `${(raw.data as Record<string, Object>)['name'] ?? ''}` : '';
      if (uploadedName.length > 0) {
        this.mode = 'fixed';
        this.selectedName = uploadedName;
      }
      await this.loadWallpapers();
      this.toast(L10n.homeWallpaperUploadSuccess);
    } finally {
      this.isUploading = false;
    }
  }

  private async uploadDirect(bytes: Uint8Array, filename: string): Promise<string> {
    const api = APIClient.getInstance();
    const url = `${api.baseUrl}/api/appearance/uploadWallpaper`;
    const header: Record<string, string> = { 'Content-Type': 'multipart/form-data' };
    const token = api.accessToken;
    if (token && token.length > 0) {
      header['Authorization'] = `Bearer ${token}`;
    }
    const req = http.createHttp();
    try {
      const response = await req.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        multiFormDataList: [{
          name: 'file',
          contentType: HomeWallpaperPicker.mimeFor(filename),
          remoteFileName: filename,
          data: bytes.buffer as ArrayBuffer
        }],
        connectTimeout: 10000,
        readTimeout: 180000,
        expectDataType: http.HttpDataType.STRING,
        usingProtocol: http.HttpProtocol.HTTP1_1,
        remoteValidation: 'skip',
      });
      return response.result as string;
    } finally {
      req.destroy();
    }
  }

  private async uploadViaP2p(bytes: Uint8Array, filename: string): Promise<string> {
    const path = '/api/appearance/uploadWallpaper';
    const boundary = `----nascab${Date.now()}`;
    const encoder = new util.TextEncoder();
    const head = encoder.encodeInto(
      `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${filename}"\r\n` +
      `Content-Type: ${HomeWallpaperPicker.mimeFor(filename)}\r\n\r\n`);
    const tail = encoder.encodeInto(`\r\n--${boundary}--\r\n`);
    const body = new Uint8Array(head.length + bytes.length + tail.length);
    body.set(head, 0);
    body.set(bytes, head.length);
    body.set(tail, head.length + bytes.length);

    const headers = new HeaderMap();
    headers.set('Content-Type', `multipart/form-data; boundary=${boundary}`);
    const token = APIClient.getInstance().accessToken;
    if (token && token.length > 0) {
      headers.set('Authorization', `Bearer ${token}`);
    }
    const channel = P2pChannelUtil.resolvePath(path);
    const response = await P2PService.getInstance().sendOnChannel(
      channel, 'POST', path, headers, body, 300000);
    if (response.status !== 200) {
      throw new Error(`wallpaper_upload_http_${response.status}`);
    }
    const decoder = new util.TextDecoder();
    return decoder.decodeToString(response.bodyBytes);
  }

  private static mimeFor(filename: string): string {
    const lower = filename.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    return 'image/jpeg';
  }

  private confirmDelete(name: string): void {
    this.getUIContext().showAlertDialog({
      title: L10n.homeWallpaperDeleteTitle,
      message: L10n.homeWallpaperDeleteConfirm(name),
      primaryButton: {
        value: L10n.cancel,
        action: () => {
        }
      },
      secondaryButton: {
        value: L10n.delete,
        action: () => {
          void this.deleteWallpaper(name);
        }
      },
      cancel: () => {
      }
    });
  }

  private async deleteWallpaper(name: string): Promise<void> {
    const resp = await AppearanceService.getInstance().deleteWallpaper(name);
    if (!resp.success || !resp.data) {
      this.toast(resp.message ?? L10n.homeWallpaperDeleteFailed);
      return;
    }
    const fallback = resp.data.fallback;
    if (fallback) {
      CurrentUserStore.getInstance().setWallpaperFromJson(fallback);
      this.onApplied();
    }
    if (this.selectedName === name) {
      this.selectedName = '';
    }
    await this.loadWallpapers();
    this.toast(L10n.homeWallpaperDeleteSuccess);
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  @Builder
  private ModeChip(labelKey: string, value: string) {
    // 绑定内解析语言key：切换语言后自动刷新（@Builder 按值传参不会随状态更新）
    Text(L10n.t(labelKey))
      .fontSize(13)
      .fontColor(this.mode === value ? Color.White : '#CCFFFFFF')
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(18)
      .backgroundColor(this.mode === value ? '#3D5AFE' : '#33FFFFFF')
      .onClick(() => {
        if (this.mode === value) {
          return;
        }
        this.mode = value;
        if (value === 'random') {
          this.selectedName = '';
        }
      })
  }

  @Builder
  private UploadCard() {
    Column() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(24)
        .fontColor(['#CCFFFFFF'])
      Text(this.isUploading ? L10n.homeWallpaperUploading : L10n.homeWallpaperUpload)
        .fontSize(12)
        .fontColor('#CCFFFFFF')
        .maxLines(1)
        .margin({ top: 6 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .border({ width: 1, color: '#1FFFFFFF' })
    .backgroundColor('#F0252528')
    .onClick(() => {
      void this.pickAndUpload();
    })
  }

  @Builder
  private WallpaperItemView(item: WallpaperItemJson) {
    Stack() {
      Column() {
        WallpaperThumb({ url: this.previewUrlFor(item) })
          .width('100%')
          .height('100%')
      }
      .borderRadius(6)
      .clip(true)

      if (this.isCustom(item) || (this.selectedName === item.name && this.mode === 'fixed')) {
        Row({ space: 4 }) {
          if (this.selectedName === item.name && this.mode === 'fixed') {
            Row() {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(13)
                .fontColor([Color.White])
            }
            .padding(3)
            .borderRadius(4)
            .backgroundColor('#3D5AFE')
          }
          if (this.isCustom(item)) {
            Row() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(14)
                .fontColor(['#FF6B6B'])
            }
            .padding(5)
            .borderRadius(6)
            .backgroundColor('#E6252528')
            .onClick(() => {
              this.confirmDelete(item.name ?? '');
            })
          }
        }
        .width('100%')
        .justifyContent(this.selectedName === item.name && this.mode === 'fixed'
          ? FlexAlign.SpaceBetween
          : FlexAlign.End)
        .padding(4)
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .borderRadius(8)
    .border({
      width: this.selectedName === item.name && this.mode === 'fixed' ? 2 : 0,
      color: '#3D5AFE'
    })
    .onClick(() => {
      if (this.mode === 'fixed') {
        this.selectedName = item.name ?? '';
      }
    })
  }

  build() {
    Column() {
      Text(L10n.homeWallpaperTitle)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .margin({ left: 16, top: 12, bottom: 12 })
        .width('100%')

      Row({ space: 12 }) {
        this.ModeChip('home_wallpaper_random', 'random')
        this.ModeChip('home_wallpaper_fixed', 'fixed')
      }
      .width('100%')
      .padding({ left: 16, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(Color.White)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.loadError.length > 0) {
        Column() {
          Text(this.loadError)
            .fontSize(14)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .padding(24)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.wallpapers, (item: WallpaperItemJson) => {
            GridItem() {
              this.WallpaperItemView(item)
            }
            .aspectRatio(4 / 3)
          }, (item: WallpaperItemJson) => `${item.name ?? ''}_${item.url ?? ''}`)
          GridItem() {
            this.UploadCard()
          }
          .aspectRatio(4 / 3)
        }
        .columnsTemplate(this.columnsTemplate())
        .columnsGap(10)
        .rowsGap(10)
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
        .scrollBar(BarState.Off)
        .onAreaChange((_old: Area, newVal: Area) => {
          const width = newVal.width as number;
          const count = Math.floor(width / 110);
          this.crossCount = Math.min(4, Math.max(2, count));
        })
      }

      Row({ space: 12 }) {
        Button(L10n.homeWallpaperCancel)
          .layoutWeight(1)
          .height(42)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor('#33FFFFFF')
          .borderRadius(12)
          .onClick(() => {
            this.onDismiss();
          })
        Button(L10n.homeWallpaperApply)
          .layoutWeight(1)
          .height(42)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor('#3D5AFE')
          .borderRadius(12)
          .opacity(this.mode === 'fixed' && this.selectedName.length === 0 ? 0.4 : 1)
          .onClick(() => {
            void this.apply();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1A1A2E')
    .alignItems(HorizontalAlign.Start)
  }

  private columnsTemplate(): string {
    const parts: string[] = [];
    for (let i = 0; i < this.crossCount; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }
}
