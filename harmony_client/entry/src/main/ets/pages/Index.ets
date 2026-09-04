import { AppRouter } from '../router/AppRouter';
import { AppEventBus } from '../common/AppEventBus';
import { ServerListPage } from '../auth/views/ServerListPage';
import { ServerListViewModel } from '../auth/views/server_list/ServerListViewModel';
import { LoginPage } from '../auth/views/login/LoginPage';
import { RecoverPasswordView } from '../auth/views/recover_password/RecoverPasswordView';
import { ServerAddPage } from '../auth/views/server_add/ServerAddPage';
import { HomePage } from './HomePage';

@Entry
@Component
struct Index {
  @State pageStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    AppEventBus.onAuthSessionExpired(() => {
      this.pageStack.clear();
    });
  }

  @Builder
  pageMap(name: string, param: object) {
    if (name === AppRouter.HOME) {
      HomePageBuilder(() => {
        this.pageStack.clear();
      })
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
function HomePageBuilder(onNavigateServerList: () => void) {
  HomePage({ onNavigateServerList: onNavigateServerList })
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
