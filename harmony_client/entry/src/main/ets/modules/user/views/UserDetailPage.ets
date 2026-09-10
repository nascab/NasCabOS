import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { EmptyState } from '../../../common/components/EmptyState';
import { UserManagementController } from '../controllers/UserManagementController';
import { UserProfile } from '../models/UserModels';
import { UserInfoCard } from '../components/UserInfoCard';
import { TwofaTab } from '../components/TwofaTab';
import { LoginRecordsTab } from '../components/LoginRecordsTab';
import { OperationLogsTab } from '../components/OperationLogsTab';
import { PermissionEditor } from '../components/PermissionEditor';
import { UserDetailPageParam } from '../router/UserRoutes';

/**
 * 用户详情页（对齐 Flutter 移动端 _AppUserManagementDetailPage / _AppUserManagementDetailPanel）：
 * 信息卡（编辑/删除）+ Tabs（2FA / 登录记录 / 操作日志 / 权限设置，super_admin 隐藏权限）。
 */
@ComponentV2
export struct UserDetailPage {
  @Param param: UserDetailPageParam = new UserDetailPageParam();
  @Param popPage: () => void = (): void => {
  };
  ctrl: UserManagementController = UserManagementController.getInstance();
  @Local activeTabIndex: number = 0;

  aboutToAppear(): void {
    // 直接进入详情时以参数为准（对齐 Flutter selectedIds 单值收敛）
    if (this.ctrl.selectedId !== this.param.uid) {
      this.ctrl.selectUser(this.param.uid);
    }
    this.ctrl.ensureInit();
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private user(): UserProfile | undefined {
    return this.ctrl.getCurrentUser();
  }

  /** super_admin 无权限设置 Tab（对齐 showPermissionsTab = type != 'super_admin'） */
  private showPermissions(): boolean {
    const u = this.user();
    return u !== undefined && u.type !== 'super_admin';
  }

  private currentTabIndex(): number {
    return this.activeTabIndex;
  }

  @Builder
  TabLabel(title: string, index: number) {
    Text(title)
      .fontSize(14)
      .fontWeight(this.currentTabIndex() === index ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.currentTabIndex() === index
        ? this.palette().primary : this.palette().subText)
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
  }

  @Builder
  DetailBody() {
    Column() {
      UserInfoCard({
        user: this.user()!,
        ctrl: this.ctrl,
        onDeleted: (): void => {
          // 删除成功后控制器已刷新列表，详情页退出（移动端回到列表）
          this.popPage();
        }
      })

      Tabs({ index: this.activeTabIndex, barPosition: BarPosition.Start }) {
        TabContent() {
          TwofaTab({ uid: this.user()!.id, user: this.user()!, ctrl: this.ctrl })
        }
        .tabBar(this.TabLabel(L10n.t('user_mgmt_2fa', '双重验证'), 0))

        TabContent() {
          LoginRecordsTab({ ctrl: this.ctrl })
        }
        .tabBar(this.TabLabel(L10n.t('user_mgmt_login_records', '登录记录'), 1))

        TabContent() {
          OperationLogsTab({ ctrl: this.ctrl })
        }
        .tabBar(this.TabLabel(L10n.t('user_mgmt_operation_logs', '操作日志'), 2))

        if (this.showPermissions()) {
          TabContent() {
            PermissionEditor({ uid: this.user()!.id, ctrl: this.ctrl })
          }
          .tabBar(this.TabLabel(L10n.t('user_mgmt_permissions', '权限设置'), 3))
        }
      }
      .barMode(BarMode.Scrollable)
      .onChange((index: number): void => {
        this.activeTabIndex = index;
      })
      .width('100%')
      .layoutWeight(1)
      .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .padding(12)
  }

  @Builder
  Content() {
    if (this.user() === undefined) {
      // 列表尚未装载/选中用户不存在：加载或空态
      Column() {
        if (this.ctrl.loading) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(this.palette().primary)
        } else {
          EmptyState({
            message: L10n.t('no_data', '暂无数据'),
            imagePath: $rawfile('icons/no_data.png')
          })
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      this.DetailBody()
    }
  }

  build() {
    PageScaffold({
      title: this.user() !== undefined && this.user()!.username.length > 0
        ? this.user()!.username
        : L10n.t('user_mgmt_title', '用户管理'),
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.Content()
      }
    })
  }
}
