import { AppRouter } from '../router/AppRouter';
import { AppEventBus } from '../common/AppEventBus';
import { DialogUtil } from '../common/DialogUtil';
import { SheetUtil } from '../common/SheetUtil';
import { ServerListPage } from '../auth/views/ServerListPage';
import { ServerListViewModel } from '../auth/views/server_list/ServerListViewModel';
import { LoginPage } from '../auth/views/login/LoginPage';
import { RecoverPasswordView } from '../auth/views/recover_password/RecoverPasswordView';
import { ServerAddPage } from '../auth/views/server_add/ServerAddPage';
import { HomePage } from './HomePage';
import { SettingsPage } from '../settings/SettingsPage';
import { LegalPage, LegalPageParam } from './LegalPage';
import { FileBrowserPage, FileBrowserParam } from '../files/views/FileBrowserPage';

@Entry
@Component
struct Index {
  @State pageStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    // 初始化全局弹窗工具（DialogUtil 依赖 UIContext）
    DialogUtil.init(this.getUIContext());
    SheetUtil.init(this.getUIContext());
    AppEventBus.onAuthSessionExpired(() => {
      this.pageStack.clear();
    });
  }

  @Builder
  pageMap(name: string, param: object) {
    if (name === AppRouter.HOME) {
      HomePageBuilder(
        () => {
          this.pageStack.clear();
        },
        (name: string, param?: object) => {
          this.pageStack.pushPathByName(name, param ?? new Object());
        }
      )
    } else if (name === AppRouter.LOGIN) {
      LoginPageBuilder(() => {
        this.pageStack.clear();
      })
    } else if (name === AppRouter.RECOVER) {
      RecoverPageBuilder(() => {
        this.pageStack.pop();
      })
    } else if (name === AppRouter.SERVER_ADD) {
      ServerAddPageBuilder(
        param instanceof ServerListViewModel ? param : new ServerListViewModel(),
        () => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.SETTINGS) {
      SettingsPageBuilder(
        () => {
          this.pageStack.pop();
        },
        (legalParam: LegalPageParam) => {
          this.pageStack.pushPathByName(AppRouter.LEGAL, legalParam);
        }
      )
    } else if (name === AppRouter.FILES) {
      FileBrowserPageBuilder(
        param instanceof FileBrowserParam ? param : new FileBrowserParam(),
        (n: string, p?: object): void => {
          this.pageStack.pushPathByName(n, p ?? new Object());
        },
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.LEGAL) {
      LegalPageBuilder(
        param instanceof LegalPageParam ? param : new LegalPageParam(),
        () => {
          this.pageStack.pop();
        }
      )
    }
  }

  build() {
    Navigation(this.pageStack) {
      ServerListPage({
        onNavigateHome: () => {
          this.pageStack.pushPathByName(AppRouter.HOME, new Object());
        },
        pageStack: this.pageStack
      })
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
  }
}

@Builder
function HomePageBuilder(onNavigateServerList: () => void, pushPage: (name: string, param?: object) => void) {
  HomePage({ onNavigateServerList: onNavigateServerList, pushPage: pushPage })
}

@Builder
export function LoginPageBuilder(onNavigateHome: () => void) {
  LoginPage({ onNavigateHome: onNavigateHome })
}

@Builder
export function RecoverPageBuilder(onBack: () => void) {
  RecoverPasswordView({ onBack: onBack })
}

@Builder
export function ServerAddPageBuilder(listVm: ServerListViewModel, onBack: () => void) {
  ServerAddPage({ listVm: listVm, onBack: onBack })
}

@Builder
function SettingsPageBuilder(onBack: () => void, pushLegal: (param: LegalPageParam) => void) {
  SettingsPage({ onBack: onBack, pushLegal: pushLegal })
}

@Builder
function LegalPageBuilder(param: LegalPageParam, onBack: () => void) {
  LegalPage({ param: param, onBack: onBack })
}

@Builder
function FileBrowserPageBuilder(param: FileBrowserParam, pushPage: (name: string, param?: object) => void,
  popPage: () => void) {
  FileBrowserPage({ param: param, pushPage: pushPage, popPage: popPage })
}
