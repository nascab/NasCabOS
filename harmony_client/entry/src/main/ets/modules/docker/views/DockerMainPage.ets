import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { BottomTabBar, BottomTabItem } from '../../../common/components/BottomTabBar';
import { DockerController } from '../controllers/DockerController';
import { DockerErrorBanner } from './parts/DockerSharedWidgets';
import { DockerOverviewTab } from './DockerOverviewTab';
import { DockerImagesTab } from './DockerImagesTab';
import { DockerContainersTab } from './DockerContainersTab';
import { DockerTasksTab } from './DockerTasksTab';
import { DockerMainPageParam } from '../router/DockerRoutes';

/**
 * Docker 主页（对齐 Flutter DockerManagerView 移动端 appMode 形态）：
 * 公共 PageScaffold 顶栏（返回 + 标题 + 刷新），底部 4 标签（总览/镜像/容器/任务），
 * 错误文案以横幅展示在页签上方（对齐 Flutter _DockerBody 的 _ErrorBanner 分支）。
 */
@ComponentV2
export struct DockerMainPage {
  @Param param: DockerMainPageParam = new DockerMainPageParam();
  @Param popPage: () => void = (): void => {
  };
  /** 控制器随页面创建销毁（对齐 Flutter GetBuilder init/dispose 生命周期） */
  @Local ctrl: DockerController = new DockerController();

  aboutToAppear(): void {
    this.ctrl.onInit();
  }

  aboutToDisappear(): void {
    this.ctrl.onClose();
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  /** 底部标签（对齐 Flutter BottomNavigationBar 4 项） */
  private tabItems(): BottomTabItem[] {
    return [
      new BottomTabItem($r('sys.symbol.square_grid_2x2'),
        L10n.t('docker_tab_overview', '总览')),
      new BottomTabItem($r('sys.symbol.square_stack_3d'),
        L10n.t('docker_tab_images', '镜像')),
      new BottomTabItem($r('sys.symbol.archivebox'),
        L10n.t('docker_tab_containers', '容器')),
      new BottomTabItem($r('sys.symbol.list_bullet'),
        L10n.t('docker_tab_tasks', '任务'))
    ];
  }

  private tabIndexOf(tab: string): number {
    if (tab === 'images') {
      return 1;
    }
    if (tab === 'containers') {
      return 2;
    }
    if (tab === 'tasks') {
      return 3;
    }
    return 0;
  }

  private tabForIndex(index: number): string {
    if (index === 1) {
      return 'images';
    }
    if (index === 2) {
      return 'containers';
    }
    if (index === 3) {
      return 'tasks';
    }
    return 'overview';
  }

  build() {
    PageScaffold({
      title: this.param.title.length > 0 ? this.param.title : L10n.t('app_docker', 'Docker'),
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

  /** 顶栏动作（对齐 Flutter AppBar actions：刷新） */
  @Builder
  HeaderActions() {
    Row({ space: 10 }) {
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
    Column() {
      if (this.ctrl.errorText.trim().length > 0) {
        Column() {
          DockerErrorBanner({ text: this.ctrl.errorText })
        }
        .margin({ left: 12, right: 12, top: 12 })
        .width('100%')
      }

      Column() {
        this.Body()
      }
      .width('100%')
      .layoutWeight(1)

      BottomTabBar({
        items: this.tabItems(),
        selectedIndex: this.tabIndexOf(this.ctrl.currentTab),
        onSelect: (index: number): void => {
          this.ctrl.changeTab(this.tabForIndex(index));
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().pageBg)
  }

  /** 主体（对齐 _DockerBody 按 tab 切换） */
  @Builder
  Body() {
    if (this.ctrl.currentTab === 'images') {
      DockerImagesTab({ ctrl: this.ctrl })
    } else if (this.ctrl.currentTab === 'containers') {
      DockerContainersTab({ ctrl: this.ctrl })
    } else if (this.ctrl.currentTab === 'tasks') {
      DockerTasksTab({ ctrl: this.ctrl })
    } else {
      DockerOverviewTab({ ctrl: this.ctrl })
    }
  }
}
