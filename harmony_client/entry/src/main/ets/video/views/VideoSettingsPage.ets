import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { PageScaffold } from '../../common/PageScaffold';
import { VideoSourceSettingsView } from './VideoSourceSettingsView';
import { VideoOtherSettingsView } from './VideoOtherSettingsView';

/**
 * 影音设置页（对齐 Flutter AppVideoSettingsView）：
 * 顶部两个标签（来源设置/其他设置），内容区分别承载 VideoSourceSettingsView 与
 * VideoOtherSettingsView。
 */
@ComponentV2
export struct VideoSettingsPage {
  @Param popPage: () => void = (): void => {
  };

  build() {
    PageScaffold({
      title: L10n.setting,
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      content: this.SettingsContent
    })
  }

  @Builder
  SettingsContent() {
    Tabs({ barPosition: BarPosition.Start }) {
      TabContent() {
        VideoSourceSettingsView()
      }
      .tabBar(this.TabLabel(L10n.t('settings_source', '来源设置')))

      TabContent() {
        VideoOtherSettingsView()
      }
      .tabBar(this.TabLabel(L10n.t('video_other_settings_title', '其他设置')))
    }
    .barMode(BarMode.Fixed)
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().cardBg)
  }

  @Builder
  TabLabel(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.current().onSurface)
      .padding({ top: 10, bottom: 10 })
  }
}
