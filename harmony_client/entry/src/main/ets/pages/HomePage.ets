import { image } from '@kit.ImageKit';
import { L10n } from '../core/localization/L10n';
import { APIClient } from '../core/network/APIClient';
import { CurrentUserStore } from '../core/user/CurrentUserStore';
import { AppEventBus } from '../common/AppEventBus';
import { HomeViewModel } from '../home/HomeViewModel';
import { WallpaperLoader } from '../home/WallpaperLoader';
import { HomeServerInfoCard } from '../home/views/HomeServerInfoCard';
import { HomeMonitorCard } from '../home/views/HomeMonitorCard';
import { HomeAppsGrid } from '../home/views/HomeAppsGrid';
import { HomeUserInfoDialog } from '../home/views/HomeUserInfoDialog';
import { HomeWallpaperPicker } from '../home/views/HomeWallpaperPicker';
import { AppRouter } from '../router/AppRouter';
import { LanguageService } from '../core/localization/LanguageService';

/** 首页：对应 Flutter AppHomePage */
@ComponentV2
export struct HomePage {
  @Local vm: HomeViewModel = new HomeViewModel();
  @Local userStore: CurrentUserStore = CurrentUserStore.getInstance();
  @Local wallpaperPixelMap: image.PixelMap | undefined = undefined;
  @Local showUserInfo: boolean = false;
  @Local showWallpaperPicker: boolean = false;
  @Param onNavigateServerList: () => void = () => {
  };
  @Param pushPage: (name: string, param?: object) => void = (_name: string, _param?: object) => {
  };
  private lastWallpaperUrl: string = '';
  @Local localeBump: number = 0;
  private localeListener: (data: string) => void = (_data: string) => {
    this.vm.notifyLocaleChanged();
    this.localeBump++;
  };

  aboutToAppear(): void {
    this.vm.init();
    void this.refreshWallpaper();
    AppEventBus.on(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
  }

  aboutToDisappear(): void {
    AppEventBus.off(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    void this.wallpaperPixelMap?.release();
    this.wallpaperPixelMap = undefined;
  }

  /** 加载会话壁纸（对应 Flutter SessionWallpaperBackground） */
  private async refreshWallpaper(): Promise<void> {
    const url = WallpaperLoader.resolveUrl(this.userStore.wallpaperUrl ?? '');
    if (url.length === 0) {
      this.lastWallpaperUrl = '';
      this.wallpaperPixelMap = undefined;
      return;
    }
    if (url === this.lastWallpaperUrl && this.wallpaperPixelMap) {
      return;
    }
    this.lastWallpaperUrl = url;
    try {
      const pm = await WallpaperLoader.loadPixelMap(url);
      const old = this.wallpaperPixelMap;
      this.wallpaperPixelMap = pm;
      void old?.release();
    } catch (_e) {
      // 加载失败保持占位背景
    }
  }

  private openApp(app: string): void {
    if (this.vm.openApp(app)) {
      if (app === 'setting') {
        this.pushPage(AppRouter.SETTINGS);
      } else if (app === 'folder') {
        this.pushPage(AppRouter.FILES);
      }
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: L10n.featureComingSoon });
  }

  build() {
    // navDestination builder 分支的组件必须以 NavDestination 为根，否则内容无法挂载（空白页）
    NavDestination() {
      if (!APIClient.getInstance().isAuthenticated || !this.userStore.isLoggedIn) {
        this.SessionExpiredView();
      } else {
        this.MainHomeView();
      }
    }
    .hideTitleBar(true)
    .mode(NavDestinationMode.STANDARD)
    // 依赖 localeBump：切换语言后触发首页整体刷新
    .opacity(this.localeBump >= 0 ? 1 : 1)
  }

  @Builder
  SessionExpiredView() {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(48)
        .fontColor(['#3D5AFE'])
      Text(L10n.serviceSessionExpired)
        .fontSize(16)
        .textAlign(TextAlign.Center)
        .margin({ top: 16, bottom: 24 })
      Button(L10n.ok)
        .onClick(() => {
          CurrentUserStore.getInstance().clear();
          APIClient.getInstance().clearAuthInfo();
          this.onNavigateServerList();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
    .backgroundColor('#1a1a2e')
  }

  @Builder
  MainHomeView() {
    Stack() {
      // 壁纸背景（上下延伸到系统安全区外，对齐 Flutter 首页沉浸效果）
      if (this.wallpaperPixelMap) {
        Image(this.wallpaperPixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#2d3436')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }

      Column() {
        HomeServerInfoCard({
          vm: this.vm,
          onOpenUserInfo: () => {
            this.showUserInfo = true;
          },
          onOpenWallpaper: () => {
            this.showWallpaperPicker = true;
          }
        })

        HomeMonitorCard({
          vm: this.vm,
          onTapAction: (_action: string) => {
            // 上传/下载/相册备份模块迁移后接入路由
            this.getUIContext().getPromptAction().showToast({ message: L10n.featureComingSoon });
          }
        })

        HomeAppsGrid({
          vm: this.vm,
          onTapApp: (app: string) => {
            this.openApp(app);
          }
        })
      }
      .width('100%')
      .height('100%')
      .padding({ top: 8, bottom: 24 })

      if (this.showUserInfo) {
        HomeUserInfoDialog({
          onDismiss: () => {
            this.showUserInfo = false;
          },
          onLoggedOut: () => {
            this.showUserInfo = false;
            AppEventBus.emitAuthSessionExpired();
            this.onNavigateServerList();
          }
        })
      }

      if (this.showWallpaperPicker) {
        HomeWallpaperPicker({
          onDismiss: () => {
            this.showWallpaperPicker = false;
          },
          onApplied: () => {
            void this.refreshWallpaper();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
  }
}
