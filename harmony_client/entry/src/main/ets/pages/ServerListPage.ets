import { L10n } from '../core/localization/L10n';
import { ServerInfo } from '../auth/models/ServerInfo';
import { ServerListViewModel } from './ServerListViewModel';
@ComponentV2
export struct ServerListPage {
  @Local vm: ServerListViewModel = new ServerListViewModel();
  @Param onNavigateHome: () => void = () => {};

  aboutToAppear(): void {
    this.vm.init();
  }

  aboutToDisappear(): void {
    this.vm.destroy();
  }

  build() {
    Column() {
      Text(L10n.serverListTitle)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 16, bottom: 8 })
        .width('100%')
        .padding({ left: 16 })

      if (this.vm.statusMessage.length > 0) {
        Text(this.vm.statusMessage)
          .fontSize(14)
          .fontColor('#FF6B6B')
          .padding({ left: 16, right: 16, bottom: 8 })
      }

      if (this.vm.isConnecting) {
        LoadingProgress().width(32).height(32).margin(8)
      }

      List({ space: 8 }) {
        ListItem() {
          Text(L10n.savedServers).fontSize(16).fontWeight(FontWeight.Medium).padding(16)
        }

        ForEach(this.vm.savedServers, (server: ServerInfo) => {
          ListItem() {
            this.ServerCard(server)
          }
        }, (server: ServerInfo) => server.uniqueKey)

        ListItem() {
          Text(L10n.discoveredServers).fontSize(16).fontWeight(FontWeight.Medium).padding(16)
        }

        ForEach(this.vm.discoveredServers, (server: ServerInfo) => {
          ListItem() {
            this.ServerCard(server)
          }
        }, (server: ServerInfo) => `disc-${server.uniqueKey}`)

        ListItem() {
          Button(L10n.addServer)
            .width('90%')
            .margin(16)
            .onClick(() => {
              this.vm.showAddDialog = true;
            })
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1a1a2e')
    .bindSheet(this.vm.showAddDialog, this.AddServerSheet(), {
      height: SheetSize.MEDIUM,
      onDisappear: () => { this.vm.showAddDialog = false; },
    })
    .bindSheet(this.vm.showPasswordDialog, this.PasswordSheet(), {
      height: SheetSize.MEDIUM,
      onDisappear: () => { this.vm.showPasswordDialog = false; },
    })
    .bindSheet(this.vm.showTwofaDialog, this.TwofaSheet(), {
      height: SheetSize.MEDIUM,
      onDisappear: () => { this.vm.showTwofaDialog = false; },
    })
  }

  @Builder
  ServerCard(server: ServerInfo) {
    Row() {
      Column() {
        Text(server.serverName || server.displayHostName)
          .fontSize(16)
          .fontColor(Color.White)
        Text(server.platformFriendlyName)
          .fontSize(12)
          .fontColor('#AAAAAA')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (server.hasPairCode()) {
        Text('P2P').fontSize(12).fontColor('#4ECDC4').margin({ right: 8 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#16213e')
    .borderRadius(12)
    .margin({ left: 16, right: 16 })
    .onClick(async () => {
      const ok = await this.vm.connectServer(server);
      if (ok) {
        this.onNavigateHome();
      }
    })
  }

  @Builder
  AddServerSheet() {
    Column({ space: 12 }) {
      Text(L10n.addServer).fontSize(18).fontWeight(FontWeight.Bold)
      TextInput({ placeholder: L10n.serverUrl, text: this.vm.addUrl })
        .onChange((v) => { this.vm.addUrl = v; })
      TextInput({ placeholder: L10n.pairCode, text: this.vm.addPairCode })
        .onChange((v) => { this.vm.addPairCode = v; })
      Row({ space: 12 }) {
        Button(L10n.cancel)
          .layoutWeight(1)
          .onClick(() => { this.vm.showAddDialog = false; })
        Button(L10n.login)
          .layoutWeight(1)
          .onClick(async () => {
            const ok = await this.vm.addManualServer();
            if (ok) {
              this.onNavigateHome();
            }
          })
      }
    }
    .padding(24)
  }

  @Builder
  PasswordSheet() {
    Column({ space: 12 }) {
      Text(L10n.password).fontSize(18)
      TextInput({ placeholder: L10n.password, text: this.vm.passwordInput })
        .type(InputType.Password)
        .onChange((v) => { this.vm.passwordInput = v; })
      Button(L10n.login)
        .onClick(async () => {
          const ok = await this.vm.submitPassword();
          if (ok) {
            this.onNavigateHome();
          }
        })
    }
    .padding(24)
  }

  @Builder
  TwofaSheet() {
    Column({ space: 12 }) {
      Text(L10n.twofaTitle).fontSize(18)
      TextInput({ placeholder: L10n.twofaCode, text: this.vm.twofaCode })
        .onChange((v) => { this.vm.twofaCode = v; })
      Button(L10n.login)
        .onClick(async () => {
          const ok = await this.vm.submitTwofa();
          if (ok) {
            this.onNavigateHome();
          }
        })
    }
    .padding(24)
  }
}

@Builder
export function ServerListPageBuilder(onNavigateHome: () => void) {
  ServerListPage({ onNavigateHome: onNavigateHome })
}
