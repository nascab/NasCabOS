import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { AppEventBus } from '../../common/AppEventBus';
import { PageScaffold } from '../../common/PageScaffold';
import { AppRouter } from '../../router/AppRouter';
import { LanguageService } from '../../core/localization/LanguageService';
import { FileController, FileUiHook } from '../controllers/FileController';
import { showFileAddCustomPathSheet, showFileCreateSheet } from './FileSheets';
import { pickTargetFolderViaSheet } from './FolderPickerSheet';
import { FileTopActionsBar } from './components/FileTopActionsBar';
import { FileSearchSection } from './components/FileSearchSection';
import { FileViewToolbar } from './components/FileViewToolbar';
import { FileListBodyView } from './components/FileListBodyView';
import { FileMultiSelectBarView } from './components/FileMultiSelectBarView';
import { NavUtil } from '../../common/NavUtil';
import { TaskCenterPageParam } from '../../transfer/views/TaskCenterPage';

/** 文件浏览器页面参数 */
export class FileBrowserParam {
  initialPath: string = '';
  initFolderName: string = '';
  isRootPage: boolean = true;
}

/**
 * 文件管理页面（对齐 Flutter AppFileBrowser 移动端布局）：
 * 顶部操作栏 + 搜索栏 + 视图工具栏 + 文件列表（网格/大图/列表）+ 底部导航（根页）/多选操作栏。
 * 顶栏/搜索/工具栏/列表/多选栏均为 files 通用组件（components/），与 folder_view 模块共享。
 */
@ComponentV2
export struct FileBrowserPage {
  @Param param: FileBrowserParam = new FileBrowserParam();
  /** 上推新页面（进入子目录） */
  @Param pushPage: (name: string, param?: object) => void = (_n: string, _p?: object): void => {
  };
  /** 返回上一页 */
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: FileController = new FileController(false);
  @Local localeBump: number = 0;
  private localeListener: (data: string) => void = (_data: string): void => {
    this.localeBump++;
  };

  aboutToAppear(): void {
    AppEventBus.on(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    const hook: FileUiHook = {
      showAddCustomPath: (): void => {
        showFileAddCustomPathSheet(this.ctrl);
      },
      pickTargetFolder: (): Promise<string[]> => {
        return new Promise<string[]>((resolve: (paths: string[]) => void) => {
          pickTargetFolderViaSheet('', (paths: string[]): void => {
            resolve(paths);
          });
        });
      }
    };
    this.ctrl.uiHook = hook;
    this.ctrl.init();
    void this.ctrl.listDirectory(this.param.initialPath, 'normal');
  }

  aboutToDisappear(): void {
    AppEventBus.off(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    this.ctrl.close();
  }

  private get isRootPage(): boolean {
    return this.param.isRootPage;
  }

  private pageTitle(): string {
    if (!this.isRootPage) {
      const t = this.param.initFolderName.trim();
      return t.length > 0 ? t : L10n.t('app_folder', '文件');
    }
    const m = this.ctrl.currentModule;
    if (m === 'favorites') {
      return L10n.t('favorites', '收藏');
    }
    if (m === 'recent') {
      return L10n.t('recent', '最近');
    }
    return L10n.t('app_folder', '文件');
  }

  private moduleIndex(): number {
    const m = this.ctrl.currentModule;
    if (m === 'favorites') {
      return 1;
    }
    if (m === 'recent') {
      return 2;
    }
    return 0;
  }

  private handleBack(): void {
    if (this.ctrl.isMultiSelectMode) {
      this.ctrl.exitMultiSelectMode();
      return;
    }
    if (this.isRootPage) {
      // 根页返回由外层（首页容器）处理：直接 pop
    }
    this.popPage();
  }

  private customBack(): boolean {
    if (this.ctrl.isMultiSelectMode) {
      this.ctrl.exitMultiSelectMode();
      return true;
    }
    return false;
  }

  private openDir(path: string, folderName: string): void {
    const p = new FileBrowserParam();
    p.initialPath = path;
    p.initFolderName = folderName;
    p.isRootPage = false;
    this.pushPage(AppRouter.FILES, p);
  }

  build() {
    PageScaffold({
      title: '',
      showBack: false,
      statusBarBg: AppTheme.current().pageBg,
      customBack: (): boolean => this.customBack(),
      onBack: (): void => {
        this.handleBack();
      },
      content: (): void => {
        this.PageContent()
      }
    })
  }

  @Builder
  PageContent() {
    Column() {
      // 顶部操作栏
      FileTopActionsBar({
        title: this.pageTitle(),
        showClose: !this.isRootPage,
        onBack: (): void => {
          this.handleBack();
        },
        onClose: (): void => {
          this.popPage();
        },
        onCreate: (): void => {
          showFileCreateSheet(this.ctrl, (n: string, p?: object): void => {
            this.pushPage(n, p);
          });
        },
        onTask: (): void => {
          // 任务中心（管理员为文件操作日志，对齐 Flutter AppTaskCenterPage）
          NavUtil.push(AppRouter.TASK_CENTER, new TaskCenterPageParam());
        }
      })
      // 搜索栏
      FileSearchSection({ ctrl: this.ctrl })
      // 视图工具栏
      FileViewToolbar({ ctrl: this.ctrl })
      Divider()
        .color(AppTheme.current().divider)
      // 主列表
      Column() {
        FileListBodyView({
          ctrl: this.ctrl,
          onOpenDir: (p: string, n: string): void => {
            this.openDir(p, n);
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      // 底部：多选操作栏 / 根页底部导航
      if (this.ctrl.isMultiSelectMode) {
        FileMultiSelectBarView({ ctrl: this.ctrl })
      } else if (this.isRootPage) {
        this.BottomNavBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().pageBg)
  }

  @Builder
  BottomNavBarItem(icon: Resource, label: string, index: number) {
    Column({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.moduleIndex() === index ? AppTheme.current().primary : AppTheme.current().subText])
      Text(label)
        .fontSize(11)
        .fontColor(this.moduleIndex() === index ? AppTheme.current().primary : AppTheme.current().subText)
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .padding({ top: 8, bottom: 8 })
    .onClick((): void => {
      if (index === this.moduleIndex()) {
        return;
      }
      if (index === 1) {
        void this.ctrl.listDirectory('', 'favorites');
        return;
      }
      if (index === 2) {
        void this.ctrl.listDirectory('', 'recent');
        return;
      }
      void this.ctrl.listDirectory('', 'normal');
    })
  }

  @Builder
  BottomNavBar() {
    Row() {
      this.BottomNavBarItem($r('sys.symbol.folder'), L10n.t('app_folder', '文件'), 0)
      this.BottomNavBarItem($r('sys.symbol.star'), L10n.t('favorites', '收藏'), 1)
      this.BottomNavBarItem($r('sys.symbol.clock'), L10n.t('recent', '最近'), 2)
    }
    .width('100%')
    .border({ width: { top: 0.5 }, color: AppTheme.current().divider })
    .backgroundColor(AppTheme.current().surfaceBg)
    // 背景延伸到底部导航条安全区，避免露出页面底色
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
