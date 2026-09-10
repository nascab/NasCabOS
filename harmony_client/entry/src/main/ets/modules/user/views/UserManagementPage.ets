import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { NavUtil } from '../../../common/NavUtil';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { EmptyState } from '../../../common/components/EmptyState';
import { UserManagementController } from '../controllers/UserManagementController';
import { UserProfile } from '../models/UserModels';
import { UserCard } from '../components/UserCard';
import { openUserFormDialog } from '../components/UserFormDialog';
import { UserDetailPageParam, UserManagementPageParam, UserRoutes } from '../router/UserRoutes';

/**
 * 用户管理主页（对齐 Flutter 移动端 _AppUserManagementListPage）：
 * 标题栏（新建动作）+ 搜索框 + 用户卡片列表（触底加载更多），点击卡片进入用户详情页。
 */
@ComponentV2
export struct UserManagementPage {
  @Param param: UserManagementPageParam = new UserManagementPageParam();
  @Param popPage: () => void = (): void => {
  };
  ctrl: UserManagementController = UserManagementController.getInstance();

  aboutToAppear(): void {
    this.ctrl.ensureInit();
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  /** 新建用户（对齐 AppBar add 动作 → CustomUserFormDialog） */
  private openCreateDialog(): void {
    openUserFormDialog(undefined, (_ok: boolean): void => {
      // 创建成功后控制器内部已 fetchUsers 刷新列表
    });
  }

  /** 进入用户详情（对齐 onUserTap：选中并刷新登录记录后 push 详情页） */
  private openUserDetail(user: UserProfile): void {
    this.ctrl.selectUser(user.id);
    NavUtil.push(UserRoutes.PAGE_DETAIL, new UserDetailPageParam(user.id));
  }

  @Builder
  Footer() {
    if (this.ctrl.usersLoadingMore) {
      Row() {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(this.palette().primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding(12)
    } else if (!this.ctrl.usersHasMore && this.ctrl.users.length > 0) {
      Text(L10n.t('no_more', '没有更多'))
        .fontSize(13)
        .fontColor(this.palette().hint)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding(12)
    }
  }

  @Builder
  Content() {
    Column() {
      // 搜索框（对齐 CustomExpandableSearchBar defaultExpanded）
      Row() {
        SearchInputBar({
          hintText: L10n.t('user_mgmt_search', '搜索用户'),
          text: this.ctrl.keyword,
          onChanged: (v: string): void => {
            this.ctrl.onSearchChanged(v);
          },
          onClear: (): void => {
            this.ctrl.onSearchChanged('');
          }
        })
      }
      .width('100%')
      .padding({ top: 10, bottom: 12, left: 16, right: 16 })

      if (this.ctrl.users.length === 0) {
        Column() {
          EmptyState({
            message: L10n.t('no_data', '暂无数据'),
            imagePath: $rawfile('icons/no_data.png')
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 10 }) {
          ForEach(this.ctrl.users, (user: UserProfile) => {
            ListItem() {
              UserCard({ user: user, onTap: (): void => {
                this.openUserDetail(user);
              } })
            }
          }, (user: UserProfile): string =>
            `${user.id}_${user.username}_${user.type}_${user.phone}_${user.userRemark}_${user.isActive}`)
          ListItem() {
            this.Footer()
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 12 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd((): void => {
          void this.ctrl.loadMoreUsers();
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageScaffold({
      title: L10n.t('user_mgmt_title', '用户管理'),
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        BorderedIconButton({
          icon: $r('sys.symbol.plus'),
          onTap: (): void => {
            this.openCreateDialog();
          }
        })
      },
      content: (): void => {
        this.Content()
      }
    })
  }
}
