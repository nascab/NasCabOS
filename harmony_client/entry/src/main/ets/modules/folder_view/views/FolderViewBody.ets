import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { DialogUtil } from '../../../common/DialogUtil';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { FileUiHook } from '../../../files/controllers/FileController';
import { showFileCreateSheet, showFileViewSheet } from '../../../files/views/FileSheets';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';
import { FileTopActionsBar } from '../../../files/views/components/FileTopActionsBar';
import { FileSearchSection } from '../../../files/views/components/FileSearchSection';
import { FileViewToolbar } from '../../../files/views/components/FileViewToolbar';
import { FileListBodyView } from '../../../files/views/components/FileListBodyView';
import { FileMultiSelectBarView } from '../../../files/views/components/FileMultiSelectBarView';
import { FolderViewController } from '../controllers/FolderViewController';
import { FolderViewModuleType, FolderViewModuleTypes } from '../models/FolderViewModuleType';
import { FolderViewPageParam } from '../router/FolderViewRoutes';
import { TaskCenterPageParam } from '../../../transfer/views/TaskCenterPage';

/**
 * 文件视图主体（通用组件，对齐 Flutter AppFolderViewPage _buildScaffold）：
 * 顶部操作栏 + 搜索栏 + 视图工具栏 + 文件列表 + 多选操作栏。
 * 照片/影音库/音乐/图书四个主页的"文件"标签嵌入此组件；
 * 点目录推入 FolderViewPage 子页（同一模块类型，继续以此组件为主体）。
 */
@ComponentV2
export struct FolderViewBody {
  /** 模块类型（photo/video/book/music），决定列表与搜索 API */
  @Param moduleType: string = FolderViewModuleType.Photo;
  @Param initialPath: string = '';
  @Param initFolderName: string = '';
  /** 根页（嵌入主页 tab）无返回/关闭按钮；子页显示 */
  @Param isRootPage: boolean = true;
  /** 状态栏高度（vp）：嵌入沉浸式全屏主页时由主页传入避让；路由子页由 PageScaffold 避让传 0 */
  @Param statusBarHeight: number = 0;
  /** 子页返回回调（仅路由页注入） */
  @Param popPage: () => void = (): void => {
  };
  /** 注册返回拦截钩子（路由页注入，系统返回手势时先退出多选） */
  @Param registerCustomBack: (hook: () => boolean) => void = (_hook: () => boolean): void => {
  };
  @Local ctrl: FolderViewController = new FolderViewController(FolderViewModuleType.Photo);
  /** 服务端版本过低时只弹一次提示 */
  private lowVersionDialogShown: boolean = false;

  aboutToAppear(): void {
    this.registerCustomBack((): boolean => this.customBack());
    this.ctrl = new FolderViewController(this.moduleType as FolderViewModuleType);
    // 对齐 Flutter builder 内 ctrl.onlyShowDir.value = false
    this.ctrl.onlyShowDir = false;
    const hook: FileUiHook = {
      showAddCustomPath: (): void => {
        // 文件视图禁用自定义根路径入口（showRootCustomPathEntry=false），不会触发
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
    void this.ctrl.listDirectory(this.initialPath, 'normal');
    if (!FolderViewModuleTypes.isServerVersionSupported()) {
      // 对齐 Flutter _showLowServerVersionDialogOnce：延迟到首帧后弹出
      setTimeout((): void => {
        if (this.lowVersionDialogShown) {
          return;
        }
        this.lowVersionDialogShown = true;
        DialogUtil.showInfoDialog(L10n.tip, L10n.t('server_version_too_low',
          '您的服务端版本过低，请升级到最新版本并重新登录后再使用此功能'));
      }, 300);
    }
  }

  aboutToDisappear(): void {
    this.ctrl.close();
  }

  private get serverVersionSupported(): boolean {
    return FolderViewModuleTypes.isServerVersionSupported();
  }

  /** 标题：子页显示文件夹名（空回退模块标题）；根页显示模块标题 */
  private titleText(): string {
    if (!this.isRootPage) {
      const t = this.initFolderName.trim();
      return t.length > 0 ? t : FolderViewModuleTypes.title(this.moduleType as FolderViewModuleType);
    }
    return FolderViewModuleTypes.title(this.moduleType as FolderViewModuleType);
  }

  private handleBack(): void {
    if (this.ctrl.isMultiSelectMode) {
      this.ctrl.exitMultiSelectMode();
      return;
    }
    if (this.isRootPage) {
      return;
    }
    this.popPage();
  }

  /** 系统返回拦截：多选模式下先退出多选（对齐 Flutter WillPopScope） */
  private customBack(): boolean {
    if (this.ctrl.isMultiSelectMode) {
      this.ctrl.exitMultiSelectMode();
      return true;
    }
    return false;
  }

  /** 关闭按钮：一次性关闭所有文件视图子页（对齐 Flutter popUntil _childRouteName） */
  private closeChildPages(): void {
    NavUtil.popUntilTopNot(AppRouter.FOLDER_VIEW);
  }

  private openDir(path: string, folderName: string): void {
    const p = new FolderViewPageParam();
    p.moduleType = this.moduleType;
    p.initialPath = path;
    p.initFolderName = folderName;
    p.isRootPage = false;
    NavUtil.push(AppRouter.FOLDER_VIEW, p);
  }

  build() {
    if (!this.serverVersionSupported) {
      // 服务端版本过低占位（对齐 Flutter build 中 _isServerVersionTooLow 分支）
      this.LowVersionBody()
    } else {
      Column() {
        // 顶部操作栏
        FileTopActionsBar({
          title: this.titleText(),
          showBack: !this.isRootPage,
          showClose: !this.isRootPage,
          onBack: (): void => {
            this.handleBack();
          },
          onClose: (): void => {
            this.closeChildPages();
          },
          onCreate: (): void => {
            showFileCreateSheet(this.ctrl, (n: string, p?: object): void => {
              NavUtil.push(n, p);
            });
          },
          onTask: (): void => {
            // 任务中心（管理员为文件操作日志，对齐 Flutter AppTaskCenterPage）
            NavUtil.push(AppRouter.TASK_CENTER, new TaskCenterPageParam());
          }
        })
        // 搜索栏
        FileSearchSection({ ctrl: this.ctrl })
        // 视图选择 文件类型筛选（视图按钮弹选择 sheet，对齐 Flutter AppFolderViewPage）
        FileViewToolbar({
          ctrl: this.ctrl,
          onViewPressed: (): void => {
            showFileViewSheet(this.ctrl);
          }
        })
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
        // 多选操作栏（多选模式显示，嵌入主页时位于底部标签栏上方）
        if (this.ctrl.isMultiSelectMode) {
          FileMultiSelectBarView({ ctrl: this.ctrl })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight })
      .backgroundColor(AppTheme.current().pageBg)
    }
  }

  /** 服务端版本过低占位（对齐 Flutter SafeArea + SingleChildScrollView + CustomGlassCard） */
  @Builder
  LowVersionBody() {
    Scroll() {
      Column() {
        Text(FolderViewModuleTypes.title(this.moduleType as FolderViewModuleType))
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
        Blank().height(12)
        Column() {
          Text(L10n.t('server_version_too_low',
            '您的服务端版本过低，请升级到最新版本并重新登录后再使用此功能'))
            .fontSize(14)
            .fontColor(AppTheme.current().subText)
            .lineHeight(20)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .borderRadius(12)
        .backgroundColor(AppTheme.current().surfaceBg)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .padding({ left: 16, right: 16, bottom: 16, top: this.statusBarHeight + 16 })
    .scrollBar(BarState.Off)
    .backgroundColor(AppTheme.current().pageBg)
  }
}
