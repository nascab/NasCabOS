import { L10n } from '../../core/localization/L10n';
import { APIClient } from '../../core/network/APIClient';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { ServerInfo } from '../../auth/models/ServerInfo';
import { AuthService } from '../../auth/AuthService';
import { ServerStorageService } from '../../core/storage/ServerStorageService';
import { AppIconMap } from '../AppIconMap';
import { P2PService } from '../../p2p/P2PService';
import { P2pTransportKind } from '../../p2p/P2pProtocol';

/** 用户信息弹窗：对应 Flutter UserInfoDialog */
@ComponentV2
export struct HomeUserInfoDialog {
  @Param onDismiss: () => void = () => {
  };
  /** 退出登录完成后的跳转回调 */
  @Param onLoggedOut: () => void = () => {
  };
  @Local isLoggingOut: boolean = false;

  private currentUser() {
    return CurrentUserStore.getInstance().current;
  }

  /** 对齐 Flutter UserInfoDialog：serverId+用户名 优先，其次 baseUrl 匹配 */
  private resolveCurrentServer(): ServerInfo | undefined {
    const api = APIClient.getInstance();
    const currentServerId = api.state.serverId.trim();
    const currentBaseUrl = api.state.baseUrl.trim();
    const username = (this.currentUser()?.username ?? '').trim();
    const servers = ServerStorageService.getInstance().loadServers();

    let server: ServerInfo | undefined = undefined;
    if (currentServerId.length > 0) {
      if (username.length > 0) {
        server = servers.find((s: ServerInfo) =>
          s.serverId === currentServerId && (s.username ?? '').trim() === username);
      } else {
        server = servers.find((s: ServerInfo) => s.serverId === currentServerId);
      }
    }
    if (server === undefined) {
      if (username.length > 0) {
        server = servers.find((s: ServerInfo) =>
          s.serverUrl.trim() === currentBaseUrl && (s.username ?? '').trim() === username);
      } else {
        server = servers.find((s: ServerInfo) => s.serverUrl.trim() === currentBaseUrl);
      }
    }
    return server;
  }

  private serverDisplayName(server: ServerInfo | undefined): string {
    const custom = (server?.customHostname ?? '').trim();
    if (custom.length > 0) {
      return custom;
    }
    const name = (server?.serverName ?? '').trim();
    if (name.length > 0) {
      return name;
    }
    return server?.serverHostName ?? 'Unknown';
  }

  /** 对齐 Flutter _resolveServerIpv4：lanIpv4 > baseUrl host > serverHost */
  private resolveServerIpv4(server: ServerInfo | undefined): string {
    const lan = (server?.lanIpv4 ?? '').trim();
    if (lan.length > 0) {
      return lan;
    }
    const url = APIClient.getInstance().baseUrl.trim();
    const m = /^[a-zA-Z]+:\/\/([^/:?#]+)/.exec(url);
    const hostFromUrl = (m && m.length > 1 ? m[1] : '').trim();
    if (HomeUserInfoDialog.isIpv4(hostFromUrl)) {
      return hostFromUrl;
    }
    const host = (server?.serverHost ?? '').trim();
    if (HomeUserInfoDialog.isIpv4(host)) {
      return host;
    }
    return '';
  }

  private static isIpv4(host: string): boolean {
    const s = host.trim();
    if (s.length === 0) {
      return false;
    }
    if (!/^(\d{1,3}\.){3}\d{1,3}$/.test(s)) {
      return false;
    }
    const parts = s.split('.');
    for (let i = 0; i < parts.length; i++) {
      const v = Number(parts[i]);
      if (Number.isNaN(v) || v < 0 || v > 255) {
        return false;
      }
    }
    return true;
  }

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

  private async handleLogout(): Promise<void> {
    if (this.isLoggingOut) {
      return;
    }
    this.isLoggingOut = true;
    try {
      await AuthService.getInstance().logout();
      this.onLoggedOut();
    } finally {
      this.isLoggingOut = false;
    }
  }

  @Builder
  private InfoRow(label: string, value: string, icon?: Resource) {
    Row() {
      Text(label)
        .width(90)
        .fontSize(14)
        .fontColor('#99FFFFFF')
      Row() {
        if (icon) {
          Image(icon)
            .width(20)
            .height(20)
            .margin({ right: 8 })
        }
        Text(value.length > 0 ? value : L10n.homeUnknown)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Stack() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          this.onDismiss();
        })

      Column() {
        Row() {
          Text(this.avatarLetter())
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
          Column() {
            Text(this.currentUser()?.username ?? 'Unknown')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 16 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Divider()
          .color('#33FFFFFF')
          .margin({ top: 20, bottom: 20 })

        Column({ space: 16 }) {
          this.InfoRow(L10n.serverNameLabel, this.serverDisplayName(this.resolveCurrentServer()))
          this.InfoRow(L10n.serverPlatformLabel,
            this.resolveCurrentServer()?.platformFriendlyName ?? L10n.homeUnknown,
            AppIconMap.getServerPlatformIcon(this.resolveCurrentServer()?.serverPlatform ?? ''))
          this.InfoRow(L10n.serverConnectChannel, this.channelDisplayValue())
          this.InfoRow('IP', this.resolveServerIpv4(this.resolveCurrentServer()))
          this.InfoRow(L10n.serverIdLabel, APIClient.getInstance().state.serverId)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Button() {
          Row() {
            SymbolGlyph($r('sys.symbol.entrance_and_exit'))
              .fontSize(18)
              .fontColor([Color.White])
            Text(this.isLoggingOut ? L10n.loading : L10n.homeStatusLogout)
              .fontSize(15)
              .fontColor(Color.White)
              .margin({ left: 8 })
          }
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height(44)
        .borderRadius(12)
        .backgroundColor('#3D5AFE')
        .margin({ top: 32 })
        .onClick(() => {
          void this.handleLogout();
        })
      }
      .width(330)
      .padding(24)
      .borderRadius(16)
      .backgroundColor('#F0252528')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }

  private avatarLetter(): string {
    const name = this.currentUser()?.username ?? 'U';
    if (name.length === 0) {
      return 'U';
    }
    return name.substring(0, 1).toUpperCase();
  }
}
