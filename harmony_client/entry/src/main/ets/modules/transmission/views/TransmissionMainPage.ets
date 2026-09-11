import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { BottomTabBar, BottomTabItem } from '../../../common/components/BottomTabBar';
import { TransmissionController } from '../controllers/TransmissionController';
import { showAddTorrentSheet } from '../components/AddTorrentSheet';
import { TransmissionOverviewTab } from './TransmissionOverviewTab';
import { TransmissionTorrentsTab } from './TransmissionTorrentsTab';
import { TransmissionSettingsTab } from './TransmissionSettingsTab';
import { TransmissionMainPageParam } from '../router/TransmissionRoutes';

/**
 * Transmission 主页（对齐 Flutter TransmissionView 移动端 appMode 形态）：
 * 公共 PageScaffold 顶栏（返回 + 标题 + 添加任务 + 刷新），
 * 底部 3 标签（总览/任务/设置），服务端版本过低时整页展示错误文案。
 */
@ComponentV2
export struct TransmissionMainPage {
  @Param param: TransmissionMainPageParam = new TransmissionMainPageParam();
  @Param popPage: () => void = (): void => {
  };
  /** 控制器随页面创建销毁（对齐 Flutter GetBuilder init/dispose 生命周期） */
  @Local ctrl: TransmissionController = new TransmissionController();

  aboutToAppear(): void {
    this.ctrl.onInit();
  }

  aboutToDisappear(): void {
    this.ctrl.onClose();
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  /** 底部标签（对齐 Flutter BottomNavigationBar 3 项） */
  private tabItems(): BottomTabItem[] {
    return [
      new BottomTabItem($r('sys.symbol.square_grid_2x2'),
        L10n.t('transmission_tab_overview', '总览')),
      new BottomTabItem($r('sys.symbol.download'),
        L10n.t('transmission_tab_torrents', '任务')),
      new BottomTabItem($r('sys.symbol.gearshape'),
        L10n.t('transmission_tab_settings', '设置'))
    ];
  }

  private tabIndexOf(tab: string): number {
    if (tab === 'torrents') {
      return 1;
    }
    if (tab === 'settings') {
      return 2;
    }
    return 0;
  }

  private tabForIndex(index: number): string {
    if (index === 1) {
      return 'torrents';
    }
    if (index === 2) {
      return 'settings';
    }
    return 'overview';
  }

  build() {
    PageScaffold({
      title: L10n.t('app_transmission', 'Transmission'),
      showBack: true,
      // 底部导航条安全区与标签栏同底色（对齐照片主页背景层模式）
      bottomSafeAreaBg: this.palette().surfaceBg,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.HeaderActions()
      },
      content: (): void => {
        this.Content()
      }
    })
  }

  /** 顶栏动作（对齐 Flutter AppBar actions：添加任务 + 刷新） */
  @Builder
  HeaderActions() {
    Row({ space: 10 }) {
      BorderedIconButton({
        icon: $r('sys.symbol.plus'),
        onTap: (): void => {
          showAddTorrentSheet(this.ctrl);
        }
      })
      BorderedIconButton({
        icon: $r('sys.symbol.arrow_clockwise'),
        onTap: (): void => {
          void this.ctrl.refreshAll(false);
        }
      })
    }
  }

  @Builder
  Content() {
    if (this.ctrl.errorText.length > 0) {
      // 服务端版本过低等错误：整页文案（对齐 Flutter errorText 分支）
      this.ErrorBody()
    } else {
      Column() {
        Column() {
          this.Body()
        }
        .width('100%')
        .layoutWeight(1)

        BottomTabBar({
          items: this.tabItems(),
          selectedIndex: this.tabIndexOf(this.ctrl.currentTab),
          onSelect: (index: number): void => {
            this.ctrl.currentTab = this.tabForIndex(index);
          }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.palette().pageBg)
    }
  }

  /** 主体（对齐 _TransmissionBody 按 tab 切换） */
  @Builder
  Body() {
    if (this.ctrl.currentTab === 'torrents') {
      TransmissionTorrentsTab({ ctrl: this.ctrl })
    } else if (this.ctrl.currentTab === 'settings') {
      TransmissionSettingsTab({ ctrl: this.ctrl })
    } else {
      TransmissionOverviewTab({ ctrl: this.ctrl })
    }
  }

  /** 错误页（整页居中文案） */
  @Builder
  ErrorBody() {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(44)
        .fontColor([this.palette().error])
      Text(this.ctrl.errorText)
        .fontSize(14)
        .fontColor(this.palette().subText)
        .textAlign(TextAlign.Center)
        .lineHeight(21)
        .margin({ top: 16 })
        .padding({ left: 32, right: 32 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
