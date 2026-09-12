import { AppTheme } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { FolderViewBody } from './FolderViewBody';
import { FolderViewPageParam } from '../router/FolderViewRoutes';

/**
 * 文件视图路由页（对齐 Flutter AppFolderViewPage 子页路由）：
 * 四个主页（照片/影音库/音乐/图书）的"文件"标签嵌入 FolderViewBody（根页），
 * 点击目录后推入本页（子页，同一模块类型），PageScaffold 提供状态栏与返回处理。
 */
@ComponentV2
export struct FolderViewPage {
  @Param param: FolderViewPageParam = new FolderViewPageParam();
  /** 返回上一页（由路由注入） */
  @Param popPage: () => void = (): void => {
  };
  /** 由 FolderViewBody 注册的返回拦截（多选模式下返回先退出多选，对齐 Flutter WillPopScope） */
  private customBackFn: () => boolean = (): boolean => false;

  build() {
    PageScaffold({
      title: '',
      showBack: false,
      statusBarBg: AppTheme.current().pageBg,
      customBack: (): boolean => this.customBackFn(),
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.PageContent()
      }
    })
  }

  @Builder
  PageContent() {
    FolderViewBody({
      moduleType: this.param.moduleType,
      initialPath: this.param.initialPath,
      initFolderName: this.param.initFolderName,
      isRootPage: this.param.isRootPage,
      popPage: (): void => {
        this.popPage();
      },
      registerCustomBack: (h: () => boolean): void => {
        this.customBackFn = h;
      }
    })
  }
}
