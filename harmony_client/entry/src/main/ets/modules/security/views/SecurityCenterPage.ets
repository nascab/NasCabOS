import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { BottomTabBar, BottomTabItem } from '../../../common/components/BottomTabBar';
import { SecurityCenterController } from '../controllers/SecurityCenterController';
import { SecurityCenterPageParam, SecurityPageKeys } from '../router/SecurityRoutes';
import { IpBlacklistPanel } from './IpBlacklistPanel';
import { DeviceManagePanel } from './DeviceManagePanel';
import { BestPracticesPanel } from './BestPracticesPanel';
import { SecuritySettingsPanel } from './SecuritySettingsPanel';

/**
 * 安全中心主页（对齐 Flutter AppSecurityCenterPage 移动端形态）：
 * - 管理员：标题栏 + 面板区 + 底部 4 标签（最佳实践/安全设置/IP黑名单/设备管理，
 *   顺序对齐桌面端侧栏菜单，覆盖全部四个面板）；IP黑名单/设备管理标签在标题栏提供刷新与清空动作。
 * - 非管理员：直达设备管理面板，仅刷新动作（无底部标签，对齐 Flutter 权限分支）。
 * 控制器随页面创建销毁（对齐 Flutter SecurityCenterScope 生命周期）。
 */
@ComponentV2
export struct SecurityCenterPage {
  @Param param: SecurityCenterPageParam = new SecurityCenterPageParam();
  @Param popPage: () => void = (): void => {
  };
  ctrl: SecurityCenterController = new SecurityCenterController();

  aboutToAppear(): void {
    this.ctrl.onInit();
  }

  aboutToDisappear(): void {
    this.ctrl.onClose();
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  /** 面板顺序（对齐桌面端 _LeftMenu items 顺序；Flutter 控制器默认页为最佳实践） */
  private pageKeys(): string[] {
    return [
      SecurityPageKeys.BEST_PRACTICES,
      SecurityPageKeys.SETTINGS,
      SecurityPageKeys.IP_BLACKLIST,
      SecurityPageKeys.DEVICES
    ];
  }

  private currentIndex(): number {
    const idx = this.pageKeys().indexOf(this.ctrl.currentPageKey);
    return idx >= 0 ? idx : 0;
  }

  private tabItems(): BottomTabItem[] {
    return [
      new BottomTabItem($r('sys.symbol.checkmark_shield'),
        L10n.t('security.menu_best_practices', '最佳实践')),
      new BottomTabItem($r('sys.symbol.lock_shield'),
        L10n.t('security.menu_settings', '安全设置')),
      new BottomTabItem($r('sys.symbol.nosign'),
        L10n.t('security.menu_ip_blacklist', 'IP黑名单')),
      new BottomTabItem($r('sys.symbol.display'),
        L10n.t('security.menu_devices', '设备管理'))
    ];
  }

  build() {
    PageScaffold({
      title: L10n.t('app_security', '安全中心'),
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

  /** 标题栏动作（对齐 Flutter mobile actions：IP黑名单=刷新+清空，设备管理=刷新） */
  @Builder
  HeaderActions() {
    if (this.ctrl.isAdmin && this.ctrl.currentPageKey === SecurityPageKeys.IP_BLACKLIST) {
      Row({ space: 10 }) {
        BorderedIconButton({
          icon: $r('sys.symbol.arrow_clockwise'),
          onTap: (): void => {
            void this.ctrl.loadBlacklist(true);
          }
        })
        BorderedIconButton({
          icon: $r('sys.symbol.trash'),
          onTap: (): void => {
            void this.ctrl.clearBlacklist();
          }
        })
      }
    }
    if (this.ctrl.currentPageKey === SecurityPageKeys.DEVICES) {
      BorderedIconButton({
        icon: $r('sys.symbol.arrow_clockwise'),
        onTap: (): void => {
          void this.ctrl.loadDevices(true);
        }
      })
    }
  }

  @Builder
  Content() {
    if (!this.ctrl.isAdmin) {
      // 非管理员：仅设备管理（对齐 Flutter !isAdmin 分支）
      DeviceManagePanel({ ctrl: this.ctrl })
    } else {
      Column() {
        Column() {
          this.PanelBody()
        }
        .width('100%')
        .layoutWeight(1)

        BottomTabBar({
          items: this.tabItems(),
          selectedIndex: this.currentIndex(),
          onSelect: (index: number): void => {
            const keys = this.pageKeys();
            if (index < 0 || index >= keys.length) {
              return;
            }
            this.ctrl.selectPage(keys[index]);
          }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.palette().pageBg)
    }
  }

  /** 面板主体（对齐 _RightPanel 的 key 分发） */
  @Builder
  PanelBody() {
    if (this.ctrl.currentPageKey === SecurityPageKeys.BEST_PRACTICES) {
      BestPracticesPanel({ ctrl: this.ctrl })
    } else if (this.ctrl.currentPageKey === SecurityPageKeys.SETTINGS) {
      SecuritySettingsPanel({ ctrl: this.ctrl })
    } else if (this.ctrl.currentPageKey === SecurityPageKeys.IP_BLACKLIST) {
      IpBlacklistPanel({ ctrl: this.ctrl })
    } else if (this.ctrl.currentPageKey === SecurityPageKeys.DEVICES) {
      DeviceManagePanel({ ctrl: this.ctrl })
    }
  }
}
