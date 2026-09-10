import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { DialogUtil } from '../../../common/DialogUtil';
import { UserManagementController } from '../controllers/UserManagementController';
import { UserProfile } from '../models/UserModels';
import { openUserFormDialog } from './UserFormDialog';

/**
 * 用户信息卡（详情页顶部，对齐 Flutter CustomUserInfoCard）：
 * 用户名 + 类型徽标 + 编辑/删除按钮（super_admin 不显示删除）。
 */
@ComponentV2
export struct UserInfoCard {
  @Require @Param user: UserProfile;
  @Require @Param ctrl: UserManagementController;
  /** 删除成功回调（详情页据此返回列表；Flutter 桌面布局无此交互） */
  @Param onDeleted: () => void = (): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  /** 编辑（对齐 onPressed：打开表单弹窗，成功后刷新列表） */
  private editUser(): void {
    openUserFormDialog(this.user, (): void => {
      void this.ctrl.fetchUsers();
    });
  }

  /** 删除（对齐 onPressed：二次确认 → selectedIds 收敛 → deleteSelected） */
  private async deleteUser(): Promise<void> {
    if (this.user.type === 'super_admin') {
      return;
    }
    const confirmed = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('user_delete_confirm_message', '确定删除用户[@username]吗？',
        L10n.paramsOf('username', this.user.username)),
      undefined,
      L10n.ok, L10n.cancel
    );
    if (confirmed !== true) {
      return;
    }
    this.ctrl.selectUser(this.user.id);
    const ok = await this.ctrl.deleteSelected();
    if (ok) {
      this.onDeleted();
    }
  }

  @Builder
  ActionButton(icon: Resource, label: string, color: string, onTap: () => void) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([color])
      Text(label)
        .fontSize(13)
        .fontColor(color)
        .maxLines(1)
    }
    .justifyContent(FlexAlign.Center)
    .height(34)
    .padding({ left: 14, right: 14 })
    .borderRadius(17)
    .border({ width: 1, color: color })
    .onClick((): void => {
      onTap();
    })
  }

  build() {
    Column() {
      // 行 1：用户名 + 类型徽标
      Row({ space: 8 }) {
        Text(this.user.username)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.ctrl.userTypeLabel(this.user.type))
          .fontSize(11)
          .fontColor(this.palette().buttonText)
          .padding({ left: 4, right: 4, top: 2, bottom: 3 })
          .borderRadius(8)
          .backgroundColor(this.user.type === 'super_admin'
            ? this.palette().primary
            : AppTheme.withAlpha(this.palette().onSurface, 0.5))
      }
      .width('100%')

      // 行 2：编辑 / 删除
      Row({ space: 8 }) {
        this.ActionButton($r('sys.symbol.square_and_pencil'),
          L10n.t('edit', '编辑'), this.palette().primary, (): void => {
            this.editUser();
          })
        if (this.user.type !== 'super_admin') {
          this.ActionButton($r('sys.symbol.trash'),
            L10n.t('delete', '删除'), this.palette().error, (): void => {
              void this.deleteUser();
            })
        }
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(this.palette().cardBg)
    .border({ width: 1, color: AppTheme.withAlpha(this.palette().divider, 0.4) })
  }
}
