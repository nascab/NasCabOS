import { webview } from '@kit.ArkWeb';
import { PageScaffold } from '../common/PageScaffold';
import { AppTheme } from '../core/theme/AppTheme';

export class LegalPageParam {
  title: string = '';
  url: string = '';
}

@ComponentV2
export struct LegalPage {
  @Param param: LegalPageParam = new LegalPageParam();
  @Param onBack: () => void = () => {
  };
  private controller: webview.WebviewController = new webview.WebviewController();

  build() {
    // PageScaffold 根节点即 NavDestination，直接作为 navDestination 分支内容
    PageScaffold({
      title: this.param.title,
      showBack: true,
      onBack: () => {
        this.onBack();
      },
      // Web 内部历史回退优先
      customBack: (): boolean => {
        if (this.controller.accessBackward()) {
          this.controller.backward();
          return true;
        }
        return false;
      },
      content: () => {
        this.WebContent()
      }
    })
  }

  @Builder
  WebContent() {
    Web({ src: this.param.url, controller: this.controller })
      .width('100%')
      .height('100%')
      .javaScriptAccess(true)
      .darkMode(AppTheme.isDark() ? WebDarkMode.On : WebDarkMode.Off)
      .backgroundColor(AppTheme.current().pageBg)
  }
}
