import { promptAction } from '@kit.ArkUI';
import { L10n } from '../core/localization/L10n';
import { APIClient } from '../core/network/APIClient';
import { CurrentUserStore } from '../core/user/CurrentUserStore';
import { AppEventBus } from '../common/AppEventBus';
import { HomeViewModel } from '../home/HomeViewModel';
import { AppIconMap } from '../home/AppIconMap';
@ComponentV2
export struct HomePage {
  @Local vm: HomeViewModel = new HomeViewModel();
  @Local userStore: CurrentUserStore = CurrentUserStore.getInstance();
  @Param onNavigateServerList: () => void = () => {};

  aboutToAppear(): void {
    this.vm.init();
  }

  build() {
    if (!APIClient.getInstance().isAuthenticated || !this.userStore.isLoggedIn) {
      this.SessionExpiredView();
    } else {
      this.MainHomeView();
    }
  }

  @Builder
  SessionExpiredView() {
    Column() {
      Text(L10n.serviceSessionExpired)
        .fontSize(16)
        .textAlign(TextAlign.Center)
        .margin({ bottom: 24 })
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
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.userStore.wallpaperUrl) {
        Image(this.userStore.wallpaperUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(0.6)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#2d3436')
      }

      Column() {
        this.TopArea()
        this.SearchBar()
        this.MonitorCard()
        this.AppsGrid()
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TopArea() {
    Column() {
      if (this.vm.currentServer) {
        Text(this.vm.currentServer.serverName || this.vm.currentServer.displayHostName)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        Text(this.vm.currentServer.platformFriendlyName)
          .fontSize(13)
          .fontColor('#DDDDDD')
          .margin({ top: 4 })
      }
      if (this.vm.serverMessage.length > 0) {
        Text(this.vm.serverMessage)
          .fontSize(12)
          .fontColor('#CCCCCC')
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding({ top: 48, left: 16, right: 16, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SearchBar() {
    TextInput({ placeholder: L10n.searchApps, text: this.vm.searchQuery })
      .width('92%')
      .height(40)
      .margin({ bottom: 12 })
      .backgroundColor('#33FFFFFF')
      .borderRadius(20)
      .onChange((v) => { this.vm.searchQuery = v; })
  }

  @Builder
  MonitorCard() {
    Row({ space: 12 }) {
      this.QuickAction(L10n.homeQuickUpload, $r('sys.symbol.arrow_up_circle'))
      this.QuickAction(L10n.homeDownloadCenter, $r('sys.symbol.arrow_down_circle'))
      this.QuickAction(L10n.homePhotoBackup, $r('sys.symbol.camera'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 12 })
  }

  @Builder
  QuickAction(title: string, icon: Resource) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(32)
        .fontColor([Color.White])
      Text(title)
        .fontSize(11)
        .fontColor(Color.White)
        .margin({ top: 6 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .padding(12)
    .backgroundColor('#44000000')
    .borderRadius(12)
    .onClick(() => {
      promptAction.showToast({ message: L10n.featureComingSoon });
    })
  }

  @Builder
  AppsGrid() {
    Scroll() {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.vm.filteredApps(), (appId: string) => {
          Column() {
            SymbolGlyph(AppIconMap.getSymbol(appId))
              .fontSize(36)
              .fontColor([Color.White])
            Text(this.vm.getAppDisplayName(appId))
              .fontSize(11)
              .fontColor(Color.White)
              .margin({ top: 6 })
              .maxLines(1)
          }
          .width('25%')
          .padding(10)
          .onClick(() => {
            promptAction.showToast({ message: L10n.featureComingSoon });
          })
        }, (appId: string) => appId)
      }
      .width('100%')
      .padding({ left: 8, right: 8, bottom: 24 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }
}

@Builder
export function HomePageBuilder(onNavigateServerList: () => void) {
  HomePage({ onNavigateServerList: onNavigateServerList })
}
