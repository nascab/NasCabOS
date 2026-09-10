import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { ToastUtil } from '../../../common/ToastUtil';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';
import { UserManagementController } from '../controllers/UserManagementController';
import { PermissionGroup, groupPermissions } from '../models/UserModels';

/** 权限操作项（对齐 CustomPermissionEditor._actionChip 的六个 action） */
class PermissionAction {
  key: string = '';
  labelKey: string = '';
  fallback: string = '';

  constructor(key: string, labelKey: string, fallback: string) {
    this.key = key;
    this.labelKey = labelKey;
    this.fallback = fallback;
  }
}

const PERMISSION_ACTIONS: PermissionAction[] = [
  new PermissionAction('view', 'perm_view', '查看'),
  new PermissionAction('download', 'download', '下载'),
  new PermissionAction('update', 'perm_update', '更新'),
  new PermissionAction('delete', 'perm_delete', '删除'),
  new PermissionAction('upload', 'upload', '上传'),
  new PermissionAction('share', 'share', '分享')
];

/**
 * 自定义权限编辑器（对齐 Flutter CustomPermissionEditor + CustomPermissionEditorController）：
 * 「添加授权目录」卡片 + 授权目录列表（每目录六个操作 chip），任何变更立即自动保存；
 * 保存失败时回滚到进入时的原始数据并提示。
 */
@ComponentV2
export struct PermissionEditor {
  @Require @Param uid: number;
  @Require @Param ctrl: UserManagementController;
  @Local groups: PermissionGroup[] = [];
  @Local loaded: boolean = false;
  /** 进入时的原始权限（保存失败回滚用，对齐 initialPermissions） */
  private initialGroups: PermissionGroup[] = [];

  aboutToAppear(): void {
    void this.init();
  }

  private async init(): Promise<void> {
    await this.ctrl.loadPermissions(this.uid);
    this.initialGroups = this.ctrl.getPermissions(this.uid);
    this.groups = this.copyGroups(this.initialGroups);
    this.loaded = this.ctrl.hasPermissions(this.uid);
  }

  private copyGroups(src: PermissionGroup[]): PermissionGroup[] {
    const result: PermissionGroup[] = [];
    src.forEach((g: PermissionGroup): void => {
      const c = new PermissionGroup();
      c.resType = g.resType;
      c.resPath = g.resPath;
      c.actions = g.actions.slice();
      result.push(c);
    });
    return result;
  }

  /** 保存失败回滚：恢复到进入时的原始数据（对齐 _initializeItems 恢复语义） */
  private reinitialize(items: PermissionGroup[]): void {
    this.initialGroups = items;
    this.groups = this.copyGroups(items);
    this.loaded = true;
  }

  // ===== 变更 + 自动保存（对齐 addPermission/removePermission/toggleAction → autoSave） =====
  // 说明：嵌套 actions 数组不在 V2 观察范围内，所有变更都在副本上操作后整体重赋值触发刷新。

  addPermission(path: string): void {
    const next: PermissionGroup[] = this.copyGroups(this.groups);
    let idx = -1;
    for (let i = 0; i < next.length; i++) {
      if (next[i].resType === 'file' && next[i].resPath === path) {
        idx = i;
        break;
      }
    }
    if (idx >= 0) {
      if (!next[idx].actions.includes('view')) {
        next[idx].actions.push('view');
      }
    } else {
      const g = new PermissionGroup();
      g.resType = 'file';
      g.resPath = path;
      g.actions.push('view');
      next.push(g);
    }
    this.groups = next;
    void this.autoSave();
  }

  removePermission(index: number): void {
    if (index < 0 || index >= this.groups.length) {
      return;
    }
    const next: PermissionGroup[] = this.copyGroups(this.groups);
    next.splice(index, 1);
    this.groups = next;
    void this.autoSave();
  }

  toggleAction(index: number, action: string): void {
    if (index < 0 || index >= this.groups.length) {
      return;
    }
    const next: PermissionGroup[] = this.copyGroups(this.groups);
    const acts = next[index].actions;
    const pos = acts.indexOf(action);
    if (pos >= 0) {
      acts.splice(pos, 1);
    } else {
      acts.push(action);
    }
    this.groups = next;
    void this.autoSave();
  }

  private async autoSave(): Promise<void> {
    const success = await this.ctrl.setPermissions(this.uid, this.groups);
    if (success) {
      ToastUtil.show(L10n.t('user_mgmt_permission_saved', '权限保存成功'));
    } else {
      // 保存失败：回滚到进入时的原始数据（对齐 _initializeItems 恢复语义）
      this.reinitialize(this.initialGroups);
      ToastUtil.show(L10n.t('user_mgmt_permission_save_failed', '权限保存失败'));
    }
  }

  /** 选择授权目录（对齐 pickDirectory → showFolderPickerBottomSheet 多选） */
  private pickDirectory(): void {
    pickTargetFolderViaSheet('', (paths: string[]): void => {
      paths.forEach((p: string): void => {
        this.addPermission(p);
      });
    }, true);
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  @Builder
  ActionChip(group: PermissionGroup, index: number, action: PermissionAction) {
    Text(L10n.t(action.labelKey, action.fallback))
      .fontSize(11)
      .fontColor(group.actions.includes(action.key)
        ? this.palette().primary : this.palette().onSurface)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(15)
      .border({
        width: 1,
        color: group.actions.includes(action.key)
          ? this.palette().primary : this.palette().divider
      })
      .backgroundColor(group.actions.includes(action.key)
        ? AppTheme.withAlpha(this.palette().primary, 0.12)
        : AppTheme.withAlpha(this.palette().onSurface, 0.05))
      .onClick((): void => {
        this.toggleAction(index, action.key);
      })
  }

  build() {
    if (!this.loaded) {
      // 权限未装载完成：居中加载（对齐 Flutter LoadingProgress 分支）
      Column() {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(this.palette().primary)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 10 }) {
        // 卡 0：添加授权目录
        ListItem() {
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(22)
              .fontColor([this.palette().primary])
            Column({ space: 4 }) {
              Text(L10n.t('user_mgmt_add_auth_dir', '添加授权目录'))
                .fontSize(15)
                .fontColor(this.palette().onSurface)
              Text(L10n.t('user_mgmt_add_auth_dir_alert',
                '如果添加已有目录的子目录,权限将以父目录为准'))
                .fontSize(12)
                .fontColor(AppTheme.withAlpha(this.palette().onSurface, 0.6))
              Text(L10n.t('user_mgmt_add_auth_dir_hint',
                '如需设置照片,电影等权限,直接授权对应模块的来源目录或其子目录即可'))
                .fontSize(12)
                .fontColor(AppTheme.withAlpha(this.palette().onSurface, 0.6))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .padding(12)
          .borderRadius(12)
          .backgroundColor(this.palette().cardBg)
          .border({ width: 1, color: AppTheme.withAlpha(this.palette().divider, 0.4) })
          .onClick((): void => {
            this.pickDirectory();
          })
        }

        // 授权目录条目
        ForEach(this.groups, (g: PermissionGroup, index: number) => {
          ListItem() {
            Column() {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(18)
                  .fontColor([this.palette().subText])
                  .onClick((): void => {
                    this.removePermission(index);
                  })
                Text(g.resPath)
                  .fontSize(14)
                  .fontColor(this.palette().onSurface)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')

              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(PERMISSION_ACTIONS, (action: PermissionAction) => {
                  this.ActionChip(g, index, action)
                }, (action: PermissionAction): string =>
                  `${index}_${action.key}_${g.actions.includes(action.key)}`)
              }
              .margin({ top: 8 })
              .width('100%')
            }
            .width('100%')
            .padding(12)
            .borderRadius(12)
            .backgroundColor(this.palette().cardBg)
            .border({ width: 1, color: AppTheme.withAlpha(this.palette().divider, 0.4) })
          }
        }, (g: PermissionGroup, index: number): string =>
          `${index}_${g.resType}_${g.resPath}_${g.actions.join(',')}`)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 12 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }
}
