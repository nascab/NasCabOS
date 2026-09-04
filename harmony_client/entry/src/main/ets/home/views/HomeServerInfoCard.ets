import { L10n } from '../../core/localization/L10n';
import { APIClient } from '../../core/network/APIClient';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { ServerInfo } from '../../auth/models/ServerInfo';
import { HomeViewModel } from '../HomeViewModel';
import { AppIconMap } from '../AppIconMap';
import { P2PService } from '../../p2p/P2PService';
import { P2pTransportKind } from '../../p2p/P2pProtocol';

/** 顶部服务器信息卡片：对应 Flutter AppHomeTopArea + AppServerInfoCard */
@ComponentV2
export struct HomeServerInfoCard {
  @Require @Param vm: HomeViewModel;
  @Param onOpenUserInfo: () => void = () => {
  };
  @Param onOpenWallpaper: () => void = () => {
  };
  /** 连接通道刷新计数（对应 Flutter connectChannelRevision） */
  @Local channelRevision: number = 0;

  private currentServer(): ServerInfo | undefined {
    return this.vm.currentServer;
  }

  private platformIcon(): Resource {
    return AppIconMap.getServerPlatformIcon(this.currentServer()?.serverPlatform ?? '');
  }

  private titleText(): string {
    const server = this.currentServer();
    const unknown = L10n.homeUnknown;
    const platform = server ? server.platformFriendlyName : unknown;
    const host = server ? server.displayHostName : L10n.homeServerDefault;
    return `${platform} - ${host}`;
  }

  private usernameText(): string {
    const user = CurrentUserStore.getInstance().current?.username ?? '';
    return user.length > 0 ? user : L10n.homeUnknown;
  }

  /** 连接通道显示值：对应 Flutter ApiController.connectChannelDisplayValue */
  private channelDisplayValue(): string {
    const api = APIClient.getInstance();
    if (api.isP2pMode) {
      const p2p = P2PService.getInstance();
      const isRelay = p2p.transportKind === P2pTransportKind.RELAY;
      if (isRelay && p2p.relayAddress.trim().length > 0) {
        return `P2P ${p2p.relayAddress.trim()}`;
      }
      return 'P2P';
    }
    return api.baseUrl;
  }

  private messageText(): string {
    return this.vm.serverMessage.length > 0 ? this.vm.serverMessage : L10n.homeNoMessage;
  }

  build() {
    Column() {
      Column() {
        Row() {
          Image(this.platformIcon())
            .width(48)
            .height(48)
            .objectFit(ImageFit.Contain)
            .onClick(() => {
              this.onOpenUserInfo();
            })

          Column() {
            Text(this.titleText())
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.usernameText())
              .fontSize(14)
              .fontColor(Color.White)
              .margin({ top: 4 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Row() {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(14)
                .fontColor([Color.White])
                .onClick(() => {
                  this.channelRevision++;
                })
              Text(this.channelDisplayValue())
                .fontSize(12)
                .fontColor(Color.White)
                .margin({ left: 6 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .margin({ top: 2 })
            .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 16 })
          .onClick(() => {
            this.onOpenUserInfo();
          })

          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(22)
            .fontColor([Color.White])
            .onClick(() => {
              this.onOpenWallpaper();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Divider()
          .color('#99FFFFFF')
          .margin({ top: 12, bottom: 10 })

        Row() {
          SymbolGlyph($r('sys.symbol.bell'))
            .fontSize(18)
            .fontColor([Color.White])
          Text(this.messageText())
            .fontSize(14)
            .fontColor(Color.White)
            .margin({ left: 8 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([Color.White])
        }
        .width('100%')
        .onClick(() => {
          // 消息中心模块迁移后接入路由
          this.getUIContext().getPromptAction().showToast({ message: L10n.featureComingSoon });
        })
      }
      .width('100%')
      .padding(20)
      .borderRadius(22)
      .backgroundColor('#E6252528')
    }
    .width('100%')
    .padding({ left: 10, right: 10, bottom: 10 })
  }
}

