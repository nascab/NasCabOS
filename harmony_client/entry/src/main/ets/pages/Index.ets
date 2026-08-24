import { AppRouter } from '../router/AppRouter';
import { AppEventBus } from '../common/AppEventBus';
import { ServerListPage } from './ServerListPage';
import { HomePageBuilder } from './HomePage';

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
  pageMap(name: string) {
    if (name === AppRouter.HOME) {
      HomePageBuilder(() => {
        this.pageStack.clear();
      })
    }
  }

  build() {
    Navigation(this.pageStack) {
      ServerListPage({ onNavigateHome: () => {
        this.pageStack.pushPathByName(AppRouter.HOME, null);
      }})
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
  }
}
