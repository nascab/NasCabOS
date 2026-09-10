import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { AppEventBus } from '../../../common/AppEventBus';
import { LanguageService } from '../../../core/localization/LanguageService';
import { PageScaffold } from '../../../common/PageScaffold';
import { DialogUtil } from '../../../common/DialogUtil';
import { NavUtil } from '../../../common/NavUtil';
import { BottomTabBar, BottomTabItem } from '../../../common/components/BottomTabBar';
import { FileMountController, OpenlistMountController } from '../controllers/FileMountControllers';
import { MountPluginStatus } from '../services/MountPluginStatus';
import {
  FileMountRoutes, MountPageKeys, FileMountPageParam,
  FileMountEditPageParam, OpenlistMountEditPageParam
} from '../router/FileMountRoutes';
import { MountListPanel, OpenlistMountListPanel } from './FileMountPanels';

/**
 * 挂载插件未就绪横幅（对齐 Flutter MountPluginNotReadyBanner）：
 * 就绪时不渲染；未就绪时浅色底 + 小加载圈 + 提示文案。
 */
@ComponentV2
struct PluginNotReadyBanner {
  @Param ready: boolean = true;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    if (!this.ready) {
      Row({ space: 12 }) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.palette().primary)
        Text(L10n.t('mount_share_plugin_not_ready', '此功能所需插件还未下载完成，请稍后再试。'))
          .fontSize(13)
          .fontColor(this.palette().onSurface)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor(AppTheme.withAlpha(this.palette().secondary, 0.15))
    }
  }
}

/**
 * 远程挂载主页（对齐 Flutter FileMountView 移动端形态）：
 * 标题栏（帮助/刷新/新增）+ 插件状态横幅 + 列表面板 + 底部 2 标签（文件协议管理 / 网盘挂载）。
 */
@ComponentV2
export struct FileMountPage {
  @Param param: FileMountPageParam = new FileMountPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: FileMountController = FileMountController.getInstance();
  @Local openlistCtrl: OpenlistMountController = OpenlistMountController.getInstance();
  @Local plugin: MountPluginStatus = MountPluginStatus.ensure();
  /** 依赖 localeBump：切换语言后触发整页刷新（驱动名等非语言包文案） */
  @Local localeBump: number = 0;
  private localeListener: (data: string) => void = (_data: string): void => {
    this.localeBump++;
  };

  aboutToAppear(): void {
    AppEventBus.on(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    // 对齐 Flutter：进入页面即确保插件状态轮询进行中
    this.plugin.ensurePolling();
    this.ctrl.onInit();
    this.openlistCtrl.onInit();
  }

  aboutToDisappear(): void {
    AppEventBus.off(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
  }

  private get isOpenlist(): boolean {
    return this.ctrl.currentPageKey === MountPageKeys.OPENLIST;
  }

  private pageTitle(): string {
    return this.isOpenlist
      ? L10n.t('file_mount_menu_openlist', '网盘挂载')
      : L10n.t('file_mount_menu_manage', '文件协议管理');
  }

  private tabItems(): BottomTabItem[] {
    return [
      new BottomTabItem($r('sys.symbol.folder'), L10n.t('file_mount_menu_manage', '文件协议管理')),
      new BottomTabItem($r('sys.symbol.cloud'), L10n.t('file_mount_menu_openlist', '网盘挂载'))
    ];
  }

  private showHelp(): void {
    const content = this.isOpenlist
      ? L10n.t('openlist_mount_help_tooltip',
        '支持百度网盘、123云盘、115 Open、OneDrive、阿里云盘 Open、对象存储(S3)等，' +
        'OAuth 类网盘请先在授权页获取 Token；对象存储需填写桶、端点与密钥。')
      : L10n.t('file_mount_help_tooltip', '将远程驱动器（WebDAV/FTP/SFTP等）挂载到服务端磁盘路径');
    void DialogUtil.showInfoDialog(this.pageTitle(), content);
  }

  private onRefresh(): void {
    if (this.isOpenlist) {
      void this.openlistCtrl.refreshList(true);
    } else {
      void this.ctrl.refreshList(true);
    }
  }

  /** 新增（对齐 Flutter 移动端标题栏 add：先 WinFsp 检测，网盘还需加载驱动列表） */
  private async onCreate(): Promise<void> {
    if (this.isOpenlist) {
      const allowed = await this.openlistCtrl.ensureWinfspReady();
      if (!allowed) {
        return;
      }
      await this.openlistCtrl.loadDrivers();
      NavUtil.push(FileMountRoutes.PAGE_OPENLIST_EDIT, new OpenlistMountEditPageParam());
      return;
    }
    const allowed = await this.ctrl.ensureWinfspReady();
    if (!allowed) {
      return;
    }
    NavUtil.push(FileMountRoutes.PAGE_MOUNT_EDIT, new FileMountEditPageParam());
  }

  build() {
    PageScaffold({
      title: this.pageTitle(),
      showBack: true,
      statusBarBg: AppTheme.current().pageBg,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.TitleActions()
      },
      content: (): void => {
        this.PageContent()
      }
    })
  }

  @Builder
  TitleActions() {
    SymbolGlyph($r('sys.symbol.questionmark_circle'))
      .fontSize(22)
      .fontColor([AppTheme.current().appBarFg])
      .onClick((): void => {
        this.showHelp();
      })
    SymbolGlyph($r('sys.symbol.arrow_clockwise'))
      .fontSize(22)
      .fontColor([AppTheme.current().appBarFg])
      .onClick((): void => {
        this.onRefresh();
      })
    SymbolGlyph($r('sys.symbol.plus'))
      .fontSize(22)
      .fontColor([AppTheme.current().appBarFg])
      .onClick((): void => {
        void this.onCreate();
      })
  }

  @Builder
  PageContent() {
    Column() {
      // 插件未就绪横幅
      PluginNotReadyBanner({
        ready: this.isOpenlist ? this.plugin.canUseOpenlistMount : this.plugin.canUseFileMount
      })
      // 当前面板
      Column() {
        if (this.isOpenlist) {
          OpenlistMountListPanel({ ctrl: this.openlistCtrl })
        } else {
          MountListPanel({ ctrl: this.ctrl })
        }
      }
      .width('100%')
      .layoutWeight(1)
      // 底部 2 标签（对齐 Flutter BottomNavigationBar）
      BottomTabBar({
        items: this.tabItems(),
        selectedIndex: this.isOpenlist ? 1 : 0,
        onSelect: (index: number): void => {
          this.ctrl.selectPage(index === 1 ? MountPageKeys.OPENLIST : MountPageKeys.LIST);
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().pageBg)
    // 依赖 localeBump：切换语言后触发整页刷新
    .opacity(this.localeBump >= 0 ? 1 : 1)
  }
}
