import { L10n } from '../../../../core/localization/L10n';
import { AppTheme } from '../../../../core/theme/AppTheme';
import { DialogUtil } from '../../../../common/DialogUtil';
import { pickTargetFolderViaSheet } from '../../../../files/views/FolderPickerSheet';
import { EmptyState } from '../../../../common/components/EmptyState';
import { ShareRootPath, ShareServerConfigRecord, ShareUserOption } from '../../models/ShareServerModels';
import { ShareServerController } from '../../controllers/ShareServerController';

/**
 * 用户权限配置新建/编辑弹窗（对齐 Flutter _ConfigDialog + _ConfigDialogState + _RootPathRow）：
 * 全屏遮罩 + 居中卡片。选择用户（嵌套用户选择浮层，对齐 _UserPickerDialog），
 * 路径行列表（选择目录 + 读取/写入/修改/删除 权限 chips）。
 * 提交校验通过后回调 onSubmit（页面注入 ctrl.upsertConfig 包装），成功后关闭。
 */
@ComponentV2
export struct ShareConfigDialog {
  @Param ctrl: ShareServerController = new ShareServerController();
  @Param serverType: string = 'WebDav';
  /** 编辑目标；undefined 表示创建模式 */
  @Param initialItem: ShareServerConfigRecord | undefined = undefined;
  /** 提交回调：返回 true 表示成功（成功后关闭弹窗） */
  @Param onSubmit: (uid: number, rootPath: ShareRootPath[]) => Promise<boolean> =
    (_uid: number, _rootPath: ShareRootPath[]): Promise<boolean> => Promise.resolve(false);
  @Param onDismiss: () => void = (): void => {
  };

  @Local selectedUid: number = -1;
  @Local rows: ShareRootPath[] = [];
  @Local submitting: boolean = false;
  @Local showUserPicker: boolean = false;
  private existingUids: number[] = [];

  aboutToAppear(): void {
    if (this.initialItem !== undefined) {
      this.selectedUid = this.initialItem.uid;
    }
    this.rows = ShareConfigDialog.buildInitialRows(
      this.initialItem !== undefined ? this.initialItem.rootPath : []);
    // 已有配置的 uid 快照（对齐 Flutter existingUids 参数）
    this.existingUids = this.ctrl.configsFor(this.serverType).map(
      (c: ShareServerConfigRecord): number => c.uid);
  }

  /** 初始路径行（对齐 _buildInitialRows：无行时补一行空行） */
  private static buildInitialRows(rootPath: ShareRootPath[]): ShareRootPath[] {
    const rows: ShareRootPath[] = [];
    rootPath.forEach((r: ShareRootPath): void => {
      const row = new ShareRootPath();
      row.path = r.path;
      row.write = r.write;
      row.update = r.update;
      row.delete = r.delete;
      rows.push(row);
    });
    if (rows.length === 0) {
      rows.push(new ShareRootPath());
    }
    return rows;
  }

  private selectedUsername(): string {
    if (this.selectedUid < 0) {
      return L10n.t('file_share_server_choose_user_hint', '未选择用户');
    }
    return this.ctrl.usernameForUid(this.selectedUid);
  }

  private addUserRow(): void {
    const next = this.rows.slice();
    next.push(new ShareRootPath());
    this.rows = next;
  }

  private removeRow(index: number): void {
    if (this.rows.length <= 1) {
      return;
    }
    const next: ShareRootPath[] = [];
    for (let i = 0; i < this.rows.length; i++) {
      if (i !== index) {
        next.push(this.rows[i]);
      }
    }
    this.rows = next;
  }

  private pickPathForRow(index: number): void {
    pickTargetFolderViaSheet('', (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      const picked = paths[0].trim();
      if (picked.length === 0) {
        return;
      }
      const next = this.rows.slice();
      const row = new ShareRootPath();
      const src = next[index];
      row.path = picked;
      row.write = src !== undefined ? src.write : true;
      row.update = src !== undefined ? src.update : true;
      row.delete = src !== undefined ? src.delete : true;
      next[index] = row;
      this.rows = next;
    });
  }

  private togglePerm(index: number, field: string, value: boolean): void {
    const next = this.rows.slice();
    const row = new ShareRootPath();
    const src = next[index];
    if (src === undefined) {
      return;
    }
    row.path = src.path;
    row.write = field === 'write' ? value : src.write;
    row.update = field === 'update' ? value : src.update;
    row.delete = field === 'delete' ? value : src.delete;
    next[index] = row;
    this.rows = next;
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    if (this.selectedUid < 0) {
      DialogUtil.showErrorDialog(L10n.t('file_share_server_choose_user_hint', '未选择用户'));
      return;
    }
    // 用户重复校验（编辑时自身 uid 除外，对齐 Flutter）
    const isDuplicate = this.existingUids.indexOf(this.selectedUid) >= 0
      && (this.initialItem === undefined || this.selectedUid !== this.initialItem.uid);
    if (isDuplicate) {
      DialogUtil.showErrorDialog(L10n.t('file_share_server_user_duplicate', '该用户已存在配置'));
      return;
    }
    // 路径校验
    const out: ShareRootPath[] = [];
    const seenPaths: string[] = [];
    for (let i = 0; i < this.rows.length; i++) {
      const row = this.rows[i];
      const path = row.path.trim();
      if (path.length === 0) {
        continue;
      }
      if (seenPaths.indexOf(path) >= 0) {
        DialogUtil.showErrorDialog(L10n.t('file_share_server_path_duplicate', '路径已存在'));
        return;
      }
      seenPaths.push(path);
      const item = new ShareRootPath();
      item.path = path;
      item.write = row.write;
      item.update = row.update;
      item.delete = row.delete;
      out.push(item);
    }
    if (out.length === 0) {
      DialogUtil.showErrorDialog(L10n.t('file_share_server_no_path_selected', '未选择路径'));
      return;
    }
    this.submitting = true;
    try {
      const ok = await this.onSubmit(this.selectedUid, out);
      if (ok) {
        this.onDismiss();
      }
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Stack() {
      // 遮罩（提交中禁止关闭，对齐 Flutter WillPopScope）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          if (!this.submitting) {
            this.onDismiss();
          }
        })

      Column() {
        Text(this.initialItem !== undefined
          ? L10n.t('file_share_server_edit_config', '编辑配置')
          : L10n.t('file_share_server_add_config', '添加配置'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)

        Scroll() {
          Column() {
            // 用户选择行（对齐 _pickUser 入口）
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.person'))
                .fontSize(20)
                .fontColor([AppTheme.current().onSurface])
              Text(this.selectedUsername())
                .fontSize(14)
                .fontColor(AppTheme.current().onSurface)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(16)
                .fontColor([AppTheme.current().hint])
            }
            .width('100%')
            .padding(12)
            .borderRadius(10)
            .border({ width: 1, color: AppTheme.current().divider })
            .onClick(() => {
              if (!this.submitting) {
                this.showUserPicker = true;
              }
            })

            // 路径列表标题 + 添加路径
            Row() {
              Text(L10n.t('file_share_server_paths', '路径列表'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.current().onSurface)
                .layoutWeight(1)
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.plus'))
                  .fontSize(14)
                  .fontColor([AppTheme.current().primary])
                Text(L10n.t('file_share_server_add_path', '添加路径'))
                  .fontSize(13)
                  .fontColor(AppTheme.current().primary)
              }
              .padding({ left: 8, right: 8, top: 6, bottom: 6 })
              .onClick(() => {
                if (!this.submitting) {
                  this.addUserRow();
                }
              })
            }
            .width('100%')
            .margin({ top: 14 })

            // 路径行列表（对齐 SizedBox(height: 280)）
            List({ space: 10 }) {
              ForEach(this.rows, (row: ShareRootPath, idx: number) => {
                ListItem() {
                  this.RootPathRow(row, idx)
                }
              }, (row: ShareRootPath, idx: number) => `${idx}_${row.path}_${row.write}_${row.update}_${row.delete}`)
            }
            .width('100%')
            .height(280)
            .scrollBar(BarState.Auto)
            .margin({ top: 8 })
          }
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .align(Alignment.Top)
        .margin({ top: 14 })
        .layoutWeight(1)

        // 取消 + 确认
        Row({ space: 8 }) {
          Button(L10n.cancel)
            .fontSize(14)
            .fontColor(AppTheme.current().primary)
            .backgroundColor(Color.Transparent)
            .height(36)
            .enabled(!this.submitting)
            .onClick(() => {
              this.onDismiss();
            })
          Button(L10n.t('confirm', '确认'))
            .fontSize(14)
            .fontColor(AppTheme.current().buttonText)
            .backgroundColor(AppTheme.current().buttonBg)
            .height(36)
            .enabled(!this.submitting)
            .opacity(this.submitting ? 0.45 : 1)
            .onClick(() => {
              void this.submit();
            })
        }
        .justifyContent(FlexAlign.End)
        .margin({ top: 12 })
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .borderRadius(24)
      .backgroundColor(AppTheme.current().surfaceBg)
      .width('86%')
      .height('70%')
      .constraintSize({ minWidth: 300, maxWidth: 560 })

      // 嵌套用户选择浮层（对齐 _UserPickerDialog）
      if (this.showUserPicker) {
        this.UserPickerOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }

  /** 用户选择浮层（按用户名排序，点击选中并关闭） */
  @Builder
  UserPickerOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          this.showUserPicker = false;
        })

      Column() {
        Text(L10n.t('file_share_server_choose_user', '请选择用户'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)

        if (this.ctrl.usersById.size === 0) {
          Column() {
            EmptyState({ message: L10n.t('no_data', '暂无数据') })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.sortedUsers(), (u: UserInfo) => {
              ListItem() {
                Row({ space: 10 }) {
                  SymbolGlyph($r('sys.symbol.person'))
                    .fontSize(20)
                    .fontColor([AppTheme.current().onSurface])
                  Text(u.username)
                    .fontSize(14)
                    .fontColor(AppTheme.current().onSurface)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  if (u.id === this.selectedUid) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(18)
                      .fontColor([AppTheme.current().primary])
                  }
                }
                .width('100%')
                .padding(12)
                .borderRadius(10)
                .border({
                  width: 1,
                  color: u.id === this.selectedUid ? AppTheme.current().primary : AppTheme.current().divider
                })
                .onClick(() => {
                  this.selectedUid = u.id;
                  this.showUserPicker = false;
                })
              }
            }, (u: UserInfo) => `${u.id}_${u.username}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .margin({ top: 12 })
        }

        Row() {
          Button(L10n.cancel)
            .fontSize(14)
            .fontColor(AppTheme.current().primary)
            .backgroundColor(Color.Transparent)
            .height(36)
            .onClick(() => {
              this.showUserPicker = false;
            })
        }
        .justifyContent(FlexAlign.End)
        .width('100%')
        .margin({ top: 8 })
      }
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .borderRadius(24)
      .backgroundColor(AppTheme.current().surfaceBg)
      .width('80%')
      .height('60%')
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }

  private sortedUsers(): UserInfo[] {
    const out: UserInfo[] = [];
    this.ctrl.usersById.forEach((u: ShareUserOption): void => {
      const info = new UserInfo();
      info.id = u.id;
      info.username = u.username;
      out.push(info);
    });
    return out.sort((a: UserInfo, b: UserInfo): number => a.username.localeCompare(b.username));
  }

  /** 单条路径行（对齐 _RootPathRow：路径 + 选择目录 + 删除 + 权限 chips） */
  @Builder
  RootPathRow(row: ShareRootPath, idx: number) {
    Column() {
      Row({ space: 8 }) {
        Text(row.path.length > 0 ? row.path : '-')
          .fontSize(12)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(L10n.t('user_mgmt_select_dir', '选择目录'))
          .fontSize(12)
          .fontColor(AppTheme.current().primary)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            if (!this.submitting) {
              this.pickPathForRow(idx);
            }
          })
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(14)
          .fontColor([this.rows.length > 1 ? AppTheme.current().onSurface : AppTheme.current().hint])
          .opacity(this.rows.length > 1 ? 1 : 0.4)
          .onClick(() => {
            if (!this.submitting && this.rows.length > 1) {
              this.removeRow(idx);
            }
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        this.PermChip(true, L10n.t('file_share_server_perm_read', '读取'), false, (): void => {
        })
        this.PermChip(row.write, L10n.t('file_share_server_perm_write', '写入'), true,
          (): void => {
            this.togglePerm(idx, 'write', !row.write);
          })
        this.PermChip(row.update, L10n.t('file_share_server_perm_update', '修改'), true,
          (): void => {
            this.togglePerm(idx, 'update', !row.update);
          })
        this.PermChip(row.delete, L10n.t('file_share_server_perm_delete', '删除'), true,
          (): void => {
            this.togglePerm(idx, 'delete', !row.delete);
          })
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .border({ width: 1, color: AppTheme.current().divider })
    .alignItems(HorizontalAlign.Start)
  }

  /** 权限 chip（对齐 FilterChip：选中主色浅底，未选中灰边） */
  @Builder
  PermChip(selected: boolean, label: string, toggleable: boolean, onTap: () => void) {
    Text(label)
      .fontSize(10)
      .fontColor(selected ? AppTheme.current().primary : AppTheme.current().onSurface)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(999)
      .border({
        width: 1,
        color: selected ? AppTheme.current().primary : AppTheme.current().divider
      })
      .backgroundColor(selected
        ? AppTheme.withAlpha(AppTheme.current().primary, 0.10)
        : '#00000000')
      .opacity(toggleable ? 1 : 0.85)
      .onClick(() => {
        if (toggleable && !this.submitting) {
          onTap();
        }
      })
  }
}

/** 用户选择浮层条目（ForEach key 用的稳定对象） */
class UserInfo {
  id: number = 0;
  username: string = '';
}
