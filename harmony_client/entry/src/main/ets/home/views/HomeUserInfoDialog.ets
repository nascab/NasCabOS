import { L10n } from '../../core/localization/L10n';
import { APIClient } from '../../core/network/APIClient';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { ServerInfo } from '../../auth/models/ServerInfo';
import { AuthService } from '../../auth/AuthService';
import { ServerStorageService } from '../../core/storage/ServerStorageService';
import { AppIconMap } from '../AppIconMap';
import { P2PService } from '../../p2p/P2PService';
import { P2pTransportKind } from '../../p2p/P2pProtocol';
import { DevConnectMode } from '../../core/network/DevConnectMode';
import { PhotoBackupController } from '../../modules/photo_backup/controllers/PhotoBackupController';
import { ConnectChannelManager } from '../../core/network/ConnectChannelManager';
import { ToastUtil } from '../../common/ToastUtil';

/** 用户信息弹窗：对应 Flutter UserInfoDialog */
@ComponentV2
export struct HomeUserInfoDialog {
  @Param onDismiss: () => void = () => {
  };
  /** 退出登录完成后的跳转回调 */
  @Param onLoggedOut: () => void = () => {
  };
  @Local isLoggingOut: boolean = false;
  /** 连接通道开发者切换浮层开关 */
  @Local showModePicker: boolean = false;
  @Local switchingMode: boolean = false;
  /** 通道切换计数：通道值/当前勾选依赖此刷新 */
  @Local channelRevision: number = 0;

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
    // 读取 revision：切换通道后触发本行刷新
    const _rev = this.channelRevision;
    const api = APIClient.getInstance();
    if (api.isP2pMode) {
      const p2p = P2PService.getInstance();
      // 对齐 Flutter connectChannelDisplayValue：devConnectMode 为 p2pRelay 时也按中继展示
      const isRelay = p2p.transportKind === P2pTransportKind.RELAY
        || ConnectChannelManager.getMode() === DevConnectMode.P2P_RELAY;
      if (isRelay && p2p.relayAddress.trim().length > 0) {
        return `P2P ${p2p.relayAddress.trim()}`;
      }
      return 'P2P';
    }
    return api.baseUrl;
  }

  /** 通道模式选项（对齐 Flutter _showDevConnectModePicker：auto/direct + 有配对码时的 p2p 直连/中继） */
  private modeOptions(): DevConnectMode[] {
    const opts: DevConnectMode[] = [DevConnectMode.AUTO, DevConnectMode.DIRECT];
    if (this.resolveCurrentServer()?.hasPairCode() ?? false) {
      opts.push(DevConnectMode.P2P_DIRECT);
      opts.push(DevConnectMode.P2P_RELAY);
    }
    return opts;
  }

  private modeLabel(m: DevConnectMode): string {
    switch (m) {
      case DevConnectMode.DIRECT:
        return L10n.t('dev_connect_mode_direct', '直连');
      case DevConnectMode.P2P:
      case DevConnectMode.P2P_DIRECT:
        return L10n.t('dev_connect_mode_p2p_direct', 'P2P直连');
      case DevConnectMode.P2P_RELAY:
        return L10n.t('dev_connect_mode_p2p_relay', 'P2P中继');
      default:
        return L10n.t('auto', '自动');
    }
  }

  private isModeActive(m: DevConnectMode): boolean {
    const current = ConnectChannelManager.getMode();
    if (current === DevConnectMode.P2P && m === DevConnectMode.P2P_DIRECT) {
      return true;
    }
    return current === m;
  }

  /** 切换连接通道（对齐 Flutter：setDevConnectMode 后刷新展示，失败 toast） */
  private async selectMode(m: DevConnectMode): Promise<void> {
    if (this.switchingMode) {
      return;
    }
    this.switchingMode = true;
    try {
      await ConnectChannelManager.setMode(m);
      this.showModePicker = false;
      this.channelRevision++;
    } catch (e) {
      const msg = e instanceof Error ? e.message : `${e}`;
      ToastUtil.show(msg.length > 0 ? msg : L10n.t('operation_failed', '操作失败'));
    } finally {
      this.switchingMode = false;
    }
  }

  private async handleLogout(): Promise<void> {
    if (this.isLoggingOut) {
      return;
    }
    this.isLoggingOut = true;
    try {
      // 登出前取消进行中的相册备份上传（对齐 Flutter user_info_dialog → cancelAllRunning）
      PhotoBackupController.getInstance().cancelAllRunning();
      await AuthService.getInstance().logout();
      this.onLoggedOut();
    } finally {
      this.isLoggingOut = false;
    }
  }

  @Builder
  private InfoRow(labelKey: string, value: string, icon?: Resource, showSwitch?: boolean) {
    Row() {
      // 绑定内解析语言key：切换语言后自动刷新（@Builder 按值传参不会随状态更新）
      Text(L10n.t(labelKey))
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
          .layoutWeight(1)
        // 开发者通道切换入口（对齐 Flutter dev_switch TextButton）
        if (showSwitch) {
          Text(this.switchingMode ? L10n.loading : L10n.t('dev_switch', '切换'))
            .fontSize(14)
            .fontColor('#6C9FFF')
            .margin({ left: 8 })
            .onClick(() => {
              if (!this.switchingMode) {
                this.showModePicker = true;
              }
            })
        }
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
          this.InfoRow('server_name', this.serverDisplayName(this.resolveCurrentServer()))
          this.InfoRow('server_platform',
            this.resolveCurrentServer()?.platformFriendlyName ?? '',
            AppIconMap.getServerPlatformIcon(this.resolveCurrentServer()?.serverPlatform ?? ''))
          this.InfoRow('server_connect_channel', this.channelDisplayValue(), undefined, true)
          this.InfoRow('IP', this.resolveServerIpv4(this.resolveCurrentServer()))
          this.InfoRow('server_id', APIClient.getInstance().state.serverId)
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

      // 开发者通道选择浮层（对齐 Flutter _showDevConnectModePicker SimpleDialog）
      if (this.showModePicker) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#80000000')
          .onClick(() => {
            // 仅关闭浮层，不关闭用户信息弹窗
            this.showModePicker = false;
          })
        Column() {
          Text(L10n.t('server_connect_channel', '连接通道'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .margin({ bottom: 8 })
          ForEach(this.modeOptions(), (m: DevConnectMode) => {
            Row() {
              Text(this.modeLabel(m))
                .fontSize(15)
                .fontColor(Color.White)
              if (this.isModeActive(m)) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(18)
                  .fontColor(['#6C9FFF'])
              }
            }
            .width('100%')
            .height(44)
            .padding({ left: 12, right: 12 })
            .borderRadius(8)
            .alignItems(VerticalAlign.Center)
            .justifyContent(FlexAlign.SpaceBetween)
            .onClick(() => {
              void this.selectMode(m);
            })
          }, (m: DevConnectMode) => `${m}`)
        }
        .width(240)
        .padding(16)
        .borderRadius(16)
        .backgroundColor('#F0252528')
      }
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
