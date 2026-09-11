import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { AppEventBus } from '../../../common/AppEventBus';
import { PageScaffold } from '../../../common/PageScaffold';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { BottomTabBar, BottomTabItem } from '../../../common/components/BottomTabBar';
import { NavUtil } from '../../../common/NavUtil';
import { L10n } from '../../../core/localization/L10n';
import { ShareServerController } from '../controllers/ShareServerController';
import {
  SharePortsPageParam, ShareServerMainPageParam, ShareServerPageKeys, ShareServerRoutes
} from '../router/ShareServerRoutes';
import { QuickShareView } from './QuickShareView';
import { ShareTypePanel } from './ShareTypePanel';
import { UserShareFoldersPanel } from './UserShareFoldersPanel';

/**
 * 分享管理主页（对齐 Flutter FileShareServerView 移动端 _FileShareMobileScaffold）：
 * - 管理员：标题栏（右侧端口设置入口）+ 面板区（保活切换，对齐 IndexedStack）+ 底部 5 标签
 *   （快速分享/WebDAV/FTP/SFTP/用户共享）。
 * - 非管理员：仅快速分享面板，无底部标签。
 * - Flutter 挂载插件就绪横幅（MountPluginNotReadyBanner）未迁移，鸿蒙端省略。
 */
@ComponentV2
export struct ShareServerMainPage {
  @Param param: ShareServerMainPageParam = new ShareServerMainPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: ShareServerController = ShareServerController.getInstance();
  /** 主题变化刷新计数（驱动 content builder 重渲染换色） */
  @Local themeTick: number = 0;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
  };

  aboutToAppear(): void {
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 初始页 key（对齐 Flutter initialPageKey/arguments['pageKey']；普通用户强制快速分享）
    const rawKey = this.param.pageKey.trim();
    let desired = rawKey;
    if (!this.ctrl.isAdmin && rawKey !== ShareServerPageKeys.QUICK) {
      desired = ShareServerPageKeys.QUICK;
    }
    this.ctrl.onInit(desired);
    // 端口设置 key 在移动端转独立页打开（对齐 Flutter openPortsSettingsOnInit）
    if (rawKey === ShareServerPageKeys.PORTS) {
      setTimeout((): void => {
        NavUtil.push(ShareServerRoutes.PAGE_PORTS, new SharePortsPageParam());
      }, 120);
    }
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.ctrl.onClose();
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private isAdmin(): boolean {
    return this.ctrl.isAdmin;
  }

  private pageKeys(): string[] {
    return [
      ShareServerPageKeys.QUICK,
      ShareServerPageKeys.WEBDAV,
      ShareServerPageKeys.FTP,
      ShareServerPageKeys.SFTP,
      ShareServerPageKeys.USER_FOLDERS
    ];
  }

  private currentIndex(): number {
    const idx = this.pageKeys().indexOf(this.ctrl.currentPageKey);
    return idx >= 0 ? idx : 0;
  }

  /** 标题（对齐 _titleForKey） */
  private titleFor(key: string): string {
    if (key === ShareServerPageKeys.FTP) {
      return L10n.t('file_share_server_ftp', 'FTP');
    }
    if (key === ShareServerPageKeys.SFTP) {
      return L10n.t('file_share_server_sftp', 'SFTP');
    }
    if (key === ShareServerPageKeys.USER_FOLDERS) {
      return L10n.t('user_share_folders_title', '用户共享');
    }
    if (key === ShareServerPageKeys.WEBDAV) {
      return L10n.t('file_share_server_webdav', 'WebDAV');
    }
    return L10n.t('quick_share_title', '快速分享');
  }

  private tabItems(): BottomTabItem[] {
    return [
      new BottomTabItem($r('sys.symbol.qrcode'), L10n.t('quick_share_title', '快速分享')),
      new BottomTabItem($r('sys.symbol.cloud'), L10n.t('file_share_server_webdav', 'WebDAV')),
      new BottomTabItem($r('sys.symbol.cloud'), L10n.t('file_share_server_ftp', 'FTP')),
      new BottomTabItem($r('sys.symbol.checkmark_icloud_fill'), L10n.t('file_share_server_sftp', 'SFTP')),
      new BottomTabItem($r('sys.symbol.folder'), L10n.t('user_share_folders_title', '用户共享'))
    ];
  }

  private openPortsSettings(): void {
    NavUtil.push(ShareServerRoutes.PAGE_PORTS, new SharePortsPageParam());
  }

  build() {
    PageScaffold({
      title: this.titleFor(this.ctrl.currentPageKey),
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

  /** 标题栏动作：端口设置（管理员，对齐 Flutter AppBar settings 图标） */
  @Builder
  HeaderActions() {
    if (this.isAdmin()) {
      BorderedIconButton({
        icon: $r('sys.symbol.gearshape'),
        onTap: (): void => {
          this.openPortsSettings();
        }
      })
    }
  }

  @Builder
  Content() {
    Column() {
      // 面板区（Stack 保活 + 可见性切换，对齐 Flutter IndexedStack）
      Stack() {
        QuickShareView({
          initialCreatePath: this.param.quickShareCreatePath,
          themeTick: this.themeTick
        })
          .width('100%')
          .height('100%')
          .visibility(this.ctrl.currentPageKey === ShareServerPageKeys.QUICK
            ? Visibility.Visible : Visibility.None)

        if (this.isAdmin()) {
          ShareTypePanel({
            ctrl: this.ctrl,
            serverType: 'WebDav',
            themeTick: this.themeTick
          })
            .width('100%')
            .height('100%')
            .visibility(this.ctrl.currentPageKey === ShareServerPageKeys.WEBDAV
              ? Visibility.Visible : Visibility.None)

          ShareTypePanel({
            ctrl: this.ctrl,
            serverType: 'FTP',
            themeTick: this.themeTick
          })
            .width('100%')
            .height('100%')
            .visibility(this.ctrl.currentPageKey === ShareServerPageKeys.FTP
              ? Visibility.Visible : Visibility.None)

          ShareTypePanel({
            ctrl: this.ctrl,
            serverType: 'SFTP',
            themeTick: this.themeTick
          })
            .width('100%')
            .height('100%')
            .visibility(this.ctrl.currentPageKey === ShareServerPageKeys.SFTP
              ? Visibility.Visible : Visibility.None)

          UserShareFoldersPanel({
            ctrl: this.ctrl,
            themeTick: this.themeTick
          })
            .width('100%')
            .height('100%')
            .visibility(this.ctrl.currentPageKey === ShareServerPageKeys.USER_FOLDERS
              ? Visibility.Visible : Visibility.None)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .alignContent(Alignment.Top)

      if (this.isAdmin()) {
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().pageBg)
  }
}
